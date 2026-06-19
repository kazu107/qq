extends RefCounted
class_name CardEffectResolver


static func resolve(engine: RealtimeBattleEngine, battle_state: BattleState, instance: ActiveCardInstance, card_def: CardDef) -> Array[String]:
	var messages: Array[String] = []
	var actor := battle_state.get_unit(instance.owner_side)
	var target := battle_state.get_opponent(instance.owner_side)
	for raw_effect in card_def.effects:
		var effect := Dictionary(raw_effect)
		var effect_type := String(effect.get("type", ""))
		match effect_type:
			"deal_damage":
				var amount := int(effect.get("amount", 0))
				if effect.has("bonus_if_target_hp_below_ratio"):
					var ratio := float(effect.get("bonus_if_target_hp_below_ratio", 0.0))
					if float(target.hp) / max(1.0, float(target.max_hp)) <= ratio:
						amount += int(effect.get("bonus_amount", 0))
				if effect.has("bonus_if_target_has_status"):
					var required_status := String(effect.get("bonus_if_target_has_status", ""))
					if target.has_status(required_status):
						amount += int(effect.get("bonus_amount", 0))
				var result := DamageResolver.apply_damage(actor, target, amount)
				messages.append(Localization.get_textf("battle.log.card_damage", "{card_name} dealt {amount} to {target_name}", {
					"card_name": card_def.name,
					"amount": int(result["total_damage"]),
					"target_name": target.display_name,
				}))
			"gain_shield":
				var shield_amount := DamageResolver.gain_shield(_resolve_target_unit(actor, target, effect), int(effect.get("amount", 0)))
				messages.append(Localization.get_textf("battle.log.card_shield", "{card_name} gained {amount} shield", {
					"card_name": card_def.name,
					"amount": shield_amount,
				}))
			"heal":
				var healed := DamageResolver.heal(_resolve_target_unit(actor, target, effect), int(effect.get("amount", 0)))
				messages.append(Localization.get_textf("battle.log.card_heal", "{card_name} healed {amount} HP", {
					"card_name": card_def.name,
					"amount": healed,
				}))
			"apply_status":
				var target_unit := _resolve_target_unit(actor, target, effect)
				var status_id := String(effect.get("status", ""))
				var duration := float(effect.get("duration", 0.0))
				target_unit.add_status(status_id, duration)
				messages.append(Localization.get_textf("battle.log.card_apply_status", "{card_name} applied {status_name} to {target_name}", {
					"card_name": card_def.name,
					"status_name": Localization.get_status_name(status_id),
					"target_name": target_unit.display_name,
				}))
			"remove_status":
				var remove_target := _resolve_target_unit(actor, target, effect)
				var remove_status_id := String(effect.get("status", ""))
				remove_target.remove_status(remove_status_id)
				messages.append(Localization.get_textf("battle.log.card_remove_status", "{card_name} removed {status_name}", {
					"card_name": card_def.name,
					"status_name": Localization.get_status_name(remove_status_id),
				}))
			"delay_enemy_active_card":
				var delayed := engine.delay_active_cards(_opponent_side(instance.owner_side), float(effect.get("amount", 0.0)), String(effect.get("scope", "single")))
				messages.append(Localization.get_textf("battle.log.card_delay", "{card_name} delayed {count} target(s)", {
					"card_name": card_def.name,
					"count": delayed,
				}))
			"haste_own_active_card":
				var hasted := engine.haste_active_cards(instance.owner_side, float(effect.get("amount", 0.0)), String(effect.get("scope", "single")), instance.instance_id)
				messages.append(Localization.get_textf("battle.log.card_haste", "{card_name} hastened {count} target(s)", {
					"card_name": card_def.name,
					"count": hasted,
				}))
			"reduce_recast":
				var reduced := engine.reduce_cooldowns(instance.owner_side, float(effect.get("amount", 0.0)), String(effect.get("scope", "highest_cooldown")), instance.runtime_id)
				messages.append(Localization.get_textf("battle.log.card_reduce_recast", "{card_name} reduced cooldown on {count} card(s)", {
					"card_name": card_def.name,
					"count": reduced,
				}))
			"interrupt_card":
				var interrupted := engine.interrupt_active_card(_opponent_side(instance.owner_side), String(effect.get("scope", "single_interruptible")))
				messages.append(Localization.get_textf("battle.log.card_interrupt", "{card_name} interrupted {count} card(s)", {
					"card_name": card_def.name,
					"count": interrupted,
				}))
			"modify_attack":
				var attack_target := _resolve_target_unit(actor, target, effect)
				attack_target.attack += int(effect.get("amount", 0))
				messages.append(Localization.get_textf("battle.log.card_modify_attack", "{card_name} modified attack of {target_name}", {
					"card_name": card_def.name,
					"target_name": attack_target.display_name,
				}))
			"modify_speed":
				var speed_target := _resolve_target_unit(actor, target, effect)
				speed_target.speed += int(effect.get("amount", 0))
				messages.append(Localization.get_textf("battle.log.card_modify_speed", "{card_name} modified speed of {target_name}", {
					"card_name": card_def.name,
					"target_name": speed_target.display_name,
				}))
			"empower_card":
				var empowered_count: int = engine.empower_cards(instance.owner_side, instance.card_id, effect)
				messages.append(Localization.get_textf("battle.log.card_empower", "{card_name} empowered {count} card(s): {stat} {amount}", {
					"card_name": card_def.name,
					"count": empowered_count,
					"stat": String(effect.get("stat", "damage")),
					"amount": _format_signed_float(float(effect.get("amount", 0.0))),
				}))
			"auto_queue_card":
				var queued_count: int = engine.auto_queue_card(instance.owner_side, instance, effect)
				messages.append(Localization.get_textf("battle.log.card_auto_queue", "{card_name} queued {count} extra card(s)", {
					"card_name": card_def.name,
					"count": queued_count,
				}))
			"timeline_flow":
				var affected_count: int = engine.apply_timeline_flow(instance.owner_side, effect)
				messages.append(Localization.get_textf("battle.log.card_timeline_flow", "{card_name} changed timeline flow for {duration}s ({count} active)", {
					"card_name": card_def.name,
					"duration": "%.1f" % float(effect.get("duration", 0.0)),
					"count": affected_count,
				}))
			_:
				messages.append(Localization.get_textf("battle.log.card_unknown_effect", "{card_name} had unknown effect {effect_type}", {
					"card_name": card_def.name,
					"effect_type": effect_type,
				}))
	return messages


static func _resolve_target_unit(actor: UnitState, target: UnitState, effect: Dictionary) -> UnitState:
	var target_key := String(effect.get("target", "self"))
	if target_key == "enemy":
		return target
	return actor


static func _opponent_side(side: String) -> String:
	if side == "player":
		return "enemy"
	return "player"


static func _format_signed_float(amount: float) -> String:
	if absf(amount - roundf(amount)) < 0.01:
		if amount >= 0.0:
			return "+%d" % int(roundf(amount))
		return "%d" % int(roundf(amount))
	if amount >= 0.0:
		return "+%.1f" % amount
	return "%.1f" % amount
