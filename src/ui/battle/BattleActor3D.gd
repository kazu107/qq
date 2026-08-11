extends Node3D
class_name BattleActor3D

const PLAYER_PRIMARY := Color(0.08, 0.42, 0.96, 1.0)
const PLAYER_ACCENT := Color(0.22, 0.88, 1.0, 1.0)
const ENEMY_PRIMARY := Color(0.76, 0.12, 0.11, 1.0)
const ENEMY_ACCENT := Color(1.0, 0.46, 0.18, 1.0)
const ARMOR_DARK := Color(0.045, 0.065, 0.09, 1.0)

var actor_side: String = "player"
var _body_pivot: Node3D
var _left_arm_pivot: Node3D
var _right_arm_pivot: Node3D
var _platform_material: StandardMaterial3D
var _primary_material: StandardMaterial3D
var _accent_material: StandardMaterial3D
var _elapsed: float = 0.0
var _phase_offset: float = 0.0
var _visual_built: bool = false


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


func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, TAU * 8.0)
	_update_idle_pose()


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
	_add_mesh(self, "Platform", platform_mesh, Vector3(0.0, 0.06, 0.0), Vector3.ZERO, _platform_material)

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

	var shield := CylinderMesh.new()
	shield.top_radius = 0.38
	shield.bottom_radius = 0.38
	shield.height = 0.08
	_add_mesh(
		_left_arm_pivot,
		"Shield",
		shield,
		Vector3(0.0, -0.62, -0.18),
		Vector3(90.0, 0.0, 0.0),
		_primary_material
	)
	var shield_core := CylinderMesh.new()
	shield_core.top_radius = 0.18
	shield_core.bottom_radius = 0.18
	shield_core.height = 0.10
	_add_mesh(
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


func _update_idle_pose() -> void:
	if _body_pivot == null or _left_arm_pivot == null or _right_arm_pivot == null:
		return
	var wave: float = sin(_elapsed * 2.1 + _phase_offset)
	var slow_wave: float = sin(_elapsed * 1.05 + _phase_offset)
	_body_pivot.position.y = 0.94 + wave * 0.035
	_body_pivot.rotation.z = slow_wave * 0.018
	_left_arm_pivot.rotation.z = -0.18 - wave * 0.045
	_right_arm_pivot.rotation.z = 0.22 + wave * 0.06
	if _accent_material != null:
		_accent_material.emission_energy_multiplier = 1.0 + (slow_wave + 1.0) * 0.18


func _apply_palette() -> void:
	if _primary_material == null or _accent_material == null or _platform_material == null:
		return
	var primary: Color = PLAYER_PRIMARY if actor_side == "player" else ENEMY_PRIMARY
	var accent: Color = PLAYER_ACCENT if actor_side == "player" else ENEMY_ACCENT
	_primary_material.albedo_color = primary
	_accent_material.albedo_color = accent
	_accent_material.emission = accent
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
