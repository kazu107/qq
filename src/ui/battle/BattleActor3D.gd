extends Node3D
class_name BattleActor3D

const HUMANOID_SCENE: PackedScene = preload("res://scenes/battle/CommonBattleHumanoid3D.tscn")
const PLAYER_PRIMARY := Color(0.08, 0.42, 0.96, 1.0)
const PLAYER_ACCENT := Color(0.22, 0.88, 1.0, 1.0)
const ENEMY_PRIMARY := Color(0.76, 0.12, 0.11, 1.0)
const ENEMY_ACCENT := Color(1.0, 0.46, 0.18, 1.0)
const ACTION_IDLE: StringName = &"idle"
const ACTION_READY: StringName = &"ready"
const ACTION_CAST: StringName = &"cast"
const ACTION_ATTACK: StringName = &"attack"
const ACTION_HIT: StringName = &"hit"
const ACTION_BLOCK: StringName = &"block"
const ACTION_HEAL: StringName = &"heal"
const ACTION_SHIELD: StringName = &"shield"
const ACTION_STATUS: StringName = &"status"
const ACTION_INTERRUPT: StringName = &"interrupt"
const ACTION_VICTORY: StringName = &"victory"
const ACTION_DEFEAT: StringName = &"defeat"

const ACTION_DURATIONS: Dictionary = {
	ACTION_CAST: 0.52,
	ACTION_ATTACK: 0.72,
	ACTION_HIT: 0.50,
	ACTION_BLOCK: 0.56,
	ACTION_HEAL: 0.72,
	ACTION_SHIELD: 0.68,
	ACTION_STATUS: 0.66,
	ACTION_INTERRUPT: 0.62,
	ACTION_VICTORY: 1.10,
	ACTION_DEFEAT: 1.10,
}

static var _authored_scene_cache: Dictionary = {}

var actor_side: String = "player"
var _humanoid: CommonBattleHumanoid3D
var _authored_model: Node3D
var _authored_skeleton: Skeleton3D
var _authored_model_path: String = ""
var _authored_bone_pairs: Array[Vector2i] = []
var _platform_mesh: MeshInstance3D
var _platform_material: StandardMaterial3D
var _platform_base_scale: Vector3 = Vector3.ONE
var _visual_profile_id: String = ""
var _visual_profile: Dictionary = {}
var _elapsed: float = 0.0
var _phase_offset: float = 0.0
var _visual_built: bool = false
var _action: StringName = ACTION_IDLE
var _action_elapsed: float = 0.0
var _action_duration: float = 0.0
var _casting: bool = false
var _timeline_stance_blend: float = 0.0
var _animation_speed_scale: float = 1.0
var _defeated: bool = false
var _home_position: Vector3 = Vector3.ZERO
var _home_rotation: Vector3 = Vector3.ZERO
var _home_position_initialized: bool = false
var _last_action: StringName = ACTION_IDLE


func configure(side: String, visual_profile_id: String = "", visual_profile: Dictionary = {}) -> void:
	actor_side = side
	_phase_offset = 0.0 if actor_side == "player" else PI
	if not _visual_built:
		_build_visual()
	if visual_profile_id != "" or not visual_profile.is_empty():
		_visual_profile_id = visual_profile_id
		_visual_profile = visual_profile.duplicate(true)
	elif _visual_profile_id == "":
		_visual_profile_id = "default_player" if actor_side == "player" else "default_enemy"
		_visual_profile = _default_visual_profile()
	_apply_palette()
	set_process(true)


func configure_visual(visual_profile_id: String, visual_profile: Dictionary) -> void:
	_visual_profile_id = visual_profile_id
	_visual_profile = visual_profile.duplicate(true)
	if _visual_profile.is_empty():
		_visual_profile = _default_visual_profile()
	_apply_palette()


func _ready() -> void:
	if not _visual_built:
		configure(actor_side)
	_home_position = position
	_home_rotation = rotation
	_home_position_initialized = true


func _process(delta: float) -> void:
	var animation_delta: float = delta * _animation_speed_scale
	_elapsed = fmod(_elapsed + animation_delta, TAU * 8.0)
	_timeline_stance_blend = move_toward(
		_timeline_stance_blend,
		1.0 if _casting else 0.0,
		animation_delta * 4.8
	)
	if not _home_position_initialized:
		_home_position = position
		_home_rotation = rotation
		_home_position_initialized = true
	if _action != ACTION_IDLE and _action != ACTION_READY and _action != ACTION_CAST:
		_action_elapsed = minf(_action_elapsed + animation_delta, _action_duration)
		if _action_elapsed >= _action_duration and _action != ACTION_VICTORY and _action != ACTION_DEFEAT:
			_action = ACTION_READY if _casting else ACTION_IDLE
			_action_elapsed = 0.0
			_action_duration = 0.0
	_update_pose()


func play_action(action: StringName, duration: float = -1.0) -> void:
	if _defeated and action != ACTION_DEFEAT:
		return
	_last_action = action
	if action == ACTION_READY:
		start_timeline_stance()
		return
	if action == ACTION_CAST:
		_casting = true
		if _action == ACTION_IDLE or _action == ACTION_READY or _action == ACTION_CAST:
			_action = ACTION_CAST
			_action_elapsed = 0.0
			_action_duration = 0.0
		return
	if action == ACTION_IDLE:
		_casting = false
		_action = ACTION_IDLE
		_action_elapsed = 0.0
		_action_duration = 0.0
		return
	if action == ACTION_DEFEAT:
		_defeated = true
		_casting = false
	if action == ACTION_VICTORY:
		_casting = false
	_action = action
	_action_elapsed = 0.0
	_action_duration = duration if duration > 0.0 else float(ACTION_DURATIONS.get(action, 0.62))


func start_timeline_stance() -> void:
	if _defeated:
		return
	_casting = true
	_last_action = ACTION_READY
	if _action == ACTION_IDLE or _action == ACTION_READY or _action == ACTION_CAST:
		_action = ACTION_READY
		_action_elapsed = 0.0
		_action_duration = 0.0


func stop_timeline_stance() -> void:
	_casting = false
	if _action == ACTION_READY or _action == ACTION_CAST:
		_action = ACTION_IDLE
		_action_elapsed = 0.0
		_action_duration = 0.0


func stop_casting() -> void:
	stop_timeline_stance()


func reset_performance() -> void:
	_casting = false
	_timeline_stance_blend = 0.0
	_defeated = false
	_action = ACTION_IDLE
	_last_action = ACTION_IDLE
	_action_elapsed = 0.0
	_action_duration = 0.0
	_update_pose()


func capture_home_transform() -> void:
	_home_position = position
	_home_rotation = rotation
	_home_position_initialized = true


func get_action_name() -> String:
	return String(_action)


func get_last_action_name() -> String:
	return String(_last_action)


func is_timeline_stance_active() -> bool:
	return _casting


func get_timeline_stance_blend() -> float:
	return _timeline_stance_blend


func set_animation_speed_scale(speed_scale: float) -> void:
	_animation_speed_scale = clampf(speed_scale, 0.0, 2.0)


func get_animation_speed_scale() -> float:
	return _animation_speed_scale


func get_humanoid_model() -> CommonBattleHumanoid3D:
	return _humanoid


func is_using_authored_model() -> bool:
	return _authored_model != null and is_instance_valid(_authored_model) and _authored_skeleton != null


func get_authored_model_path() -> String:
	return _authored_model_path


func get_authored_model_root() -> Node3D:
	return _authored_model


func get_authored_skeleton() -> Skeleton3D:
	return _authored_skeleton


func get_authored_mesh_count() -> int:
	return _count_meshes(_authored_model) if _authored_model != null else 0


static func warm_authored_model_cache(profiles: Array[Dictionary]) -> int:
	for profile: Dictionary in profiles:
		var model_path: String = String(profile.get("model_scene", ""))
		if model_path != "":
			_get_authored_scene(model_path)
	return _authored_scene_cache.size()


static func get_cached_authored_model_count() -> int:
	return _authored_scene_cache.size()


func get_visual_profile_id() -> String:
	return _visual_profile_id


func get_weapon_type() -> String:
	return _humanoid.get_weapon_type() if _humanoid != null else ""


func get_offhand_type() -> String:
	return _humanoid.get_offhand_type() if _humanoid != null else ""


func get_head_type() -> String:
	return _humanoid.get_head_type() if _humanoid != null else ""


func get_back_type() -> String:
	return _humanoid.get_back_type() if _humanoid != null else ""


func get_body_scale() -> Vector3:
	return _humanoid.get_body_scale() if _humanoid != null else Vector3.ONE


func is_boss_profile() -> bool:
	return _humanoid.is_boss_profile() if _humanoid != null else false


func get_skeleton() -> Skeleton3D:
	return _humanoid.get_skeleton() if _humanoid != null else null


func get_equipment_socket(socket_id: String) -> BoneAttachment3D:
	return _humanoid.get_socket(socket_id) if _humanoid != null else null


func get_bone_pose_rotation(bone_name: String) -> Quaternion:
	return _humanoid.get_bone_rotation(bone_name) if _humanoid != null else Quaternion.IDENTITY


func get_bone_model_position(bone_name: String) -> Vector3:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return Vector3.ZERO
	var bone_index: int = skeleton.find_bone(bone_name)
	if bone_index < 0:
		return Vector3.ZERO
	return skeleton.get_bone_global_pose(bone_index).origin


func get_effect_world_position() -> Vector3:
	var chest_socket: BoneAttachment3D = get_equipment_socket("chest")
	return chest_socket.global_position if chest_socket != null else global_position + Vector3(0.0, 1.48, 0.0)


func get_weapon_world_position() -> Vector3:
	var weapon_socket: BoneAttachment3D = get_equipment_socket("right_hand")
	return weapon_socket.global_position if weapon_socket != null else get_effect_world_position()


func _build_visual() -> void:
	_visual_built = true
	_platform_material = _make_material(Color(0.06, 0.28, 0.58, 0.88), 0.7)
	var platform_mesh := CylinderMesh.new()
	platform_mesh.top_radius = 0.86
	platform_mesh.bottom_radius = 0.94
	platform_mesh.height = 0.12
	platform_mesh.radial_segments = 16
	platform_mesh.rings = 1
	_platform_mesh = _add_mesh(self, "Platform", platform_mesh, Vector3(0.0, 0.06, 0.0), _platform_material)

	_humanoid = HUMANOID_SCENE.instantiate() as CommonBattleHumanoid3D
	if _humanoid == null:
		push_error("Common battle humanoid scene could not be instantiated")
		return
	_humanoid.name = "CommonBattleHumanoid3D"
	add_child(_humanoid)


func _update_pose() -> void:
	if _humanoid == null:
		return
	var wave: float = sin(_elapsed * 2.1 + _phase_offset)
	var slow_wave: float = sin(_elapsed * 1.05 + _phase_offset)
	position = _home_position
	rotation = _home_rotation
	_humanoid.begin_pose()
	_apply_idle_pose(wave, slow_wave)
	if (_action == ACTION_IDLE or _action == ACTION_READY) and _timeline_stance_blend > 0.001:
		_apply_ready_pose(wave, slow_wave, _timeline_stance_blend)
	var action_progress: float = clampf(_action_elapsed / maxf(0.001, _action_duration), 0.0, 1.0)
	match _action:
		ACTION_READY:
			pass
		ACTION_CAST:
			_apply_cast_pose(wave)
		ACTION_ATTACK:
			_apply_attack_pose(action_progress)
		ACTION_HIT:
			_apply_hit_pose(action_progress)
		ACTION_BLOCK:
			_apply_block_pose(action_progress)
		ACTION_HEAL:
			_apply_heal_pose(action_progress)
		ACTION_SHIELD:
			_apply_shield_pose(action_progress)
		ACTION_STATUS:
			_apply_status_pose(action_progress)
		ACTION_INTERRUPT:
			_apply_interrupt_pose(action_progress)
		ACTION_VICTORY:
			_apply_victory_pose()
		ACTION_DEFEAT:
			_apply_defeat_pose(action_progress)
	var action_energy: float = 0.72
	if _action == ACTION_READY:
		action_energy = 0.94
	elif _action != ACTION_IDLE:
		action_energy = 1.18
	_humanoid.set_accent_energy(action_energy + (slow_wave + 1.0) * 0.18)
	_humanoid.finish_pose()
	_sync_authored_pose()
	if _platform_mesh != null:
		_platform_mesh.scale = _platform_base_scale * (1.0 + sin(_elapsed * 3.2) * 0.018)


func _apply_idle_pose(wave: float, slow_wave: float) -> void:
	_humanoid.set_bone_position_offset("root", Vector3(0.0, wave * 0.035, 0.0))
	_humanoid.set_bone_rotation("spine", Vector3(slow_wave * 0.012, 0.0, slow_wave * 0.020))
	_humanoid.set_bone_rotation("chest", Vector3(-slow_wave * 0.008, 0.0, -slow_wave * 0.012))
	_humanoid.set_bone_rotation("head", Vector3(0.0, slow_wave * 0.035, 0.0))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(wave * 0.028, 0.0, -0.18 - wave * 0.045))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(-wave * 0.035, 0.0, 0.22 + wave * 0.060))
	_humanoid.set_bone_rotation("left_forearm", Vector3(-0.12, 0.0, -0.04))
	_humanoid.set_bone_rotation("right_forearm", Vector3(-0.10, 0.0, 0.04))
	_humanoid.set_bone_rotation("left_upper_leg", Vector3(-wave * 0.018, 0.0, 0.0))
	_humanoid.set_bone_rotation("right_upper_leg", Vector3(wave * 0.018, 0.0, 0.0))


func _apply_ready_pose(wave: float, slow_wave: float, blend: float) -> void:
	var weight: float = smoothstep(0.0, 1.0, clampf(blend, 0.0, 1.0))
	var shift: float = sin(_elapsed * 0.72 + _phase_offset)
	var breath: float = sin(_elapsed * 1.62 + _phase_offset)
	var idle_root := Vector3(0.0, wave * 0.035, 0.0)
	var ready_root := Vector3(0.0, -0.045 + breath * 0.018, -0.025 + shift * 0.012)
	var idle_spine := Vector3(slow_wave * 0.012, 0.0, slow_wave * 0.020)
	var idle_chest := Vector3(-slow_wave * 0.008, 0.0, -slow_wave * 0.012)
	var idle_head := Vector3(0.0, slow_wave * 0.035, 0.0)
	var idle_left_upper_arm := Vector3(wave * 0.028, 0.0, -0.18 - wave * 0.045)
	var idle_right_upper_arm := Vector3(-wave * 0.035, 0.0, 0.22 + wave * 0.060)
	var idle_left_forearm := Vector3(-0.12, 0.0, -0.04)
	var idle_right_forearm := Vector3(-0.10, 0.0, 0.04)
	var idle_left_upper_leg := Vector3(-wave * 0.018, 0.0, 0.0)
	var idle_right_upper_leg := Vector3(wave * 0.018, 0.0, 0.0)

	_humanoid.set_bone_position_offset("root", idle_root.lerp(ready_root, weight))
	_humanoid.set_bone_rotation("hips", Vector3.ZERO.lerp(
		Vector3(0.08 + breath * 0.012, -0.08 + shift * 0.025, 0.0),
		weight
	))
	_humanoid.set_bone_rotation("spine", idle_spine.lerp(
		Vector3(-0.11 + breath * 0.012, 0.10 + shift * 0.025, -0.025),
		weight
	))
	_humanoid.set_bone_rotation("chest", idle_chest.lerp(
		Vector3(-0.07 - breath * 0.010, -0.08 - shift * 0.020, 0.018),
		weight
	))
	_humanoid.set_bone_rotation("head", idle_head.lerp(
		Vector3(0.035 - breath * 0.008, shift * 0.022, -0.012),
		weight
	))
	_humanoid.set_bone_rotation("left_upper_arm", idle_left_upper_arm.lerp(
		Vector3(0.62 + breath * 0.020, -0.10 + shift * 0.018, 0.22 + shift * 0.024),
		weight
	))
	_humanoid.set_bone_rotation("left_forearm", idle_left_forearm.lerp(
		Vector3(1.04 + breath * 0.018, -0.05, -0.10),
		weight
	))
	_humanoid.set_bone_rotation("right_upper_arm", idle_right_upper_arm.lerp(
		Vector3(0.68 - breath * 0.020, 0.08 - shift * 0.018, -0.28 - shift * 0.024),
		weight
	))
	_humanoid.set_bone_rotation("right_forearm", idle_right_forearm.lerp(
		Vector3(0.80 - breath * 0.018, 0.06, 0.12),
		weight
	))
	_humanoid.set_bone_rotation("left_upper_leg", idle_left_upper_leg.lerp(
		Vector3(0.14 + shift * 0.015, -0.05, -0.02),
		weight
	))
	_humanoid.set_bone_rotation("right_upper_leg", idle_right_upper_leg.lerp(
		Vector3(0.10 - shift * 0.015, 0.05, 0.02),
		weight
	))
	_humanoid.set_bone_rotation("left_lower_leg", Vector3.ZERO.lerp(Vector3(-0.18, 0.0, 0.0), weight))
	_humanoid.set_bone_rotation("right_lower_leg", Vector3.ZERO.lerp(Vector3(-0.15, 0.0, 0.0), weight))


func _apply_cast_pose(wave: float) -> void:
	_humanoid.set_bone_position_offset("root", Vector3(0.0, 0.07 + wave * 0.025, 0.0))
	_humanoid.set_bone_rotation("spine", Vector3(-0.10, wave * 0.03, 0.0))
	_humanoid.set_bone_rotation("chest", Vector3(-0.08, -wave * 0.04, 0.0))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(-0.92 + wave * 0.08, 0.0, -0.56))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(-0.92 - wave * 0.08, 0.0, 0.56))
	_humanoid.set_bone_rotation("left_forearm", Vector3(-0.48, 0.0, 0.22))
	_humanoid.set_bone_rotation("right_forearm", Vector3(-0.48, 0.0, -0.22))
	_humanoid.set_bone_rotation("head", Vector3(-0.12, 0.0, 0.0))


func _apply_attack_pose(progress: float) -> void:
	var strike: float = sin(progress * PI)
	position += -transform.basis.z * strike * 0.52
	_humanoid.set_bone_position_offset("root", Vector3(0.0, -strike * 0.04, -strike * 0.06))
	_humanoid.set_bone_rotation("hips", Vector3(0.0, -0.18 * strike, 0.0))
	_humanoid.set_bone_rotation("spine", Vector3(-0.18 * strike, -0.34 * strike, 0.04 * strike))
	_humanoid.set_bone_rotation("chest", Vector3(-0.10 * strike, -0.22 * strike, 0.0))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(-1.92 + progress * 2.82, -0.20, 0.48 - strike * 0.72))
	_humanoid.set_bone_rotation("right_forearm", Vector3(-0.72 + progress * 0.44, 0.0, -0.12))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(-0.18, 0.0, -0.48))
	_humanoid.set_bone_rotation("left_upper_leg", Vector3(0.18 * strike, 0.0, 0.0))
	_humanoid.set_bone_rotation("right_upper_leg", Vector3(-0.24 * strike, 0.0, 0.0))


func _apply_hit_pose(progress: float) -> void:
	var impact: float = sin(progress * PI)
	position += transform.basis.z * impact * 0.20
	var shake: float = sin(progress * PI * 5.0) * (1.0 - progress)
	_humanoid.set_bone_position_offset("root", Vector3(0.0, -impact * 0.08, impact * 0.04))
	_humanoid.set_bone_rotation("spine", Vector3(0.24 * impact, 0.0, shake * 0.15))
	_humanoid.set_bone_rotation("chest", Vector3(0.18 * impact, 0.0, -shake * 0.10))
	_humanoid.set_bone_rotation("head", Vector3(0.22 * impact, 0.0, -shake * 0.08))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(0.18, 0.0, -0.72))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(0.18, 0.0, 0.72))


func _apply_block_pose(progress: float) -> void:
	var brace: float = sin(minf(1.0, progress * 1.8) * PI * 0.5)
	_humanoid.set_bone_position_offset("root", Vector3(0.0, -brace * 0.08, brace * 0.04))
	_humanoid.set_bone_rotation("spine", Vector3(0.12 * brace, 0.10 * brace, 0.0))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(-1.28, -0.28, -0.62))
	_humanoid.set_bone_rotation("left_forearm", Vector3(-0.72, 0.0, 0.22))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(-0.14, 0.0, 0.52))
	_humanoid.set_bone_rotation("left_upper_leg", Vector3(0.18 * brace, 0.0, 0.0))
	_humanoid.set_bone_rotation("right_upper_leg", Vector3(0.12 * brace, 0.0, 0.0))
	_humanoid.set_shield_pulse(1.06, 1.8 + sin(progress * PI * 4.0) * 0.24)


func _apply_heal_pose(progress: float) -> void:
	var lift: float = sin(progress * PI)
	_humanoid.set_bone_position_offset("root", Vector3(0.0, lift * 0.16, 0.0))
	_humanoid.set_bone_rotation("spine", Vector3(-0.10 * lift, 0.0, 0.0))
	_humanoid.set_bone_rotation("head", Vector3(-0.16 * lift, 0.0, 0.0))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(-1.34, 0.0, -0.84))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(-1.34, 0.0, 0.84))
	_humanoid.set_bone_rotation("left_forearm", Vector3(-0.36, 0.0, 0.18))
	_humanoid.set_bone_rotation("right_forearm", Vector3(-0.36, 0.0, -0.18))


func _apply_shield_pose(progress: float) -> void:
	var pulse: float = sin(progress * PI)
	_humanoid.set_bone_rotation("spine", Vector3(-0.06, 0.12, 0.0))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(-1.28, -0.24, -0.50))
	_humanoid.set_bone_rotation("left_forearm", Vector3(-0.64, 0.0, 0.18))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(-0.36, 0.0, 0.52))
	_humanoid.set_shield_pulse(1.0 + pulse * 0.34, 1.45 + pulse * 1.15)


func _apply_status_pose(progress: float) -> void:
	var pulse: float = sin(progress * PI * 3.0) * (1.0 - progress)
	_humanoid.set_bone_position_offset("root", Vector3(0.0, absf(pulse) * 0.07, 0.0))
	_humanoid.set_bone_rotation("hips", Vector3(0.0, -pulse * 0.12, 0.0))
	_humanoid.set_bone_rotation("spine", Vector3(0.0, pulse * 0.22, pulse * 0.06))
	_humanoid.set_bone_rotation("chest", Vector3(0.0, -pulse * 0.30, -pulse * 0.06))
	_humanoid.set_bone_rotation("head", Vector3(0.0, pulse * 0.18, 0.0))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(-0.48, 0.0, -0.50))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(-0.48, 0.0, 0.50))


func _apply_interrupt_pose(progress: float) -> void:
	var recoil: float = sin(progress * PI)
	var shake: float = sin(progress * PI * 6.0) * (1.0 - progress)
	_humanoid.set_bone_position_offset("root", Vector3(0.0, -recoil * 0.12, recoil * 0.06))
	_humanoid.set_bone_rotation("spine", Vector3(recoil * 0.18, shake * 0.10, shake * 0.20))
	_humanoid.set_bone_rotation("chest", Vector3(recoil * 0.12, -shake * 0.14, -shake * 0.12))
	_humanoid.set_bone_rotation("head", Vector3(recoil * 0.20, 0.0, shake * 0.16))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(0.16, 0.0, -0.82 + recoil * 0.28))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(0.16, 0.0, 0.82 - recoil * 0.28))


func _apply_victory_pose() -> void:
	var celebration: float = absf(sin(_elapsed * 2.8))
	_humanoid.set_bone_position_offset("root", Vector3(0.0, 0.10 + celebration * 0.09, 0.0))
	_humanoid.set_bone_rotation("spine", Vector3(-0.10, sin(_elapsed * 1.6) * 0.08, 0.0))
	_humanoid.set_bone_rotation("head", Vector3(-0.16, 0.0, 0.0))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(-2.08, 0.0, -0.52))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(-2.08, 0.0, 0.52))
	_humanoid.set_bone_rotation("left_forearm", Vector3(-0.42, 0.0, 0.0))
	_humanoid.set_bone_rotation("right_forearm", Vector3(-0.42, 0.0, 0.0))


func _apply_defeat_pose(progress: float) -> void:
	var fall: float = _ease_out_cubic(progress)
	rotation.z = _home_rotation.z + (1.20 if actor_side == "player" else -1.20) * fall
	position.y = _home_position.y - fall * 0.44
	_humanoid.set_bone_position_offset("root", Vector3(0.0, -fall * 0.18, fall * 0.06))
	_humanoid.set_bone_rotation("spine", Vector3(fall * 0.28, 0.0, 0.0))
	_humanoid.set_bone_rotation("head", Vector3(fall * 0.35, 0.0, 0.0))
	_humanoid.set_bone_rotation("left_upper_arm", Vector3(0.30 * fall, 0.0, -0.46))
	_humanoid.set_bone_rotation("right_upper_arm", Vector3(0.30 * fall, 0.0, 0.46))


func _apply_palette() -> void:
	var default_primary: Color = PLAYER_PRIMARY if actor_side == "player" else ENEMY_PRIMARY
	var default_accent: Color = PLAYER_ACCENT if actor_side == "player" else ENEMY_ACCENT
	var primary: Color = Color.from_string(String(_visual_profile.get("primary", "")), default_primary)
	var accent: Color = Color.from_string(String(_visual_profile.get("accent", "")), default_accent)
	if _humanoid != null:
		_humanoid.configure_visual(_visual_profile_id, _visual_profile)
		var body_scale: Vector3 = _humanoid.get_body_scale()
		_platform_base_scale = Vector3(maxf(1.0, body_scale.x * 0.94), 1.0, maxf(1.0, body_scale.z * 0.94))
	if _platform_material != null:
		var team_primary: Color = PLAYER_PRIMARY if actor_side == "player" else ENEMY_PRIMARY
		var team_accent: Color = PLAYER_ACCENT if actor_side == "player" else ENEMY_ACCENT
		_platform_material.albedo_color = team_primary.darkened(0.32)
		_platform_material.emission = team_accent.darkened(0.32)
	_configure_authored_model()


func _configure_authored_model() -> void:
	var model_path: String = String(_visual_profile.get("model_scene", ""))
	if model_path == "":
		_clear_authored_model()
		_set_procedural_geometry_visible(true)
		return
	if model_path == _authored_model_path and is_using_authored_model():
		_authored_model.scale = _humanoid.get_body_scale()
		_set_procedural_geometry_visible(false)
		_sync_authored_pose()
		return

	_clear_authored_model()
	var authored_scene: PackedScene = _get_authored_scene(model_path)
	if authored_scene == null:
		push_warning("Authored battle model could not be loaded: %s" % model_path)
		_set_procedural_geometry_visible(true)
		return
	_authored_model = authored_scene.instantiate() as Node3D
	if _authored_model == null:
		push_warning("Authored battle model is not a Node3D: %s" % model_path)
		_set_procedural_geometry_visible(true)
		return
	_authored_model.name = "AuthoredBattleModel"
	_authored_model.scale = _humanoid.get_body_scale()
	add_child(_authored_model)
	_authored_skeleton = _find_skeleton(_authored_model)
	if _authored_skeleton == null:
		push_warning("Authored battle model has no Skeleton3D: %s" % model_path)
		_clear_authored_model()
		_set_procedural_geometry_visible(true)
		return
	_authored_model_path = model_path
	_build_authored_bone_pairs()
	if _authored_bone_pairs.is_empty():
		push_warning("Authored battle model has no compatible bones: %s" % model_path)
		_clear_authored_model()
		_set_procedural_geometry_visible(true)
		return
	_set_procedural_geometry_visible(false)
	_sync_authored_pose()


func _clear_authored_model() -> void:
	_authored_bone_pairs.clear()
	_authored_skeleton = null
	_authored_model_path = ""
	if _authored_model != null and is_instance_valid(_authored_model):
		_authored_model.free()
	_authored_model = null


func _build_authored_bone_pairs() -> void:
	_authored_bone_pairs.clear()
	var source_skeleton: Skeleton3D = _humanoid.get_skeleton() if _humanoid != null else null
	if source_skeleton == null or _authored_skeleton == null:
		return
	for source_index in range(source_skeleton.get_bone_count()):
		var bone_name: String = source_skeleton.get_bone_name(source_index)
		var target_index: int = _authored_skeleton.find_bone(bone_name)
		if target_index >= 0:
			_authored_bone_pairs.append(Vector2i(source_index, target_index))


func _sync_authored_pose() -> void:
	if not is_using_authored_model() or _humanoid == null:
		return
	var source_skeleton: Skeleton3D = _humanoid.get_skeleton()
	if source_skeleton == null:
		return
	for bone_pair: Vector2i in _authored_bone_pairs:
		_authored_skeleton.set_bone_pose_position(
			bone_pair.y,
			source_skeleton.get_bone_pose_position(bone_pair.x)
		)
		_authored_skeleton.set_bone_pose_rotation(
			bone_pair.y,
			source_skeleton.get_bone_pose_rotation(bone_pair.x)
		)
		_authored_skeleton.set_bone_pose_scale(
			bone_pair.y,
			source_skeleton.get_bone_pose_scale(bone_pair.x)
		)
	_authored_skeleton.force_update_all_bone_transforms()


func _set_procedural_geometry_visible(geometry_visible: bool) -> void:
	if _humanoid == null:
		return
	var geometry_nodes: Array[Node] = _humanoid.find_children("*", "MeshInstance3D", true, false)
	for geometry_node: Node in geometry_nodes:
		var mesh_instance: MeshInstance3D = geometry_node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.visible = geometry_visible


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _count_meshes(root: Node) -> int:
	if root == null:
		return 0
	var count: int = 1 if root is MeshInstance3D else 0
	for child: Node in root.get_children():
		count += _count_meshes(child)
	return count


static func _get_authored_scene(model_path: String) -> PackedScene:
	if model_path == "" or not model_path.begins_with("res://"):
		return null
	if _authored_scene_cache.has(model_path):
		return _authored_scene_cache[model_path] as PackedScene
	if not ResourceLoader.exists(model_path, "PackedScene"):
		return null
	var packed_scene: PackedScene = load(model_path) as PackedScene
	if packed_scene != null:
		_authored_scene_cache[model_path] = packed_scene
	return packed_scene


func _default_visual_profile() -> Dictionary:
	var primary: Color = PLAYER_PRIMARY if actor_side == "player" else ENEMY_PRIMARY
	var accent: Color = PLAYER_ACCENT if actor_side == "player" else ENEMY_ACCENT
	return {
		"primary": primary.to_html(false),
		"secondary": CommonBattleHumanoid3D.ARMOR_DARK.to_html(false),
		"accent": accent.to_html(false),
		"body_scale": [1.0, 1.0, 1.0],
		"weapon": "blade",
		"offhand": "shield",
		"head": "visor",
		"back": "power_pack",
		"boss": false,
	}


func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh, local_position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _make_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.34
	material.roughness = 0.52
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material


func _ease_out_cubic(value: float) -> float:
	var inverse: float = 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - inverse * inverse * inverse
