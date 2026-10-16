extends Control
class_name EnemyEncounterDialog

signal confirmed(node_id: String)
signal dismissed

var preview_data: Dictionary = {}
var _frame: PanelContainer
var _heading: Label
var _counter: Label
var _enemy_name: Label
var _note: Label
var _stats: HFlowContainer
var _model: StarterModelPreview
var _cards: HFlowContainer
var _card_buttons: Array[CardButton] = []
var _start: Button
var _close: Button
var _model_box: VBoxContainer
var _layout_pending: bool = false
var _density: float = 1.0
var _body: VBoxContainer
var _content: HBoxContainer
var _footer: HBoxContainer
var _cards_title: Label


func _ready() -> void:
	name = "EnemyEncounterDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	visibility_changed.connect(_update_preview_activity)
	hide()
	_layout()


func open(data: Dictionary) -> void:
	if data.is_empty(): return
	preview_data = data
	var unit: UnitState = data["unit"] as UnitState
	_heading.text = Localization.get_text("encounter.title", "Enemy Intel")
	_counter.text = Localization.get_textf("encounter.counter", "Enemy {current} / {total}", {"current": data["index"], "total": data["total"]})
	_enemy_name.text = Localization.get_enemy_name(String(data["enemy_id"]), unit.display_name)
	if Game.current_run.infinite_mode:
		_enemy_name.text += "  ∞%d" % RealtimeBattleEngine._get_infinite_power(Game.current_run)
	_note.text = Localization.get_text("encounter.hazard_note", "Rewards after every battle. You may withdraw between waves.") if data["node_type"] == "hazard" else Localization.get_text("encounter.note", "Review the enemy before entering battle.")
	for child: Node in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	_add_stat("hp", "%d / %d" % [unit.hp, unit.max_hp], Localization.get_text("run_banner.hp", "HP"))
	_add_stat("attack", str(unit.attack), Localization.get_text("stats.attack", "Attack"))
	_add_stat("speed", str(unit.speed), Localization.get_text("stats.speed", "Speed"))
	_add_stat("card_equipped", str(unit.active_slot_max), Localization.get_text("encounter.slots", "Active slots"))
	var runtime: Array[CardRuntimeState] = unit.card_runtime_states
	while _card_buttons.size() < runtime.size():
		var holder: Control = Control.new()
		holder.custom_minimum_size = CardButton.get_tile_extent(Vector2.ONE * 144) * _density
		_cards.add_child(holder)
		var button: CardButton = CardButton.new()
		button.name = "EnemyPreviewCard_%d" % _card_buttons.size()
		button.set_tile_size(Vector2.ONE * 144)
		button.scale = Vector2.ONE * _density
		holder.add_child(button)
		_card_buttons.append(button)
	for index: int in _card_buttons.size():
		var button: CardButton = _card_buttons[index]
		button.visible = index < runtime.size()
		(button.get_parent() as Control).visible = button.visible
		if not button.visible: continue
		var context: Dictionary = CardTooltipResolver.build_context(runtime[index].card_id, null, unit)
		button.bind_preview(context["card"] as CardDef, runtime[index].runtime_id, false, "", context["comparison"] as CardDef)
	_start.text = Localization.get_text("encounter.enter", "Enter Battle")
	_close.text = Localization.get_text("common.close", "Close")
	_start.disabled = false
	_model.show_enemy(String(data["enemy_id"]))
	SceneRouter.schedule_battle_visuals(Game.current_run.starter_id, String(data["enemy_id"]))
	show()
	_layout()
	_start.grab_focus()


func close() -> void:
	hide()
	dismissed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.005, 0.012, 0.02, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_frame = PanelContainer.new()
	_frame.name = "EnemyEncounterFrame"
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("101b25")
	style.border_color = Color("c9a85d")
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(24)
	_frame.add_theme_stylebox_override("panel", style)
	_frame.minimum_size_changed.connect(_queue_layout)
	add_child(_frame)
	var body: VBoxContainer = VBoxContainer.new()
	_body = body
	body.add_theme_constant_override("separation", 16)
	_frame.add_child(body)
	var header: HBoxContainer = HBoxContainer.new()
	body.add_child(header)
	_heading = Label.new()
	_heading.theme_type_variation = "SectionTitle"
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_heading)
	_counter = Label.new()
	_counter.name = "EnemyEncounterCounter"
	_counter.add_theme_color_override("font_color", Color("ffd679"))
	_counter.add_theme_font_size_override("font_size", 22)
	header.add_child(_counter)
	body.add_child(HSeparator.new())
	var content: HBoxContainer = HBoxContainer.new()
	_content = content
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	body.add_child(content)
	_model_box = VBoxContainer.new()
	_model_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_box.size_flags_stretch_ratio = 0.82
	content.add_child(_model_box)
	_model = StarterModelPreview.new()
	_model.set_auto_frame(true)
	_model.custom_minimum_size = Vector2(200, 240)
	_model.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_model_box.add_child(_model)
	_enemy_name = Label.new()
	_enemy_name.name = "EnemyEncounterName"
	_enemy_name.add_theme_font_size_override("font_size", 28)
	_enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_model_box.add_child(_enemy_name)
	var details: VBoxContainer = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 16)
	content.add_child(details)
	_stats = HFlowContainer.new()
	_stats.name = "EnemyEncounterStats"
	_stats.add_theme_constant_override("h_separation", 22)
	details.add_child(_stats)
	var title: Label = Label.new()
	_cards_title = title
	title.text = Localization.get_text("encounter.cards", "Enemy Cards")
	details.add_child(title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "EnemyEncounterCardsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(scroll)
	_cards = HFlowContainer.new()
	_cards.name = "EnemyEncounterCards"
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("h_separation", 16)
	_cards.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_cards)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", Color("b1c0c8"))
	body.add_child(_note)
	var footer: HBoxContainer = HBoxContainer.new()
	_footer = footer
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 16)
	body.add_child(footer)
	_close = Button.new()
	_close.name = "EnemyEncounterClose"
	_close.custom_minimum_size = Vector2(160, 52)
	_close.pressed.connect(close)
	footer.add_child(_close)
	_start = Button.new()
	_start.name = "EnemyEncounterStart"
	_start.theme_type_variation = "PrimaryButton"
	_start.custom_minimum_size = Vector2(240, 52)
	_start.pressed.connect(func() -> void:
		if _start.disabled: return
		_start.disabled = true
		confirmed.emit(String(preview_data.get("node_id", "")))
	)
	footer.add_child(_start)
	_start.focus_next = _start.get_path_to(_close)
	_start.focus_previous = _start.get_path_to(_close)
	_close.focus_next = _close.get_path_to(_start)
	_close.focus_previous = _close.get_path_to(_start)


func _add_stat(icon_id: String, value: String, hint: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.tooltip_text = hint
	row.add_theme_constant_override("separation", 8)
	_stats.add_child(row)
	var icon: TextureRect = TextureRect.new()
	icon.texture = StatIconFactory.get_icon(icon_id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2.ONE * 28 * _density
	row.add_child(icon)
	var label: Label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", ceili(24 * _density))
	row.add_child(label)


func _queue_layout() -> void:
	if _layout_pending: return
	_layout_pending = true
	call_deferred("_layout")


func _layout() -> void:
	_layout_pending = false
	if _frame == null: return
	var area: Vector2 = get_viewport_rect().size
	var density: float = 1.0 if DisplayServer.get_name() == "headless" else clampf(area.x / maxf(1, get_window().size.x), 0.75, 3.0)
	if not is_equal_approx(_density, density):
		_density = density
		var style: StyleBoxFlat = _frame.get_theme_stylebox("panel") as StyleBoxFlat
		style.set_content_margin_all(24 * density)
		_heading.add_theme_font_size_override("font_size", ceili(22 * density))
		_counter.add_theme_font_size_override("font_size", ceili(22 * density))
		_enemy_name.add_theme_font_size_override("font_size", ceili(28 * density))
		_note.add_theme_font_size_override("font_size", ceili(16 * density))
		_cards_title.add_theme_font_size_override("font_size", ceili(18 * density))
		for button: Button in [_start, _close]: button.add_theme_font_size_override("font_size", ceili(18 * density))
		_start.custom_minimum_size = Vector2(240, 52) * density
		_close.custom_minimum_size = Vector2(160, 52) * density
		_model.custom_minimum_size = Vector2(200, 240) * density
		_body.add_theme_constant_override("separation", ceili(16 * density))
		_content.add_theme_constant_override("separation", ceili(24 * density))
		_footer.add_theme_constant_override("separation", ceili(16 * density))
		_cards.add_theme_constant_override("h_separation", ceili(16 * density))
		_cards.add_theme_constant_override("v_separation", ceili(12 * density))
		_stats.add_theme_constant_override("h_separation", ceili(22 * density))
		# Scale the complete card, not only its art, so badges and names remain readable.
		for card: CardButton in _card_buttons:
			(card.get_parent() as Control).custom_minimum_size = CardButton.get_tile_extent(Vector2.ONE * 144) * density
			card.scale = Vector2.ONE * density
		for row: Node in _stats.get_children():
			(row.get_child(0) as TextureRect).custom_minimum_size = Vector2.ONE * 28 * density
			(row.get_child(1) as Label).add_theme_font_size_override("font_size", ceili(24 * density))
	_frame.size = Vector2(minf(1120 * density, area.x - 64 * density), minf(780 * density, area.y - 64 * density))
	_frame.position = (area - _frame.size) * 0.5
	_model_box.custom_minimum_size.x = minf(330 * density, _frame.size.x * 0.34)


func _update_preview_activity() -> void:
	if _model == null: return
	_model.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED
	_model.get_preview_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
