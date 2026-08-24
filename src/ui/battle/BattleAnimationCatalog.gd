extends RefCounted
class_name BattleAnimationCatalog

const DATA_PATH: String = "res://data/battle_animations.json"
const SKELETON_TRACK_PATH: String = "VisualMotionRoot/CommonBattleHumanoid3D/HumanoidSkeleton"
const MOTION_ROOT_TRACK_PATH: String = "VisualMotionRoot"

static var _data: Dictionary = {}
static var _animation_library: AnimationLibrary
static var _load_error: String = ""


static func warm_cache() -> int:
	_ensure_loaded()
	_build_animation_library()
	return get_clip_ids().size()


static func get_load_error() -> String:
	_ensure_loaded()
	return _load_error


static func get_fps() -> int:
	_ensure_loaded()
	return maxi(1, int(_data.get("fps", 30)))


static func get_blend_time() -> float:
	_ensure_loaded()
	return maxf(0.0, float(_data.get("blend_time", 0.18)))


static func get_clip_ids() -> Array[String]:
	_ensure_loaded()
	var clip_ids: Array[String] = []
	var clips: Dictionary = Dictionary(_data.get("clips", {}))
	for raw_clip_id: Variant in clips.keys():
		clip_ids.append(String(raw_clip_id))
	clip_ids.sort()
	return clip_ids


static func has_clip(clip_id: String) -> bool:
	_ensure_loaded()
	return Dictionary(_data.get("clips", {})).has(clip_id)


static func get_clip_data(clip_id: String) -> Dictionary:
	_ensure_loaded()
	return Dictionary(Dictionary(_data.get("clips", {})).get(clip_id, {})).duplicate(true)


static func get_clip_duration(clip_id: String, fallback: float = 0.62) -> float:
	var clip_data: Dictionary = get_clip_data(clip_id)
	return maxf(0.01, float(clip_data.get("duration", fallback)))


static func is_looping(clip_id: String) -> bool:
	return bool(get_clip_data(clip_id).get("loop", false))


static func get_clip_events(clip_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_events: Array = Array(get_clip_data(clip_id).get("events", []))
	for raw_event: Variant in raw_events:
		if raw_event is Dictionary:
			result.append(Dictionary(raw_event).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("time", 0.0)) < float(right.get("time", 0.0))
	)
	return result


static func get_marker_time(clip_id: String, marker_id: String, fallback: float = -1.0) -> float:
	for event_data: Dictionary in get_clip_events(clip_id):
		if String(event_data.get("id", "")) == marker_id:
			return float(event_data.get("time", fallback))
	return fallback


static func resolve_clip(action_id: String, weapon_type: String, offhand_type: String) -> String:
	_ensure_loaded()
	if action_id != "ready" and action_id != "attack":
		return action_id if has_clip(action_id) else "idle"
	var variants: Dictionary = Dictionary(_data.get("variants", {}))
	var variant_data: Dictionary = Dictionary(variants.get(action_id, {}))
	var weapon_variants: Dictionary = Dictionary(variant_data.get("weapon", {}))
	if weapon_variants.has(weapon_type):
		return String(weapon_variants.get(weapon_type, variant_data.get("default", "idle")))
	var offhand_variants: Dictionary = Dictionary(variant_data.get("offhand", {}))
	if offhand_variants.has(offhand_type):
		return String(offhand_variants.get(offhand_type, variant_data.get("default", "idle")))
	return String(variant_data.get("default", "idle"))


static func get_animation_library() -> AnimationLibrary:
	_ensure_loaded()
	_build_animation_library()
	return _animation_library


static func get_source_sha256() -> String:
	if not FileAccess.file_exists(DATA_PATH):
		return ""
	return FileAccess.get_sha256(DATA_PATH)


static func _ensure_loaded() -> void:
	if not _data.is_empty() or _load_error != "":
		return
	if not FileAccess.file_exists(DATA_PATH):
		_load_error = "Battle animation catalog is missing: %s" % DATA_PATH
		push_error(_load_error)
		return
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		_load_error = "Battle animation catalog could not be opened: %s" % DATA_PATH
		push_error(_load_error)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_load_error = "Battle animation catalog root must be a Dictionary"
		push_error(_load_error)
		return
	_data = Dictionary(parsed)
	if Dictionary(_data.get("clips", {})).is_empty():
		_load_error = "Battle animation catalog has no clips"
		_data.clear()
		push_error(_load_error)


static func _build_animation_library() -> void:
	if _animation_library != null or _data.is_empty():
		return
	_animation_library = AnimationLibrary.new()
	var clips: Dictionary = Dictionary(_data.get("clips", {}))
	for clip_id: String in get_clip_ids():
		var clip_data: Dictionary = Dictionary(clips.get(clip_id, {}))
		var animation: Animation = _build_animation(clip_id, clip_data)
		_animation_library.add_animation(StringName(clip_id), animation)


static func _build_animation(clip_id: String, clip_data: Dictionary) -> Animation:
	var animation := Animation.new()
	animation.resource_name = clip_id
	animation.length = get_clip_duration(clip_id)
	animation.loop_mode = Animation.LOOP_LINEAR if bool(clip_data.get("loop", false)) else Animation.LOOP_NONE
	var keyframes: Array[Dictionary] = _normalized_keyframes(clip_data, animation.length)
	var rotation_bones: Array[String] = _all_bone_names()
	var position_bones: Array[String] = rotation_bones.duplicate()
	var rest_positions: Dictionary = _bone_rest_positions()

	for bone_name: String in rotation_bones:
		var track_index: int = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track_index, NodePath("%s:%s" % [SKELETON_TRACK_PATH, bone_name]))
		animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_LINEAR)
		for keyframe: Dictionary in keyframes:
			var rotations: Dictionary = Dictionary(keyframe.get("rotations", {}))
			var rotation_euler: Vector3 = _vector3_from_json(rotations.get(bone_name, []), Vector3.ZERO)
			animation.track_insert_key(track_index, float(keyframe.get("time", 0.0)), Quaternion.from_euler(rotation_euler))

	for bone_name: String in position_bones:
		var track_index: int = animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track_index, NodePath("%s:%s" % [SKELETON_TRACK_PATH, bone_name]))
		animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_LINEAR)
		var rest_position: Vector3 = Vector3(rest_positions.get(bone_name, Vector3.ZERO))
		for keyframe: Dictionary in keyframes:
			var positions: Dictionary = Dictionary(keyframe.get("positions", {}))
			var position_offset: Vector3 = _vector3_from_json(positions.get(bone_name, []), Vector3.ZERO)
			animation.track_insert_key(track_index, float(keyframe.get("time", 0.0)), rest_position + position_offset)

	var motion_position_track: int = animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(motion_position_track, NodePath(MOTION_ROOT_TRACK_PATH))
	animation.track_set_interpolation_type(motion_position_track, Animation.INTERPOLATION_LINEAR)
	var motion_rotation_track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(motion_rotation_track, NodePath(MOTION_ROOT_TRACK_PATH))
	animation.track_set_interpolation_type(motion_rotation_track, Animation.INTERPOLATION_LINEAR)
	for keyframe: Dictionary in keyframes:
		var key_time: float = float(keyframe.get("time", 0.0))
		animation.track_insert_key(
			motion_position_track,
			key_time,
			_vector3_from_json(keyframe.get("motion_position", []), Vector3.ZERO)
		)
		var motion_rotation: Vector3 = _vector3_from_json(keyframe.get("motion_rotation", []), Vector3.ZERO)
		animation.track_insert_key(
			motion_rotation_track,
			key_time,
			Quaternion.from_euler(motion_rotation)
		)

	var events: Array[Dictionary] = get_clip_events(clip_id)
	if not events.is_empty():
		var method_track: int = animation.add_track(Animation.TYPE_METHOD)
		animation.track_set_path(method_track, NodePath("."))
		for event_data: Dictionary in events:
			var marker_id: String = String(event_data.get("id", ""))
			var marker_time: float = clampf(float(event_data.get("time", 0.0)), 0.0, animation.length)
			animation.track_insert_key(method_track, marker_time, {
				"method": &"_on_animation_marker_from_clip",
				"args": [clip_id, marker_id, marker_time],
			})
	return animation


static func _normalized_keyframes(clip_data: Dictionary, duration: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_keyframes: Array = Array(clip_data.get("keyframes", []))
	for raw_keyframe: Variant in raw_keyframes:
		if raw_keyframe is Dictionary:
			result.append(Dictionary(raw_keyframe).duplicate(true))
	if result.is_empty():
		result.append({"time": 0.0, "rotations": {}})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("time", 0.0)) < float(right.get("time", 0.0))
	)
	if float(result[0].get("time", 0.0)) > 0.0001:
		result.push_front({"time": 0.0, "rotations": {}})
	if float(result[-1].get("time", 0.0)) < duration - 0.0001:
		result.append({"time": duration, "rotations": {}})
	return result


static func _collect_animated_bones(keyframes: Array[Dictionary], property_name: String) -> Array[String]:
	var seen: Dictionary = {}
	for keyframe: Dictionary in keyframes:
		var bone_values: Dictionary = Dictionary(keyframe.get(property_name, {}))
		for raw_bone_name: Variant in bone_values.keys():
			seen[String(raw_bone_name)] = true
	var result: Array[String] = []
	for raw_bone_name: Variant in seen.keys():
		result.append(String(raw_bone_name))
	result.sort()
	return result


static func _all_bone_names() -> Array[String]:
	var result: Array[String] = []
	for definition: Dictionary in CommonBattleHumanoid3D.BONE_DEFINITIONS:
		result.append(String(definition.get("name", "")))
	return result


static func _keyframes_have_property(keyframes: Array[Dictionary], property_name: String) -> bool:
	for keyframe: Dictionary in keyframes:
		if keyframe.has(property_name):
			return true
	return false


static func _bone_rest_positions() -> Dictionary:
	var result: Dictionary = {}
	for definition: Dictionary in CommonBattleHumanoid3D.BONE_DEFINITIONS:
		result[String(definition.get("name", ""))] = Vector3(definition.get("position", Vector3.ZERO))
	return result


static func _vector3_from_json(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
