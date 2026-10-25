extends RefCounted
class_name RepeatRules

const MAX_CHARGES: int = 3
const EFFECT_REPEATS: int = 2


static func is_setup_card(card: CardDef) -> bool:
	if card == null: return false
	for effect: Dictionary in card.effects:
		if effect.get("type", "") == "repeat_next_card": return true
	return false


static func is_eligible(card: CardDef, auto_queued: bool, side: String) -> bool:
	return card != null and side in ["player", "enemy"] and not auto_queued and not is_setup_card(card)
