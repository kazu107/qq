extends RefCounted
class_name BattleEnvironmentArt

const SCENE_PATH: String = "res://assets/models/environment/qq_battlefield.glb"
const DETAIL_COUNTS: Dictionary = {
	"grass": 112, "rocks": 18, "flowers": 16, "ruin_clusters": 2,
	"barrels": 2, "crates": 4, "distant_hills": 5,
	"distant_trees": 18, "distant_ruins": 2,
}

static var _scene: PackedScene


static func warm_cache() -> int:
	if _scene == null and ResourceLoader.exists(SCENE_PATH):
		_scene = ResourceLoader.load(SCENE_PATH) as PackedScene
	return 1 if _scene != null else 0


static func instantiate_field() -> Node3D:
	if warm_cache() == 0:
		return null
	var field: Node3D = _scene.instantiate() as Node3D
	if field != null:
		field.name = "AuthoredBattleField"
		field.set_meta("blender_source", "art_src/blender/environment/qq_battlefield.blend")
	return field
