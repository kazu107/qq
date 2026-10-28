extends RefCounted
class_name BattleEnvironmentArt

const SCENE_PATH: String = "res://assets/models/environment/qq_battlefield.glb"
const DETAIL_COUNTS: Dictionary = {
	"grass": 112, "rocks": 18, "flowers": 16, "ruin_clusters": 2,
	"barrels": 2, "crates": 4, "distant_hills": 5,
	"distant_trees": 18, "distant_ruins": 2,
}

static var _scene: PackedScene
static var _biomes: Dictionary = {}

const REGIONS: Array[String] = ["clock_ruins", "brass_foundry", "rift_gallery", "forgotten_sanctuary"]
const FIELDS: Array[Dictionary] = [
	{"id": "clock_ruins", "ja": "苔むす時計遺跡", "en": "Mossy Clock Ruins", "theme": "meadow"},
	{"id": "brass_foundry", "ja": "真鍮の機械工房", "en": "Brass Foundry", "theme": "foundry"},
	{"id": "rift_gallery", "ja": "亀裂の浮遊回廊", "en": "Fractured Sky Gallery", "theme": "rift"},
	{"id": "forgotten_sanctuary", "ja": "忘れられた時の聖域", "en": "Forgotten Sanctuary", "theme": "sanctuary"},
	{"id": "timekeeper_engine", "ja": "大時計塔の機関室", "en": "Great Clock Engine", "theme": "foundry"},
	{"id": "paradox_reactor", "ja": "循環する中枢炉", "en": "Recursive Core Reactor", "theme": "rift"},
	{"id": "axiom_altar", "ja": "崩壊した法則の祭壇", "en": "Broken Axiom Altar", "theme": "sanctuary"},
	{"id": "eternity_temple", "ja": "終刻の神殿", "en": "Temple of the Final Hour", "theme": "sanctuary"},
]
const BOSSES: Dictionary = {
	"boss_timekeeper": "timekeeper_engine", "boss_paradox_core": "paradox_reactor",
	"boss_axiom_breaker": "axiom_altar", "boss_eternity_zero": "eternity_temple",
}
const MODEL_ROOT: String = "res://assets/models/environment/biomes/"
const BACKGROUND_ROOT: String = "assets/backgrounds/biomes/"


static func get_context(run: RunState, enemy_id: String = "", tutorial: bool = false) -> Dictionary:
	# Pure presentation: do not advance maps or consume the gameplay RNG.
	if run == null or tutorial:
		return {"id": REGIONS[0], "infinite": false}
	var step: int = maxi(0, int(run.map_state.get("current_step", 0)))
	var region: int = (step % 28) / 7
	if run.arena_mode:
		region = ((maxi(1, run.arena_round) - 1) / 3) % 4
	var field_id: String = REGIONS[region]
	var base_enemy: String = enemy_id.trim_suffix("_ascended")
	if not run.arena_mode and BOSSES.has(base_enemy):
		field_id = String(BOSSES[base_enemy])
	return {"id": field_id, "infinite": run.infinite_mode and step >= 28}


static func get_field(field_id: String) -> Dictionary:
	for field: Dictionary in FIELDS:
		if field["id"] == field_id:
			return field.duplicate()
	return FIELDS[0].duplicate()


static func get_overlay_id(field_id: String) -> String:
	if REGIONS.has(field_id):
		return field_id + "_infinite"
	match String(get_field(field_id)["theme"]):
		"foundry": return "brass_foundry_infinite"
		"rift": return "rift_gallery_infinite"
		_: return "forgotten_sanctuary_infinite"


static func get_scene(asset_id: String) -> PackedScene:
	if not _biomes.has(asset_id):
		var path: String = MODEL_ROOT + asset_id + ".glb"
		if ResourceLoader.exists(path):
			_biomes[asset_id] = ResourceLoader.load(path) as PackedScene
	return _biomes.get(asset_id) as PackedScene


static func warm_biomes() -> int:
	for field: Dictionary in FIELDS:
		get_scene(String(field["id"]))
		ArtCatalog.get_texture(BACKGROUND_ROOT + String(field["id"]) + ".png")
	for region: String in REGIONS:
		get_scene(region + "_infinite")
		for facility: String in ["shop", "forge", "heal"]:
			ArtCatalog.get_texture(BACKGROUND_ROOT + region + "_" + facility + ".png")
	return _biomes.size()


static func warm_biomes_async(tree: SceneTree) -> int:
	var ids: Array[String] = REGIONS.duplicate()
	for field: Dictionary in FIELDS:
		if not ids.has(String(field["id"])): ids.append(String(field["id"]))
	for region: String in REGIONS: ids.append(region + "_infinite")
	for asset_id: String in ids:
		# Spread model loading over paint frames so the boot overlay can animate.
		get_scene(asset_id)
		await tree.process_frame
	for field: Dictionary in FIELDS:
		ArtCatalog.get_texture(BACKGROUND_ROOT + String(field["id"]) + ".png")
		await tree.process_frame
	for region: String in REGIONS:
		for facility: String in ["shop", "forge", "heal"]:
			ArtCatalog.get_texture(BACKGROUND_ROOT + region + "_" + facility + ".png")
			await tree.process_frame
	return _biomes.size()


static func background_for(run: RunState, facility_type: String = "") -> String:
	var region: String = String(get_context(run)["id"])
	var suffix: String = "_" + facility_type if facility_type in ["shop", "forge", "heal"] else ""
	return BACKGROUND_ROOT + region + suffix + ".png"


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
