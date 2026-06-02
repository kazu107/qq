extends RefCounted
class_name EnemyAI

var think_interval: float = 2.4
var _think_timer: float = 0.0


func reset() -> void:
	_think_timer = 0.0


func update(engine: RealtimeBattleEngine, delta: float) -> void:
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = think_interval

	var battle_state := engine.battle_state
	if battle_state == null or battle_state.winner != "":
		return

	var enemy := battle_state.enemy
	if not enemy.is_alive():
		return

	var best_runtime: CardRuntimeState
	var best_score := -INF
	for runtime_state in enemy.card_runtime_states:
		if not runtime_state.can_use():
			continue
		var card_def := Database.get_card(runtime_state.card_id)
		if card_def == null:
			continue
		if enemy.active_slots_used + card_def.active_slot_cost > enemy.active_slot_max:
			continue
		var score := _score_card(engine, runtime_state, card_def)
		if score > best_score:
			best_score = score
			best_runtime = runtime_state
	if best_runtime != null:
		engine.request_use_card("enemy", best_runtime.runtime_id)


func _score_card(engine: RealtimeBattleEngine, runtime_state: CardRuntimeState, card_def: CardDef) -> float:
	var score := 0.0
	var player := engine.battle_state.player
	var enemy := engine.battle_state.enemy

	for effect in card_def.effects:
		var effect_type := String(effect.get("type", ""))
		match effect_type:
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
				if engine.has_heavy_preparing_card("player"):
					score += 11.0
				elif engine.battle_state.get_active_instances_for_side("player").size() > 0:
					score += 5.0
			"haste_own_active_card":
				score += float(engine.battle_state.get_active_instances_for_side("enemy", -1).size()) * 3.5
			"apply_status":
				score += 4.0
				var status_id: String = String(effect.get("status", ""))
				if not player.has_status(status_id):
					score += 2.0
			"reduce_recast":
				score += 3.0
			"modify_attack", "modify_defense", "modify_speed":
				score += 3.5
			"remove_status":
				if enemy.has_status(String(effect.get("status", ""))):
					score += 5.0
	if card_def.interruptible:
		score -= 1.0
	score += _role_bonus(enemy, card_def)
	score += float(enemy.speed) * 0.1
	score -= card_def.cast_time * 0.1
	score += float(runtime_state.loadout_index) * 0.01
	return score


func _role_bonus(enemy: UnitState, card_def: CardDef) -> float:
	match enemy.unit_id:
		"raider":
			if card_def.tags.has("bleed") or card_def.tags.has("attack"):
				return 2.0
		"medic_drone":
			if card_def.tags.has("heal") or card_def.tags.has("defense"):
				return 2.5
		"chronoguard", "boss_timekeeper":
			if card_def.tags.has("control") or card_def.tags.has("delay") or card_def.tags.has("haste"):
				return 2.5
			if card_def.tags.has("finisher"):
				return 1.5
	return 0.0
