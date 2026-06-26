extends Control

const MODAL_WIDTH: float = 650.0
const MODAL_CARD_SIZE: Vector2 = Vector2(128.0, 128.0)

var _gold_reward_label: Label
var _heal_reward_label: Label
var _reward_relic_icon_row: RelicIconRow
var _reward_cards_panel: CardHandPanel
var _reroll_button: Button
var _developer_panel: DeveloperPanel


func _ready() -> void:
	if Game.current_run == null:
		SceneRouter.go_to_title()
		return
	if Game.reward_options.is_empty():
		if Game.current_run.run_complete:
			SceneRouter.go_to_result()
		else:
			SceneRouter.go_to_map()
		return

	var dim_overlay: ColorRect = ColorRect.new()
	dim_overlay.name = "RewardDimOverlay"
	dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_overlay.color = Color(0.0, 0.0, 0.0, 0.66)
	dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim_overlay)

	var modal: PanelContainer = PanelContainer.new()
	modal.name = "RewardModal"
	modal.custom_minimum_size = Vector2(MODAL_WIDTH, 0.0)
	modal.add_theme_stylebox_override("panel", _make_modal_stylebox())
	modal.anchor_left = 0.5
	modal.anchor_top = 0.5
	modal.anchor_right = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -MODAL_WIDTH * 0.5
	modal.offset_right = MODAL_WIDTH * 0.5
	modal.offset_top = -260.0
	modal.offset_bottom = 260.0
	add_child(modal)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 24)
	modal.add_child(margin)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var title := Label.new()
	title.name = "RewardModalTitle"
	title.text = Localization.get_text("reward.title", "Reward")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	var gains_row: HBoxContainer = HBoxContainer.new()
	gains_row.name = "RewardGainsRow"
	gains_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gains_row.add_theme_constant_override("separation", 18)
	root.add_child(gains_row)

	_gold_reward_label = _add_gain_item(gains_row, "gold")
	_heal_reward_label = _add_gain_item(gains_row, "hp")

	var relic_group: HBoxContainer = HBoxContainer.new()
	relic_group.name = "RewardRelicGain"
	relic_group.add_theme_constant_override("separation", 8)
	gains_row.add_child(relic_group)

	var relic_icon: TextureRect = _build_stat_icon("relic")
	relic_group.add_child(relic_icon)

	_reward_relic_icon_row = RelicIconRow.new()
	_reward_relic_icon_row.name = "RewardRelicIconRow"
	_reward_relic_icon_row.set_icon_size(Vector2(34.0, 34.0))
	relic_group.add_child(_reward_relic_icon_row)

	_reward_cards_panel = CardHandPanel.new()
	_reward_cards_panel.name = "RewardCards"
	_reward_cards_panel.set_interactive(true)
	_reward_cards_panel.alignment = FlowContainer.ALIGNMENT_CENTER
	_reward_cards_panel.set_tile_size(MODAL_CARD_SIZE)
	_reward_cards_panel.card_requested.connect(_on_reward_selected)
	root.add_child(_reward_cards_panel)
	_reward_cards_panel.refresh_card_ids(Game.reward_options, true, "PICK", Game.current_run)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 10)
	root.add_child(button_row)

	_reroll_button = Button.new()
	_reroll_button.name = "RewardRerollButton"
	_reroll_button.pressed.connect(_on_paid_reroll)
	button_row.add_child(_reroll_button)

	var skip_button := Button.new()
	skip_button.text = Localization.get_text("reward.skip", "Skip")
	skip_button.pressed.connect(_on_skip)
	button_row.add_child(skip_button)

	var info := Label.new()
	info.name = "RewardChooseHint"
	info.text = Localization.get_text("reward.choose_one", "Choose one card. Hover to inspect details.")
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(info)

	_refresh_reward_ui()

	if Game.is_developer_mode_enabled():
		_build_developer_panel()


func _refresh_reward_ui() -> void:
	_refresh_reward_gains()
	if _reward_cards_panel != null:
		_reward_cards_panel.refresh_card_ids(Game.reward_options, true, "PICK", Game.current_run)
	_refresh_reward_relics()
	_refresh_reroll_button()


func _refresh_reward_gains() -> void:
	var reward_bundle: Dictionary = Game.get_last_reward_bundle()
	if _gold_reward_label != null:
		_gold_reward_label.text = "+%d" % int(reward_bundle.get("gold", 0))
	if _heal_reward_label != null:
		_heal_reward_label.text = "+%d" % int(reward_bundle.get("heal", 0))


func _refresh_reward_relics() -> void:
	if _reward_relic_icon_row == null:
		return
	var relic_ids: Array[String] = _get_reward_relic_ids()
	_reward_relic_icon_row.refresh_relic_ids(relic_ids, Localization.get_text("status.none", "None"))


func _get_reward_relic_ids() -> Array[String]:
	var relic_id: String = String(Game.last_battle_summary.get("bonus_relic_id", ""))
	if relic_id == "":
		return []
	return [relic_id]


func _refresh_reroll_button() -> void:
	if _reroll_button == null:
		return
	var cost: int = Game.get_reward_reroll_cost()
	_reroll_button.text = Localization.get_textf("reward.reroll", "Reroll ({cost}G)", {"cost": cost})
	_reroll_button.disabled = not Game.can_reroll_rewards()


func _add_gain_item(parent: Control, icon_id: String) -> Label:
	var group: HBoxContainer = HBoxContainer.new()
	group.name = "RewardGain_%s" % icon_id
	group.add_theme_constant_override("separation", 6)
	parent.add_child(group)

	group.add_child(_build_stat_icon(icon_id))

	var value_label: Label = Label.new()
	value_label.name = "RewardGainValue_%s" % icon_id
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 20)
	group.add_child(value_label)
	return value_label


func _build_stat_icon(icon_id: String) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.name = "RewardIcon_%s" % icon_id
	icon.custom_minimum_size = Vector2(30.0, 30.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = StatIconFactory.get_icon(icon_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _make_modal_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.040, 0.048, 0.97)
	style.border_color = Color(0.80, 0.72, 0.56, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 8.0)
	return style


func _on_reward_selected(card_id: String) -> void:
	Game.choose_reward(card_id)
	if Game.current_run != null and Game.current_run.run_complete:
		SceneRouter.go_to_result()
	else:
		SceneRouter.go_to_map()


func _on_skip() -> void:
	Game.skip_reward()
	if Game.current_run != null and Game.current_run.run_complete:
		SceneRouter.go_to_result()
	else:
		SceneRouter.go_to_map()


func _on_open_replay_viewer() -> void:
	if not Game.open_last_replay_view("reward"):
		AudioManager.play_sfx("ui_error")
		return
	SceneRouter.go_to_replay_viewer()


func _on_paid_reroll() -> void:
	if Game.reroll_rewards_for_gold():
		_refresh_reward_ui()
		return
	_refresh_reroll_button()


func _build_developer_panel() -> void:
	_developer_panel = DeveloperPanel.new()
	add_child(_developer_panel)
	_developer_panel.pin_top_right()
	_developer_panel.configure(
		Localization.get_text("developer.title", "Developer Mode"),
		[
			{"id": "DevTakeFirstReward", "label": Localization.get_text("reward.dev.take_first", "Take First"), "callback": Callable(self, "_on_dev_take_first_reward")},
			{"id": "DevSkipReward", "label": Localization.get_text("reward.dev.skip", "Skip Reward"), "callback": Callable(self, "_on_skip")},
			{"id": "DevRerollRewards", "label": Localization.get_text("reward.dev.reroll", "Reroll Rewards"), "callback": Callable(self, "_on_dev_reroll_rewards")},
			{"id": "DevPreviewEliteReward", "label": Localization.get_text("reward.dev.preview_elite", "Preview Elite"), "callback": Callable(self, "_on_dev_preview_elite")},
			{"id": "DevExportReplay", "label": Localization.get_text("reward.dev.export_replay", "Export Replay"), "callback": Callable(self, "_on_dev_export_replay")},
			{"id": "DevOpenReplay", "label": Localization.get_text("reward.dev.open_replay", "Open Replay"), "callback": Callable(self, "_on_dev_open_replay")},
		],
		Localization.get_text("reward.dev.summary", "Fast reward inspection and selection.")
	)


func _on_dev_take_first_reward() -> void:
	if Game.reward_options.is_empty():
		return
	_on_reward_selected(Game.reward_options[0])


func _on_dev_reroll_rewards() -> void:
	Game.developer_reroll_rewards()
	_refresh_reward_ui()


func _on_dev_preview_elite() -> void:
	Game.developer_open_reward_preview("elite", Game.current_run.current_area)
	_refresh_reward_ui()


func _on_dev_export_replay() -> void:
	Game.export_last_battle_replay()


func _on_dev_open_replay() -> void:
	_on_open_replay_viewer()
