extends Node

const BLENDER_LIBRARY_PATH: String = "res://assets/models/battle/battle_animation_library.glb"
const BLENDER_MANIFEST_PATH: String = "res://assets/models/battle/battle_animation_library.manifest.json"


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	var clip_ids: Array[String] = BattleAnimationCatalog.get_clip_ids()
	if clip_ids.size() != 18 or BattleAnimationCatalog.get_load_error() != "":
		_fail("Battle animation smoke failed: catalog was invalid (%d clips, %s)" % [
			clip_ids.size(),
			BattleAnimationCatalog.get_load_error(),
		])
		return
	var library: AnimationLibrary = BattleAnimationCatalog.get_animation_library()
	if library == null or library.get_animation_list().size() != clip_ids.size():
		_fail("Battle animation smoke failed: runtime AnimationLibrary was incomplete")
		return

	var imported_scene: PackedScene = load(BLENDER_LIBRARY_PATH) as PackedScene
	if imported_scene == null:
		_fail("Battle animation smoke failed: Blender GLB was not imported")
		return
	var imported_root: Node = imported_scene.instantiate()
	add_child(imported_root)
	var imported_player: AnimationPlayer = _find_animation_player(imported_root)
	if imported_player == null:
		_fail("Battle animation smoke failed: Blender GLB had no AnimationPlayer")
		return
	var imported_clips: Array[String] = []
	for raw_name: StringName in imported_player.get_animation_list():
		var clip_name: String = String(raw_name).trim_prefix("BattleAnimationArmature|")
		if clip_ids.has(clip_name):
			imported_clips.append(clip_name)
	if imported_clips.size() != clip_ids.size():
		_fail("Battle animation smoke failed: Blender GLB exposed %d/%d clips (%s)" % [
			imported_clips.size(), clip_ids.size(), imported_player.get_animation_list(),
		])
		return
	var manifest_file: FileAccess = FileAccess.open(BLENDER_MANIFEST_PATH, FileAccess.READ)
	var manifest_raw: Variant = JSON.parse_string(manifest_file.get_as_text()) if manifest_file != null else null
	var manifest: Dictionary = Dictionary(manifest_raw) if manifest_raw is Dictionary else {}
	if String(manifest.get("source_sha256", "")) != BattleAnimationCatalog.get_source_sha256():
		_fail("Battle animation smoke failed: Blender outputs are stale relative to the JSON catalog")
		return

	var actor := BattleActor3D.new()
	actor.configure("player")
	add_child(actor)
	await get_tree().process_frame
	if not actor.is_animation_graph_ready() \
	or actor.get_animation_player() == null \
	or actor.get_animation_tree() == null \
	or actor.get_animation_state_count() != clip_ids.size():
		_fail("Battle animation smoke failed: actor graph was not ready")
		return
	actor.reset_performance()
	actor.start_timeline_stance()
	actor._process(0.24)
	var ready_chest_z: float = actor.get_bone_model_position("chest").z
	var ready_left_depth: float = ready_chest_z - actor.get_bone_model_position("left_hand").z
	var ready_right_depth: float = ready_chest_z - actor.get_bone_model_position("right_hand").z
	for _sample_index in range(12):
		actor._process(0.1)
		ready_chest_z = actor.get_bone_model_position("chest").z
		var sampled_left_depth: float = ready_chest_z - actor.get_bone_model_position("left_hand").z
		var sampled_right_depth: float = ready_chest_z - actor.get_bone_model_position("right_hand").z
		ready_left_depth = minf(ready_left_depth, sampled_left_depth)
		ready_right_depth = minf(ready_right_depth, sampled_right_depth)
	if actor.get_active_animation_clip() != "ready_guard" \
	or ready_left_depth < 0.45 \
	or ready_right_depth < 0.45:
		_fail("Battle animation smoke failed: ready_guard did not hold both hands forward (%.3f / %.3f)" % [
			ready_left_depth,
			ready_right_depth,
		])
		return
	actor.configure_visual("scout", Database.get_battle_visual_profile("scout", "default_enemy"))
	actor.reset_performance()
	actor.start_timeline_stance()
	actor._process(0.24)
	if actor.get_active_animation_clip() != "ready_melee":
		_fail("Battle animation smoke failed: dual-blade loadout did not select ready_melee")
		return
	if not _assert_attack_variant(actor, "fortress", "attack_heavy") \
	or not _assert_attack_variant(actor, "chrono", "attack_arcane") \
	or not _assert_attack_variant(actor, "turret", "attack_ranged"):
		return
	actor.configure_visual("balanced", Database.get_battle_visual_profile("balanced", "default_player"))

	actor.reset_performance()
	actor.play_action(BattleActor3D.ACTION_HIT)
	var hit_angle: float = 0.0
	for _frame_index in range(8):
		actor._process(0.05)
		hit_angle = maxf(
			hit_angle,
			Quaternion.IDENTITY.angle_to(actor.get_bone_pose_rotation("spine"))
		)
	if actor.get_active_animation_clip() != "hit" or hit_angle < 0.12:
		_fail("Battle animation smoke failed: hit clip did not drive the skeleton (%.3f)" % hit_angle)
		return

	actor.clear_animation_marker_history()
	actor.reset_performance()
	actor.play_action(BattleActor3D.ACTION_ATTACK)
	for _frame_index in range(14):
		actor._process(0.05)
	var marker_ids: Array[String] = []
	for marker_data: Dictionary in actor.get_animation_marker_history():
		marker_ids.append(String(marker_data.get("marker", "")))
	if actor.get_active_animation_clip() != "attack_melee" \
	or not marker_ids.has("release") \
	or not marker_ids.has("impact"):
		_fail("Battle animation smoke failed: attack markers were incomplete (%s)" % [marker_ids])
		return

	print("BATTLE_ANIMATION_SYSTEM_SMOKE_OK 18 Blender/runtime clips, AnimationTree, and markers validated")
	get_tree().quit()


func _assert_attack_variant(actor: BattleActor3D, visual_id: String, expected_clip: String) -> bool:
	actor.configure_visual(visual_id, Database.get_battle_visual_profile(visual_id, "default_player"))
	actor.reset_performance()
	actor.play_action(BattleActor3D.ACTION_ATTACK)
	actor._process(0.05)
	if actor.get_active_animation_clip() != expected_clip:
		_fail("Battle animation smoke failed: %s selected %s instead of %s" % [
			visual_id,
			actor.get_active_animation_clip(),
			expected_clip,
		])
		return false
	return true


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child: Node in root.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
