extends SubViewportContainer
class_name BattleStage3D

const DEFAULT_VIEWPORT_SIZE := Vector2i(960, 540)
const TILE_COLUMNS: int = 7
const TILE_ROWS: int = 5

var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D
var _player_actor: BattleActor3D
var _enemy_actor: BattleActor3D


func _ready() -> void:
	name = "BattleStage3D"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_build_stage()


func _build_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "BattleStageViewport"
	_viewport.size = DEFAULT_VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "BattleStageWorld"
	_viewport.add_child(_world_root)

	_build_environment()
	_build_arena()
	_build_actors()
	_build_camera()


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "BattleWorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.035, 0.055, 1.0)
	environment.background_energy_multiplier = 0.82
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.48, 0.64, 1.0)
	environment.ambient_light_energy = 0.72
	world_environment.environment = environment
	_world_root.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "BattleKeyLight"
	key_light.rotation_degrees = Vector3(-54.0, -32.0, 0.0)
	key_light.light_color = Color(0.84, 0.91, 1.0, 1.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	_world_root.add_child(key_light)

	var warm_fill := OmniLight3D.new()
	warm_fill.name = "BattleWarmFill"
	warm_fill.position = Vector3(-3.5, 3.2, -1.5)
	warm_fill.light_color = Color(1.0, 0.45, 0.22, 1.0)
	warm_fill.light_energy = 1.25
	warm_fill.omni_range = 7.0
	warm_fill.shadow_enabled = false
	_world_root.add_child(warm_fill)


func _build_arena() -> void:
	var base_material: StandardMaterial3D = _make_material(Color(0.025, 0.075, 0.09, 1.0), 0.0)
	var tile_a: StandardMaterial3D = _make_material(Color(0.075, 0.14, 0.16, 1.0), 0.0)
	var tile_b: StandardMaterial3D = _make_material(Color(0.055, 0.105, 0.13, 1.0), 0.0)
	var blue_line: StandardMaterial3D = _make_material(Color(0.08, 0.62, 0.92, 1.0), 0.78)
	var red_line: StandardMaterial3D = _make_material(Color(0.92, 0.20, 0.12, 1.0), 0.72)
	var prop_material: StandardMaterial3D = _make_material(Color(0.07, 0.09, 0.12, 1.0), 0.0)

	var arena_base := BoxMesh.new()
	arena_base.size = Vector3(13.4, 0.28, 8.4)
	_add_mesh("ArenaBase", arena_base, Vector3(0.0, -0.14, 0.0), base_material)

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(1.62, 0.10, 1.30)
	for row in range(TILE_ROWS):
		for column in range(TILE_COLUMNS):
			var tile_x: float = (float(column) - float(TILE_COLUMNS - 1) * 0.5) * 1.76
			var tile_z: float = (float(row) - float(TILE_ROWS - 1) * 0.5) * 1.44
			var tile_name: String = "ArenaTile_%d_%d" % [column, row]
			_add_mesh(tile_name, tile_mesh, Vector3(tile_x, 0.01, tile_z), tile_a if (column + row) % 2 == 0 else tile_b)

	var lane_mesh := BoxMesh.new()
	lane_mesh.size = Vector3(0.08, 0.025, 6.96)
	_add_mesh("PlayerLaneGlow", lane_mesh, Vector3(0.88, 0.08, 0.0), blue_line)
	_add_mesh("EnemyLaneGlow", lane_mesh, Vector3(-0.88, 0.08, 0.0), red_line)

	var divider_mesh := BoxMesh.new()
	divider_mesh.size = Vector3(10.62, 0.028, 0.055)
	_add_mesh("CenterDivider", divider_mesh, Vector3(0.0, 0.085, 0.0), _make_material(Color(0.46, 0.72, 0.78, 1.0), 0.46))

	var prop_mesh := BoxMesh.new()
	prop_mesh.size = Vector3(1.0, 1.0, 1.0)
	var prop_positions: Array[Vector3] = [
		Vector3(-5.6, 0.5, -3.7),
		Vector3(-4.3, 0.34, -3.85),
		Vector3(5.5, 0.46, -3.7),
		Vector3(4.2, 0.28, -3.9),
	]
	var prop_scales: Array[Vector3] = [
		Vector3(0.9, 1.0, 0.9),
		Vector3(0.62, 0.68, 0.62),
		Vector3(0.82, 0.92, 0.82),
		Vector3(0.54, 0.56, 0.54),
	]
	for index in range(prop_positions.size()):
		var prop: MeshInstance3D = _add_mesh("ArenaProp_%d" % index, prop_mesh, prop_positions[index], prop_material)
		prop.scale = prop_scales[index]


func _build_actors() -> void:
	_enemy_actor = BattleActor3D.new()
	_enemy_actor.name = "EnemyBattleActor3D"
	_enemy_actor.configure("enemy")
	_enemy_actor.position = Vector3(-2.55, 0.08, -0.75)
	_world_root.add_child(_enemy_actor)

	_player_actor = BattleActor3D.new()
	_player_actor.name = "PlayerBattleActor3D"
	_player_actor.configure("player")
	_player_actor.position = Vector3(2.55, 0.08, 0.85)
	_world_root.add_child(_player_actor)

	_enemy_actor.look_at(_player_actor.position, Vector3.UP)
	_player_actor.look_at(_enemy_actor.position, Vector3.UP)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "BattleStageCamera"
	_camera.position = Vector3(0.0, 7.4, 10.6)
	_camera.fov = 42.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_world_root.add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.82, -0.15), Vector3.UP)
	_camera.current = true


func _add_mesh(
	node_name: String,
	mesh: Mesh,
	world_position: Vector3,
	material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = world_position
	instance.material_override = material
	_world_root.add_child(instance)
	return instance


func _make_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.14
	material.roughness = 0.74
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
