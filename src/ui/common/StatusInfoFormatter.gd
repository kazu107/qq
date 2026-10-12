extends RefCounted
class_name StatusInfoFormatter


static func tooltip(id: String, remaining: float) -> String:
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
