extends Node3D
class_name CommonBattleHumanoid3D

const DEFAULT_PRIMARY := Color(0.08, 0.42, 0.96, 1.0)
const DEFAULT_ACCENT := Color(0.22, 0.88, 1.0, 1.0)
const ARMOR_DARK := Color(0.035, 0.050, 0.072, 1.0)
const JOINT_DARK := Color(0.085, 0.105, 0.135, 1.0)
const LOW_POLY_RADIAL_SEGMENTS: int = 6

const BONE_DEFINITIONS: Array[Dictionary] = [
	{"name": "root", "parent": "", "position": Vector3(0.0, 0.28, 0.0)},
	{"name": "hips", "parent": "root", "position": Vector3(0.0, 0.68, 0.0)},
	{"name": "spine", "parent": "hips", "position": Vector3(0.0, 0.22, 0.0)},
	{"name": "chest", "parent": "spine", "position": Vector3(0.0, 0.40, 0.0)},
	{"name": "neck", "parent": "chest", "position": Vector3(0.0, 0.35, 0.0)},
	{"name": "head", "parent": "neck", "position": Vector3(0.0, 0.22, 0.0)},
	{"name": "left_upper_leg", "parent": "hips", "position": Vector3(-0.23, -0.05, 0.0)},
	{"name": "left_lower_leg", "parent": "left_upper_leg", "position": Vector3(0.0, -0.43, 0.0)},
	{"name": "left_foot", "parent": "left_lower_leg", "position": Vector3(0.0, -0.40, -0.02)},
	{"name": "right_upper_leg", "parent": "hips", "position": Vector3(0.23, -0.05, 0.0)},
	{"name": "right_lower_leg", "parent": "right_upper_leg", "position": Vector3(0.0, -0.43, 0.0)},
	{"name": "right_foot", "parent": "right_lower_leg", "position": Vector3(0.0, -0.40, -0.02)},
	{"name": "left_upper_arm", "parent": "chest", "position": Vector3(-0.50, 0.22, 0.0)},
	{"name": "left_forearm", "parent": "left_upper_arm", "position": Vector3(0.0, -0.43, 0.0)},
	{"name": "left_hand", "parent": "left_forearm", "position": Vector3(0.0, -0.38, 0.0)},
	{"name": "right_upper_arm", "parent": "chest", "position": Vector3(0.50, 0.22, 0.0)},
	{"name": "right_forearm", "parent": "right_upper_arm", "position": Vector3(0.0, -0.43, 0.0)},
	{"name": "right_hand", "parent": "right_forearm", "position": Vector3(0.0, -0.38, 0.0)},
]

const SOCKET_DEFINITIONS: Array[Dictionary] = [
	{"id": "left_hand", "bone": "left_hand", "node": "LeftHandSocket"},
	{"id": "right_hand", "bone": "right_hand", "node": "RightHandSocket"},
	{"id": "chest", "bone": "chest", "node": "ChestSocket"},
	{"id": "head", "bone": "head", "node": "HeadSocket"},
	{"id": "back", "bone": "chest", "node": "BackSocket"},
]

static var _mesh_cache: Dictionary = {}

var _skeleton: Skeleton3D
var _bone_indices: Dictionary = {}
var _sockets: Dictionary = {}
var _geometry_pieces: Array[MeshInstance3D] = []
var _primary_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _joint_material: StandardMaterial3D
var _accent_material: StandardMaterial3D
var _shield_material: StandardMaterial3D
var _shield_disc: MeshInstance3D
var _shield_core: MeshInstance3D
var _built: bool = false
var _palette_configured: bool = false


func _ready() -> void:
	if not _built:
		_build_model()
	if not _palette_configured:
		configure_palette(DEFAULT_PRIMARY, DEFAULT_ACCENT)


func configure_palette(primary: Color, accent: Color) -> void:
	if not _built:
		_build_model()
	_palette_configured = true
	_primary_material.albedo_color = primary
	_accent_material.albedo_color = accent
	_accent_material.emission = accent
	_shield_material.albedo_color = Color(primary.r, primary.g, primary.b, 0.78)
	_shield_material.emission = accent


func begin_pose() -> void:
	if _skeleton == null:
		return
	_skeleton.reset_bone_poses()
	set_shield_pulse(1.0, 0.54)


func finish_pose() -> void:
	if _skeleton != null:
		_skeleton.force_update_all_bone_transforms()


func set_bone_rotation(bone_name: String, euler_radians: Vector3) -> void:
	var bone_index: int = int(_bone_indices.get(bone_name, -1))
	if _skeleton == null or bone_index < 0:
		return
	_skeleton.set_bone_pose_rotation(bone_index, Quaternion.from_euler(euler_radians))


func set_bone_position_offset(bone_name: String, offset: Vector3) -> void:
	var bone_index: int = int(_bone_indices.get(bone_name, -1))
	if _skeleton == null or bone_index < 0:
		return
	var rest: Transform3D = _skeleton.get_bone_rest(bone_index)
	_skeleton.set_bone_pose_position(bone_index, rest.origin + offset)


func set_bone_scale(bone_name: String, bone_scale: Vector3) -> void:
	var bone_index: int = int(_bone_indices.get(bone_name, -1))
	if _skeleton != null and bone_index >= 0:
		_skeleton.set_bone_pose_scale(bone_index, bone_scale)


func set_shield_pulse(pulse_scale: float, emission_energy: float) -> void:
	if _shield_disc != null:
		_shield_disc.scale = Vector3.ONE * pulse_scale
	if _shield_core != null:
		_shield_core.scale = Vector3.ONE * lerpf(1.0, pulse_scale, 1.35)
	if _shield_material != null:
		_shield_material.emission_energy_multiplier = emission_energy


func set_accent_energy(emission_energy: float) -> void:
	if _accent_material != null:
		_accent_material.emission_energy_multiplier = emission_energy


func get_skeleton() -> Skeleton3D:
	return _skeleton


func get_socket(socket_id: String) -> BoneAttachment3D:
	return _sockets.get(socket_id) as BoneAttachment3D


func get_socket_ids() -> Array[String]:
	var result: Array[String] = []
	for socket_id: Variant in _sockets.keys():
		result.append(String(socket_id))
	result.sort()
	return result


func get_geometry_piece_count() -> int:
	return _geometry_pieces.size()


static func warm_mesh_cache() -> int:
	var preview := CommonBattleHumanoid3D.new()
	preview.configure_palette(DEFAULT_PRIMARY, DEFAULT_ACCENT)
	preview.free()
	return _mesh_cache.size()


static func get_cached_mesh_count() -> int:
	return _mesh_cache.size()


func get_bone_rotation(bone_name: String) -> Quaternion:
	var bone_index: int = int(_bone_indices.get(bone_name, -1))
	if _skeleton == null or bone_index < 0:
		return Quaternion.IDENTITY
	return _skeleton.get_bone_pose_rotation(bone_index)


func _build_model() -> void:
	_built = true
	_primary_material = _make_material(DEFAULT_PRIMARY, 0.0)
	_dark_material = _make_material(ARMOR_DARK, 0.0)
	_joint_material = _make_material(JOINT_DARK, 0.0)
	_accent_material = _make_material(DEFAULT_ACCENT, 1.0)
	_shield_material = _make_material(Color(DEFAULT_PRIMARY.r, DEFAULT_PRIMARY.g, DEFAULT_PRIMARY.b, 0.78), 0.54)
	_shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_skeleton = Skeleton3D.new()
	_skeleton.name = "HumanoidSkeleton"
	add_child(_skeleton)
	_build_skeleton()
	_build_body_geometry()
	_build_sockets()
	_build_default_equipment()
	_skeleton.force_update_all_bone_transforms()


func _build_skeleton() -> void:
	for raw_definition: Dictionary in BONE_DEFINITIONS:
		var bone_name: String = String(raw_definition.get("name", ""))
		var parent_name: String = String(raw_definition.get("parent", ""))
		var rest_position: Vector3 = Vector3(raw_definition.get("position", Vector3.ZERO))
		var bone_index: int = _skeleton.add_bone(bone_name)
		_bone_indices[bone_name] = bone_index
		if parent_name != "":
			_skeleton.set_bone_parent(bone_index, int(_bone_indices.get(parent_name, -1)))
		_skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, rest_position))


func _build_body_geometry() -> void:
	_add_bone_piece("hips", "HipsArmor", _tapered_cylinder_mesh("hips", 0.29, 0.31, 0.25), Vector3(0.0, 0.02, 0.0), Vector3.ZERO, Vector3(1.42, 1.0, 1.0), _dark_material)
	_add_bone_piece("spine", "TorsoArmor", _tapered_cylinder_mesh("torso", 0.42, 0.32, 0.62), Vector3(0.0, 0.23, 0.0), Vector3.ZERO, Vector3(1.08, 1.0, 0.76), _primary_material)
	_add_bone_piece("chest", "ChestPlate", _box_mesh("chest_plate", Vector3(0.74, 0.18, 0.13)), Vector3(0.0, 0.10, -0.28), Vector3.ZERO, Vector3.ONE, _accent_material)
	_add_bone_piece("neck", "NeckGuard", _cylinder_mesh("neck", 0.14, 0.18), Vector3(0.0, 0.06, 0.0), Vector3.ZERO, Vector3.ONE, _joint_material)
	_add_bone_piece("head", "Helmet", _sphere_mesh("helmet", 0.33, 0.60), Vector3(0.0, 0.08, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.92), _dark_material)
	_add_bone_piece("head", "Visor", _box_mesh("visor", Vector3(0.48, 0.14, 0.08)), Vector3(0.0, 0.10, -0.29), Vector3.ZERO, Vector3.ONE, _accent_material)

	_build_leg("left")
	_build_leg("right")
	_build_arm("left")
	_build_arm("right")


func _build_leg(side: String) -> void:
	var upper_bone: String = "%s_upper_leg" % side
	var lower_bone: String = "%s_lower_leg" % side
	var foot_bone: String = "%s_foot" % side
	var prefix: String = "Left" if side == "left" else "Right"
	_add_bone_piece(upper_bone, "%sThigh" % prefix, _tapered_cylinder_mesh("thigh", 0.16, 0.13, 0.43), Vector3(0.0, -0.21, 0.0), Vector3.ZERO, Vector3.ONE, _primary_material)
	_add_bone_piece(lower_bone, "%sShin" % prefix, _tapered_cylinder_mesh("shin", 0.13, 0.105, 0.39), Vector3(0.0, -0.19, 0.0), Vector3.ZERO, Vector3.ONE, _dark_material)
	_add_bone_piece(foot_bone, "%sBoot" % prefix, _box_mesh("boot", Vector3(0.29, 0.15, 0.43)), Vector3(0.0, -0.02, -0.13), Vector3.ZERO, Vector3.ONE, _dark_material)
	_add_bone_piece(lower_bone, "%sKnee" % prefix, _sphere_mesh("knee", 0.145, 0.25), Vector3(0.0, 0.01, -0.03), Vector3.ZERO, Vector3(1.0, 0.72, 0.88), _joint_material)


func _build_arm(side: String) -> void:
	var upper_bone: String = "%s_upper_arm" % side
	var forearm_bone: String = "%s_forearm" % side
	var hand_bone: String = "%s_hand" % side
	var prefix: String = "Left" if side == "left" else "Right"
	_add_bone_piece(upper_bone, "%sUpperArm" % prefix, _tapered_cylinder_mesh("upper_arm", 0.145, 0.115, 0.42), Vector3(0.0, -0.20, 0.0), Vector3.ZERO, Vector3.ONE, _dark_material)
	_add_bone_piece(forearm_bone, "%sForearm" % prefix, _tapered_cylinder_mesh("forearm", 0.125, 0.095, 0.37), Vector3(0.0, -0.18, 0.0), Vector3.ZERO, Vector3.ONE, _primary_material)
	_add_bone_piece(hand_bone, "%sGauntlet" % prefix, _box_mesh("gauntlet", Vector3(0.19, 0.19, 0.17)), Vector3(0.0, -0.06, 0.0), Vector3.ZERO, Vector3.ONE, _joint_material)
	_add_bone_piece(upper_bone, "%sPauldron" % prefix, _sphere_mesh("pauldron", 0.22, 0.26), Vector3(0.0, 0.02, 0.0), Vector3.ZERO, Vector3(1.18, 0.70, 1.0), _primary_material)


func _build_sockets() -> void:
	for raw_definition: Dictionary in SOCKET_DEFINITIONS:
		var socket_id: String = String(raw_definition.get("id", ""))
		var bone_name: String = String(raw_definition.get("bone", ""))
		var node_name: String = String(raw_definition.get("node", "EquipmentSocket"))
		var socket := BoneAttachment3D.new()
		socket.name = node_name
		socket.bone_name = bone_name
		_skeleton.add_child(socket)
		_sockets[socket_id] = socket
	var back_socket: BoneAttachment3D = get_socket("back")
	if back_socket != null:
		back_socket.position = Vector3(0.0, 0.08, 0.30)


func _build_default_equipment() -> void:
	var right_hand: BoneAttachment3D = get_socket("right_hand")
	if right_hand != null:
		var weapon_mount := Node3D.new()
		weapon_mount.name = "DefaultWeapon"
		right_hand.add_child(weapon_mount)
		_add_piece(weapon_mount, "WeaponGrip", _cylinder_mesh("weapon_grip", 0.055, 0.24), Vector3(0.0, -0.14, 0.0), Vector3.ZERO, Vector3.ONE, _joint_material)
		_add_piece(weapon_mount, "WeaponGuard", _box_mesh("weapon_guard", Vector3(0.38, 0.08, 0.15)), Vector3(0.0, -0.26, 0.0), Vector3.ZERO, Vector3.ONE, _primary_material)
		_add_piece(weapon_mount, "WeaponBlade", _tapered_cylinder_mesh("weapon_blade", 0.085, 0.035, 0.92), Vector3(0.0, -0.73, 0.0), Vector3.ZERO, Vector3(0.72, 1.0, 0.34), _accent_material)

	var left_hand: BoneAttachment3D = get_socket("left_hand")
	if left_hand != null:
		var shield_mount := Node3D.new()
		shield_mount.name = "DefaultShield"
		shield_mount.position = Vector3(0.0, -0.08, -0.18)
		shield_mount.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		left_hand.add_child(shield_mount)
		_shield_disc = _add_piece(shield_mount, "ShieldDisc", _cylinder_mesh("shield_disc", 0.39, 0.075), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.86), _shield_material)
		_shield_core = _add_piece(shield_mount, "ShieldCore", _cylinder_mesh("shield_core", 0.17, 0.095), Vector3(0.0, -0.055, 0.0), Vector3.ZERO, Vector3.ONE, _accent_material)

	var back_socket: BoneAttachment3D = get_socket("back")
	if back_socket != null:
		_add_piece(back_socket, "PowerPack", _box_mesh("power_pack", Vector3(0.42, 0.48, 0.18)), Vector3(0.0, 0.02, 0.0), Vector3.ZERO, Vector3.ONE, _dark_material)
		_add_piece(back_socket, "PowerCore", _box_mesh("power_core", Vector3(0.18, 0.26, 0.06)), Vector3(0.0, 0.02, 0.12), Vector3.ZERO, Vector3.ONE, _accent_material)


func _add_bone_piece(
	bone_name: String,
	node_name: String,
	mesh: Mesh,
	local_position: Vector3,
	local_rotation_degrees: Vector3,
	local_scale: Vector3,
	material: Material
) -> MeshInstance3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = "%sAttachment" % node_name
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	return _add_piece(attachment, node_name, mesh, local_position, local_rotation_degrees, local_scale, material)


func _add_piece(
	parent: Node3D,
	node_name: String,
	mesh: Mesh,
	local_position: Vector3,
	local_rotation_degrees: Vector3,
	local_scale: Vector3,
	material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.rotation_degrees = local_rotation_degrees
	instance.scale = local_scale
	instance.material_override = material
	parent.add_child(instance)
	_geometry_pieces.append(instance)
	return instance


static func _box_mesh(cache_key: String, box_size: Vector3) -> BoxMesh:
	var key: String = "box:%s" % cache_key
	var cached: Variant = _mesh_cache.get(key)
	if cached is BoxMesh:
		return cached as BoxMesh
	var mesh := BoxMesh.new()
	mesh.size = box_size
	_mesh_cache[key] = mesh
	return mesh


static func _cylinder_mesh(cache_key: String, radius: float, height: float) -> CylinderMesh:
	var key: String = "cylinder:%s" % cache_key
	var cached: Variant = _mesh_cache.get(key)
	if cached is CylinderMesh:
		return cached as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = LOW_POLY_RADIAL_SEGMENTS
	mesh.rings = 1
	_mesh_cache[key] = mesh
	return mesh


static func _tapered_cylinder_mesh(cache_key: String, top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var key: String = "tapered:%s" % cache_key
	var cached: Variant = _mesh_cache.get(key)
	if cached is CylinderMesh:
		return cached as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = LOW_POLY_RADIAL_SEGMENTS
	mesh.rings = 1
	_mesh_cache[key] = mesh
	return mesh


static func _sphere_mesh(cache_key: String, radius: float, height: float) -> SphereMesh:
	var key: String = "sphere:%s" % cache_key
	var cached: Variant = _mesh_cache.get(key)
	if cached is SphereMesh:
		return cached as SphereMesh
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 4
	_mesh_cache[key] = mesh
	return mesh


static func _make_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.30
	material.roughness = 0.58
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
