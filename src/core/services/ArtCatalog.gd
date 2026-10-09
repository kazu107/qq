extends RefCounted
class_name ArtCatalog

const PROVENANCE_PATH: String = "res://data/art_provenance.json"
static var _entries: Array[Dictionary] = []
static var _textures: Dictionary = {}


static func get_entries() -> Array[Dictionary]:
	if _entries.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROVENANCE_PATH))
		if parsed is Dictionary:
			for raw: Variant in Array(Dictionary(parsed).get("assets", [])):
				if raw is Dictionary:
					_entries.append(Dictionary(raw).duplicate(true))
		_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return "%s/%s" % [a.get("category", ""), a.get("asset_id", "")] < "%s/%s" % [b.get("category", ""), b.get("asset_id", "")]
		)
	return _entries.duplicate(true)


static func get_texture(path: String) -> Texture2D:
	var resource_path: String = path if path.begins_with("res://") else "res://" + path
	if not _textures.has(resource_path) and ResourceLoader.exists(resource_path):
		var texture: Texture2D = ResourceLoader.load(resource_path) as Texture2D
		if texture != null:
			_textures[resource_path] = texture
	return _textures.get(resource_path) as Texture2D


static func warm_background_cache() -> int:
	var warmed: int = 0
	for path: String in ["assets/backgrounds/hub.png", "assets/backgrounds/run_result.png"]:
		if get_texture(path) != null:
			warmed += 1
	return warmed
