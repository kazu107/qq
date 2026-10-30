extends RefCounted
class_name EnemyAI

var think_interval: float = 2.4
var side: String = "enemy"
var _think_timer: float = 0.0
var _timekeeper_cycle: int = -1
var _mark_attempted: bool = false


func reset() -> void:
	_think_timer = 0.0
	_timekeeper_cycle = -1
	_mark_attempted = false


func update(engine: RealtimeBattleEngine, delta: float) -> void:
	if side == "enemy" and engine.battle_state != null and InfiniteEnemyCatalog.base_id(engine.battle_state.enemy.unit_id) == "boss_timekeeper" and (not engine.public_sandbox or (bool(engine.sandbox_options.get("boss_passive",true)) and engine.battle_state.enemy.card_runtime_states.any(func(r:CardRuntimeState)->bool:return r.card_id=="timekeeper_final_strike"))):
		_update_timekeeper(engine)
		return
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = think_interval

	var battle_state := engine.battle_state
	if battle_state == null or battle_state.winner != "":
		return

	var enemy := battle_state.get_unit(side)
	if not enemy.is_alive():
		return

	var best_runtime: CardRuntimeState
	var best_score := -INF
	for runtime_state in enemy.card_runtime_states:
		if not runtime_state.can_use():
			continue
		var card_def: CardDef = engine._get_card_def(side,runtime_state.card_id,runtime_state.runtime_id) if engine.public_sandbox else Database.get_card(runtime_state.card_id)
		if card_def == null:
			continue
		var profile: Dictionary = {"cast_time": card_def.cast_time, "slot_cost": card_def.active_slot_cost}
		ReservedCardRules.commit_profile(profile, ReservedCardRules.select(enemy.card_reservations, card_def, "commit"), enemy.active_slot_max)
		if enemy.active_slots_used + int(profile["slot_cost"]) > enemy.active_slot_max:
			continue
		if not CardEffectResolver.can_pay_shield_cost(enemy, card_def):
			continue
		var score := _score_card(engine, runtime_state, card_def)
		if score > best_score:
			best_score = score
			best_runtime = runtime_state
	if best_runtime != null:
		engine.request_use_card(side, best_runtime.runtime_id)


func _update_timekeeper(engine: RealtimeBattleEngine) -> void:
	var state: BattleState = engine.battle_state
	if state.winner != "" or not state.enemy.is_alive():
		return
	var strike: ActiveCardInstance = null
	for instance: ActiveCardInstance in state.get_active_instances_for_side("enemy"):
		if instance.card_id == "timekeeper_final_strike":
			strike = instance
			break
	if strike == null:
		_use_timekeeper_card(engine, "timekeeper_final_strike")
		return
	if _timekeeper_cycle != strike.instance_id:
		_timekeeper_cycle = strike.instance_id
		_mark_attempted = false
	if InfiniteEnemyCatalog.is_variant(state.enemy.unit_id) and state.enemy.shield < 4 and strike.get_remaining(state.battle_time) > 12.0:
		if _use_timekeeper_card(engine, "ascendant_bulwark"):
			return
	# Reserve the final window for the mark; amplify repeatedly while time remains.
	if not _mark_attempted and strike.scheduled_time - state.battle_time <= 8.0:
		_mark_attempted = _use_timekeeper_card(engine, "timekeeper_time_mark")
		return
	if strike.scheduled_time - state.battle_time > 8.0 and state.battle_time - strike.created_at >= 6.0:
		_use_timekeeper_card(engine, "timekeeper_amplify")


func _use_timekeeper_card(engine: RealtimeBattleEngine, id: String) -> bool:
	for runtime: CardRuntimeState in engine.battle_state.enemy.card_runtime_states:
		if runtime.card_id == id and runtime.can_use():
			return engine.request_use_card("enemy", runtime.runtime_id)
	return false


func _score_card(engine: RealtimeBattleEngine, runtime_state: CardRuntimeState, card_def: CardDef) -> float:
	var score := 0.0
	var player := engine.battle_state.get_opponent(side)
	var enemy := engine.battle_state.get_unit(side)
	var opponent_side: String = "enemy" if side == "player" else "player"

	for effect in card_def.effects:
		var effect_type := String(effect.get("type", ""))
		match effect_type:
			"damage_conversion":
				var waiting: float = float(Dictionary(enemy.statuses.get("conversion_lockout", {})).get("duration", 0))
				score += -30.0 if enemy.has_status("damage_conversion") or waiting > card_def.cast_time else (12.0 if engine.has_heavy_preparing_card(opponent_side) else 4.0)
			"reserve_next_card": score += _score_reservation(engine, effect, player if effect.get("target") == "enemy" else enemy)
			"repeat_next_card":
				score += 7.0 if enemy.repeat_charges < RepeatRules.MAX_CHARGES else -30.0
			"consume_shield":
				score -= float(effect.get("amount", 0)) * 0.25
			"deal_damage":
				score += float(effect.get("amount", 0))
				if float(player.hp) / max(1.0, float(player.max_hp)) < 0.4:
					score += 6.0
				if effect.has("bonus_if_target_hp_below_ratio"):
					var threshold: float = float(effect.get("bonus_if_target_hp_below_ratio", 0.0))
					if float(player.hp) / max(1.0, float(player.max_hp)) <= threshold:
						score += float(effect.get("bonus_amount", 0))
				if effect.has("bonus_if_target_has_status"):
					var required_status: String = String(effect.get("bonus_if_target_has_status", ""))
					if player.has_status(required_status):
						score += float(effect.get("bonus_amount", 0))
			"gain_shield", "heal":
				if float(enemy.hp) / max(1.0, float(enemy.max_hp)) < 0.55:
					score += 8.0
				else:
					score += 2.0
			"delay_enemy_active_card", "interrupt_card":
				if engine.has_heavy_preparing_card(opponent_side):
					score += 11.0
				elif engine.battle_state.get_active_instances_for_side(opponent_side).size() > 0:
					score += 5.0
			"haste_own_active_card":
				score += float(engine.battle_state.get_active_instances_for_side(side, -1).size()) * 3.5
			"apply_status":
				if effect.get("status") == "regen":
					score += 8.0 if float(enemy.hp) / maxf(1, enemy.max_hp) < 0.7 else -4.0
					if int(Dictionary(enemy.statuses.get("regen", {})).get("stacks", 0)) >= RegenerationRules.MAX_LAYERS: score -= 5
					continue
				score += 4.0
				var status_id: String = String(effect.get("status", ""))
				if not player.has_status(status_id):
					score += 2.0
			"reduce_recast":
				score += 3.0
			"modify_attack", "modify_speed":
				score += 3.5
			"remove_status":
				if enemy.has_status(String(effect.get("status", ""))):
					score += 5.0
	if card_def.interruptible:
		score -= 1.0
	score += _role_bonus(enemy, card_def)
	if InfiniteEnemyCatalog.is_variant(enemy.unit_id):
		score += _ascended_bonus(engine, enemy, card_def)
	score += float(enemy.speed) * 0.1
	score -= card_def.cast_time * 0.1
	score += float(runtime_state.loadout_index) * 0.01
	return score


func _role_bonus(enemy: UnitState, card_def: CardDef) -> float:
	match InfiniteEnemyCatalog.base_id(enemy.unit_id):
		"raider":
			if card_def.tags.has("bleed") or card_def.tags.has("attack"):
				return 2.0
		"medic_drone":
			if card_def.tags.has("heal") or card_def.tags.has("shield"):
				return 2.5
		"guardian":
			if card_def.tags.has("shield_spend"):
				return 3.0
			if card_def.tags.has("shield"):
				return 2.0
		"chronoguard", "boss_timekeeper":
			if card_def.tags.has("control") or card_def.tags.has("delay") or card_def.tags.has("haste"):
				return 2.5
			if card_def.tags.has("finisher"):
				return 1.5
	return 0.0


func _ascended_bonus(engine: RealtimeBattleEngine, unit: UnitState, card: CardDef) -> float:
	var bonus: float = 0.0
	for effect: Dictionary in card.effects:
		if effect.get("type", "") == "gain_shield":
			for runtime: CardRuntimeState in unit.card_runtime_states:
				if not runtime.can_use(): continue
				var candidate: CardDef = Database.get_card(runtime.card_id)
				if candidate == null: continue
				for cost: Dictionary in candidate.effects:
					if cost.get("type", "") == "consume_shield" and unit.shield < int(cost.get("amount", 0)) + ceili(candidate.cast_time):
						return 10.0
		elif effect.get("type", "") == "timeline_flow":
			var count: int = engine.battle_state.get_active_instances_for_side("player" if side == "enemy" else "enemy").size()
			bonus += 4.0 + count * 2.0 if count > 0 else -5.0
	return bonus


func _score_reservation(engine: RealtimeBattleEngine, effect: Dictionary, recipient: UnitState) -> float:
	if recipient.card_reservations.size() >= ReservedCardRules.MAX_PENDING: return -30
	var kind: String = effect.get("reservation", "")
	var count: int = 0
	for entry: Dictionary in recipient.card_reservations:
		if entry.get("reservation") == kind: count += 1
	if count >= ReservedCardRules.MAX_PER_KIND: return -30
	var trigger: String = "commit" if ReservedCardRules.COMMIT_KINDS.has(kind) else "resolve"
	for runtime: CardRuntimeState in recipient.card_runtime_states:
		if ReservedCardRules.matches(effect, Database.get_card(runtime.card_id), trigger):
			return 7.0 / float(count + 1)
	return -30
