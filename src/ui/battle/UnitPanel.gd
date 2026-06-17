extends VBoxContainer
class_name UnitPanel

const PORTRAIT_PATH_TEMPLATE := "res://assets/portraits/%s.png"
const STATUS_ICON_PATH_TEMPLATE := "res://assets/icons/status/%s.png"
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
const SLOT_PREVIEW_FILL := Color(0.38, 0.74, 1.0, 1.0)
const SLOT_PREVIEW_BORDER := Color(0.58, 0.86, 1.0, 1.0)
const SLOT_OVERFLOW_FILL := Color(1.0, 0.28, 0.23, 1.0)
const SLOT_OVERFLOW_BORDER := Color(1.0, 0.18, 0.16, 1.0)
const SLOT_PREVIEW_ALPHA_MAX: float = 0.58
const SLOT_PREVIEW_ALPHA_MIN: float = 0.32
const SLOT_PREVIEW_ALPHA_CYCLE_SECONDS: float = 1.0
const DAMAGE_COLOR := Color(1.0, 0.40, 0.35, 1.0)
const HEAL_COLOR := Color(0.48, 0.95, 0.58, 1.0)
const SHIELD_COLOR := Color(0.47, 0.82, 1.0, 1.0)
const FLOATING_TEXT_LIFETIME: float = 1.25
const FLOATING_TEXT_FADE_START: float = 0.58
const FLOATING_TEXT_FONT_SIZE: int = 32
const STATUS_ICON_SIZE: Vector2 = Vector2(26.0, 26.0)
const STATUS_BRIGHTNESS_MIN: float = 0.08
const STATUS_BRIGHTNESS_MAX: float = 1.0
const STATUS_DARKEN_ALPHA_MAX: float = 0.78
const STATUS_FALLBACK_DURATIONS: Dictionary = {
	"bleed": 36.0,
	"weak": 30.0,
	"slow": 36.0,
	"vulnerable": 30.0,
}

class FloatingStatText:
	extends RefCounted

	var control: Control
	var label: Label
	var lifetime: float = FLOATING_TEXT_LIFETIME
	var elapsed: float = 0.0
	var drift: Vector2 = Vector2.ZERO

static var _portrait_cache: Dictionary = {}
static var _status_icon_cache: Dictionary = {}

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
var _status_icons_box: HBoxContainer
var _status_none_label: Label
var _status_item_nodes: Dictionary = {}
var _status_icon_nodes: Dictionary = {}
var _status_time_labels: Dictionary = {}
var _status_darken_nodes: Dictionary = {}
var _status_hovered_id: String = ""
var _status_hovered_icon: TextureRect
var _status_tooltip_popup: PanelContainer
var _status_tooltip_label: Label
var _floating_texts: Array[FloatingStatText] = []
var _last_hp: int = -1
var _last_shield: int = -1
var _last_stat_line: String = ""
var _last_status_line: String = ""
var _has_previous_snapshot: bool = false
var _slot_preview_active: bool = false
var _slot_preview_key: String = ""
var _slot_preview_elapsed: float = 0.0
var _slot_preview_used: int = 0
var _slot_preview_total: int = 0
var _slot_preview_cost: int = 0


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
	_status_label.text = Localization.get_text("unit.status_icons", "Status")
	info_column.add_child(_status_label)

	_status_icons_box = HBoxContainer.new()
	_status_icons_box.name = "StatusIconRow"
	_status_icons_box.add_theme_constant_override("separation", 6)
	info_column.add_child(_status_icons_box)

	_status_none_label = Label.new()
	_status_none_label.name = "StatusNoneLabel"
	_status_none_label.text = Localization.get_text("status.none", "None")
	_status_none_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_icons_box.add_child(_status_none_label)

	set_process(true)


func _exit_tree() -> void:
	if _status_tooltip_popup != null and is_instance_valid(_status_tooltip_popup):
		_status_tooltip_popup.queue_free()


func set_title(title: String) -> void:
	_title_label.text = title


func configure_visual(unit_side: String, portrait_key: String) -> void:
	_unit_side = unit_side
	_portrait_key = portrait_key
	if _portrait_rect != null:
		_portrait_rect.texture = _get_portrait_texture(portrait_key)


func refresh_unit(unit: UnitState, preview_slot_cost: int = 0, suppressed_shield_loss: int = 0) -> void:
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
		_emit_delta_popups(hp_value, shield_value, suppressed_shield_loss)

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
	_refresh_slot_battery(unit.active_slots_used, unit.active_slot_max, preview_slot_cost)
	_stats_label.text = stat_line
	_status_label.text = Localization.get_text("unit.status_icons", "Status")
	_refresh_status_icons(unit.statuses)

	_last_hp = hp_value
	_last_shield = shield_value
	_last_stat_line = stat_line
	_last_status_line = status_line
	_has_previous_snapshot = true


func _refresh_status_icons(statuses: Dictionary) -> void:
	if _status_icons_box == null:
		return

	var rendered_count: int = 0
	var active_status_ids: Array[String] = []
	for raw_status_id in statuses.keys():
		var status_id: String = String(raw_status_id)
		var status_data: Dictionary = Dictionary(statuses.get(status_id, {}))
		var remaining: float = float(status_data.get("duration", 0.0))
		if remaining <= 0.0:
			continue
		active_status_ids.append(status_id)
		var reference_duration: float = _get_status_reference_duration(status_id, status_data, remaining)
		var brightness: float = _get_status_brightness(remaining, reference_duration)
		var darken_alpha: float = _get_status_darken_alpha(remaining, reference_duration)
		var icon: TextureRect = _get_or_create_status_icon(status_id)
		var time_label: Label = _status_time_labels[status_id] as Label
		var darken: ColorRect = _status_darken_nodes[status_id] as ColorRect
		icon.visible = true
		icon.texture = _get_status_icon_texture(status_id)
		icon.self_modulate = Color(brightness, brightness, brightness, 1.0)
		icon.tooltip_text = _build_status_tooltip(status_id, remaining)
		time_label.text = _format_status_remaining(remaining)
		time_label.self_modulate = Color(brightness, brightness, brightness, 1.0)
		darken.color = Color(0.0, 0.0, 0.0, darken_alpha)
		if _status_hovered_id == status_id:
			_status_hovered_icon = icon
			_show_status_tooltip(icon.tooltip_text, icon)
		rendered_count += 1

	_remove_inactive_status_icons(active_status_ids)
	if _status_none_label == null:
		_status_none_label = Label.new()
		_status_none_label.name = "StatusNoneLabel"
		_status_none_label.text = Localization.get_text("status.none", "None")
		_status_none_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_icons_box.add_child(_status_none_label)
	if rendered_count == 0:
		_status_none_label.text = Localization.get_text("status.none", "None")
		_status_none_label.visible = true
	else:
		_status_none_label.visible = false


func _get_or_create_status_icon(status_id: String) -> TextureRect:
	if _status_icon_nodes.has(status_id):
		var existing_icon: TextureRect = _status_icon_nodes[status_id] as TextureRect
		if existing_icon != null and is_instance_valid(existing_icon):
			return existing_icon

	var icon: TextureRect = TextureRect.new()
	icon.name = "StatusIcon_%s" % status_id
	icon.custom_minimum_size = STATUS_ICON_SIZE
	icon.size = STATUS_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.mouse_entered.connect(_on_status_icon_mouse_entered.bind(status_id, icon))
	icon.mouse_exited.connect(_on_status_icon_mouse_exited.bind(status_id))

	var darken: ColorRect = ColorRect.new()
	darken.name = "StatusDarken_%s" % status_id
	darken.anchor_right = 1.0
	darken.anchor_bottom = 1.0
	darken.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(darken)

	var time_label: Label = Label.new()
	time_label.name = "StatusTime_%s" % status_id
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var item: HBoxContainer = HBoxContainer.new()
	item.name = "StatusItem_%s" % status_id
	item.add_theme_constant_override("separation", 3)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(icon)
	item.add_child(time_label)
	_status_icons_box.add_child(item)

	_status_item_nodes[status_id] = item
	_status_icon_nodes[status_id] = icon
	_status_time_labels[status_id] = time_label
	_status_darken_nodes[status_id] = darken
	return icon


func _remove_inactive_status_icons(active_status_ids: Array[String]) -> void:
	for raw_status_id in _status_icon_nodes.keys():
		var status_id: String = String(raw_status_id)
		if active_status_ids.has(status_id):
			continue
		var item: HBoxContainer = _status_item_nodes[status_id] as HBoxContainer
		_status_item_nodes.erase(status_id)
		_status_icon_nodes.erase(status_id)
		_status_time_labels.erase(status_id)
		_status_darken_nodes.erase(status_id)
		if _status_hovered_id == status_id:
			_hide_status_tooltip()
		if item != null and is_instance_valid(item):
			_status_icons_box.remove_child(item)
			item.queue_free()


func _get_status_reference_duration(status_id: String, status_data: Dictionary, remaining: float) -> float:
	var reference_duration: float = float(status_data.get("max_duration", 0.0))
	if reference_duration <= 0.0:
		reference_duration = float(STATUS_FALLBACK_DURATIONS.get(status_id, remaining))
	return maxf(reference_duration, 0.1)


func _get_status_brightness(remaining: float, reference_duration: float) -> float:
	var remaining_ratio: float = clampf(remaining / maxf(reference_duration, 0.1), 0.0, 1.0)
	var eased_ratio: float = pow(remaining_ratio, 2.2)
	return lerpf(STATUS_BRIGHTNESS_MIN, STATUS_BRIGHTNESS_MAX, eased_ratio)


func _get_status_darken_alpha(remaining: float, reference_duration: float) -> float:
	var remaining_ratio: float = clampf(remaining / maxf(reference_duration, 0.1), 0.0, 1.0)
	return lerpf(STATUS_DARKEN_ALPHA_MAX, 0.0, pow(remaining_ratio, 1.25))


func _format_status_remaining(remaining: float) -> String:
	return "%.1fs" % snappedf(remaining, 0.1)


func _build_status_tooltip(status_id: String, remaining: float) -> String:
	var lines: Array[String] = [
		Localization.get_status_name(status_id),
		Localization.get_textf("status.tooltip.remaining", "Remaining: {value}s", {
			"value": "%.1f" % snappedf(remaining, 0.1),
		}),
	]
	var detail_text: String = _get_status_detail_text(status_id)
	if detail_text != "":
		lines.append(Localization.get_textf("status.tooltip.effect", "Effect: {value}", {
			"value": detail_text,
		}))
	return "\n".join(lines)


func _get_status_detail_text(status_id: String) -> String:
	match status_id:
		"bleed":
			return Localization.get_textf("status.detail.bleed", "Takes {amount} damage every {interval}s.", {
				"amount": 1,
				"interval": "%.1f" % UnitState.BLEED_TICK_INTERVAL,
			})
		"weak":
			return Localization.get_textf("status.detail.weak", "ATK -{amount} while active.", {"amount": 2})
		"slow":
			return Localization.get_textf("status.detail.slow", "Cast time +{percent}% while active.", {"percent": 10})
		"vulnerable":
			return Localization.get_textf("status.detail.vulnerable", "Incoming damage +{amount} while active.", {"amount": 3})
		_:
			return Localization.get_text("status.detail.unknown", "Temporary status effect.")


func _on_status_icon_mouse_entered(status_id: String, icon: TextureRect) -> void:
	_status_hovered_id = status_id
	_status_hovered_icon = icon
	_show_status_tooltip(icon.tooltip_text, icon)


func _on_status_icon_mouse_exited(status_id: String) -> void:
	if _status_hovered_id != status_id:
		return
	_hide_status_tooltip()


func _show_status_tooltip(text: String, anchor: Control) -> void:
	if text == "" or anchor == null:
		return
	_ensure_status_tooltip_popup()
	if _status_tooltip_popup == null or _status_tooltip_label == null:
		return
	_status_tooltip_label.text = text
	_status_tooltip_label.reset_size()
	var label_size: Vector2 = _status_tooltip_label.get_combined_minimum_size()
	var popup_size: Vector2 = label_size + Vector2(16.0, 12.0)
	_status_tooltip_popup.custom_minimum_size = Vector2.ZERO
	_status_tooltip_popup.size = popup_size
	_status_tooltip_popup.visible = true
	_status_tooltip_popup.global_position = anchor.get_global_position() + Vector2(0.0, anchor.size.y + 8.0)


func _hide_status_tooltip() -> void:
	_status_hovered_id = ""
	_status_hovered_icon = null
	if _status_tooltip_popup != null and is_instance_valid(_status_tooltip_popup):
		_status_tooltip_popup.visible = false


func _ensure_status_tooltip_popup() -> void:
	if _status_tooltip_popup != null and is_instance_valid(_status_tooltip_popup):
		return

	_status_tooltip_popup = PanelContainer.new()
	_status_tooltip_popup.name = "StatusTooltipPopup"
	_status_tooltip_popup.visible = false
	_status_tooltip_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_tooltip_popup.z_index = 140
	_status_tooltip_popup.anchor_left = 0.0
	_status_tooltip_popup.anchor_top = 0.0
	_status_tooltip_popup.anchor_right = 0.0
	_status_tooltip_popup.anchor_bottom = 0.0
	_status_tooltip_popup.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_status_tooltip_popup.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	_status_tooltip_popup.add_child(margin)

	_status_tooltip_label = Label.new()
	_status_tooltip_label.name = "StatusTooltipText"
	_status_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_status_tooltip_label)

	var owner: Node = get_tree().current_scene
	if owner == null:
		owner = get_tree().root
	owner.add_child(_status_tooltip_popup)


func _refresh_slot_battery(used_slots: int, total_slots: int, preview_slot_cost: int = 0) -> void:
	var resolved_total: int = maxi(0, total_slots)
	var resolved_used: int = clampi(used_slots, 0, resolved_total)
	var resolved_preview_cost: int = maxi(0, preview_slot_cost)
	var preview_key: String = "%d:%d:%d" % [resolved_used, resolved_total, resolved_preview_cost]
	if resolved_preview_cost > 0:
		if not _slot_preview_active or _slot_preview_key != preview_key:
			_slot_preview_elapsed = 0.0
		_slot_preview_active = true
		_slot_preview_key = preview_key
	else:
		_slot_preview_active = false
		_slot_preview_key = ""
		_slot_preview_elapsed = 0.0
	_slot_preview_used = resolved_used
	_slot_preview_total = resolved_total
	_slot_preview_cost = resolved_preview_cost
	_apply_slot_battery_styles()


func _apply_slot_battery_styles() -> void:
	var preview_end: int = _slot_preview_used + _slot_preview_cost
	var visible_count: int = maxi(_slot_preview_total, preview_end)
	var has_overflow: bool = preview_end > _slot_preview_total
	_ensure_slot_cell_count(visible_count)
	for index in range(_slot_cells.size()):
		var slot_cell: Panel = _slot_cells[index]
		var is_visible: bool = index < visible_count
		slot_cell.visible = is_visible
		if not is_visible:
			continue
		var is_used: bool = index < _slot_preview_used
		var is_preview: bool = index >= _slot_preview_used and index < preview_end
		var is_overflow_slot: bool = has_overflow and is_preview
		slot_cell.add_theme_stylebox_override("panel", _make_slot_cell_stylebox(is_used, is_preview, is_overflow_slot))


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
	if _slot_preview_active:
		_slot_preview_elapsed = fposmod(_slot_preview_elapsed + delta, SLOT_PREVIEW_ALPHA_CYCLE_SECONDS)
		_apply_slot_battery_styles()

	for index in range(_floating_texts.size() - 1, -1, -1):
		var floating_text: FloatingStatText = _floating_texts[index]
		if floating_text == null or floating_text.control == null or not is_instance_valid(floating_text.control):
			_floating_texts.remove_at(index)
			continue
		floating_text.elapsed += delta
		var progress: float = clampf(floating_text.elapsed / floating_text.lifetime, 0.0, 1.0)
		floating_text.control.position += floating_text.drift * delta
		var fade_progress: float = clampf((progress - FLOATING_TEXT_FADE_START) / (1.0 - FLOATING_TEXT_FADE_START), 0.0, 1.0)
		floating_text.control.modulate.a = 1.0 - fade_progress
		var pop_scale: float = 1.0
		if progress < 0.16:
			pop_scale = lerpf(1.18, 1.0, progress / 0.16)
		floating_text.control.scale = Vector2(pop_scale, pop_scale)
		if floating_text.elapsed >= floating_text.lifetime:
			floating_text.control.queue_free()
			_floating_texts.remove_at(index)


func _emit_delta_popups(current_hp: int, current_shield: int, suppressed_shield_loss: int = 0) -> void:
	if current_hp < _last_hp:
		_spawn_floating_text("-%d" % (_last_hp - current_hp), DAMAGE_COLOR, 0.0)
	elif current_hp > _last_hp:
		_spawn_floating_text("+%d" % (current_hp - _last_hp), HEAL_COLOR, 18.0)

	if current_shield < _last_shield:
		var shield_loss: int = _last_shield - current_shield
		var visible_shield_loss: int = max(0, shield_loss - max(0, suppressed_shield_loss))
		if visible_shield_loss <= 0:
			return
		_spawn_floating_text(Localization.get_textf("unit.shield_delta", "Shield {amount}", {
			"amount": "-%d" % visible_shield_loss,
		}), SHIELD_COLOR, 32.0)
	elif current_shield > _last_shield:
		_spawn_floating_text(Localization.get_textf("unit.shield_delta", "Shield {amount}", {
			"amount": "+%d" % (current_shield - _last_shield),
		}), SHIELD_COLOR, -26.0)


func _spawn_floating_text(text: String, color: Color, x_offset: float) -> void:
	if _portrait_effect_layer == null or text == "":
		return

	var badge: PanelContainer = PanelContainer.new()
	badge.name = "FloatingStatBadge"
	badge.position = Vector2(14.0 + x_offset, 50.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 24
	badge.add_theme_stylebox_override("panel", _make_floating_text_stylebox(color))
	_portrait_effect_layer.add_child(badge)

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_bottom", 3)
	badge.add_child(margin)

	var label: Label = Label.new()
	label.name = "FloatingStatLabel"
	label.text = text
	label.custom_minimum_size = Vector2(58.0, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FLOATING_TEXT_FONT_SIZE)
	label.add_theme_color_override("font_color", color.lightened(0.12))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.96))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.80))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(label)

	var floating_text: FloatingStatText = FloatingStatText.new()
	floating_text.control = badge
	floating_text.label = label
	floating_text.drift = Vector2(0.0, -24.0)
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


func _get_status_icon_texture(status_id: String) -> Texture2D:
	if _status_icon_cache.has(status_id):
		return _status_icon_cache[status_id] as Texture2D

	var path: String = STATUS_ICON_PATH_TEMPLATE % status_id
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var resource: Resource = load(path)
		texture = resource as Texture2D
	if texture == null:
		texture = _build_status_placeholder_texture(status_id)
	_status_icon_cache[status_id] = texture
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


func _build_status_placeholder_texture(status_id: String) -> Texture2D:
	var image: Image = Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var base_hue: float = float(abs(status_id.hash()) % 1000) / 1000.0
	image.fill(Color(0.02, 0.03, 0.04, 0.0))
	var fill_color: Color = Color.from_hsv(base_hue, 0.68, 0.88, 1.0)
	image.fill_rect(Rect2i(18, 18, 60, 60), fill_color)
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


func _make_floating_text_stylebox(accent_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var background_color: Color = accent_color.darkened(0.72)
	background_color.a = 0.84
	var border_color: Color = accent_color.lightened(0.20)
	border_color.a = 1.0
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _make_slot_cell_stylebox(is_filled: bool, is_preview: bool = false, is_overflow: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var fill_color: Color = SLOT_USED_FILL if is_filled else SLOT_EMPTY_FILL
	var border_color: Color = SLOT_BORDER
	if is_preview:
		var preview_alpha: float = _get_slot_preview_alpha()
		fill_color = SLOT_OVERFLOW_FILL if is_overflow else SLOT_PREVIEW_FILL
		border_color = SLOT_OVERFLOW_BORDER if is_overflow else SLOT_PREVIEW_BORDER
		fill_color.a = preview_alpha
		border_color.a = preview_alpha
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


func _get_slot_preview_alpha() -> float:
	var cycle_position: float = _slot_preview_elapsed / SLOT_PREVIEW_ALPHA_CYCLE_SECONDS
	if cycle_position <= 0.5:
		return lerpf(SLOT_PREVIEW_ALPHA_MAX, SLOT_PREVIEW_ALPHA_MIN, cycle_position * 2.0)
	return lerpf(SLOT_PREVIEW_ALPHA_MIN, SLOT_PREVIEW_ALPHA_MAX, (cycle_position - 0.5) * 2.0)
