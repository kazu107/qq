extends RefCounted
class_name DeckPresetService

const MAX_PRESETS: int = 20
const MAX_CARDS: int = 32


static func list_presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in Game.settings.get("deck_presets", []):
		if value is Dictionary and result.size() < MAX_PRESETS:
			result.append(Dictionary(value).duplicate(true))
	return result


static func save_preset(preset_name: String, cards: Array[String]) -> bool:
	preset_name = preset_name.strip_edges().left(32)
	if preset_name.is_empty() or not valid_cards(cards):
		return false
	var presets: Array[Dictionary] = list_presets()
	var index: int = -1
	for i in range(presets.size()):
		if String(presets[i].get("name", "")) == preset_name:
			index = i
	if index < 0:
		if presets.size() >= MAX_PRESETS:
			return false
		presets.append({})
		index = presets.size() - 1
	presets[index] = {"name": preset_name, "cards": cards.duplicate()}
	Game.settings["deck_presets"] = presets
	SaveManager.save_game(Game.current_screen_hint)
	return true


static func delete_preset(preset_name: String) -> void:
	var presets: Array[Dictionary] = list_presets()
	for i in range(presets.size() - 1, -1, -1):
		if String(presets[i].get("name", "")) == preset_name:
			presets.remove_at(i)
	Game.settings["deck_presets"] = presets
	SaveManager.save_game(Game.current_screen_hint)


static func valid_cards(cards: Array[String]) -> bool:
	if cards.is_empty() or cards.size() > MAX_CARDS:
		return false
	for card_id in cards:
		if Database.get_card(card_id) == null:
			return false
	return true


static func validate(run: RunState, cards: Array[String]) -> Dictionary:
	if run == null or not valid_cards(cards):
		return {"ok": false, "reason": "Invalid deck"}
	var needed: Dictionary = {}
	for card_id in cards:
		needed[card_id] = int(needed.get(card_id, 0)) + 1
		if int(needed[card_id]) > run.player_cards.count(card_id):
			return {"ok": false, "reason": Database.get_card(card_id).name + " : " + Localization.get_text("presets.missing", "Not enough copies")}
	var cost: int = RelicService.get_effective_loadout_cost_for_cards(run, cards)
	var limit: int = run.loadout_limit + RelicService.get_allowed_loadout_overage(run)
	return {"ok": cost <= limit, "cost": cost, "reason": "%d / %d" % [cost, limit]}


static func apply(run: RunState, cards: Array[String]) -> bool:
	if not bool(validate(run, cards).get("ok", false)):
		return false
	run.equipped_cards = cards.duplicate()
	return true
