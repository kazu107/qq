extends VBoxContainer
class_name UnitPanel

const PORTRAIT_PATH_TEMPLATE := "res://assets/portraits/%s.png"
const PANEL_FILL := Color(0.08, 0.10, 0.13, 0.92)
const PANEL_STROKE := Color(0.28, 0.34, 0.42, 1.0)
const HP_BAR_FILL := Color(0.77, 0.19, 0.22, 1.0)
const HP_BAR_BG := Color(0.18, 0.05, 0.06, 0.96)
const SHIELD_BAR_FILL := Color(0.26, 0.63, 0.92, 1.0)
const SHIELD_BAR_BG := Color(0.04, 0.11, 0.18, 0.96)
const SHIELD_BAR_SOFT_MAX: float = 12.0
const TEXT_LIGHT := Color(0.95, 0.95, 0.93, 1.0)
const SLOT_USED_FILL := Color(0.38, 0.93, 0.72, 1.0)
const SLOT_EMPTY_FILL := Color(0.05, 0.09, 0.12, 0.46)
const SLOT_BORDER := Color(0.53, 0.69, 0.74, 1.0)
const DAMAGE_COLOR := Color(1.0, 0.40, 0.35, 1.0)
const HEAL_COLOR := Color(0.48, 0.95, 0.58, 1.0)
const SHIELD_COLOR := Color(0.47, 0.82, 1.0, 1.0)

class FloatingStatText:
	extends RefCounted

	var label: Label
	var lifetime: float = 0.9
	var elapsed: float = 0.0
	var drift: Vector2 = Vector2.ZERO

static var _portrait_cache: Dictionary = {}

var _title_label: Label
var _portrait_key: String = ""
var _unit_side: String = "player"
var _name_label: Label
var _portrait_rect: TextureRect
var _portrait_effect_layer: Control
var _hp_bar: ProgressBar
var _hp_label: Label
var _shield_bar: ProgressBar
var _shield_label: Label
var _slots_label: Label
var _slot_bars: HBoxContainer
var _slot_cells: Array[Panel] = []
var _stats_label: Label
var _status_label: Label
var _floating_texts: Array[FloatingStatText] = []
var _last_hp: int = -1
var _last_shield: int = -1
var _last_stat_line: String = ""
var _last_status_line: String = ""
var _has_previous_snapshot: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_title_label = Label.new()
	_title_label.text = Localization.get_text("unit.title", "Unit")
	add_child(_title_label)

	var body_row: HBoxContainer = HBoxContainer.new()
	body_row.name = "BodyRow"
	body_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_row.add_theme_constant_override("separation", 14)
	add_child(body_row)

	var portrait_frame: PanelContainer = PanelContainer.new()
	portrait_frame.name = "PortraitFrame"
	portrait_frame.custom_minimum_size = Vector2(152.0, 152.0)
	portrait_frame.add_theme_stylebox_override("panel", _make_frame_stylebox())
	body_row.add_child(portrait_frame)

	var portrait_root: MarginContainer = MarginContainer.new()
	portrait_root.name = "PortraitMargin"
	portrait_root.add_theme_constant_override("margin_left", 6)
	portrait_root.add_theme_constant_override("margin_top", 6)
	portrait_root.add_theme_constant_override("margin_right", 6)
	portrait_root.add_theme_constant_override("margin_bottom", 6)
	portrait_frame.add_child(portrait_root)

	var portrait_anchor: Control = Control.new()
	portrait_anchor.name = "PortraitAnchor"
	portrait_anchor.custom_minimum_size = Vector2(140.0, 140.0)
	portrait_root.add_child(portrait_anchor)

	_portrait_rect = TextureRect.new()
	_portrait_rect.name = "Portrait"
	_portrait_rect.anchor_right = 1.0
	_portrait_rect.anchor_bottom = 1.0
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_anchor.add_child(_portrait_rect)

	_portrait_effect_layer = Control.new()
	_portrait_effect_layer.name = "EffectLayer"
	_portrait_effect_layer.anchor_right = 1.0
	_portrait_effect_layer.anchor_bottom = 1.0
	_portrait_effect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_anchor.add_child(_portrait_effect_layer)

	var info_column: VBoxContainer = VBoxContainer.new()
	info_column.name = "InfoColumn"
	info_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_column.add_theme_constant_override("separation", 8)
	body_row.add_child(info_column)

	_name_label = Label.new()
	_name_label.name = "UnitName"
	_name_label.add_theme_font_size_override("font_size", 18)
	info_column.add_child(_name_label)

	var hp_stack: Control = Control.new()
	hp_stack.name = "HpStack"
	hp_stack.custom_minimum_size = Vector2(0.0, 34.0)
	hp_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_column.add_child(hp_stack)

	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HpBar"
	_hp_bar.anchor_right = 1.0
	_hp_bar.anchor_bottom = 1.0
	_hp_bar.show_percentage = false
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 1.0
	_hp_bar.value = 1.0
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.add_theme_stylebox_override("background", _make_hp_background_stylebox())
	_hp_bar.add_theme_stylebox_override("fill", _make_hp_fill_stylebox())
	hp_stack.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.name = "HpLabel"
	_hp_label.anchor_right = 1.0
	_hp_label.anchor_bottom = 1.0
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_color_override("font_color", TEXT_LIGHT)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_stack.add_child(_hp_label)

	var shield_stack: Control = Control.new()
	shield_stack.name = "ShieldStack"
	shield_stack.custom_minimum_size = Vector2(0.0, 25.0)
	shield_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_column.add_child(shield_stack)

	_shield_bar = ProgressBar.new()
	_shield_bar.name = "ShieldBar"
	_shield_bar.anchor_right = 1.0
	_shield_bar.anchor_bottom = 1.0
	_shield_bar.show_percentage = false
	_shield_bar.min_value = 0.0
	_shield_bar.max_value = SHIELD_BAR_SOFT_MAX
	_shield_bar.value = 0.0
	_shield_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_bar.add_theme_stylebox_override("background", _make_shield_background_stylebox())
	_shield_bar.add_theme_stylebox_override("fill", _make_shield_fill_stylebox())
	shield_stack.add_child(_shield_bar)

	_shield_label = Label.new()
	_shield_label.name = "ShieldLabel"
	_shield_label.anchor_right = 1.0
	_shield_label.anchor_bottom = 1.0
	_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shield_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shield_label.add_theme_color_override("font_color", TEXT_LIGHT)
	_shield_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_stack.add_child(_shield_label)

	var slot_battery: HBoxContainer = HBoxContainer.new()
	slot_battery.name = "SlotBattery"
	slot_battery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_battery.add_theme_constant_override("separation", 10)
	info_column.add_child(slot_battery)

	_slots_label = Label.new()
	_slots_label.name = "SlotLabel"
	_slots_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_battery.add_child(_slots_label)

	_slot_bars = HBoxContainer.new()
	_slot_bars.name = "SlotBatteryBars"
	_slot_bars.add_theme_constant_override("separation", 4)
	slot_battery.add_child(_slot_bars)

	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_column.add_child(_stats_label)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_column.add_child(_status_label)

	set_process(true)


func set_title(title: String) -> void:
	_title_label.text = title


func configure_visual(unit_side: String, portrait_key: String) -> void:
	_unit_side = unit_side
	_portrait_key = portrait_key
	if _portrait_rect != null:
		_portrait_rect.texture = _get_portrait_texture(portrait_key)


func refresh_unit(unit: UnitState) -> void:
	if _portrait_rect != null and _portrait_rect.texture == null:
		_portrait_rect.texture = _get_portrait_texture(_portrait_key)

	var hp_value: int = max(0, unit.hp)
	var max_hp_value: int = max(1, unit.max_hp)
	var shield_value: int = max(0, unit.shield)
	var stat_line: String = Localization.get_textf("unit.stats_line", "ATK {attack} | DEF {defense} | SPD {speed}", {
		"attack": unit.attack,
		"defense": unit.defense,
		"speed": unit.speed,
	})
	var status_line: String = unit.get_status_summary()

	if _has_previous_snapshot:
		_emit_delta_popups(hp_value, shield_value)

	_name_label.text = unit.display_name
	_hp_bar.max_value = float(max_hp_value)
	_hp_bar.value = float(hp_value)
	_hp_label.text = "%d / %d" % [hp_value, max_hp_value]
	_shield_bar.max_value = maxf(SHIELD_BAR_SOFT_MAX, float(shield_value))
	_shield_bar.value = float(shield_value)
	_shield_label.text = Localization.get_textf("unit.shield", "Shield {value}", {"value": shield_value})
	_slots_label.text = Localization.get_textf("unit.slots", "Slots {used} / {total}", {
		"used": unit.active_slots_used,
		"total": unit.active_slot_max,
	})
	_refresh_slot_battery(unit.active_slots_used, unit.active_slot_max)
	_stats_label.text = stat_line
	_status_label.text = Localization.get_textf("unit.status", "Status: {value}", {"value": status_line})

	_last_hp = hp_value
	_last_shield = shield_value
	_last_stat_line = stat_line
	_last_status_line = status_line
	_has_previous_snapshot = true


func _refresh_slot_battery(used_slots: int, total_slots: int) -> void:
	var resolved_total: int = max(0, total_slots)
	var resolved_used: int = clampi(used_slots, 0, resolved_total)
	_ensure_slot_cell_count(resolved_total)
	for index in range(_slot_cells.size()):
		var slot_cell: Panel = _slot_cells[index]
		var is_visible: bool = index < resolved_total
		slot_cell.visible = is_visible
		if not is_visible:
			continue
		slot_cell.add_theme_stylebox_override("panel", _make_slot_cell_stylebox(index < resolved_used))


func _ensure_slot_cell_count(total_slots: int) -> void:
	if _slot_bars == null:
		return
	while _slot_cells.size() < total_slots:
		var slot_cell: Panel = Panel.new()
		slot_cell.name = "SlotCell%d" % _slot_cells.size()
		slot_cell.custom_minimum_size = Vector2(10.0, 28.0)
		slot_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slot_bars.add_child(slot_cell)
		_slot_cells.append(slot_cell)


func _process(delta: float) -> void:
	for index in range(_floating_texts.size() - 1, -1, -1):
		var floating_text: FloatingStatText = _floating_texts[index]
		if floating_text == null or floating_text.label == null:
			_floating_texts.remove_at(index)
			continue
		floating_text.elapsed += delta
		var progress: float = clampf(floating_text.elapsed / floating_text.lifetime, 0.0, 1.0)
		floating_text.label.position += floating_text.drift * delta
		var color: Color = floating_text.label.get_theme_color("font_color")
		color.a = 1.0 - progress
		floating_text.label.add_theme_color_override("font_color", color)
		if floating_text.elapsed >= floating_text.lifetime:
			floating_text.label.queue_free()
			_floating_texts.remove_at(index)


func _emit_delta_popups(current_hp: int, current_shield: int) -> void:
	if current_hp < _last_hp:
		_spawn_floating_text("-%d" % (_last_hp - current_hp), DAMAGE_COLOR, 0.0)
	elif current_hp > _last_hp:
		_spawn_floating_text("+%d" % (current_hp - _last_hp), HEAL_COLOR, 18.0)

	if current_shield < _last_shield:
		_spawn_floating_text(Localization.get_textf("unit.shield_delta", "Shield {amount}", {
			"amount": "-%d" % (_last_shield - current_shield),
		}), SHIELD_COLOR, 32.0)
	elif current_shield > _last_shield:
		_spawn_floating_text(Localization.get_textf("unit.shield_delta", "Shield {amount}", {
			"amount": "+%d" % (current_shield - _last_shield),
		}), SHIELD_COLOR, -26.0)


func _spawn_floating_text(text: String, color: Color, x_offset: float) -> void:
	if _portrait_effect_layer == null or text == "":
		return

	var label: Label = Label.new()
	label.text = text
	label.position = Vector2(22.0 + x_offset, 68.0)
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.82))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_effect_layer.add_child(label)

	var floating_text: FloatingStatText = FloatingStatText.new()
	floating_text.label = label
	floating_text.drift = Vector2(0.0, -34.0)
	_floating_texts.append(floating_text)


func _get_portrait_texture(portrait_key: String) -> Texture2D:
	if portrait_key == "":
		return _build_placeholder_texture(_unit_side, "unknown")
	if _portrait_cache.has(portrait_key):
		return _portrait_cache[portrait_key] as Texture2D

	var path: String = PORTRAIT_PATH_TEMPLATE % portrait_key
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var resource: Resource = load(path)
		texture = resource as Texture2D
	if texture == null:
		texture = _build_placeholder_texture(_unit_side, portrait_key)
	_portrait_cache[portrait_key] = texture
	return texture


func _build_placeholder_texture(unit_side: String, portrait_key: String) -> Texture2D:
	var image: Image = Image.create(320, 320, false, Image.FORMAT_RGBA8)
	var base_hue: float = float(abs(portrait_key.hash()) % 1000) / 1000.0
	var base_color: Color = Color.from_hsv(base_hue, 0.52, 0.82, 1.0)
	if unit_side == "enemy":
		base_color = base_color.darkened(0.15)
	var accent_color: Color = base_color.lightened(0.18)
	var shadow_color: Color = base_color.darkened(0.36)

	image.fill(base_color)
	image.fill_rect(Rect2i(0, 224, 320, 96), shadow_color)
	image.fill_rect(Rect2i(32, 34, 256, 252), accent_color)
	image.fill_rect(Rect2i(92, 56, 136, 108), shadow_color)
	image.fill_rect(Rect2i(72, 168, 176, 96), shadow_color.lightened(0.10))
	image.fill_rect(Rect2i(108, 84, 38, 38), accent_color.lightened(0.08))
	image.fill_rect(Rect2i(174, 84, 38, 38), accent_color.lightened(0.08))
	return ImageTexture.create_from_image(image)


func _make_frame_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_FILL
	style.border_color = PANEL_STROKE
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	return style


func _make_hp_background_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = HP_BAR_BG
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 4
	style.content_margin_top = 4
	style.content_margin_right = 4
	style.content_margin_bottom = 4
	return style


func _make_hp_fill_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = HP_BAR_FILL
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style


func _make_shield_background_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = SHIELD_BAR_BG
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	style.content_margin_left = 3
	style.content_margin_top = 3
	style.content_margin_right = 3
	style.content_margin_bottom = 3
	return style


func _make_shield_fill_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = SHIELD_BAR_FILL
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _make_slot_cell_stylebox(is_filled: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = SLOT_USED_FILL if is_filled else SLOT_EMPTY_FILL
	style.border_color = SLOT_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style
