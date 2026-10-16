extends RefCounted
class_name AchievementIconCatalog

const ICON_DIRECTORY: String = "res://assets/icons/achievements"
static var _textures: Dictionary = {}


static func get_icon(achievement_id: String) -> Texture2D:
	if _textures.has(achievement_id): return _textures[achievement_id] as Texture2D
	if Database.get_achievement(achievement_id).is_empty(): return null
	var path: String = "%s/%s.png" % [ICON_DIRECTORY, achievement_id]
	if not ResourceLoader.exists(path): return null
	var texture: Texture2D = load(path) as Texture2D
	if texture != null: _textures[achievement_id] = texture
	return texture


static func warm_cache() -> int:
	for id: String in Database.get_all_achievement_ids(): get_icon(id)
	return _textures.size()
