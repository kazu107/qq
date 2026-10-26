extends RefCounted
class_name StatusInfoFormatter


static func bleed_detail(power: int) -> String:
	return Localization.get_textf("status.detail.bleed", "Takes {amount} damage per layer every {interval}s, ignoring shield. Up to 3 layers with independent durations. Power adds 25% of attack and additive card damage (rounded down), fixed on application.", {"amount": power, "interval": "%.1f" % BleedRules.TICK_INTERVAL})


static func regen_detail(power: int) -> String:
	return Localization.get_textf("status.detail.regen", "Heals {amount} HP per layer every 3s. Up to 3 layers with independent durations and fixed power. Reapplication does not reset the shared clock. Cannot overheal or revive.", {"amount": power})


static func tooltip(id: String, remaining: float, multiplier: float = 2.0, status_data: Dictionary = {}) -> String:
	if id == "regen" and status_data.is_empty(): return Localization.get_status_name("regen") + "\n" + regen_detail(1)
	if id in ["reservation_boost", "reservation_hex"]:
		var lines: Array[String] = [Localization.get_status_name(id)]
		for entry: Dictionary in Array(status_data.get("reservations", [])):
			lines.append(ReservedCardRules.kind_name(entry.get("reservation", "")))
			lines.append(ReservedCardRules.describe(entry))
		lines.append(Localization.get_text("reservation.rules", "Same kind: 3 charges; total: 8.\nManual cards only. Interrupted resolves preserve charges.").replace("。", "。\n"))
		return "\n".join(lines)
	if id == "echo_ready":
		return Localization.get_textf("status.detail.echo_ready", "Echo: {charges}/3 charges\nThe next manual card to resolve repeats twice.\nAlready-casting cards qualify.\nAuto cards and reservation setup cards are excluded.\nInterruption preserves charges.\nCosts, cooldown and card-use relic hooks occur once.", {"charges": int(status_data.get("charges", 1))})
	if id == "attack_charge":
		return Localization.get_textf("status.detail.attack_charge", "Next attack x{multiplier} (one card)\nStacks multiplicatively: x2, x4, x8.\nIncludes attack bonuses and already-casting cards.\nConsumed by one attack card; bleed, fatigue and relic damage do not consume it.", {"multiplier": String.num(multiplier, 0)})
	var detail: String
	match id:
		"damage_conversion":
			detail = Localization.get_textf("conversion.detail", "Prevent non-fatigue combat damage before shield. Convert {percent}% to {mode}. Fractions accumulate; reapplication does not extend it. HP costs are excluded.", {"percent": String.num(float(status_data.get("ratio", .25)) * 100, 0), "mode": Localization.get_text("conversion.mode." + String(status_data.get("mode", "heal")), "HP" if status_data.get("mode", "heal") == "heal" else "shield")})
			detail = detail.replace("。", "。\n").replace(". ", ".\n").strip_edges()
		"conversion_lockout": detail = Localization.get_text("conversion.lockout", "Damage conversion is rearming. Damage is received normally during this time.")
		"regen":
			var data: Dictionary = RegenerationRules.normalize(status_data)
			detail = Localization.get_textf("status.regen.total", "Heal {power} HP every 3s. {stacks}/3 layers. Overheal is ignored; cannot revive.", {"power": data["power"], "stacks": data["stacks"]})
			detail = detail.replace("。", "。\n").replace(". ", ".\n").strip_edges()
			var next: float = RegenerationRules.next_tick_in(data)
			if next >= 0: detail += "\n" + Localization.get_textf("status.regen.next", "Next heal in {seconds}s", {"seconds": "%.1f" % next})
			for index: int in Array(data["layers"]).size():
				var layer: Dictionary = data["layers"][index]
				detail += "\n" + Localization.get_textf("status.regen.layer", "Layer {index}: heal {power} / {seconds}s left", {"index": index + 1, "power": layer["power"], "seconds": "%.1f" % float(layer["duration"])})
		"bleed":
			if status_data.is_empty(): detail = bleed_detail(1)
			else:
				var data: Dictionary = BleedRules.normalize(status_data)
				detail = Localization.get_textf("status.bleed.total", "Takes {damage} damage every 6s, ignoring shield. {stacks}/3 layers.", {"stacks": data["stacks"], "damage": data["damage"]})
				var next: float = BleedRules.next_tick_in(data)
				if float(data["suspended"]) > 0: detail += "\n" + Localization.get_textf("status.bleed.paused", "Suspended: {seconds}s", {"seconds": "%.1f" % float(data["suspended"])})
				if next >= 0: detail += "\n" + Localization.get_textf("status.bleed.next", "Next tick: {seconds}s", {"seconds": "%.1f" % next})
				for index: int in Array(data["layers"]).size():
					var layer: Dictionary = data["layers"][index]
					detail += "\n" + Localization.get_textf("status.bleed.layer", "Layer {index}: {power} damage / {seconds}s left", {"index": index + 1, "power": layer["power"], "seconds": "%.1f" % float(layer["duration"])})
		"weak": detail = Localization.get_textf("status.detail.weak", "Attack -{amount} while active.", {"amount": 2})
		"slow": detail = Localization.get_textf("status.detail.slow", "Cast time +{percent}% while active.", {"percent": 10})
		"vulnerable": detail = Localization.get_textf("status.detail.vulnerable", "Incoming damage +{amount} while active.", {"amount": 3})
		_: detail = Localization.get_text("status.detail.unknown", "Temporary status effect.")
	return "\n".join([Localization.get_status_name(id),
		Localization.get_textf("status.tooltip.remaining", "Remaining: {value}s", {"value": "%.1f" % maxf(0.0, remaining)}),
		Localization.get_textf("status.tooltip.effect", "Effect: {value}", {"value": detail})])
