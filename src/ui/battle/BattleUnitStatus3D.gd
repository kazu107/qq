extends Node3D
class_name BattleUnitStatus3D

const PANEL_SIZE: Vector2 = Vector2(2.72, 1.58)
const HP_BAR_SIZE: Vector2 = Vector2(1.96, 0.22)
const HP_BAR_CENTER_X: float = 0.14
const SLOT_SIZE: Vector2 = Vector2(0.14, 0.28)
const SLOT_GAP: float = 0.07
const PANEL_COLOR: Color = Color(0.018, 0.030, 0.040, 0.92)
const HP_BACKGROUND_COLOR: Color = Color(0.14, 0.035, 0.045, 0.98)
const HP_FILL_COLOR: Color = Color(0.92, 0.12, 0.20, 1.0)
const SHIELD_COLOR: Color = Color(0.20, 0.76, 1.0, 1.0)
const TEXT_COLOR: Color = Color(0.95, 0.98, 1.0, 1.0)
const STATUS_COLOR: Color = Color(1.0, 0.82, 0.34, 1.0)

var _is_player_side: bool = false
var _accent_color: Color = Color.WHITE
var _hp_fill: MeshInstance3D
var _hp_fill_mesh: QuadMesh
var _name_label: Label3D
var _hp_label: Label3D
var _shield_label: Label3D
var _attack_label: Label3D
var _speed_label: Label3D
var _status_label: Label3D
var _slot_cells: Array[MeshInstance3D] = []
var _last_hp_ratio: float = 1.0
var _last_preview_slot_cost: int = 0
var _last_slot_overflow: int = 0


func configure(is_player_side: bool) -> void:
	_is_player_side = is_player_side
	_accent_color = Color(0.18, 0.70, 1.0, 1.0) if is_player_side else Color(1.0, 0.25, 0.20, 1.0)


func _ready() -> void:
	_build_model()


func refresh_unit(unit: UnitState, preview_slot_cost: int = 0) -> void:
	if unit == null or _hp_label == null:
		return
	var hp_value: int = maxi(0, unit.hp)
	var max_hp_value: int = maxi(1, unit.max_hp)
	_last_hp_ratio = clampf(float(hp_value) / float(max_hp_value), 0.0, 1.0)
	var fill_width: float = HP_BAR_SIZE.x * _last_hp_ratio
	_hp_fill_mesh.size = Vector2(maxf(0.001, fill_width), HP_BAR_SIZE.y)
	_hp_fill.position.x = HP_BAR_CENTER_X - HP_BAR_SIZE.x * 0.5 + fill_width * 0.5
	_hp_fill.visible = hp_value > 0
	_name_label.text = unit.display_name
	_hp_label.text = "%d / %d" % [hp_value, max_hp_value]
	_shield_label.text = "%d" % maxi(0, unit.shield)
	_attack_label.text = "%d" % unit.get_attack_value()
	_speed_label.text = "%d" % maxi(0, unit.speed)
	_refresh_slots(unit.active_slots_used, unit.active_slot_max, preview_slot_cost)
	_status_label.text = _build_status_text(unit.statuses)


func get_hp_text() -> String:
	return _hp_label.text if _hp_label != null else ""


func get_hp_ratio() -> float:
	return _last_hp_ratio


func get_status_text() -> String:
	return _status_label.text if _status_label != null else ""


func is_player_status() -> bool:
	return _is_player_side


func get_preview_slot_cost() -> int:
	return _last_preview_slot_cost


func get_preview_slot_overflow() -> int:
	return _last_slot_overflow


func _build_model() -> void:
	var panel: MeshInstance3D = _create_quad("StatusPlate", PANEL_SIZE, PANEL_COLOR, 1)
	add_child(panel)

	var accent: MeshInstance3D = _create_quad("AccentLine", Vector2(PANEL_SIZE.x, 0.055), _accent_color, 2)
	accent.position = Vector3(0.0, PANEL_SIZE.y * 0.5 - 0.045, 0.015)
	add_child(accent)

	_name_label = _create_label("UnitName3D", 30, TEXT_COLOR)
	_name_label.position = Vector3(0.0, 0.57, 0.035)
	add_child(_name_label)

	var hp_background: MeshInstance3D = _create_quad("HpBarBackground3D", HP_BAR_SIZE, HP_BACKGROUND_COLOR, 2)
	hp_background.position = Vector3(HP_BAR_CENTER_X, 0.24, 0.025)
	add_child(hp_background)

	_hp_fill_mesh = QuadMesh.new()
	_hp_fill_mesh.size = HP_BAR_SIZE
	_hp_fill = MeshInstance3D.new()
	_hp_fill.name = "HpBarFill3D"
	_hp_fill.mesh = _hp_fill_mesh
	_hp_fill.material_override = _create_billboard_material(HP_FILL_COLOR, 3)
	_hp_fill.position = Vector3(HP_BAR_CENTER_X, 0.24, 0.04)
	add_child(_hp_fill)

	var hp_icon: Sprite3D = _create_icon("HpIcon3D", "hp", Vector3(-1.10, 0.24, 0.06), 0.0062)
	add_child(hp_icon)

	_hp_label = _create_label("HpValue3D", 27, TEXT_COLOR)
	_hp_label.position = Vector3(HP_BAR_CENTER_X, 0.24, 0.07)
	add_child(_hp_label)

	var shield_icon: Sprite3D = _create_icon("ShieldIcon3D", "shield", Vector3(-1.08, -0.08, 0.06), 0.0058)
	add_child(shield_icon)
	_shield_label = _create_label("ShieldValue3D", 25, SHIELD_COLOR)
	_shield_label.position = Vector3(-0.82, -0.08, 0.07)
	add_child(_shield_label)

	var attack_icon: Sprite3D = _create_icon("AttackIcon3D", "attack", Vector3(-0.34, -0.08, 0.06), 0.0052)
	add_child(attack_icon)
	_attack_label = _create_label("AttackValue3D", 24, TEXT_COLOR)
	_attack_label.position = Vector3(-0.08, -0.08, 0.07)
	add_child(_attack_label)

	var speed_icon: Sprite3D = _create_icon("SpeedIcon3D", "speed", Vector3(0.42, -0.08, 0.06), 0.0052)
	add_child(speed_icon)
	_speed_label = _create_label("SpeedValue3D", 24, TEXT_COLOR)
	_speed_label.position = Vector3(0.68, -0.08, 0.07)
	add_child(_speed_label)

	_status_label = _create_label("StatusValue3D", 21, STATUS_COLOR)
	_status_label.position = Vector3(0.0, -0.61, 0.07)
	add_child(_status_label)


func _refresh_slots(used_slots: int, total_slots: int, preview_slot_cost: int) -> void:
	var resolved_total: int = maxi(0, total_slots)
	var resolved_used: int = clampi(used_slots, 0, resolved_total)
	_last_preview_slot_cost = maxi(0, preview_slot_cost)
	var preview_end: int = resolved_used + _last_preview_slot_cost
	_last_slot_overflow = maxi(0, preview_end - resolved_total)
	var visible_count: int = maxi(resolved_total, preview_end)
	_ensure_slot_count(visible_count)
	var total_width: float = float(maxi(0, visible_count - 1)) * (SLOT_SIZE.x + SLOT_GAP)
	for index: int in range(_slot_cells.size()):
		var cell: MeshInstance3D = _slot_cells[index]
		cell.visible = index < visible_count
		if not cell.visible:
			continue
		cell.position = Vector3(-total_width * 0.5 + float(index) * (SLOT_SIZE.x + SLOT_GAP), -0.37, 0.055)
		var color: Color = Color(0.10, 0.18, 0.22, 0.95)
		if index < resolved_used:
			color = _accent_color
		elif index < preview_end:
			color = Color(1.0, 0.28, 0.22, 1.0) if index >= resolved_total else Color(0.38, 0.95, 0.62, 1.0)
		var material: StandardMaterial3D = cell.material_override as StandardMaterial3D
		material.albedo_color = color


func _ensure_slot_count(count: int) -> void:
	while _slot_cells.size() < count:
		var cell: MeshInstance3D = _create_quad(
			"SlotCell3D%d" % _slot_cells.size(),
			SLOT_SIZE,
			Color(0.10, 0.18, 0.22, 0.95),
			3
		)
		add_child(cell)
		_slot_cells.append(cell)


func _build_status_text(statuses: Dictionary) -> String:
	var parts: Array[String] = []
	for raw_status_id: Variant in statuses.keys():
		var status_id: String = String(raw_status_id)
		var status_data: Dictionary = Dictionary(statuses.get(status_id, {}))
		var remaining: float = float(status_data.get("duration", 0.0))
		if remaining <= 0.0:
			continue
		parts.append("%s %.1fs" % [Localization.get_status_name(status_id), snappedf(remaining, 0.1)])
		if parts.size() >= 2:
			break
	return Localization.get_text("status.none", "None") if parts.is_empty() else "  ".join(parts)


func _create_quad(node_name: String, quad_size: Vector2, color: Color, priority: int) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = quad_size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = quad
	instance.material_override = _create_billboard_material(color, priority)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _create_billboard_material(color: Color, priority: int) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.no_depth_test = false
	material.render_priority = priority
	return material


func _create_label(node_name: String, font_size: int, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = node_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.render_priority = 7
	label.font_size = font_size
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.96)
	label.outline_size = 7
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _create_icon(node_name: String, icon_id: String, icon_position: Vector3, pixel_size: float) -> Sprite3D:
	var icon: Sprite3D = Sprite3D.new()
	icon.name = node_name
	icon.texture = StatIconFactory.get_icon(icon_id)
	icon.position = icon_position
	icon.pixel_size = pixel_size
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = false
	icon.render_priority = 6
	return icon
