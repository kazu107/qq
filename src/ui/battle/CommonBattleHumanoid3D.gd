extends Node3D
class_name CommonBattleHumanoid3D

const DEFAULT_PRIMARY := Color(0.08, 0.42, 0.96, 1.0)
const DEFAULT_ACCENT := Color(0.22, 0.88, 1.0, 1.0)
const ARMOR_DARK := Color(0.035, 0.050, 0.072, 1.0)
const JOINT_DARK := Color(0.085, 0.105, 0.135, 1.0)
const LOW_POLY_RADIAL_SEGMENTS: int = 6
const WEAPON_TYPES: Array[String] = [
	"blade", "rapier", "greatsword", "hammer", "staff", "blaster", "cannon", "claws", "scythe", "spear",
]
const OFFHAND_TYPES: Array[String] = ["none", "shield", "tower_shield", "buckler", "orb", "blade"]
const HEAD_TYPES: Array[String] = ["visor", "fin", "crest", "horns", "halo", "fortress", "antenna", "crown"]
const BACK_TYPES: Array[String] = ["none", "power_pack", "thrusters", "reactor", "ammo_pack", "chrono_ring", "spikes", "wings"]

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
var _equipment_roots: Array[Node3D] = []
var _equipment_pieces: Array[MeshInstance3D] = []
var _animated_accessories: Dictionary = {}
var _visual_profile_id: String = "default_player"
var _weapon_type: String = "blade"
var _offhand_type: String = "shield"
var _head_type: String = "visor"
var _back_type: String = "power_pack"
var _body_scale: Vector3 = Vector3.ONE
var _is_boss: bool = false
var _visual_elapsed: float = 0.0
var _built: bool = false
var _palette_configured: bool = false


func _ready() -> void:
	if not _built:
		_build_model()
	if not _palette_configured:
		configure_palette(DEFAULT_PRIMARY, DEFAULT_ACCENT)
	set_process(true)


func _process(delta: float) -> void:
	_visual_elapsed = fmod(_visual_elapsed + delta, TAU * 8.0)
	_animate_accessories()


func configure_palette(primary: Color, accent: Color, secondary: Color = ARMOR_DARK) -> void:
	if not _built:
		_build_model()
	_palette_configured = true
	_primary_material.albedo_color = primary
	_dark_material.albedo_color = secondary
	_joint_material.albedo_color = secondary.lightened(0.16)
	_accent_material.albedo_color = accent
	_accent_material.emission = accent
	_shield_material.albedo_color = Color(primary.r, primary.g, primary.b, 0.78)
	_shield_material.emission = accent


func configure_visual(profile_id: String, profile: Dictionary) -> void:
	if not _built:
		_build_model()
	_visual_profile_id = profile_id if profile_id != "" else "default_player"
	var primary: Color = _profile_color(profile, "primary", DEFAULT_PRIMARY)
	var secondary: Color = _profile_color(profile, "secondary", ARMOR_DARK)
	var accent: Color = _profile_color(profile, "accent", DEFAULT_ACCENT)
	_body_scale = _profile_vector3(profile.get("body_scale", []), Vector3.ONE)
	_body_scale.x = clampf(_body_scale.x, 0.72, 1.8)
	_body_scale.y = clampf(_body_scale.y, 0.72, 1.8)
	_body_scale.z = clampf(_body_scale.z, 0.72, 1.8)
	_weapon_type = _validated_type(String(profile.get("weapon", "blade")), WEAPON_TYPES, "blade")
	_offhand_type = _validated_type(String(profile.get("offhand", "shield")), OFFHAND_TYPES, "shield")
	_head_type = _validated_type(String(profile.get("head", "visor")), HEAD_TYPES, "visor")
	_back_type = _validated_type(String(profile.get("back", "power_pack")), BACK_TYPES, "power_pack")
	_is_boss = bool(profile.get("boss", false))
	scale = _body_scale
	configure_palette(primary, accent, secondary)
	_rebuild_equipment()


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


func get_visual_profile_id() -> String:
	return _visual_profile_id


func get_weapon_type() -> String:
	return _weapon_type


func get_offhand_type() -> String:
	return _offhand_type


func get_head_type() -> String:
	return _head_type


func get_back_type() -> String:
	return _back_type


func get_body_scale() -> Vector3:
	return _body_scale


func is_boss_profile() -> bool:
	return _is_boss


static func warm_mesh_cache() -> int:
	var preview := CommonBattleHumanoid3D.new()
	preview.configure_palette(DEFAULT_PRIMARY, DEFAULT_ACCENT)
	preview.free()
	return _mesh_cache.size()


static func warm_visual_profile_cache(profiles: Array[Dictionary]) -> int:
	var preview := CommonBattleHumanoid3D.new()
	preview.configure_palette(DEFAULT_PRIMARY, DEFAULT_ACCENT)
	for profile: Dictionary in profiles:
		preview.configure_visual(String(profile.get("id", "warmup")), profile)
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


func _build_default_equipment() -> void:
	_weapon_type = "blade"
	_offhand_type = "shield"
	_head_type = "visor"
	_back_type = "power_pack"
	_rebuild_equipment()


func _rebuild_equipment() -> void:
	_clear_equipment()
	_build_weapon(_weapon_type)
	_build_offhand(_offhand_type)
	_build_head_accessory(_head_type)
	_build_back_accessory(_back_type)
	if _is_boss:
		_build_boss_aura()


func _clear_equipment() -> void:
	for piece: MeshInstance3D in _equipment_pieces:
		_geometry_pieces.erase(piece)
	_equipment_pieces.clear()
	for equipment_root: Node3D in _equipment_roots:
		if equipment_root != null and is_instance_valid(equipment_root):
			equipment_root.free()
	_equipment_roots.clear()
	_animated_accessories.clear()
	_shield_disc = null
	_shield_core = null


func _build_weapon(weapon_type: String) -> void:
	var right_hand: BoneAttachment3D = get_socket("right_hand")
	if right_hand == null:
		return
	var mount: Node3D = _create_equipment_root(right_hand, "DefaultWeapon")
	match weapon_type:
		"rapier":
			_add_equipment_piece(mount, "RapierGrip", _cylinder_mesh("rapier_grip", 0.043, 0.23), Vector3(0.0, -0.13, 0.0), Vector3.ZERO, Vector3.ONE, _joint_material)
			_add_equipment_piece(mount, "RapierGuard", _cylinder_mesh("rapier_guard", 0.19, 0.035), Vector3(0.0, -0.25, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.38), _primary_material)
			_add_equipment_piece(mount, "RapierBlade", _tapered_cylinder_mesh("rapier_blade", 0.035, 0.012, 1.05), Vector3(0.0, -0.79, 0.0), Vector3.ZERO, Vector3(0.58, 1.0, 0.58), _accent_material)
		"greatsword":
			_add_equipment_piece(mount, "GreatswordGrip", _cylinder_mesh("greatsword_grip", 0.075, 0.32), Vector3(0.0, -0.18, 0.0), Vector3.ZERO, Vector3.ONE, _joint_material)
			_add_equipment_piece(mount, "GreatswordGuard", _box_mesh("greatsword_guard", Vector3(0.55, 0.10, 0.18)), Vector3(0.0, -0.34, 0.0), Vector3.ZERO, Vector3.ONE, _primary_material)
			_add_equipment_piece(mount, "GreatswordBlade", _tapered_cylinder_mesh("greatsword_blade", 0.14, 0.045, 1.22), Vector3(0.0, -0.98, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.32), _accent_material)
			_add_equipment_piece(mount, "GreatswordSpine", _box_mesh("greatsword_spine", Vector3(0.055, 0.88, 0.10)), Vector3(0.0, -0.83, 0.02), Vector3.ZERO, Vector3.ONE, _dark_material)
		"hammer":
			_add_equipment_piece(mount, "HammerShaft", _cylinder_mesh("hammer_shaft", 0.065, 0.84), Vector3(0.0, -0.46, 0.0), Vector3.ZERO, Vector3.ONE, _joint_material)
			_add_equipment_piece(mount, "HammerHead", _box_mesh("hammer_head", Vector3(0.62, 0.30, 0.34)), Vector3(0.0, -0.91, 0.0), Vector3.ZERO, Vector3.ONE, _primary_material)
			_add_equipment_piece(mount, "HammerCore", _box_mesh("hammer_core", Vector3(0.22, 0.34, 0.38)), Vector3(0.0, -0.91, 0.0), Vector3.ZERO, Vector3.ONE, _accent_material)
		"staff":
			_add_equipment_piece(mount, "StaffShaft", _cylinder_mesh("staff_shaft", 0.052, 1.28), Vector3(0.0, -0.58, 0.0), Vector3.ZERO, Vector3.ONE, _primary_material)
			_add_equipment_piece(mount, "StaffFocus", _sphere_mesh("staff_focus", 0.19, 0.36), Vector3(0.0, -1.27, 0.0), Vector3.ZERO, Vector3.ONE, _accent_material)
			_add_equipment_piece(mount, "StaffCrown", _cylinder_mesh("staff_crown", 0.27, 0.045), Vector3(0.0, -1.12, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.32), _dark_material)
		"blaster":
			_add_equipment_piece(mount, "BlasterBody", _box_mesh("blaster_body", Vector3(0.24, 0.46, 0.30)), Vector3(0.0, -0.27, -0.04), Vector3.ZERO, Vector3.ONE, _primary_material)
			_add_equipment_piece(mount, "BlasterBarrel", _cylinder_mesh("blaster_barrel", 0.085, 0.42), Vector3(0.0, -0.61, -0.04), Vector3.ZERO, Vector3.ONE, _dark_material)
			_add_equipment_piece(mount, "BlasterCell", _box_mesh("blaster_cell", Vector3(0.10, 0.22, 0.32)), Vector3(0.0, -0.24, -0.19), Vector3.ZERO, Vector3.ONE, _accent_material)
		"cannon":
			_add_equipment_piece(mount, "CannonBody", _box_mesh("cannon_body", Vector3(0.36, 0.58, 0.42)), Vector3(0.0, -0.34, -0.05), Vector3.ZERO, Vector3.ONE, _primary_material)
			_add_equipment_piece(mount, "CannonBarrel", _cylinder_mesh("cannon_barrel", 0.15, 0.58), Vector3(0.0, -0.76, -0.05), Vector3.ZERO, Vector3.ONE, _dark_material)
			_add_equipment_piece(mount, "CannonMuzzle", _cylinder_mesh("cannon_muzzle", 0.21, 0.10), Vector3(0.0, -1.08, -0.05), Vector3.ZERO, Vector3.ONE, _accent_material)
			_add_equipment_piece(mount, "CannonCell", _box_mesh("cannon_cell", Vector3(0.16, 0.28, 0.46)), Vector3(0.0, -0.33, -0.25), Vector3.ZERO, Vector3.ONE, _accent_material)
		"claws":
			for claw_index: int in range(3):
				var claw_x: float = (float(claw_index) - 1.0) * 0.09
				_add_equipment_piece(mount, "Claw_%d" % claw_index, _tapered_cylinder_mesh("claw_%d" % claw_index, 0.045, 0.012, 0.56), Vector3(claw_x, -0.38, -0.03), Vector3(0.0, 0.0, claw_x * 1.6), Vector3(0.58, 1.0, 0.48), _accent_material)
		"scythe":
			_add_equipment_piece(mount, "ScytheShaft", _cylinder_mesh("scythe_shaft", 0.055, 1.34), Vector3(0.0, -0.62, 0.0), Vector3.ZERO, Vector3.ONE, _dark_material)
			_add_equipment_piece(mount, "ScytheBlade", _tapered_cylinder_mesh("scythe_blade", 0.12, 0.025, 0.76), Vector3(0.28, -1.23, 0.0), Vector3(0.0, 0.0, 1.04), Vector3(1.0, 1.0, 0.28), _accent_material)
			_add_equipment_piece(mount, "ScytheCore", _sphere_mesh("scythe_core", 0.14, 0.24), Vector3(0.0, -1.23, 0.0), Vector3.ZERO, Vector3.ONE, _primary_material)
		"spear":
			_add_equipment_piece(mount, "SpearShaft", _cylinder_mesh("spear_shaft", 0.048, 1.46), Vector3(0.0, -0.68, 0.0), Vector3.ZERO, Vector3.ONE, _primary_material)
			_add_equipment_piece(mount, "SpearTip", _tapered_cylinder_mesh("spear_tip", 0.15, 0.012, 0.45), Vector3(0.0, -1.64, 0.0), Vector3.ZERO, Vector3(0.72, 1.0, 0.32), _accent_material)
			_add_equipment_piece(mount, "SpearCollar", _cylinder_mesh("spear_collar", 0.13, 0.08), Vector3(0.0, -1.39, 0.0), Vector3.ZERO, Vector3.ONE, _dark_material)
		_:
			_add_equipment_piece(mount, "WeaponGrip", _cylinder_mesh("weapon_grip", 0.055, 0.24), Vector3(0.0, -0.14, 0.0), Vector3.ZERO, Vector3.ONE, _joint_material)
			_add_equipment_piece(mount, "WeaponGuard", _box_mesh("weapon_guard", Vector3(0.38, 0.08, 0.15)), Vector3(0.0, -0.26, 0.0), Vector3.ZERO, Vector3.ONE, _primary_material)
			_add_equipment_piece(mount, "WeaponBlade", _tapered_cylinder_mesh("weapon_blade", 0.085, 0.035, 0.92), Vector3(0.0, -0.73, 0.0), Vector3.ZERO, Vector3(0.72, 1.0, 0.34), _accent_material)


func _build_offhand(offhand_type: String) -> void:
	if offhand_type == "none":
		return
	var left_hand: BoneAttachment3D = get_socket("left_hand")
	if left_hand == null:
		return
	var root_name: String = "DefaultShield" if offhand_type in ["shield", "tower_shield", "buckler"] else "Offhand_%s" % offhand_type
	var mount: Node3D = _create_equipment_root(left_hand, root_name)
	match offhand_type:
		"tower_shield":
			mount.position = Vector3(0.0, -0.24, -0.24)
			_shield_disc = _add_equipment_piece(mount, "TowerShield", _box_mesh("tower_shield", Vector3(0.68, 0.94, 0.12)), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, _shield_material)
			_shield_core = _add_equipment_piece(mount, "TowerShieldCore", _box_mesh("tower_shield_core", Vector3(0.20, 0.62, 0.16)), Vector3(0.0, 0.0, -0.08), Vector3.ZERO, Vector3.ONE, _accent_material)
		"buckler":
			mount.position = Vector3(0.0, -0.08, -0.15)
			mount.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			_shield_disc = _add_equipment_piece(mount, "BucklerDisc", _cylinder_mesh("buckler_disc", 0.25, 0.065), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, _shield_material)
			_shield_core = _add_equipment_piece(mount, "BucklerCore", _cylinder_mesh("buckler_core", 0.10, 0.085), Vector3(0.0, -0.045, 0.0), Vector3.ZERO, Vector3.ONE, _accent_material)
		"orb":
			var orb: MeshInstance3D = _add_equipment_piece(mount, "FocusOrb", _sphere_mesh("focus_orb", 0.20, 0.38), Vector3(0.0, -0.22, -0.08), Vector3.ZERO, Vector3.ONE, _accent_material)
			_animated_accessories["orb"] = orb
		"blade":
			_add_equipment_piece(mount, "OffhandGrip", _cylinder_mesh("offhand_grip", 0.045, 0.20), Vector3(0.0, -0.12, 0.0), Vector3.ZERO, Vector3.ONE, _joint_material)
			_add_equipment_piece(mount, "OffhandBlade", _tapered_cylinder_mesh("offhand_blade", 0.065, 0.02, 0.62), Vector3(0.0, -0.52, 0.0), Vector3.ZERO, Vector3(0.62, 1.0, 0.30), _accent_material)
		_:
			mount.position = Vector3(0.0, -0.08, -0.18)
			mount.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			_shield_disc = _add_equipment_piece(mount, "ShieldDisc", _cylinder_mesh("shield_disc", 0.39, 0.075), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.86), _shield_material)
			_shield_core = _add_equipment_piece(mount, "ShieldCore", _cylinder_mesh("shield_core", 0.17, 0.095), Vector3(0.0, -0.055, 0.0), Vector3.ZERO, Vector3.ONE, _accent_material)


func _build_head_accessory(head_type: String) -> void:
	if head_type == "visor":
		return
	var head_socket: BoneAttachment3D = get_socket("head")
	if head_socket == null:
		return
	var mount: Node3D = _create_equipment_root(head_socket, "Head_%s" % head_type)
	match head_type:
		"fin":
			_add_equipment_piece(mount, "HeadFin", _box_mesh("head_fin", Vector3(0.08, 0.46, 0.38)), Vector3(0.0, 0.28, 0.06), Vector3(0.0, 0.0, -10.0), Vector3.ONE, _accent_material)
		"crest":
			for crest_index: int in range(3):
				_add_equipment_piece(mount, "Crest_%d" % crest_index, _tapered_cylinder_mesh("crest_spike_%d" % crest_index, 0.085, 0.018, 0.34), Vector3((float(crest_index) - 1.0) * 0.14, 0.30, 0.02), Vector3(0.0, 0.0, (float(crest_index) - 1.0) * -0.18), Vector3(0.66, 1.0, 0.46), _accent_material)
		"horns":
			for side: float in [-1.0, 1.0]:
				_add_equipment_piece(mount, "Horn_%d" % int(side), _tapered_cylinder_mesh("helmet_horn", 0.10, 0.018, 0.48), Vector3(0.18 * side, 0.27, 0.03), Vector3(0.0, 0.0, -0.62 * side), Vector3(0.72, 1.0, 0.52), _primary_material)
		"halo":
			mount.position = Vector3(0.0, 0.40, 0.0)
			mount.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			_build_segment_ring(mount, "Halo", 0.34, 8, Vector3(0.18, 0.055, 0.055), _accent_material)
			_animated_accessories["halo"] = mount
		"fortress":
			_add_equipment_piece(mount, "FortressBrow", _box_mesh("fortress_brow", Vector3(0.62, 0.16, 0.42)), Vector3(0.0, 0.10, -0.03), Vector3.ZERO, Vector3.ONE, _primary_material)
			_add_equipment_piece(mount, "FortressCrown", _box_mesh("fortress_crown", Vector3(0.42, 0.22, 0.34)), Vector3(0.0, 0.28, 0.04), Vector3.ZERO, Vector3.ONE, _dark_material)
		"antenna":
			_add_equipment_piece(mount, "AntennaRod", _cylinder_mesh("antenna_rod", 0.025, 0.42), Vector3(0.14, 0.30, 0.0), Vector3(0.0, 0.0, -0.24), Vector3.ONE, _dark_material)
			_add_equipment_piece(mount, "AntennaLight", _sphere_mesh("antenna_light", 0.07, 0.12), Vector3(0.19, 0.52, 0.0), Vector3.ZERO, Vector3.ONE, _accent_material)
		"crown":
			for crown_index: int in range(5):
				var crown_x: float = (float(crown_index) - 2.0) * 0.12
				var crown_height: float = 0.42 if crown_index == 2 else 0.31
				_add_equipment_piece(mount, "Crown_%d" % crown_index, _tapered_cylinder_mesh("crown_spike_%d" % crown_index, 0.075, 0.014, crown_height), Vector3(crown_x, 0.28, 0.02), Vector3(0.0, 0.0, crown_x * -0.7), Vector3(0.62, 1.0, 0.44), _accent_material)


func _build_back_accessory(back_type: String) -> void:
	if back_type == "none":
		return
	var back_socket: BoneAttachment3D = get_socket("back")
	if back_socket == null:
		return
	var root_name: String = "PowerPack" if back_type == "power_pack" else "Back_%s" % back_type
	var mount: Node3D = _create_equipment_root(back_socket, root_name)
	mount.position = Vector3(0.0, 0.10, 0.30)
	match back_type:
		"thrusters":
			for side: float in [-1.0, 1.0]:
				_add_equipment_piece(mount, "ThrusterBody_%d" % int(side), _box_mesh("thruster_body", Vector3(0.18, 0.48, 0.20)), Vector3(0.25 * side, -0.02, 0.0), Vector3(0.0, 0.0, -8.0 * side), Vector3.ONE, _dark_material)
				var flame: MeshInstance3D = _add_equipment_piece(mount, "ThrusterGlow_%d" % int(side), _tapered_cylinder_mesh("thruster_glow", 0.075, 0.025, 0.24), Vector3(0.25 * side, -0.34, 0.0), Vector3.ZERO, Vector3(0.62, 1.0, 0.62), _accent_material)
				_animated_accessories["thruster_%d" % int(side)] = flame
		"reactor":
			_add_equipment_piece(mount, "ReactorFrame", _box_mesh("reactor_frame", Vector3(0.58, 0.60, 0.20)), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, _dark_material)
			_add_equipment_piece(mount, "ReactorCore", _cylinder_mesh("reactor_core", 0.22, 0.10), Vector3(0.0, 0.0, 0.16), Vector3(90.0, 0.0, 0.0), Vector3.ONE, _accent_material)
			_add_equipment_piece(mount, "ReactorBrace", _box_mesh("reactor_brace", Vector3(0.72, 0.10, 0.16)), Vector3(0.0, 0.0, 0.06), Vector3.ZERO, Vector3.ONE, _primary_material)
		"ammo_pack":
			_add_equipment_piece(mount, "AmmoPackBody", _box_mesh("ammo_pack_body", Vector3(0.62, 0.54, 0.22)), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, _dark_material)
			for side: float in [-1.0, 1.0]:
				_add_equipment_piece(mount, "AmmoCell_%d" % int(side), _cylinder_mesh("ammo_cell", 0.09, 0.42), Vector3(0.20 * side, 0.0, 0.15), Vector3.ZERO, Vector3.ONE, _accent_material)
		"chrono_ring":
			mount.position = Vector3(0.0, 0.08, 0.36)
			_build_segment_ring(mount, "ChronoRing", 0.54, 10, Vector3(0.22, 0.07, 0.07), _accent_material)
			_animated_accessories["chrono_ring"] = mount
		"spikes":
			for spike_index: int in range(4):
				var spike_x: float = (float(spike_index) - 1.5) * 0.18
				_add_equipment_piece(mount, "BackSpike_%d" % spike_index, _tapered_cylinder_mesh("back_spike_%d" % spike_index, 0.09, 0.018, 0.48), Vector3(spike_x, 0.10 - absf(spike_x) * 0.2, 0.18), Vector3(1.20, 0.0, spike_x * -0.9), Vector3(0.66, 1.0, 0.52), _primary_material)
		"wings":
			for side: float in [-1.0, 1.0]:
				var wing_root: Node3D = _create_equipment_root(mount, "Wing_%d" % int(side))
				wing_root.position = Vector3(0.18 * side, 0.10, 0.0)
				wing_root.rotation_degrees = Vector3(0.0, 0.0, -18.0 * side)
				for feather_index: int in range(3):
					_add_equipment_piece(wing_root, "WingBlade_%d_%d" % [int(side), feather_index], _box_mesh("wing_blade_%d" % feather_index, Vector3(0.16, 0.74 - float(feather_index) * 0.11, 0.08)), Vector3((0.20 + float(feather_index) * 0.14) * side, -0.12 - float(feather_index) * 0.13, 0.0), Vector3(0.0, 0.0, (-34.0 - float(feather_index) * 8.0) * side), Vector3.ONE, _accent_material if feather_index == 0 else _primary_material)
				_animated_accessories["wing_%d" % int(side)] = wing_root
		_:
			_add_equipment_piece(mount, "PowerPackBody", _box_mesh("power_pack", Vector3(0.42, 0.48, 0.18)), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, _dark_material)
			_add_equipment_piece(mount, "PowerCore", _box_mesh("power_core", Vector3(0.18, 0.26, 0.06)), Vector3(0.0, 0.0, 0.12), Vector3.ZERO, Vector3.ONE, _accent_material)


func _build_boss_aura() -> void:
	var aura_root: Node3D = _create_equipment_root(self, "BossAura")
	aura_root.position = Vector3(0.0, 1.02, 0.0)
	aura_root.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_build_segment_ring(aura_root, "BossAuraRing", 0.84, 12, Vector3(0.24, 0.055, 0.055), _accent_material)
	_animated_accessories["boss_aura"] = aura_root


func _build_segment_ring(parent: Node3D, prefix: String, radius: float, segments: int, segment_size: Vector3, material: Material) -> void:
	for segment_index: int in range(segments):
		var angle: float = TAU * float(segment_index) / float(segments)
		_add_equipment_piece(
			parent,
			"%s_%d" % [prefix, segment_index],
			_box_mesh("%s_segment" % prefix.to_snake_case(), segment_size),
			Vector3(cos(angle) * radius, sin(angle) * radius, 0.0),
			Vector3(0.0, 0.0, rad_to_deg(angle)),
			Vector3.ONE,
			material
		)


func _animate_accessories() -> void:
	var halo: Node3D = _animated_accessories.get("halo") as Node3D
	if halo != null:
		halo.rotation.y = _visual_elapsed * 0.72
	var chrono_ring: Node3D = _animated_accessories.get("chrono_ring") as Node3D
	if chrono_ring != null:
		chrono_ring.rotation.z = _visual_elapsed * 0.46
	var boss_aura: Node3D = _animated_accessories.get("boss_aura") as Node3D
	if boss_aura != null:
		boss_aura.rotation.y = _visual_elapsed * 0.32
		boss_aura.scale = Vector3.ONE * (1.0 + sin(_visual_elapsed * 2.2) * 0.05)
	var orb: Node3D = _animated_accessories.get("orb") as Node3D
	if orb != null:
		orb.scale = Vector3.ONE * (1.0 + sin(_visual_elapsed * 3.4) * 0.10)
	for side: int in [-1, 1]:
		var wing: Node3D = _animated_accessories.get("wing_%d" % side) as Node3D
		if wing != null:
			wing.rotation.z = deg_to_rad(-18.0 * float(side) + sin(_visual_elapsed * 1.8) * 5.0 * float(side))
		var thruster: Node3D = _animated_accessories.get("thruster_%d" % side) as Node3D
		if thruster != null:
			thruster.scale.y = 0.82 + (sin(_visual_elapsed * 7.0 + float(side)) + 1.0) * 0.14


func _create_equipment_root(parent: Node3D, root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	parent.add_child(root)
	_equipment_roots.append(root)
	return root


func _add_equipment_piece(
	parent: Node3D,
	node_name: String,
	mesh: Mesh,
	local_position: Vector3,
	local_rotation_degrees: Vector3,
	local_scale: Vector3,
	material: Material
) -> MeshInstance3D:
	var piece: MeshInstance3D = _add_piece(parent, node_name, mesh, local_position, local_rotation_degrees, local_scale, material)
	_equipment_pieces.append(piece)
	return piece


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


static func _profile_color(profile: Dictionary, key: String, fallback: Color) -> Color:
	var color_text: String = String(profile.get(key, ""))
	return Color.from_string(color_text, fallback) if color_text != "" else fallback


static func _profile_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


static func _validated_type(value: String, valid_types: Array[String], fallback: String) -> String:
	return value if valid_types.has(value) else fallback
