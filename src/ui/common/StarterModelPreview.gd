extends SubViewportContainer
class_name StarterModelPreview

const PREVIEW_VIEWPORT_SIZE := Vector2i(640, 640)
const DEFAULT_STARTER_ID := "balanced"

var _viewport: SubViewport
var _world_root: Node3D
var _presentation_pivot: Node3D
var _actor: BattleActor3D
var _camera: Camera3D
var _selected_starter_id: String = DEFAULT_STARTER_ID
var _elapsed: float = 0.0
var _selection_swing: float = 0.0


func _ready() -> void:
	name = "StarterModelPreview"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_build_preview_world()
	_apply_starter_visual()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, TAU * 8.0)
	_selection_swing = move_toward(_selection_swing, 0.0, delta * 0.48)
	if _presentation_pivot != null:
		var idle_yaw: float = deg_to_rad(sin(_elapsed * 0.62) * 5.5)
		_presentation_pivot.rotation.y = idle_yaw + _selection_swing


func show_starter(starter_id: String) -> void:
	var resolved_id: String = starter_id if starter_id != "" else DEFAULT_STARTER_ID
	if _selected_starter_id == resolved_id and _actor != null:
		_ensure_ready_pose()
		return
	_selected_starter_id = resolved_id
	_selection_swing = deg_to_rad(-8.0)
	_apply_starter_visual()


func get_selected_starter_id() -> String:
	return _selected_starter_id


func get_preview_actor() -> BattleActor3D:
	return _actor


func get_preview_viewport() -> SubViewport:
	return _viewport


func is_preview_ready() -> bool:
	return _viewport != null and _camera != null and _actor != null and _actor.is_animation_graph_ready()


func _build_preview_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "StarterPreviewViewport"
	_viewport.size = PREVIEW_VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "StarterPreviewWorld"
	_viewport.add_child(_world_root)

	_build_environment()
	_build_display_stage()
	_build_actor()
	_build_camera()


func _build_environment() -> void:
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "StarterPreviewEnvironment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.026, 0.044, 1.0)
	environment.background_energy_multiplier = 0.78
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.38, 0.52, 0.64, 1.0)
	environment.ambient_light_energy = 0.78
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	_world_root.add_child(world_environment)

	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.name = "StarterPreviewKeyLight"
	key_light.rotation_degrees = Vector3(-46.0, -32.0, 0.0)
	key_light.light_color = Color(0.82, 0.93, 1.0, 1.0)
	key_light.light_energy = 0.92
	key_light.shadow_enabled = true
	_world_root.add_child(key_light)

	var rim_light: OmniLight3D = OmniLight3D.new()
	rim_light.name = "StarterPreviewRimLight"
	rim_light.position = Vector3(-2.1, 2.7, -1.3)
	rim_light.light_color = Color(0.20, 0.76, 1.0, 1.0)
	rim_light.light_energy = 1.65
	rim_light.omni_range = 7.0
	_world_root.add_child(rim_light)

	var warm_light: OmniLight3D = OmniLight3D.new()
	warm_light.name = "StarterPreviewWarmLight"
	warm_light.position = Vector3(2.4, 1.8, 2.2)
	warm_light.light_color = Color(1.0, 0.62, 0.24, 1.0)
	warm_light.light_energy = 0.86
	warm_light.omni_range = 6.0
	_world_root.add_child(warm_light)


func _build_display_stage() -> void:
	var stage_mesh: CylinderMesh = CylinderMesh.new()
	stage_mesh.top_radius = 1.72
	stage_mesh.bottom_radius = 1.88
	stage_mesh.height = 0.12
	stage_mesh.radial_segments = 32
	var stage_material: StandardMaterial3D = _make_material(
		Color(0.035, 0.070, 0.105, 1.0),
		Color(0.08, 0.42, 0.72, 1.0),
		0.20
	)
	_add_mesh("StarterPreviewStage", stage_mesh, Vector3(0.0, -0.05, 0.0), stage_material)

	var ring_mesh: CylinderMesh = CylinderMesh.new()
	ring_mesh.top_radius = 1.88
	ring_mesh.bottom_radius = 1.94
	ring_mesh.height = 0.035
	ring_mesh.radial_segments = 32
	var ring_material: StandardMaterial3D = _make_material(
		Color(0.05, 0.18, 0.28, 1.0),
		Color(0.18, 0.72, 1.0, 1.0),
		0.74
	)
	_add_mesh("StarterPreviewStageRing", ring_mesh, Vector3(0.0, 0.025, 0.0), ring_material)

	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(14.0, 14.0)
	var floor_material: StandardMaterial3D = _make_material(
		Color(0.008, 0.014, 0.021, 1.0),
		Color(0.0, 0.0, 0.0, 1.0),
		0.0
	)
	_add_mesh("StarterPreviewFloor", floor_mesh, Vector3(0.0, -0.12, 0.0), floor_material)


func _build_actor() -> void:
	_presentation_pivot = Node3D.new()
	_presentation_pivot.name = "StarterPreviewPivot"
	_world_root.add_child(_presentation_pivot)

	_actor = BattleActor3D.new()
	_actor.name = "StarterPreviewActor"
	_actor.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_presentation_pivot.add_child(_actor)
	_actor.capture_home_transform()
	_actor.set_animation_speed_scale(0.82)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "StarterPreviewCamera"
	_camera.position = Vector3(0.0, 1.85, 6.10)
	_camera.fov = 38.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_world_root.add_child(_camera)
	_camera.look_at(Vector3(0.0, 1.30, 0.0), Vector3.UP)
	_camera.current = true


func _apply_starter_visual() -> void:
	if _actor == null:
		return
	var profile: Dictionary = Database.get_battle_visual_profile(_selected_starter_id, "default_player")
	_actor.configure("player", _selected_starter_id, profile)
	_actor.reset_performance()
	_actor.start_timeline_stance()
	_actor.set_animation_speed_scale(0.82)
	call_deferred("_ensure_ready_pose")


func _ensure_ready_pose() -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	_actor.start_timeline_stance()


func _make_material(albedo: Color, emission: Color, emission_energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = albedo
	material.metallic = 0.46
	material.roughness = 0.34
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material


func _add_mesh(node_name: String, mesh: Mesh, world_position: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = world_position
	instance.material_override = material
	_world_root.add_child(instance)
	return instance
