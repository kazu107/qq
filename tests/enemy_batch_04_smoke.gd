extends Node

const IDS: Array[String] = [
	"brute", "disruptor", "raider", "medic_drone", "chronoguard", "phase_stalker",
	"void_bastion", "echo_revenant", "rift_predator", "entropy_colossus", "omega_seraph", "grave_architect", "scout",
]
const SOCKETS: Array[String] = ["left_hand", "right_hand", "chest", "head", "back"]


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/blender/characters/qq_enemies_04.manifest.json")) as Dictionary
	var entries: Array = manifest.get("assets", [])
	if entries.size() != IDS.size():
		_fail("expected thirteen manifest entries")
		return
	var hashes: Dictionary = {}
	var profiles: Array[Dictionary] = []
	var total_bytes: int = 0
	for visual_id: String in IDS:
		var entry: Dictionary = {}
		for candidate: Dictionary in entries:
			if String(candidate.get("id", "")) == visual_id:
				entry = candidate
		if entry.is_empty() or (visual_id != "scout" and int(entry.get("triangles", 0)) > 35000):
			_fail("missing ID or triangle budget: " + visual_id)
			return
		for kind: String in ["model", "portrait"]:
			var path: String = "res://" + String(entry.get(kind, ""))
			if not FileAccess.file_exists(path):
				_fail("missing output: " + path)
				return
			var digest: String = FileAccess.get_sha256(path)
			if digest != String(entry.get(kind + "_sha256", "")) or hashes.has(digest):
				_fail("stale or duplicate output: " + path)
				return
			hashes[digest] = path
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			total_bytes += file.get_length()
		var portrait: Texture2D = load("res://" + String(entry["portrait"])) as Texture2D
		if portrait == null or portrait.get_size() != Vector2(1024, 1024):
			_fail("portrait import: " + visual_id)
			return
		# The parent registers profiles later. Test the real actor with a local override.
		var profile: Dictionary = Database.get_battle_visual_profile(visual_id).duplicate(true)
		profile["model_scene"] = "res://" + String(entry["model"])
		profiles.append(profile)
		var actor := BattleActor3D.new()
		actor.configure("enemy", visual_id, profile)
		add_child(actor)
		actor.set_process(false)
		await get_tree().process_frame
		if not actor.is_using_authored_model() or actor.get_authored_mesh_count() != 1:
			_fail("authored actor import: " + visual_id)
			return
		var source: Skeleton3D = actor.get_skeleton()
		var target: Skeleton3D = actor.get_authored_skeleton()
		if source.get_bone_count() != 18 or target.get_bone_count() != 18:
			_fail("18-bone skeleton: " + visual_id)
			return
		for socket_id: String in SOCKETS:
			var socket: BoneAttachment3D = actor.get_equipment_socket(socket_id)
			if socket == null or target.find_bone(socket.bone_name) < 0:
				_fail("socket: " + visual_id + "/" + socket_id)
				return
		var tree: AnimationTree = actor.get_animation_tree()
		var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		for clip_id: String in BattleAnimationCatalog.get_clip_ids():
			for sample: float in [0.0, 0.33, 0.66, 1.0]:
				playback.start(StringName(clip_id), true)
				tree.advance(BattleAnimationCatalog.get_clip_duration(clip_id) * sample)
				source.force_update_all_bone_transforms()
				actor.call("_sync_authored_pose")
				for bone: int in source.get_bone_count():
					var target_bone: int = target.find_bone(source.get_bone_name(bone))
					if target_bone < 0 or not source.get_bone_global_pose(bone).is_equal_approx(target.get_bone_global_pose(target_bone)):
						_fail("clip pose: %s/%s/%s" % [visual_id, clip_id, source.get_bone_name(bone)])
						return
		actor.reset_performance()
		actor.start_timeline_stance()
		actor.call("_process", 0.25)
		if not actor.get_active_animation_clip().begins_with("ready"):
			_fail("timeline stance: " + visual_id)
			return
		actor.free()
	for path: String in manifest.get("protected_assets", {}):
		if FileAccess.get_sha256("res://" + path) != String(manifest["protected_assets"][path]):
			_fail("protected asset changed: " + path)
			return
	if total_bytes > 35 * 1024 * 1024:
		_fail("35 MiB combined model/portrait budget")
		return
	var warmed: int = BattleActor3D.warm_authored_model_cache(profiles)
	if warmed != BattleActor3D.warm_authored_model_cache(profiles) or warmed < IDS.size():
		_fail("authored cache reuse")
		return
	print("ENEMY_BATCH_04_SMOKE_OK 13 actors, 234 clips at 4 times, 65 sockets, 13 portraits, cache; %d bytes" % total_bytes)
	get_tree().quit()


func _fail(reason: String) -> void:
	push_error("Enemy batch 04 smoke failed: " + reason)
	get_tree().quit(1)
