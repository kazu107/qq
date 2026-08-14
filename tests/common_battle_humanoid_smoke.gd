extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var actor := BattleActor3D.new()
	actor.name = "HumanoidSmokeActor"
	actor.configure("player")
	add_child(actor)
	await get_tree().process_frame
	actor.capture_home_transform()

	var model: CommonBattleHumanoid3D = actor.get_humanoid_model()
	var skeleton: Skeleton3D = actor.get_skeleton()
	if model == null or skeleton == null or skeleton.name != "HumanoidSkeleton":
		_fail("Common humanoid smoke failed: Skeleton3D model was not created")
		return
	if skeleton.get_bone_count() != CommonBattleHumanoid3D.BONE_DEFINITIONS.size():
		_fail("Common humanoid smoke failed: expected %d bones, found %d" % [
			CommonBattleHumanoid3D.BONE_DEFINITIONS.size(),
			skeleton.get_bone_count(),
		])
		return
	for required_bone in ["root", "hips", "spine", "chest", "head", "left_hand", "right_hand", "left_foot", "right_foot"]:
		if skeleton.find_bone(required_bone) < 0:
			_fail("Common humanoid smoke failed: missing bone %s" % required_bone)
			return

	var expected_sockets: Array[String] = ["back", "chest", "head", "left_hand", "right_hand"]
	if model.get_socket_ids() != expected_sockets:
		_fail("Common humanoid smoke failed: equipment sockets were incomplete (%s)" % [model.get_socket_ids()])
		return
	for socket_id in expected_sockets:
		var socket: BoneAttachment3D = actor.get_equipment_socket(socket_id)
		if socket == null or socket.get_skeleton() != skeleton:
			_fail("Common humanoid smoke failed: socket %s is not attached to the skeleton" % socket_id)
			return
	if actor.find_child("DefaultWeapon", true, false) == null \
	or actor.find_child("DefaultShield", true, false) == null \
	or actor.find_child("PowerPack", true, false) == null:
		_fail("Common humanoid smoke failed: default equipment was not mounted on sockets")
		return

	var geometry_count: int = model.get_geometry_piece_count()
	if geometry_count < 24 or geometry_count > 32:
		_fail("Common humanoid smoke failed: low-poly geometry budget was invalid (%d pieces)" % geometry_count)
		return
	for raw_node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = raw_node as MeshInstance3D
		if mesh_instance == null:
			continue
		var cylinder: CylinderMesh = mesh_instance.mesh as CylinderMesh
		if cylinder != null and cylinder.radial_segments > 8:
			_fail("Common humanoid smoke failed: %s exceeded the radial segment budget" % mesh_instance.name)
			return
		var sphere: SphereMesh = mesh_instance.mesh as SphereMesh
		if sphere != null and (sphere.radial_segments > 8 or sphere.rings > 4):
			_fail("Common humanoid smoke failed: %s exceeded the sphere segment budget" % mesh_instance.name)
			return

	if not _assert_bone_action(actor, BattleActor3D.ACTION_READY, "right_upper_arm", 0.45):
		return
	if not _assert_bone_action(actor, BattleActor3D.ACTION_CAST, "right_upper_arm", 0.70):
		return
	if not _assert_bone_action(actor, BattleActor3D.ACTION_ATTACK, "right_upper_arm", 0.65):
		return
	if not _assert_bone_action(actor, BattleActor3D.ACTION_HIT, "spine", 0.12):
		return
	if not _assert_bone_action(actor, BattleActor3D.ACTION_BLOCK, "left_upper_arm", 0.70):
		return
	if not _assert_bone_action(actor, BattleActor3D.ACTION_HEAL, "left_upper_arm", 0.80):
		return
	if not _assert_bone_action(actor, BattleActor3D.ACTION_SHIELD, "left_upper_arm", 0.70):
		return
	if not _assert_bone_action(actor, BattleActor3D.ACTION_STATUS, "spine", 0.05):
		return
	if not _assert_bone_action(actor, BattleActor3D.ACTION_INTERRUPT, "spine", 0.10):
		return
	if not _assert_bone_action(actor, BattleActor3D.ACTION_VICTORY, "right_upper_arm", 1.20):
		return

	actor.reset_performance()
	actor.start_timeline_stance()
	actor._process(0.05)
	var entry_blend: float = actor.get_timeline_stance_blend()
	actor._process(0.20)
	var held_blend: float = actor.get_timeline_stance_blend()
	var chest_position: Vector3 = actor.get_bone_model_position("chest")
	var left_hand_depth: float = chest_position.z - actor.get_bone_model_position("left_hand").z
	var right_hand_depth: float = chest_position.z - actor.get_bone_model_position("right_hand").z
	if left_hand_depth < 0.18 or right_hand_depth < 0.18:
		_fail("Common humanoid smoke failed: ready hands must stay in front of the chest (left %.3f, right %.3f)" % [
			left_hand_depth,
			right_hand_depth,
		])
		return
	actor.stop_timeline_stance()
	actor._process(0.08)
	var exit_blend: float = actor.get_timeline_stance_blend()
	actor._process(0.24)
	if entry_blend <= 0.0 \
	or entry_blend >= 1.0 \
	or held_blend < 0.99 \
	or exit_blend <= 0.0 \
	or exit_blend >= held_blend \
	or actor.get_timeline_stance_blend() > 0.001 \
	or actor.get_action_name() != "idle":
		_fail("Common humanoid smoke failed: timeline stance did not blend in and out smoothly")
		return

	actor.reset_performance()
	actor.play_action(BattleActor3D.ACTION_SHIELD)
	actor._process(0.24)
	var shield_disc: MeshInstance3D = actor.find_child("ShieldDisc", true, false) as MeshInstance3D
	if shield_disc == null or shield_disc.scale.x <= 1.08:
		_fail("Common humanoid smoke failed: shield animation did not pulse socket equipment")
		return

	actor.reset_performance()
	actor.play_action(BattleActor3D.ACTION_DEFEAT)
	actor._process(0.42)
	if absf(actor.rotation.z) < 0.22:
		_fail("Common humanoid smoke failed: defeat animation did not move the whole skeleton")
		return

	print("COMMON_BATTLE_HUMANOID_SMOKE_OK 18-bone low-poly model, sockets, and full action set validated")
	get_tree().quit()


func _assert_bone_action(actor: BattleActor3D, action: StringName, bone_name: String, minimum_angle: float) -> bool:
	actor.reset_performance()
	actor.play_action(action)
	actor._process(0.18)
	var rotation_angle: float = Quaternion.IDENTITY.angle_to(actor.get_bone_pose_rotation(bone_name))
	if actor.get_action_name() != String(action) or rotation_angle < minimum_angle:
		_fail("Common humanoid smoke failed: %s did not animate %s (%.3f)" % [action, bone_name, rotation_angle])
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
