extends RefCounted
class_name InfiniteEnemyCatalog

const DATA_PATH := "res://data/infinite_enemy_variants.json"
const MAP_VERSION := 1
static var _loaded: bool = false
static var _entries: Array[Dictionary] = []
static var _by_base: Dictionary = {}
static var _by_variant: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_entries.clear()
	_by_base.clear()
	_by_variant.clear()
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Array: return
	for entry: Dictionary in parsed:
		_entries.append(entry)
		_by_base[String(entry["base_id"])] = entry
		_by_variant[String(entry["id"])] = entry


static func entries() -> Array[Dictionary]:
	_ensure_loaded()
	return _entries.duplicate(true)


static func base_id(id: String) -> String:
	_ensure_loaded()
	return String(_by_variant[id]["base_id"]) if _by_variant.has(id) else id


static func is_variant(id: String) -> bool:
	_ensure_loaded()
	return _by_variant.has(id)


static func material_role(name: String) -> String:
	var clean: String = name.get_slice(".", 0).to_lower()
	var scout: Dictionary = {"scout_olivecloth": "cloth", "scout_darkleather": "dark", "scout_tanleather": "trim",
		"scout_oliveedge": "edge", "scout_darksteel": "metal", "scout_amberlens": "glow",
		"scout_hood": "armor", "scout_redcloth": "cloth_shadow", "scout_rapieredge": "silver"}
	if scout.has(clean): return String(scout[clean])
	for role: String in ["cloth_shadow", "armor", "edge", "dark", "glow", "trim", "cloth", "metal", "silver"]:
		if clean.ends_with("_" + role): return role
	return ""


static func resolve(id: String, cycle: int) -> String:
	_ensure_loaded()
	return String(_by_base[id]["id"]) if cycle >= 2 and _by_base.has(id) else id


static func resolve_for_run(id: String, run: RunState) -> String:
	return resolve(id, cycle_number(run)) if run != null and run.infinite_mode and not run.arena_mode else id


static func cycle_number(run: RunState) -> int:
	if run == null or not run.infinite_mode: return 0
	var active: String = String(run.map_state.get("active_node_id", ""))
	for step: Dictionary in run.map_state.get("steps", []):
		for node: Dictionary in step.get("nodes", []):
			if String(node.get("id", "")) == active:
				return maxi(1, int(node.get("infinite_power", node.get("cycle", 1))))
	return 1 + floori(float(maxi(0, int(run.map_state.get("current_step", 0)))) / 28.0)


static func upgrade_node(node: Dictionary, cycle: int) -> void:
	if cycle < 2: return
	if node.has("enemy_id"):
		node["enemy_id"] = resolve(String(node["enemy_id"]), cycle)
	for key: String in ["encounter_queue", "hazard_queue"]:
		if not node.has(key): continue
		var queue: Array = Array(node[key]).duplicate()
		var first: int = int(node.get("hazard_cleared_waves" if key == "hazard_queue" else "encounters_cleared", 0))
		for index: int in range(clampi(first, 0, queue.size()), queue.size()):
			queue[index] = resolve(String(queue[index]), cycle)
		node[key] = queue


static func upgrade_map(map: Dictionary) -> void:
	if not bool(map.get("infinite", false)) or int(map.get("enemy_variant_version", 0)) >= MAP_VERSION: return
	for index: int in Array(map.get("steps", [])).size():
		var step: Dictionary = map["steps"][index]
		for node: Dictionary in step.get("nodes", []):
			if node.get("status", "") == "completed": continue
			upgrade_node(node, int(node.get("cycle", 1 + floori(float(index) / 28.0))))
	map["enemy_variant_version"] = MAP_VERSION


static func apply_definitions(enemies: Dictionary, visuals: Dictionary) -> void:
	for entry: Dictionary in entries():
		var base: EnemyDef = enemies.get(String(entry["base_id"])) as EnemyDef
		if base == null: continue
		var variant: EnemyDef = EnemyDef.from_dict({"id": entry["id"], "name": entry["name"],
			"base_enemy_id": base.id, "infinite_only": true, "max_hp": roundi(base.max_hp * 1.10),
			"attack": base.attack + 1, "speed": base.speed + int(entry.get("speed_bonus", 0)),
			"cards": entry["cards"], "role": base.role, "passive": base.passive.duplicate(true),
			"description": entry["tactics_ja"] if Localization.get_language() == "ja" else entry["tactics_en"]})
		enemies[variant.id] = variant
		var profile: Dictionary = Dictionary(visuals.get(base.id, {})).duplicate(true)
		var primary: Color = Color(String(entry["primary"]))
		var secondary: Color = Color(String(entry["secondary"]))
		profile.merge({"primary": entry["primary"], "secondary": entry["secondary"], "accent": entry["accent"],
			"material_palette": {"armor": primary.to_html(), "edge": primary.lightened(0.25).to_html(),
				"cloth": secondary.to_html(), "cloth_shadow": secondary.darkened(0.35).to_html(),
				"dark": secondary.darkened(0.2).to_html(), "glow": String(entry["accent"]).trim_prefix("#"),
				"trim": "f5c76c", "metal": "90a6b4", "silver": "dae5eb"}}, true)
		visuals[variant.id] = profile
