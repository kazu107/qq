extends Node

const STARTERS: Array[String] = ["balanced", "tempo", "fortress", "vanguard", "aegis", "chrono", "turret"]
const SOCKETS: Array[String] = ["left_hand", "right_hand", "chest", "head", "back"]


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/blender/characters/qq_starters.manifest.json")) as Dictionary
	var entries: Array = manifest.get("assets", [])
	if entries.size() != STARTERS.size():
		_fail("expected seven source records")
		return
	var hashes: Dictionary = {}
	var total_bytes: int = 0
	for starter_id: String in STARTERS:
		var profile: Dictionary = Database.get_battle_visual_profile(starter_id)
		var model_path: String = "res://assets/models/battle/%s.glb" % starter_id
		if String(profile.get("model_scene", "")) != model_path:
			_fail("missing authored profile: " + starter_id)
			return
		var entry: Dictionary = {}
		for candidate: Dictionary in entries:
			if String(candidate.get("id", "")) == starter_id:
				entry = candidate
		if entry.is_empty() or int(entry.get("triangles", 0)) > 35000:
			_fail("source geometry budget: " + starter_id)
			return
		var portrait_path: String = "res://assets/portraits/%s.png" % starter_id
		for kind: String in ["model", "portrait"]:
			var path: String = model_path if kind == "model" else portrait_path
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file == null:
				_fail("missing file: " + path)
				return
			total_bytes += file.get_length()
			var digest: String = FileAccess.get_sha256(path)
			if digest != String(entry.get(kind + "_sha256", "")) or hashes.has(digest):
				_fail("stale or duplicate output: " + path)
				return
			hashes[digest] = path
		var portrait: Texture2D = load(portrait_path) as Texture2D
		if portrait == null or portrait.get_size() != Vector2(1024, 1024):
			_fail("portrait import size: " + starter_id)
			return
		var actor := BattleActor3D.new()
		actor.configure("player", starter_id, profile)
		add_child(actor)
		actor.set_process(false)
		await get_tree().process_frame
		if not actor.is_using_authored_model() or actor.get_authored_mesh_count() != 1:
			_fail("actor is using fallback geometry: " + starter_id)
			return
		var source: Skeleton3D = actor.get_skeleton()
		var target: Skeleton3D = actor.get_authored_skeleton()
		if source.get_bone_count() != 18 or target.get_bone_count() != 18:
			_fail("skeleton mismatch: " + starter_id)
			return
		for socket_id: String in SOCKETS:
			var socket: BoneAttachment3D = actor.get_equipment_socket(socket_id)
			if socket == null or target.find_bone(socket.bone_name) < 0:
				_fail("socket mismatch: " + starter_id + "/" + socket_id)
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
						_fail("pose mismatch: %s/%s/%s" % [starter_id, clip_id, source.get_bone_name(bone)])
						return
		actor.reset_performance()
		actor.start_timeline_stance()
		actor.call("_process", 0.25)
		if not actor.get_active_animation_clip().begins_with("ready"):
			_fail("timeline stance missing: " + starter_id)
			return
		actor.free()
	if total_bytes > 20 * 1024 * 1024:
		_fail("starter models and portraits exceeded the 20 MiB batch budget")
		return
	var warmed: int = BattleActor3D.warm_authored_model_cache(Database.get_all_battle_visual_profiles())
	if warmed < 8 or warmed != BattleActor3D.warm_authored_model_cache(Database.get_all_battle_visual_profiles()):
		_fail("authored model cache is incomplete or not reusable")
		return
	print("STARTER_ART_SMOKE_OK 7 starters, 126 clips at 4 samples, 5 sockets, portraits, cache, %d bytes" % total_bytes)
	get_tree().quit()


func _fail(reason: String) -> void:
	push_error("Starter art smoke failed: " + reason)
	get_tree().quit(1)
