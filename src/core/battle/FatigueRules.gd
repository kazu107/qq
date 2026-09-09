extends RefCounted
class_name FatigueRules

const CARD_ID: String = "environment_fatigue"
const SIDE: String = "environment"
const START_TIME: float = 90.0
const INTERVAL: float = 10.0
const CAST_TIME: float = 5.0
const DAMAGE_STEP: int = 10
const BORDER_COLOR: Color = Color("e6a35a")
const ART_PATH: String = "res://assets/cards/environment_fatigue.svg"

static var _cached_cards: Dictionary = {}


static func get_card(damage: int) -> CardDef:
	var title: String = Localization.get_text("fatigue.name", "Fatigue")
	var key: String = "%s:%d" % [title, damage]
	if _cached_cards.has(key):
		return _cached_cards[key] as CardDef
	var card: CardDef = CardDef.new()
	card.id = CARD_ID
	card.name = title
	card.description = Localization.get_textf("fatigue.effect", "Deal {damage} damage to both combatants. Shields and incoming damage effects apply.", {"damage": damage})
	card.cast_time = CAST_TIME
	card.recast_time = INTERVAL
	card.active_slot_cost = 0
	card.target_type = "all"
	card.effects = [{"type": "deal_damage", "amount": damage}]
	# Environment definitions never enter the collectible-card database.
	if _cached_cards.size() >= 32:
		_cached_cards.erase(_cached_cards.keys()[0])
	_cached_cards[key] = card
	return card


static func get_tooltip(damage: int) -> String:
	return "\n".join([
		Localization.get_text("fatigue.name", "Fatigue"),
		get_card(damage).description,
		Localization.get_text("fatigue.rules", "Environment card. No slots or attack bonuses. Whole-timeline time effects apply; effects limited to either combatant's cards do not. A new card is queued every 10s, with 10 more damage each wave."),
		Localization.get_text("fatigue.timing", "Cast: 5s / Queue interval: 10s / Loadout Cost: 0"),
	])
