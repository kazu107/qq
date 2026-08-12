extends Node3D
class_name BattleActor3D

const PLAYER_PRIMARY := Color(0.08, 0.42, 0.96, 1.0)
const PLAYER_ACCENT := Color(0.22, 0.88, 1.0, 1.0)
const ENEMY_PRIMARY := Color(0.76, 0.12, 0.11, 1.0)
const ENEMY_ACCENT := Color(1.0, 0.46, 0.18, 1.0)
const ARMOR_DARK := Color(0.045, 0.065, 0.09, 1.0)
const ACTION_IDLE: StringName = &"idle"
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

var actor_side: String = "player"
var _body_pivot: Node3D
var _left_arm_pivot: Node3D
var _right_arm_pivot: Node3D
var _platform_mesh: MeshInstance3D
var _shield_mesh: MeshInstance3D
var _shield_core_mesh: MeshInstance3D
var _platform_material: StandardMaterial3D
var _primary_material: StandardMaterial3D
var _accent_material: StandardMaterial3D
var _shield_material: StandardMaterial3D
var _elapsed: float = 0.0
var _phase_offset: float = 0.0
var _visual_built: bool = false
var _action: StringName = ACTION_IDLE
var _action_elapsed: float = 0.0
var _action_duration: float = 0.0
var _casting: bool = false
var _defeated: bool = false
var _home_position: Vector3 = Vector3.ZERO
var _home_rotation: Vector3 = Vector3.ZERO
var _home_position_initialized: bool = false
var _last_action: StringName = ACTION_IDLE


func configure(side: String) -> void:
	actor_side = side
	_phase_offset = 0.0 if actor_side == "player" else PI
	if not _visual_built:
		_build_visual()
	_apply_palette()
	set_process(true)


func _ready() -> void:
	if not _visual_built:
		configure(actor_side)
	_home_position = position
	_home_rotation = rotation
	_home_position_initialized = true


func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, TAU * 8.0)
	if not _home_position_initialized:
		_home_position = position
		_home_position_initialized = true
	if _action != ACTION_IDLE and _action != ACTION_CAST:
		_action_elapsed = minf(_action_elapsed + delta, _action_duration)
		if _action_elapsed >= _action_duration and _action != ACTION_VICTORY and _action != ACTION_DEFEAT:
			_action = ACTION_CAST if _casting else ACTION_IDLE
			_action_elapsed = 0.0
			_action_duration = 0.0
	_update_pose()


func play_action(action: StringName, duration: float = -1.0) -> void:
	if _defeated and action != ACTION_DEFEAT:
		return
	_last_action = action
	if action == ACTION_CAST:
		_casting = true
		if _action == ACTION_IDLE or _action == ACTION_CAST:
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


func stop_casting() -> void:
	_casting = false
	if _action == ACTION_CAST:
		play_action(ACTION_IDLE)


func reset_performance() -> void:
	_casting = false
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


func _build_visual() -> void:
	_visual_built = true
	_primary_material = _make_material(PLAYER_PRIMARY, 0.0)
	_accent_material = _make_material(PLAYER_ACCENT, 1.15)
	_platform_material = _make_material(Color(0.06, 0.28, 0.58, 0.88), 0.7)
	var dark_material: StandardMaterial3D = _make_material(ARMOR_DARK, 0.0)

	var platform_mesh := CylinderMesh.new()
	platform_mesh.top_radius = 0.86
	platform_mesh.bottom_radius = 0.94
	platform_mesh.height = 0.12
	_platform_mesh = _add_mesh(self, "Platform", platform_mesh, Vector3(0.0, 0.06, 0.0), Vector3.ZERO, _platform_material)

	var left_leg := CapsuleMesh.new()
	left_leg.radius = 0.16
	left_leg.height = 0.72
	_add_mesh(self, "LeftLeg", left_leg, Vector3(-0.22, 0.52, 0.0), Vector3.ZERO, dark_material)
	var right_leg := CapsuleMesh.new()
	right_leg.radius = 0.16
	right_leg.height = 0.72
	_add_mesh(self, "RightLeg", right_leg, Vector3(0.22, 0.52, 0.0), Vector3.ZERO, dark_material)

	_body_pivot = Node3D.new()
	_body_pivot.name = "BodyPivot"
	_body_pivot.position = Vector3(0.0, 0.94, 0.0)
	add_child(_body_pivot)

	var hips := BoxMesh.new()
	hips.size = Vector3(0.68, 0.28, 0.46)
	_add_mesh(_body_pivot, "Hips", hips, Vector3(0.0, 0.0, 0.0), Vector3.ZERO, dark_material)
	var torso := BoxMesh.new()
	torso.size = Vector3(0.9, 0.92, 0.52)
	_add_mesh(_body_pivot, "Torso", torso, Vector3(0.0, 0.52, 0.0), Vector3.ZERO, _primary_material)
	var chest := BoxMesh.new()
	chest.size = Vector3(0.52, 0.16, 0.58)
	_add_mesh(_body_pivot, "ChestLight", chest, Vector3(0.0, 0.58, -0.02), Vector3.ZERO, _accent_material)

	var head := SphereMesh.new()
	head.radius = 0.34
	head.height = 0.68
	_add_mesh(_body_pivot, "Head", head, Vector3(0.0, 1.22, 0.0), Vector3.ZERO, dark_material)
	var visor := BoxMesh.new()
	visor.size = Vector3(0.48, 0.15, 0.08)
	_add_mesh(_body_pivot, "Visor", visor, Vector3(0.0, 1.24, -0.31), Vector3.ZERO, _accent_material)

	_left_arm_pivot = _build_arm("LeftArmPivot", -0.58, dark_material)
	_right_arm_pivot = _build_arm("RightArmPivot", 0.58, dark_material)
	_left_arm_pivot.rotation.z = -0.18
	_right_arm_pivot.rotation.z = 0.22

	_shield_material = _make_material(PLAYER_PRIMARY, 0.54)
	_shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_material.albedo_color.a = 0.86
	var shield := CylinderMesh.new()
	shield.top_radius = 0.38
	shield.bottom_radius = 0.38
	shield.height = 0.08
	_shield_mesh = _add_mesh(
		_left_arm_pivot,
		"Shield",
		shield,
		Vector3(0.0, -0.62, -0.18),
		Vector3(90.0, 0.0, 0.0),
		_shield_material
	)
	var shield_core := CylinderMesh.new()
	shield_core.top_radius = 0.18
	shield_core.bottom_radius = 0.18
	shield_core.height = 0.10
	_shield_core_mesh = _add_mesh(
		_left_arm_pivot,
		"ShieldCore",
		shield_core,
		Vector3(0.0, -0.62, -0.23),
		Vector3(90.0, 0.0, 0.0),
		_accent_material
	)

	var weapon := BoxMesh.new()
	weapon.size = Vector3(0.12, 1.22, 0.12)
	_add_mesh(_right_arm_pivot, "Weapon", weapon, Vector3(0.0, -0.86, 0.0), Vector3.ZERO, _accent_material)
	var weapon_guard := BoxMesh.new()
	weapon_guard.size = Vector3(0.42, 0.10, 0.16)
	_add_mesh(_right_arm_pivot, "WeaponGuard", weapon_guard, Vector3(0.0, -0.40, 0.0), Vector3.ZERO, _primary_material)


func _build_arm(node_name: String, x_position: float, material: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = Vector3(x_position, 0.80, 0.0)
	_body_pivot.add_child(pivot)
	var arm := CapsuleMesh.new()
	arm.radius = 0.14
	arm.height = 0.76
	_add_mesh(pivot, "Arm", arm, Vector3(0.0, -0.34, 0.0), Vector3.ZERO, material)
	return pivot


func _update_pose() -> void:
	if _body_pivot == null or _left_arm_pivot == null or _right_arm_pivot == null:
		return
	var wave: float = sin(_elapsed * 2.1 + _phase_offset)
	var slow_wave: float = sin(_elapsed * 1.05 + _phase_offset)
	position = _home_position
	rotation = _home_rotation
	_body_pivot.position.y = 0.94 + wave * 0.035
	_body_pivot.rotation = Vector3(0.0, 0.0, slow_wave * 0.018)
	_left_arm_pivot.rotation.z = -0.18 - wave * 0.045
	_right_arm_pivot.rotation.z = 0.22 + wave * 0.06
	_left_arm_pivot.rotation.x = 0.0
	_right_arm_pivot.rotation.x = 0.0
	if _shield_mesh != null:
		_shield_mesh.scale = Vector3.ONE
	if _shield_core_mesh != null:
		_shield_core_mesh.scale = Vector3.ONE
	_set_shield_energy(0.54)
	var action_progress: float = clampf(_action_elapsed / maxf(0.001, _action_duration), 0.0, 1.0)
	match _action:
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
	if _accent_material != null:
		var action_energy: float = 0.72 if _action == ACTION_IDLE else 1.18
		_accent_material.emission_energy_multiplier = action_energy + (slow_wave + 1.0) * 0.18
	if _platform_mesh != null:
		_platform_mesh.scale = Vector3.ONE * (1.0 + sin(_elapsed * 3.2) * 0.018)


func _apply_cast_pose(wave: float) -> void:
	_body_pivot.position.y += 0.06
	_left_arm_pivot.rotation.x = -0.78 + wave * 0.08
	_right_arm_pivot.rotation.x = -0.78 - wave * 0.08
	_left_arm_pivot.rotation.z = -0.52
	_right_arm_pivot.rotation.z = 0.52


func _apply_attack_pose(progress: float) -> void:
	var strike: float = sin(progress * PI)
	position += -transform.basis.z * strike * 0.52
	_body_pivot.rotation.x = -0.18 * strike
	_right_arm_pivot.rotation.x = -1.82 + progress * 2.70
	_right_arm_pivot.rotation.z = 0.48 - strike * 0.70
	_left_arm_pivot.rotation.z = -0.42


func _apply_hit_pose(progress: float) -> void:
	var impact: float = sin(progress * PI)
	position += transform.basis.z * impact * 0.20
	_body_pivot.rotation.x = 0.20 * impact
	_body_pivot.rotation.z += sin(progress * PI * 5.0) * (1.0 - progress) * 0.12
	_left_arm_pivot.rotation.z = -0.64
	_right_arm_pivot.rotation.z = 0.64


func _apply_block_pose(progress: float) -> void:
	var brace: float = sin(minf(1.0, progress * 1.8) * PI * 0.5)
	_body_pivot.position.y -= brace * 0.07
	_body_pivot.rotation.x = brace * 0.10
	_left_arm_pivot.rotation.x = -1.18
	_left_arm_pivot.rotation.z = -0.58
	_right_arm_pivot.rotation.z = 0.44
	_set_shield_energy(1.8 + sin(progress * PI * 4.0) * 0.24)


func _apply_heal_pose(progress: float) -> void:
	var lift: float = sin(progress * PI)
	_body_pivot.position.y += lift * 0.16
	_left_arm_pivot.rotation.x = -1.28
	_right_arm_pivot.rotation.x = -1.28
	_left_arm_pivot.rotation.z = -0.82
	_right_arm_pivot.rotation.z = 0.82


func _apply_shield_pose(progress: float) -> void:
	var pulse: float = sin(progress * PI)
	_left_arm_pivot.rotation.x = -1.22
	_left_arm_pivot.rotation.z = -0.46
	_right_arm_pivot.rotation.z = 0.48
	_set_shield_energy(1.45 + pulse * 1.15)
	if _shield_mesh != null:
		_shield_mesh.scale = Vector3.ONE * (1.0 + pulse * 0.32)
	if _shield_core_mesh != null:
		_shield_core_mesh.scale = Vector3.ONE * (1.0 + pulse * 0.48)


func _apply_status_pose(progress: float) -> void:
	var pulse: float = sin(progress * PI * 3.0) * (1.0 - progress)
	_body_pivot.rotation.y = pulse * 0.18
	_body_pivot.position.y += absf(pulse) * 0.06


func _apply_interrupt_pose(progress: float) -> void:
	var recoil: float = sin(progress * PI)
	_body_pivot.rotation.z += sin(progress * PI * 6.0) * (1.0 - progress) * 0.18
	_body_pivot.position.y -= recoil * 0.12
	_left_arm_pivot.rotation.z = -0.80 + recoil * 0.30
	_right_arm_pivot.rotation.z = 0.80 - recoil * 0.30


func _apply_victory_pose() -> void:
	_body_pivot.position.y += 0.10 + absf(sin(_elapsed * 2.8)) * 0.08
	_left_arm_pivot.rotation.x = -2.05
	_right_arm_pivot.rotation.x = -2.05
	_left_arm_pivot.rotation.z = -0.48
	_right_arm_pivot.rotation.z = 0.48


func _apply_defeat_pose(progress: float) -> void:
	var fall: float = _ease_out_cubic(progress)
	rotation.z = (1.20 if actor_side == "player" else -1.20) * fall
	position.y = _home_position.y - fall * 0.44
	_body_pivot.position.y -= fall * 0.18


func _set_shield_energy(energy: float) -> void:
	if _shield_material != null:
		_shield_material.emission_energy_multiplier = energy


func _apply_palette() -> void:
	if _primary_material == null or _accent_material == null or _platform_material == null:
		return
	var primary: Color = PLAYER_PRIMARY if actor_side == "player" else ENEMY_PRIMARY
	var accent: Color = PLAYER_ACCENT if actor_side == "player" else ENEMY_ACCENT
	_primary_material.albedo_color = primary
	_accent_material.albedo_color = accent
	_accent_material.emission = accent
	if _shield_material != null:
		_shield_material.albedo_color = Color(primary.r, primary.g, primary.b, 0.86)
		_shield_material.emission = accent
	_platform_material.albedo_color = primary.darkened(0.32)
	_platform_material.emission = accent.darkened(0.32)


func _add_mesh(
	parent: Node3D,
	node_name: String,
	mesh: Mesh,
	local_position: Vector3,
	local_rotation_degrees: Vector3,
	material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.rotation_degrees = local_rotation_degrees
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
