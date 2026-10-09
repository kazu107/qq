extends RefCounted
class_name BattleAnalysis

var rows: Dictionary = {}
var fatigue_hits: int = 0
var fatigue_hp_damage: int = 0
var fatigue_shield_damage: int = 0
const MAX_HP_SAMPLES: int = 1024
var hp_history: Array[Dictionary] = []
var totals: Dictionary = {}
var combatants: Dictionary = {}
var _sample_interval: float = 0.5


func capture_state(state: BattleState, force: bool = false) -> void:
	if state == null or state.player == null or state.enemy == null:
		return
	if not force and not hp_history.is_empty() and state.battle_time - float(hp_history.back()["time"]) < _sample_interval:
		return
	for side: String in ["player", "enemy"]:
		var unit: UnitState = state.get_unit(side)
		totals[side] = unit.combat_totals.duplicate()
		combatants[side] = {"id": unit.unit_id, "name": unit.display_name, "max_hp": unit.max_hp}
	_append_hp({"time": state.battle_time, "player": state.player.hp, "enemy": state.enemy.hp})


func _append_hp(sample: Dictionary) -> void:
	if not hp_history.is_empty() and hp_history.back() == sample:
		return
	hp_history.append(sample)
	if hp_history.size() > MAX_HP_SAMPLES:
		var compact: Array[Dictionary] = []
		for index: int in range(0, hp_history.size(), 2):
			compact.append(hp_history[index])
		if compact.back() != hp_history.back():
			compact.append(hp_history.back())
		hp_history = compact
		_sample_interval *= 2.0


func record(event: Dictionary) -> void:
	var kind: String = String(event.get("event_type", ""))
	var result: Dictionary = Dictionary(event.get("result", {}))
	var player: Dictionary = Dictionary(result.get("player_after", result.get("player", {})))
	var enemy: Dictionary = Dictionary(result.get("enemy_after", result.get("enemy", {})))
	if not player.is_empty() and not enemy.is_empty():
		_append_hp({"time": float(event.get("time", 0.0)), "player": int(player.get("hp", 0)), "enemy": int(enemy.get("hp", 0))})
	if kind == "fatigue_card":
		fatigue_hits += 1
		for side: String in ["player", "enemy"]:
			var before: Dictionary = Dictionary(result.get(side + "_before", {}))
			var after: Dictionary = Dictionary(result.get(side + "_after", {}))
			fatigue_hp_damage += maxi(0, int(before.get("hp", 0)) - int(after.get("hp", 0)))
			fatigue_shield_damage += maxi(0, int(before.get("shield", 0)) - int(after.get("shield", 0)))
		return
	if kind != "resolve_card":
		return
	var actor: String = String(event.get("actor_id", ""))
	for side: String in combatants:
		if actor == String(combatants[side].get("id", "")):
			actor = side
			break
	# PvE enemy events use their enemy ID rather than the canonical engine side.
	if actor not in ["player", "enemy"]:
		actor = "enemy"
	var card_id: String = String(event.get("card_id", ""))
	var key: String = actor + ":" + card_id
	var row: Dictionary = rows.get(key, {"actor": actor, "card_id": card_id, "casts": 0, "damage": 0, "absorbed": 0, "shield": 0, "heal": 0})
	row["casts"] = int(row["casts"]) + 1
	var metrics: Dictionary = Dictionary(result.get("metrics", {}))
	# Old replays only have net snapshots; new recordings count each direct effect.
	if metrics.is_empty():
		for side: String in ["player", "enemy"]:
			var before: Dictionary = Dictionary(result.get(side + "_before", {}))
			var after: Dictionary = Dictionary(result.get(side + "_after", {}))
			var hp: int = int(after.get("hp", 0)) - int(before.get("hp", 0))
			var shield: int = int(after.get("shield", 0)) - int(before.get("shield", 0))
			metrics["damage"] = int(metrics.get("damage", 0)) + maxi(0, -hp)
			metrics["heal"] = int(metrics.get("heal", 0)) + maxi(0, hp)
			metrics["shield"] = int(metrics.get("shield", 0)) + maxi(0, shield)
	for metric: String in ["damage", "absorbed", "shield", "heal"]:
		row[metric] = int(row[metric]) + int(metrics.get(metric, 0))
	rows[key] = row


func to_dict() -> Dictionary:
	return {"cards": rows.values().duplicate(true), "fatigue_hits": fatigue_hits,
		"fatigue_hp_damage": fatigue_hp_damage, "fatigue_shield_damage": fatigue_shield_damage,
		"totals": totals.duplicate(true), "combatants": combatants.duplicate(true), "hp_history": hp_history.duplicate(true)}


static func get_totals(data: Dictionary) -> Dictionary:
	var result: Dictionary = Dictionary(data.get("totals", {})).duplicate(true)
	if not result.is_empty():
		return result
	result = {"player": {}, "enemy": {}}
	for row: Dictionary in Array(data.get("cards", [])):
		var side: String = String(row.get("actor", "enemy"))
		if not result.has(side):
			side = "enemy"
		for metric: String in ["damage", "absorbed", "shield", "heal", "casts"]:
			result[side][metric] = int(result[side].get(metric, 0)) + int(row.get(metric, 0))
	return result


static func from_events(events: Array) -> Dictionary:
	var analysis: BattleAnalysis = BattleAnalysis.new()
	for event: Dictionary in events:
		analysis.record(event)
	return analysis.to_dict()


static func describe(data: Dictionary) -> String:
	var lines: PackedStringArray = [Localization.get_text("analysis.columns", "Card / casts / HP damage / blocked / shield / heal")]
	for row: Dictionary in data.get("cards", []):
		var card: CardDef = Database.get_card(String(row.get("card_id", "")))
		lines.append("%s | %s : %d / %d / %d / %d / %d" % [String(row.get("actor", "")), card.name if card != null else String(row.get("card_id", "")), int(row.get("casts", 0)), int(row.get("damage", 0)), int(row.get("absorbed", 0)), int(row.get("shield", 0)), int(row.get("heal", 0))])
	lines.append(Localization.get_text("analysis.fatigue", "Fatigue: hits / HP damage / blocked") + " %d / %d / %d" % [int(data.get("fatigue_hits", 0)), int(data.get("fatigue_hp_damage", 0)), int(data.get("fatigue_shield_damage", 0))])
	lines.append(Localization.get_text("analysis.direct", "Card values count direct effects only; status/relic follow-up damage is not attributed to a card."))
	return "\n".join(lines)
