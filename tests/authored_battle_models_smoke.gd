extends Node

const MODEL_PATHS: Dictionary = {
	"balanced": "res://assets/models/battle/balanced.glb",
	"scout": "res://assets/models/battle/scout.glb",
}
const EXPECTED_BONES: Array[String] = [
	"root", "hips", "spine", "chest", "neck", "head",
	"left_upper_leg", "left_lower_leg", "left_foot",
	"right_upper_leg", "right_lower_leg", "right_foot",
	"left_upper_arm", "left_forearm", "left_hand",
	"right_upper_arm", "right_forearm", "right_hand",
]
const MINIMUM_VERTICES: Dictionary = {
	"balanced": 1400,
	"scout": 1600,
}
const MINIMUM_SURFACES: Dictionary = {
	"balanced": 14,
	"scout": 13,
}

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	for visual_id: String in MODEL_PATHS:
		var model_path: String = String(MODEL_PATHS[visual_id])
		var packed_scene: PackedScene = load(model_path) as PackedScene
		if packed_scene == null:
			_fail("Authored model smoke failed: could not load %s" % model_path)
			return
		var instance: Node = packed_scene.instantiate()
		instance.name = "%sAuthoredProbe" % visual_id.capitalize()
		add_child(instance)
		await get_tree().process_frame

		var skeleton: Skeleton3D = _find_skeleton(instance)
		if skeleton == null:
			_fail("Authored model smoke failed: %s has no Skeleton3D" % visual_id)
			return
		if skeleton.get_bone_count() != EXPECTED_BONES.size():
			_fail("Authored model smoke failed: %s has %d bones" % [visual_id, skeleton.get_bone_count()])
			return
		for bone_name: String in EXPECTED_BONES:
			if skeleton.find_bone(bone_name) < 0:
				_fail("Authored model smoke failed: %s lacks bone %s" % [visual_id, bone_name])
				return

		var mesh_count: int = _count_meshes(instance)
		var vertex_count: int = _count_vertices(instance)
		var surface_count: int = _count_surfaces(instance)
		if mesh_count != 1 \
		or vertex_count < int(MINIMUM_VERTICES[visual_id]) \
		or vertex_count > 8000 \
		or surface_count < int(MINIMUM_SURFACES[visual_id]):
			_fail("Authored model smoke failed: %s detail/optimization budget is invalid (%d meshes, %d vertices, %d surfaces)" % [
				visual_id, mesh_count, vertex_count, surface_count,
			])
			return
		var bounds: AABB = _calculate_bounds(instance)
		if bounds.size.y < 2.2 or bounds.size.y > 2.9 or bounds.size.x < 1.0:
			_fail("Authored model smoke failed: %s has invalid bounds %s" % [visual_id, bounds])
			return
		instance.queue_free()
		await get_tree().process_frame

	if not await _validate_actor_integration():
		return

	print("AUTHORED_BATTLE_MODELS_SMOKE_OK GLBs, 18-bone pose sync, stage mapping, and procedural fallback validated")
	get_tree().quit()


func _validate_actor_integration() -> bool:
	var actor := BattleActor3D.new()
	actor.name = "AuthoredIntegrationProbe"
	actor.configure("player", "balanced", Database.get_battle_visual_profile("balanced", "default_player"))
	add_child(actor)
	await get_tree().process_frame
	if not actor.is_using_authored_model() \
	or actor.get_authored_model_path() != String(MODEL_PATHS["balanced"]) \
	or actor.get_authored_mesh_count() != 1 \
	or _count_visible_meshes(actor.get_humanoid_model()) != 0:
		_fail("Authored model smoke failed: Balanced actor did not replace procedural geometry")
		return false

	actor.play_action(BattleActor3D.ACTION_ATTACK, 1.0)
	actor.call("_process", 0.35)
	var source_skeleton: Skeleton3D = actor.get_skeleton()
	var authored_skeleton: Skeleton3D = actor.get_authored_skeleton()
	var source_arm: int = source_skeleton.find_bone("right_upper_arm") if source_skeleton != null else -1
	var authored_arm: int = authored_skeleton.find_bone("right_upper_arm") if authored_skeleton != null else -1
	if source_arm < 0 \
	or authored_arm < 0 \
	or not source_skeleton.get_bone_pose_rotation(source_arm).is_equal_approx(
		authored_skeleton.get_bone_pose_rotation(authored_arm)
	):
		_fail("Authored model smoke failed: attack pose was not synchronized to the GLB skeleton")
		return false

	actor.configure_visual("scout", Database.get_battle_visual_profile("scout", "default_enemy"))
	if not actor.is_using_authored_model() \
	or actor.get_authored_model_path() != String(MODEL_PATHS["scout"]) \
	or actor.get_authored_mesh_count() != 1:
		_fail("Authored model smoke failed: Scout actor was not selected")
		return false

	actor.configure_visual("brute", Database.get_battle_visual_profile("brute", "default_enemy"))
	if actor.is_using_authored_model() or _count_visible_meshes(actor.get_humanoid_model()) == 0:
		_fail("Authored model smoke failed: procedural fallback was not restored")
		return false
	actor.queue_free()

	var stage := BattleStage3D.new()
	stage.name = "AuthoredStageProbe"
	add_child(stage)
	await get_tree().process_frame
	stage.configure_combatants("local", "opponent", "player", "balanced", "scout")
	var local_actor: BattleActor3D = stage.find_child("PlayerBattleActor3D", true, false) as BattleActor3D
	var opponent_actor: BattleActor3D = stage.find_child("EnemyBattleActor3D", true, false) as BattleActor3D
	if local_actor == null \
	or opponent_actor == null \
	or not local_actor.is_using_authored_model() \
	or not opponent_actor.is_using_authored_model():
		_fail("Authored model smoke failed: battle stage did not map Balanced and Scout GLBs")
		return false
	stage.queue_free()
	return true


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _count_meshes(root: Node) -> int:
	var count: int = 1 if root is MeshInstance3D else 0
	for child: Node in root.get_children():
		count += _count_meshes(child)
	return count


func _count_vertices(root: Node) -> int:
	var count: int = 0
	if root is MeshInstance3D:
		var mesh_instance: MeshInstance3D = root as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				count += vertices.size()
	for child: Node in root.get_children():
		count += _count_vertices(child)
	return count


func _count_surfaces(root: Node) -> int:
	var count: int = 0
	if root is MeshInstance3D:
		var mesh_instance: MeshInstance3D = root as MeshInstance3D
		if mesh_instance.mesh != null:
			count += mesh_instance.mesh.get_surface_count()
	for child: Node in root.get_children():
		count += _count_surfaces(child)
	return count


func _count_visible_meshes(root: Node) -> int:
	var count: int = 1 if root is MeshInstance3D and (root as MeshInstance3D).visible else 0
	for child: Node in root.get_children():
		count += _count_visible_meshes(child)
	return count


func _calculate_bounds(root: Node) -> AABB:
	var bounds := AABB()
	var has_bounds: bool = false
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		if has_bounds:
			bounds = bounds.merge(mesh_bounds)
		else:
			bounds = mesh_bounds
			has_bounds = true
	return bounds


func _collect_meshes(root: Node, output: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D:
		output.append(root as MeshInstance3D)
	for child: Node in root.get_children():
		_collect_meshes(child, output)


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	get_tree().quit(1)
