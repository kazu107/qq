extends RefCounted
class_name StatusInfoFormatter


static func tooltip(id: String, remaining: float, multiplier: float = 2.0) -> String:
	if id == "attack_charge":
		return Localization.get_textf("status.detail.attack_charge", "Next attack x{multiplier} (one card)\nStacks multiplicatively: x2, x4, x8.\nIncludes attack bonuses and already-casting cards.\nConsumed by one attack card; bleed, fatigue and relic damage do not consume it.", {"multiplier": String.num(multiplier, 0)})
	var detail: String
	match id:
		"bleed": detail = Localization.get_textf("status.detail.bleed", "Takes {amount} damage every {interval}s.", {"amount": 1, "interval": "%.1f" % UnitState.BLEED_TICK_INTERVAL})
		"weak": detail = Localization.get_textf("status.detail.weak", "Attack -{amount} while active.", {"amount": 2})
		"slow": detail = Localization.get_textf("status.detail.slow", "Cast time +{percent}% while active.", {"percent": 10})
		"vulnerable": detail = Localization.get_textf("status.detail.vulnerable", "Incoming damage +{amount} while active.", {"amount": 3})
		_: detail = Localization.get_text("status.detail.unknown", "Temporary status effect.")
	return "\n".join([Localization.get_status_name(id),
		Localization.get_textf("status.tooltip.remaining", "Remaining: {value}s", {"value": "%.1f" % maxf(0.0, remaining)}),
		Localization.get_textf("status.tooltip.effect", "Effect: {value}", {"value": detail})])
