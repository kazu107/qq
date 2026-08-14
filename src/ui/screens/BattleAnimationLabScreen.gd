extends Control

const PLAYER_UNIT_ID: String = "lab_player"
const ENEMY_UNIT_ID: String = "lab_enemy"
const ACTION_ENTRIES: Array[Dictionary] = [
	{"id": "idle", "ja": "待機", "en": "Idle"},
	{"id": "ready", "ja": "タイムライン構え", "en": "Timeline stance"},
	{"id": "cast", "ja": "詠唱", "en": "Cast"},
	{"id": "attack", "ja": "攻撃", "en": "Attack"},
	{"id": "block", "ja": "防御", "en": "Block"},
	{"id": "hit", "ja": "被弾", "en": "Hit"},
	{"id": "shield", "ja": "シールド", "en": "Shield"},
	{"id": "heal", "ja": "回復", "en": "Heal"},
	{"id": "status", "ja": "状態効果", "en": "Status"},
	{"id": "interrupt", "ja": "中断", "en": "Interrupt"},
	{"id": "victory", "ja": "勝利", "en": "Victory"},
	{"id": "defeat", "ja": "敗北", "en": "Defeat"},
]
const CAMERA_ENTRIES: Array[Dictionary] = [
	{"id": "battle", "ja": "戦闘視点", "en": "Battle"},
	{"id": "front", "ja": "正面", "en": "Front"},
	{"id": "side", "ja": "側面", "en": "Side"},
	{"id": "rear", "ja": "背面", "en": "Rear"},
]

var _stage: BattleStage3D
var _player_model_option: OptionButton
var _enemy_model_option: OptionButton
var _target_option: OptionButton
var _action_option: OptionButton
var _camera_option: OptionButton
var _speed_slider: HSlider
var _speed_value: Label
var _status_label: Label


func _ready() -> void:
	if not Game.is_developer_mode_enabled():
		SceneRouter.go_to_hub()
		return
	if Database.get_all_battle_visual_profiles().is_empty():
		Database.load_all()
	_build_ui()
	await get_tree().process_frame
	_reconfigure_stage()
	set_process(true)


func _process(_delta: float) -> void:
	_refresh_status()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.008, 0.014, 0.024, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var page_margin := MarginContainer.new()
	page_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 28)
	page_margin.add_theme_constant_override("margin_top", 22)
	page_margin.add_theme_constant_override("margin_right", 28)
	page_margin.add_theme_constant_override("margin_bottom", 22)
	add_child(page_margin)

	var page_root := VBoxContainer.new()
	page_root.add_theme_constant_override("separation", 12)
	page_margin.add_child(page_root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	page_root.add_child(header)

	var title_group := VBoxContainer.new()
	title_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_group)

	var title := Label.new()
	title.text = _localized("戦闘アニメーションラボ", "Battle Animation Lab")
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.42, 0.86, 1.0, 1.0))
	title_group.add_child(title)

	var subtitle := Label.new()
	subtitle.text = _localized(
		"モデル、動作、視点を固定してボーン姿勢を確認できます。",
		"Inspect skeletal poses with fixed models, actions, and camera angles."
	)
	subtitle.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	title_group.add_child(subtitle)

	var ready_both_button := Button.new()
	ready_both_button.name = "BattleAnimationLabReadyBoth"
	ready_both_button.text = _localized("両者を構え", "Ready both")
	ready_both_button.custom_minimum_size = Vector2(150.0, 44.0)
	ready_both_button.pressed.connect(_on_ready_both_pressed)
	header.add_child(ready_both_button)

	var back_button := Button.new()
	back_button.name = "BattleAnimationLabBack"
	back_button.text = _localized("戻る", "Back")
	back_button.custom_minimum_size = Vector2(110.0, 44.0)
	back_button.pressed.connect(_on_back_pressed)
	header.add_child(back_button)

	var controls_panel := PanelContainer.new()
	controls_panel.name = "BattleAnimationLabControls"
	controls_panel.add_theme_stylebox_override("panel", _make_panel_style())
	page_root.add_child(controls_panel)

	var controls_margin := MarginContainer.new()
	controls_margin.add_theme_constant_override("margin_left", 14)
	controls_margin.add_theme_constant_override("margin_top", 12)
	controls_margin.add_theme_constant_override("margin_right", 14)
	controls_margin.add_theme_constant_override("margin_bottom", 12)
	controls_panel.add_child(controls_margin)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	controls_margin.add_child(controls)

	var model_row := HBoxContainer.new()
	model_row.add_theme_constant_override("separation", 12)
	controls.add_child(model_row)

	_player_model_option = OptionButton.new()
	_player_model_option.name = "BattleAnimationLabPlayerModel"
	_player_model_option.custom_minimum_size = Vector2(300.0, 42.0)
	_populate_model_options(_player_model_option, "balanced")
	_player_model_option.item_selected.connect(_on_model_changed)
	_add_labeled_control(model_row, _localized("左モデル", "Left model"), _player_model_option)

	_enemy_model_option = OptionButton.new()
	_enemy_model_option.name = "BattleAnimationLabEnemyModel"
	_enemy_model_option.custom_minimum_size = Vector2(300.0, 42.0)
	_populate_model_options(_enemy_model_option, "scout")
	_enemy_model_option.item_selected.connect(_on_model_changed)
	_add_labeled_control(model_row, _localized("右モデル", "Right model"), _enemy_model_option)

	_target_option = OptionButton.new()
	_target_option.name = "BattleAnimationLabTarget"
	_target_option.custom_minimum_size = Vector2(190.0, 42.0)
	_target_option.add_item(_localized("左キャラクター", "Left actor"))
	_target_option.set_item_metadata(0, PLAYER_UNIT_ID)
	_target_option.add_item(_localized("右キャラクター", "Right actor"))
	_target_option.set_item_metadata(1, ENEMY_UNIT_ID)
	_target_option.item_selected.connect(_on_target_changed)
	_add_labeled_control(model_row, _localized("確認対象", "Target"), _target_option)

	_action_option = OptionButton.new()
	_action_option.name = "BattleAnimationLabAction"
	_action_option.custom_minimum_size = Vector2(220.0, 42.0)
	for action_data: Dictionary in ACTION_ENTRIES:
		_action_option.add_item(_entry_label(action_data))
		_action_option.set_item_metadata(_action_option.item_count - 1, String(action_data.get("id", "idle")))
	_select_by_metadata(_action_option, "ready")
	_add_labeled_control(model_row, _localized("アクション", "Action"), _action_option)

	var play_button := Button.new()
	play_button.name = "BattleAnimationLabPlay"
	play_button.text = _localized("再生", "Play")
	play_button.custom_minimum_size = Vector2(110.0, 42.0)
	play_button.pressed.connect(_on_play_pressed)
	model_row.add_child(play_button)

	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 12)
	controls.add_child(view_row)

	_camera_option = OptionButton.new()
	_camera_option.name = "BattleAnimationLabCamera"
	_camera_option.custom_minimum_size = Vector2(190.0, 42.0)
	for camera_data: Dictionary in CAMERA_ENTRIES:
		_camera_option.add_item(_entry_label(camera_data))
		_camera_option.set_item_metadata(_camera_option.item_count - 1, String(camera_data.get("id", "battle")))
	_select_by_metadata(_camera_option, "front")
	_camera_option.item_selected.connect(_on_camera_changed)
	_add_labeled_control(view_row, _localized("カメラ", "Camera"), _camera_option)

	var speed_group := VBoxContainer.new()
	speed_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_row.add_child(speed_group)
	var speed_header := HBoxContainer.new()
	speed_group.add_child(speed_header)
	var speed_label := Label.new()
	speed_label.text = _localized("再生速度", "Playback speed")
	speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_header.add_child(speed_label)
	_speed_value = Label.new()
	_speed_value.custom_minimum_size = Vector2(72.0, 0.0)
	_speed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_header.add_child(_speed_value)
	_speed_slider = HSlider.new()
	_speed_slider.name = "BattleAnimationLabSpeed"
	_speed_slider.min_value = 0.0
	_speed_slider.max_value = 2.0
	_speed_slider.step = 0.05
	_speed_slider.value = 1.0
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.custom_minimum_size = Vector2(420.0, 0.0)
	_speed_slider.value_changed.connect(_on_speed_changed)
	speed_group.add_child(_speed_slider)
	_update_speed_label()

	_stage = BattleStage3D.new()
	_stage.custom_minimum_size = Vector2(960.0, 610.0)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_root.add_child(_stage)
	_stage.name = "BattleAnimationLabStage"

	_status_label = Label.new()
	_status_label.name = "BattleAnimationLabStatus"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	page_root.add_child(_status_label)


func _populate_model_options(option: OptionButton, selected_id: String) -> void:
	for profile: Dictionary in Database.get_all_battle_visual_profiles():
		var profile_id: String = String(profile.get("id", ""))
		if profile_id == "":
			continue
		var kind: String = String(profile.get("kind", "unit"))
		var authored_suffix: String = " GLB" if String(profile.get("model_scene", "")) != "" else ""
		option.add_item("%s  [%s%s]" % [profile_id, kind, authored_suffix])
		option.set_item_metadata(option.item_count - 1, profile_id)
	_select_by_metadata(option, selected_id)


func _add_labeled_control(row: HBoxContainer, label_text: String, control: Control) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	group.add_child(label)
	group.add_child(control)
	row.add_child(group)


func _reconfigure_stage() -> void:
	if _stage == null:
		return
	_stage.configure_combatants(
		PLAYER_UNIT_ID,
		ENEMY_UNIT_ID,
		"player",
		_selected_metadata(_player_model_option),
		_selected_metadata(_enemy_model_option)
	)
	_apply_speed_to_actors()
	_on_ready_both_pressed(false)
	_apply_camera()


func _on_model_changed(_index: int) -> void:
	_reconfigure_stage()


func _on_target_changed(_index: int) -> void:
	_apply_camera()


func _on_camera_changed(_index: int) -> void:
	_apply_camera()


func _on_speed_changed(_value: float) -> void:
	_update_speed_label()
	_apply_speed_to_actors()


func _on_play_pressed() -> void:
	var actor: BattleActor3D = _selected_actor()
	if actor == null:
		return
	_apply_action(actor, _selected_metadata(_action_option))
	AudioManager.play_sfx("ui_confirm")


func _on_ready_both_pressed(play_sound: bool = true) -> void:
	if _stage == null:
		return
	for unit_id: String in [PLAYER_UNIT_ID, ENEMY_UNIT_ID]:
		var actor: BattleActor3D = _stage.get_combat_actor(unit_id)
		if actor != null:
			_apply_action(actor, "ready")
	if play_sound:
		AudioManager.play_sfx("ui_confirm")


func _apply_action(actor: BattleActor3D, action_id: String) -> void:
	actor.reset_performance()
	actor.set_animation_speed_scale(float(_speed_slider.value) if _speed_slider != null else 1.0)
	match action_id:
		"idle":
			pass
		"ready":
			actor.start_timeline_stance()
		_:
			actor.play_action(StringName(action_id))


func _apply_speed_to_actors() -> void:
	if _stage == null or _speed_slider == null:
		return
	for unit_id: String in [PLAYER_UNIT_ID, ENEMY_UNIT_ID]:
		var actor: BattleActor3D = _stage.get_combat_actor(unit_id)
		if actor != null:
			actor.set_animation_speed_scale(float(_speed_slider.value))


func _apply_camera() -> void:
	if _stage == null or _camera_option == null or _target_option == null:
		return
	_stage.set_camera_preset(_selected_metadata(_camera_option), _selected_metadata(_target_option))


func _selected_actor() -> BattleActor3D:
	return _stage.get_combat_actor(_selected_metadata(_target_option)) if _stage != null else null


func _refresh_status() -> void:
	if _status_label == null or _stage == null:
		return
	var player: BattleActor3D = _stage.get_combat_actor(PLAYER_UNIT_ID)
	var enemy: BattleActor3D = _stage.get_combat_actor(ENEMY_UNIT_ID)
	if player == null or enemy == null:
		return
	var player_depth: float = _minimum_hand_forward_depth(player)
	var enemy_depth: float = _minimum_hand_forward_depth(enemy)
	_status_label.text = _localized(
		"左: %s  手の前方距離 %.2f  |  右: %s  手の前方距離 %.2f",
		"Left: %s  hand forward %.2f  |  Right: %s  hand forward %.2f"
	) % [player.get_action_name(), player_depth, enemy.get_action_name(), enemy_depth]
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.38, 1.0, 0.62, 1.0) if minf(player_depth, enemy_depth) > 0.10 else Color(1.0, 0.38, 0.30, 1.0)
	)


func _minimum_hand_forward_depth(actor: BattleActor3D) -> float:
	var chest_z: float = actor.get_bone_model_position("chest").z
	var left_depth: float = chest_z - actor.get_bone_model_position("left_hand").z
	var right_depth: float = chest_z - actor.get_bone_model_position("right_hand").z
	return minf(left_depth, right_depth)


func _update_speed_label() -> void:
	if _speed_value != null and _speed_slider != null:
		_speed_value.text = "%.2fx" % float(_speed_slider.value)


func _selected_metadata(option: OptionButton) -> String:
	if option == null or option.item_count == 0 or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func _select_by_metadata(option: OptionButton, target_id: String) -> void:
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == target_id:
			option.select(index)
			return


func _entry_label(entry: Dictionary) -> String:
	return String(entry.get("ja" if Game.get_language() == "ja" else "en", entry.get("id", "")))


func _localized(japanese: String, english: String) -> String:
	return japanese if Game.get_language() == "ja" else english


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.048, 0.064, 0.96)
	style.border_color = Color(0.25, 0.68, 0.92, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _on_back_pressed() -> void:
	SceneRouter.return_from_debug_lab()
