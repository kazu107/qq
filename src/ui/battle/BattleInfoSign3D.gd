extends Node3D
class_name BattleInfoSign3D

const BOARD_SIZE: Vector3 = Vector3(3.05, 2.10, 0.14)
const CORNER_RADIUS: float = 0.17
const FRAME_THICKNESS: float = 0.038
const FRAME_COLOR: Color = Color(0.27, 0.37, 0.46, 0.82)
const BOARD_COLOR: Color = Color(0.055, 0.065, 0.080, 0.94)
const TEXT_COLOR: Color = Color(0.94, 0.98, 1.0, 1.0)
const ACCENT_COLOR: Color = Color(1.0, 0.70, 0.30, 1.0)
const READY_COLOR: Color = Color(0.42, 0.95, 0.70, 1.0)

var _title_label: Label3D
var _info_label: Label3D
var _fatigue_label: Label3D
var _ready_label: Label3D
var _countdown_label: Label3D
var _transient_label: Label3D


func _ready() -> void:
	_build_sign()


func refresh_content(
	info_text: String,
	fatigue_text: String,
	ready_text: String,
	ready_visible: bool,
	countdown_text: String,
	countdown_visible: bool,
	transient_text: String,
	transient_visible: bool
) -> void:
	_info_label.text = info_text
	_fatigue_label.text = fatigue_text
	_ready_label.text = ready_text
	_ready_label.visible = ready_visible
	_countdown_label.text = countdown_text
	_countdown_label.visible = countdown_visible
	_transient_label.text = transient_text
	_transient_label.visible = transient_visible
	var compact_mode: bool = ready_visible or countdown_visible or transient_visible
	_info_label.position.y = -0.08 if compact_mode else -0.02
	_fatigue_label.position.y = -0.72


func get_button_anchor_world_position() -> Vector3:
	return to_global(Vector3(0.0, 0.47, 0.14))


func get_toggle_anchor_world_position() -> Vector3:
	return to_global(Vector3(0.0, -0.80, 0.14))


func get_board_size() -> Vector3:
	return BOARD_SIZE


func _build_sign() -> void:
	var board_material: StandardMaterial3D = _make_material(BOARD_COLOR, true)
	var frame_material: StandardMaterial3D = _make_material(FRAME_COLOR, false)
	var board_horizontal_mesh: BoxMesh = BoxMesh.new()
	board_horizontal_mesh.size = Vector3(BOARD_SIZE.x - CORNER_RADIUS * 2.0, BOARD_SIZE.y, BOARD_SIZE.z)
	var board: MeshInstance3D = MeshInstance3D.new()
	board.name = "BattleInfoBoard"
	board.mesh = board_horizontal_mesh
	board.material_override = board_material
	add_child(board)

	var board_vertical_mesh: BoxMesh = BoxMesh.new()
	board_vertical_mesh.size = Vector3(BOARD_SIZE.x, BOARD_SIZE.y - CORNER_RADIUS * 2.0, BOARD_SIZE.z)
	var board_vertical: MeshInstance3D = MeshInstance3D.new()
	board_vertical.name = "BattleInfoBoardVertical"
	board_vertical.mesh = board_vertical_mesh
	board_vertical.material_override = board_material
	add_child(board_vertical)

	var horizontal_frame_mesh: BoxMesh = BoxMesh.new()
	horizontal_frame_mesh.size = Vector3(BOARD_SIZE.x - CORNER_RADIUS * 2.0, FRAME_THICKNESS, BOARD_SIZE.z + 0.035)
	for frame_y: float in [-BOARD_SIZE.y * 0.5 + FRAME_THICKNESS * 0.5, BOARD_SIZE.y * 0.5 - FRAME_THICKNESS * 0.5]:
		var horizontal_frame: MeshInstance3D = MeshInstance3D.new()
		horizontal_frame.name = "BattleInfoFrameHorizontal"
		horizontal_frame.mesh = horizontal_frame_mesh
		horizontal_frame.position = Vector3(0.0, frame_y, 0.01)
		horizontal_frame.material_override = frame_material
		add_child(horizontal_frame)

	var vertical_frame_mesh: BoxMesh = BoxMesh.new()
	vertical_frame_mesh.size = Vector3(FRAME_THICKNESS, BOARD_SIZE.y - CORNER_RADIUS * 2.0, BOARD_SIZE.z + 0.035)
	for frame_x: float in [-BOARD_SIZE.x * 0.5 + FRAME_THICKNESS * 0.5, BOARD_SIZE.x * 0.5 - FRAME_THICKNESS * 0.5]:
		var vertical_frame: MeshInstance3D = MeshInstance3D.new()
		vertical_frame.name = "BattleInfoFrameVertical"
		vertical_frame.mesh = vertical_frame_mesh
		vertical_frame.position = Vector3(frame_x, 0.0, 0.01)
		vertical_frame.material_override = frame_material
		add_child(vertical_frame)

	var corner_mesh: CylinderMesh = CylinderMesh.new()
	corner_mesh.top_radius = CORNER_RADIUS
	corner_mesh.bottom_radius = CORNER_RADIUS
	corner_mesh.height = BOARD_SIZE.z
	corner_mesh.radial_segments = 16
	for corner_x: float in [-BOARD_SIZE.x * 0.5 + CORNER_RADIUS, BOARD_SIZE.x * 0.5 - CORNER_RADIUS]:
		for corner_y: float in [-BOARD_SIZE.y * 0.5 + CORNER_RADIUS, BOARD_SIZE.y * 0.5 - CORNER_RADIUS]:
			var corner: MeshInstance3D = MeshInstance3D.new()
			corner.name = "BattleInfoRoundedCorner"
			corner.mesh = corner_mesh
			corner.position = Vector3(corner_x, corner_y, 0.0)
			corner.rotation_degrees.x = 90.0
			corner.material_override = board_material
			add_child(corner)

	var post_mesh: BoxMesh = BoxMesh.new()
	post_mesh.size = Vector3(0.13, 1.52, 0.17)
	for post_x: float in [-1.04, 1.04]:
		var post: MeshInstance3D = MeshInstance3D.new()
		post.name = "BattleInfoPost"
		post.mesh = post_mesh
		post.position = Vector3(post_x, -1.74, -0.02)
		post.material_override = _make_material(Color(0.16, 0.24, 0.23, 1.0), false)
		add_child(post)

	var foot_mesh: BoxMesh = BoxMesh.new()
	foot_mesh.size = Vector3(0.52, 0.10, 0.46)
	for foot_x: float in [-1.04, 1.04]:
		var foot: MeshInstance3D = MeshInstance3D.new()
		foot.name = "BattleInfoFoot"
		foot.mesh = foot_mesh
		foot.position = Vector3(foot_x, -2.48, 0.02)
		foot.material_override = _make_material(Color(0.12, 0.18, 0.18, 1.0), false)
		add_child(foot)

	_title_label = _create_label("BattleInfoTitle3D", 22, TEXT_COLOR)
	_title_label.text = Localization.get_text("battle.section.battle", "Battle")
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.position = Vector3(-1.32, 0.82, 0.11)
	add_child(_title_label)

	_info_label = _create_label("BattleInfoText3D", 20, TEXT_COLOR)
	_info_label.position = Vector3(0.0, -0.02, 0.11)
	add_child(_info_label)

	_fatigue_label = _create_label("BattleInfoFatigue3D", 20, ACCENT_COLOR)
	_fatigue_label.position = Vector3(0.0, -0.72, 0.11)
	add_child(_fatigue_label)

	_ready_label = _create_label("BattleInfoReady3D", 20, READY_COLOR)
	_ready_label.position = Vector3(0.0, 0.34, 0.12)
	_ready_label.visible = false
	add_child(_ready_label)

	_countdown_label = _create_label("BattleInfoCountdown3D", 34, ACCENT_COLOR)
	_countdown_label.position = Vector3(0.0, 0.35, 0.13)
	_countdown_label.visible = false
	add_child(_countdown_label)

	_transient_label = _create_label("BattleInfoTransient3D", 20, ACCENT_COLOR)
	_transient_label.position = Vector3(0.0, -0.88, 0.12)
	_transient_label.visible = false
	add_child(_transient_label)


func _create_label(node_name: String, font_size: int, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = node_name
	label.font = UiTheme.GAME_FONT
	label.font_size = font_size
	label.pixel_size = 0.0058
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.98)
	label.outline_size = 7
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.no_depth_test = false
	label.render_priority = 4
	return label


func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = false
	return material
