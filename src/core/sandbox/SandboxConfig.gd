extends RefCounted
class_name SandboxConfig

const MAX_CARDS: int = 64
const MAX_RELICS: int = 16
const MAX_ACTIVE: int = 256
const STAT_LIMITS: Dictionary = {"max_hp":[1,1000000], "hp":[1,1000000], "attack":[0,100000], "speed":[0,1000], "shield":[0,1000000], "slots":[1,64], "loadout_limit":[1,1000]}
static var _catalog: Dictionary = {}


static func _bounded(value: Variant, fallback: int, minimum: int, maximum: int) -> int:
	if value is not int and value is not float:return fallback
	if not is_finite(float(value)):return fallback
	return roundi(clampf(float(value),minimum,maximum))


static func side_from_starter(id: String = "balanced") -> Dictionary:
	var source: Dictionary = Database.get_starter(id)
	if source.is_empty(): source = Database.get_starter("balanced")
	var cards: Array[Dictionary] = []
	for card: String in Array(source.get("cards", ["quick_slash"])): cards.append({"id":card,"tier":0})
	return {"visual":String(source.get("id","balanced")),"max_hp":int(source.get("max_hp",60)),"hp":int(source.get("max_hp",60)),"attack":int(source.get("attack",3)),"speed":int(source.get("speed",5)),"shield":0,"slots":3,"loadout_limit":20,"cards":cards,"relics":[]}


static func side_from_enemy(id: String = "scout") -> Dictionary:
	var source: EnemyDef = Database.get_enemy(id)
	if source == null: source = Database.get_enemy("scout")
	var result: Dictionary = side_from_starter()
	result.merge({"visual":source.id,"max_hp":source.max_hp,"hp":source.max_hp,"attack":source.attack,"speed":source.speed,"cards":[]},true)
	for card: String in source.cards: result["cards"].append({"id":card,"tier":0})
	return result


static func defaults() -> Dictionary:
	return {"version":1,"enemy_id":"scout","player":side_from_starter(),"enemy":side_from_enemy(),"rules":{"fatigue":true,"enemy_ai":true,"player_ai":false,"boss_passive":true,"ignore_cost":true,"field":"clock_ruins","power":0,"seed":4242,"immortal_player":false,"immortal_enemy":false}}


static func normalize(raw: Dictionary) -> Dictionary:
	var result: Dictionary = defaults()
	var enemy_id: String = String(raw.get("enemy_id","scout"))
	if Database.get_enemy(enemy_id) != null: result["enemy_id"] = enemy_id
	for side: String in ["player","enemy"]:
		var source: Dictionary = raw.get(side,{}) if raw.get(side,{}) is Dictionary else {}
		var target: Dictionary = result[side]
		for stat: String in STAT_LIMITS:
			var value: Variant = source.get(stat,target[stat])
			if value is int or value is float:
				if is_finite(float(value)): target[stat] = _bounded(value,int(target[stat]),STAT_LIMITS[stat][0],STAT_LIMITS[stat][1])
		target["hp"] = mini(int(target["hp"]),int(target["max_hp"]))
		var visual: String = String(source.get("visual",target["visual"]))
		if Database.battle_visuals.has(visual): target["visual"] = visual
		if source.get("cards") is Array:
			target["cards"] = []
			for value: Variant in Array(source["cards"]).slice(0,MAX_CARDS):
				if value is not Dictionary: continue
				var id: String = String(value.get("id",""))
				if Database.get_card(id) != null: target["cards"].append({"id":id,"tier":_bounded(value.get("tier",0),0,0,CardUpgradeResolver.MAX_TIER)})
		if source.get("relics") is Array:
			target["relics"] = []
			for value: Variant in Array(source["relics"]).slice(0,MAX_RELICS):
				var id: String = String(value)
				if Database.get_relic(id) != null and not target["relics"].has(id): target["relics"].append(id)
	var rules: Dictionary = raw.get("rules",{}) if raw.get("rules",{}) is Dictionary else {}
	for key: String in ["fatigue","enemy_ai","player_ai","boss_passive","ignore_cost","immortal_player","immortal_enemy"]:
		if rules.get(key) is bool: result["rules"][key] = rules[key]
	result["rules"]["power"] = _bounded(rules.get("power",0),0,0,100)
	result["rules"]["seed"] = _bounded(rules.get("seed",4242),4242,1,2147483647)
	result["rules"]["field"] = String(BattleEnvironmentArt.get_field(String(rules.get("field","clock_ruins")))["id"])
	return result


static func loadout_cost(config: Dictionary, side: String) -> int:
	var cost: int = 0
	var base_cards: int = 0
	for card: Dictionary in config[side]["cards"]:
		cost += CardUpgradeResolver.build_card_at_tier(card["id"],int(card["tier"])).loadout_cost
		if int(card["tier"])==0: base_cards+=1
	if Array(config[side]["relics"]).has("unpolished_motherboard"):cost-=mini(3,maxi(0,base_cards-1))
	return maxi(0,cost)


static func errors(config: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for side: String in ["player","enemy"]:
		if Array(config[side]["cards"]).is_empty(): result.append(side + ": cards")
		if not config["rules"]["ignore_cost"]:
			var cost: int = loadout_cost(config,side)
			if cost > int(config[side]["loadout_limit"]): result.append(side + ": loadout")
	return result


static func make_run(config: Dictionary, side: String) -> RunState:
	var data: Dictionary = config[side]
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"),int(config["rules"]["seed"]))
	run.starter_id = String(data["visual"])
	run.max_hp = int(data["max_hp"]); run.player_hp = int(data["hp"])
	run.attack = int(data["attack"]); run.speed = int(data["speed"])
	run.loadout_limit = int(data["loadout_limit"])
	run.player_cards.clear(); run.equipped_cards.clear(); run.card_upgrades.clear()
	for card: Dictionary in data["cards"]: run.player_cards.append(String(card["id"]))
	run.equipped_cards.assign(run.player_cards)
	run.relics.assign(Array(data["relics"]))
	run.achievement_state = {"excluded":true}
	return run


static func catalog(kind: String) -> Array[Dictionary]:
	var key: String = Localization.get_language() + ":" + kind
	if _catalog.has(key): return _catalog[key]
	var result: Array[Dictionary] = []
	if kind == "card":
		var ids: Array[String] = Database.get_all_card_ids()
		for id: String in Database.boss_cards:
			if not ids.has(id): ids.append(id)
		for id: String in Database.enemy_cards:
			if not ids.has(id): ids.append(id)
		for id: String in ids:
			var card: CardDef = Database.get_card(id)
			if card != null: result.append({"id":id,"name":card.name,"rarity":card.rarity,"tags":card.tags})
	else:
		for id: String in Database.get_all_relic_ids():
			var relic: RelicDef = Database.get_relic(id)
			result.append({"id":id,"name":relic.name,"rarity":relic.rarity,"tags":[]})
	_catalog[key] = result
	return result
