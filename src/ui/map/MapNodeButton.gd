extends Button
class_name MapNodeButton

signal node_selected(node_id: String)

const STATUS_COLORS := {
	"available": Color(0.28, 0.63, 0.42, 1.0),
	"selected": Color(0.22, 0.48, 0.88, 1.0),
	"completed": Color(0.80, 0.68, 0.28, 1.0),
	"skipped": Color(0.44, 0.44, 0.47, 1.0),
	"locked": Color(0.24, 0.25, 0.29, 1.0),
}

const TYPE_TINTS := {
	"normal_battle": Color(0.93, 0.51, 0.37, 1.0),
	"elite_battle": Color(0.90, 0.24, 0.55, 1.0),
	"boss": Color(0.86, 0.24, 0.24, 1.0),
	"shop": Color(0.28, 0.72, 0.77, 1.0),
	"forge": Color(0.90, 0.57, 0.22, 1.0),
	"heal": Color(0.34, 0.80, 0.54, 1.0),
	"event": Color(0.73, 0.66, 0.28, 1.0),
	"hazard": Color(0.72, 0.30, 0.20, 1.0),
}

var _node_id: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(170.0, 100.0)
	focus_mode = Control.FOCUS_NONE
	flat = true
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


func bind(node_data: Dictionary, step_label: String, is_current_step: bool) -> void:
	_node_id = String(node_data.get("id", ""))

	var node_type: String = String(node_data.get("type", ""))
	var node_label: String = Localization.get_node_label(node_data)
	var status: String = String(node_data.get("status", "locked"))
	var title_prefix: String = ""
	if is_current_step:
		title_prefix = "%s\n" % Localization.get_text("map.node.next_prefix", "Next")

	text = "%s%s\n%s" % [title_prefix, node_label, _status_text(status)]
	disabled = status != "available"
	tooltip_text = "\n".join([
		step_label,
		Localization.get_textf("map.node.tooltip.type", "Type: {value}", {"value": _type_text(node_type)}),
		Localization.get_textf("map.node.tooltip.status", "Status: {value}", {"value": _status_text(status)}),
	])
	_apply_style(node_type, status, is_current_step)


func _on_pressed() -> void:
	if _node_id == "" or disabled:
		return
	node_selected.emit(_node_id)


func _apply_style(node_type: String, status: String, is_current_step: bool) -> void:
	var base_color: Color = TYPE_TINTS.get(node_type, Color(0.55, 0.55, 0.60, 1.0))
	var status_color: Color = STATUS_COLORS.get(status, Color(0.24, 0.25, 0.29, 1.0))
	var border_color: Color = base_color.lerp(status_color, 0.45)
	if is_current_step and status == "available":
		border_color = border_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.20)

	add_theme_stylebox_override("normal", _make_stylebox(status_color.darkened(0.25), border_color, 2))
	add_theme_stylebox_override("hover", _make_stylebox(status_color.darkened(0.15), border_color.lightened(0.20), 3))
	add_theme_stylebox_override("pressed", _make_stylebox(status_color.darkened(0.10), base_color.lightened(0.25), 3))
	add_theme_stylebox_override("disabled", _make_stylebox(status_color.darkened(0.30), border_color.darkened(0.15), 2))
	add_theme_color_override("font_color", Color(0.96, 0.95, 0.92, 1.0))
	add_theme_color_override("font_disabled_color", Color(0.72, 0.72, 0.72, 1.0))


func _make_stylebox(fill_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.shadow_size = 4
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	return style


func _status_text(status: String) -> String:
	match status:
		"available":
			return Localization.get_node_status_name("available")
		"selected":
			return Localization.get_node_status_name("selected")
		"completed":
			return Localization.get_node_status_name("completed")
		"skipped":
			return Localization.get_node_status_name("skipped")
		_:
			return Localization.get_node_status_name("locked")


func _type_text(node_type: String) -> String:
	match node_type:
		"normal_battle":
			return Localization.get_node_type_name("normal_battle")
		"elite_battle":
			return Localization.get_node_type_name("elite_battle")
		"boss":
			return Localization.get_node_type_name("boss")
		"shop":
			return Localization.get_node_type_name("shop")
		"forge":
			return Localization.get_node_type_name("forge")
		"heal":
			return Localization.get_node_type_name("heal")
		"event":
			return Localization.get_node_type_name("event")
		"hazard":
			return Localization.get_node_type_name("hazard")
		_:
			return node_type.capitalize()
