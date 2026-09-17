extends RefCounted
class_name BattleAnalysis

var rows: Dictionary = {}
var fatigue_hits: int = 0
var fatigue_hp_damage: int = 0
var fatigue_shield_damage: int = 0


func record(event: Dictionary) -> void:
	var kind: String = String(event.get("event_type", ""))
	var result: Dictionary = Dictionary(event.get("result", {}))
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
		"fatigue_hp_damage": fatigue_hp_damage, "fatigue_shield_damage": fatigue_shield_damage}


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
