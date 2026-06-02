extends RefCounted
class_name RealtimeBattleEngine

var battle_state: BattleState
var _timeline_resolver := TimelineResolver.new()
var _enemy_ai := EnemyAI.new()
var _boss_passive_timer: float = 0.0
var _player_run: RunState
var _relic_service: RelicService = RelicService.new()


func setup(player_run: RunState, enemy_id: String) -> void:
	var enemy_def := Database.get_enemy(enemy_id)
	if enemy_def == null:
		push_error("Enemy not found: %s" % enemy_id)
		return

	_player_run = player_run
	battle_state = BattleState.new()
	battle_state.player = _build_player_unit(player_run)
	battle_state.enemy = _build_enemy_unit(enemy_def)
	battle_state.add_log(Localization.get_textf("battle.log.started_against", "Battle started against {enemy_name}", {
		"enemy_name": enemy_def.name,
	}))
	_record_event(_build_basic_event(
		"battle_start",
		battle_state.player.unit_id,
		"",
		battle_state.enemy.unit_id,
		{
			"enemy_name": enemy_def.name,
			"player": _snapshot_unit(battle_state.player),
			"enemy": _snapshot_unit(battle_state.enemy),
		}
	))
	_enemy_ai.reset()
	_boss_passive_timer = float(enemy_def.passive.get("interval", 0.0))
	AudioManager.play_sfx("battle_start")


func update(delta: float) -> void:
	if battle_state == null or battle_state.winner != "":
		return
	if delta <= 0.0:
		return

	battle_state.battle_time += delta
	_tick_cooldowns(delta)
	_tick_shields(delta)
	_tick_statuses(delta)
	_process_boss_passive(delta)
	_enemy_ai.update(self, delta)
	_resolve_due_entries()
	_check_victory()


func request_use_card(side: String, runtime_id: String) -> bool:
	if battle_state == null or battle_state.winner != "":
		return false

	var unit := battle_state.get_unit(side)
	var runtime_state := unit.get_runtime_state(runtime_id)
	if runtime_state == null or not runtime_state.can_use():
		return false

	var card_def: CardDef = _get_card_def(side, runtime_state.card_id)
	if card_def == null:
		return false
	if unit.active_slots_used + card_def.active_slot_cost > unit.active_slot_max:
		return false

	runtime_state.begin_prepare()
	unit.previous_used_runtime_id = unit.last_used_runtime_id
	unit.last_used_runtime_id = runtime_state.runtime_id
	unit.active_slots_used += card_def.active_slot_cost

	var instance := ActiveCardInstance.new()
	instance.instance_id = battle_state.next_instance_id
	battle_state.next_instance_id += 1
	instance.owner_side = side
	instance.runtime_id = runtime_state.runtime_id
	instance.card_id = runtime_state.card_id
	instance.card_name = card_def.name
	instance.priority_modifier = card_def.priority_modifier
	instance.slot_cost = card_def.active_slot_cost
	instance.interruptible = card_def.interruptible
	instance.actor_speed = unit.speed
	instance.target_type = card_def.target_type
	instance.created_at = battle_state.battle_time
	instance.scheduled_time = battle_state.battle_time + card_def.cast_time * unit.get_cast_time_multiplier()
	instance.sort_key = instance.scheduled_time - card_def.priority_modifier

	battle_state.active_instances.append(instance)
	_timeline_resolver.rebuild_timeline(battle_state)
	battle_state.add_log(Localization.get_textf("battle.log.prepared_card", "{unit_name} prepared {card_name}", {
		"unit_name": unit.display_name,
		"card_name": card_def.name,
	}))
	AudioManager.play_sfx("card_commit", 1.03 if side == "player" else 0.94)
	_record_event(_build_basic_event(
		"prepare_card",
		unit.unit_id,
		card_def.id,
		battle_state.get_opponent(side).unit_id,
		{
			"card_name": card_def.name,
			"scheduled_time": instance.scheduled_time,
			"player": _snapshot_unit(battle_state.player),
			"enemy": _snapshot_unit(battle_state.enemy),
		},
		0,
		0,
		[],
		_snapshot_timeline()
	))
	return true


func delay_active_cards(side: String, amount: float, scope: String) -> int:
	return _shift_active_cards(side, absf(amount), scope, -1)


func haste_active_cards(side: String, amount: float, scope: String, exclude_instance_id: int = -1) -> int:
	return _shift_active_cards(side, -absf(amount), scope, exclude_instance_id)


func reduce_cooldowns(side: String, amount: float, scope: String, exclude_runtime_id: String = "") -> int:
	var unit := battle_state.get_unit(side)
	var affected: Array[CardRuntimeState] = []
	match scope:
		"all":
			for runtime_state in unit.card_runtime_states:
				if runtime_state.state == CardRuntimeState.CardState.COOLDOWN:
					affected.append(runtime_state)
		"last_used":
			var runtime_state := unit.get_runtime_state(unit.previous_used_runtime_id)
			if runtime_state != null and runtime_state.runtime_id != exclude_runtime_id and runtime_state.state == CardRuntimeState.CardState.COOLDOWN:
				affected.append(runtime_state)
		_:
			var best_runtime: CardRuntimeState
			var best_cooldown := 0.0
			for runtime_state in unit.card_runtime_states:
				if runtime_state.runtime_id == exclude_runtime_id:
					continue
				if runtime_state.state != CardRuntimeState.CardState.COOLDOWN:
					continue
				if runtime_state.cooldown_remaining > best_cooldown:
					best_cooldown = runtime_state.cooldown_remaining
					best_runtime = runtime_state
			if best_runtime != null:
				affected.append(best_runtime)

	for runtime_state in affected:
		runtime_state.set_cooldown_remaining(runtime_state.cooldown_remaining - absf(amount))
	return affected.size()


func interrupt_active_card(side: String, scope: String) -> int:
	var candidates: Array[ActiveCardInstance] = []
	for instance in battle_state.get_active_instances_for_side(side):
		if not instance.interruptible:
			continue
		candidates.append(instance)
	if candidates.is_empty():
		return 0

	candidates.sort_custom(func(a: ActiveCardInstance, b: ActiveCardInstance) -> bool:
		return a.scheduled_time < b.scheduled_time
	)

	var max_hits := 1
	if scope == "all_interruptible":
		max_hits = candidates.size()
	var hit_count := 0
	for candidate in candidates:
		_force_interrupt(candidate)
		hit_count += 1
		if hit_count >= max_hits:
			break
	return hit_count


func has_heavy_preparing_card(side: String) -> bool:
	for instance in battle_state.get_active_instances_for_side(side):
		if instance.slot_cost >= 2:
			return true
	return false


func build_summary() -> Dictionary:
	if battle_state == null:
		return {}
	return {
		"battle_id": _build_battle_id(),
		"winner": battle_state.winner,
		"battle_time": battle_state.battle_time,
		"player_hp": battle_state.player.hp,
		"enemy_id": battle_state.enemy.unit_id,
		"enemy_name": battle_state.enemy.display_name,
		"log_count": battle_state.logs.size(),
		"battle_events": battle_state.battle_events.duplicate(true),
	}


func _build_player_unit(run_state: RunState) -> UnitState:
	var unit := UnitState.new()
	unit.unit_id = "player"
	unit.display_name = Localization.get_text("battle.player_name", "Player")
	unit.max_hp = run_state.max_hp
	unit.hp = max(1, run_state.player_hp)
	unit.shield = 0
	unit.attack = run_state.attack
	unit.defense = run_state.defense
	unit.speed = run_state.speed
	unit.active_slot_max = 3
	unit.set_runtime_states(_create_runtime_states("player", run_state.equipped_cards))
	_relic_service.apply_battle_modifiers(unit, run_state)
	return unit


func _build_enemy_unit(enemy_def: EnemyDef) -> UnitState:
	var unit := UnitState.new()
	unit.unit_id = enemy_def.id
	unit.display_name = enemy_def.name
	unit.max_hp = enemy_def.max_hp
	unit.hp = enemy_def.max_hp
	unit.shield = 0
	unit.attack = enemy_def.attack
	unit.defense = enemy_def.defense
	unit.speed = enemy_def.speed
	unit.active_slot_max = 3
	unit.set_runtime_states(_create_runtime_states("enemy", enemy_def.cards))
	return unit


func _create_runtime_states(side: String, card_ids: Array[String]) -> Array[CardRuntimeState]:
	var states: Array[CardRuntimeState] = []
	for index in range(card_ids.size()):
		var runtime_state := CardRuntimeState.new()
		runtime_state.runtime_id = "%s_%d" % [side, index]
		runtime_state.card_id = card_ids[index]
		runtime_state.loadout_index = index
		states.append(runtime_state)
	return states


func _tick_cooldowns(delta: float) -> void:
	for unit in [battle_state.player, battle_state.enemy]:
		for runtime_state in unit.card_runtime_states:
			runtime_state.tick(delta)


func _tick_shields(delta: float) -> void:
	for unit in [battle_state.player, battle_state.enemy]:
		var shield_before: int = unit.shield
		var decayed: int = unit.tick_shield_decay(delta)
		if decayed > 0:
			battle_state.add_log(Localization.get_textf("battle.log.shield_decay", "{unit_name} lost {amount} shield", {
				"unit_name": unit.display_name,
				"amount": decayed,
			}))
			_record_event(_build_basic_event(
				"shield_decay",
				unit.unit_id,
				"",
				unit.unit_id,
				{
					"player": _snapshot_unit(battle_state.player),
					"enemy": _snapshot_unit(battle_state.enemy),
				},
				0,
				unit.shield - shield_before
			))


func _tick_statuses(delta: float) -> void:
	for unit in [battle_state.player, battle_state.enemy]:
		var events: Array[Dictionary] = unit.tick_statuses(delta)
		for event_data in events:
			if String(event_data.get("type", "")) == "status_damage":
				var amount := int(event_data.get("amount", 0))
				var hp_before: int = unit.hp
				unit.hp = max(0, unit.hp - amount)
				battle_state.add_log(Localization.get_textf("battle.log.status_damage", "{unit_name} took {amount} bleed damage", {
					"unit_name": unit.display_name,
					"amount": amount,
				}))
				AudioManager.play_sfx("battle_tick", 0.95)
				_record_event(_build_basic_event(
					"status_damage",
					unit.unit_id,
					"",
					unit.unit_id,
					{
						"status": String(event_data.get("status", "")),
						"amount": amount,
						"player": _snapshot_unit(battle_state.player),
						"enemy": _snapshot_unit(battle_state.enemy),
					},
					unit.hp - hp_before,
					0
				))


func _process_boss_passive(delta: float) -> void:
	var passive := Database.get_enemy(battle_state.enemy.unit_id).passive
	if passive.is_empty():
		return
	var passive_type := String(passive.get("type", ""))
	if passive_type != "periodic_delay_enemy_active":
		return
	_boss_passive_timer -= delta
	if _boss_passive_timer > 0.0:
		return
	_boss_passive_timer = float(passive.get("interval", 10.0))
	var timeline_before: Array[Dictionary] = _snapshot_timeline()
	var delayed := delay_active_cards("player", float(passive.get("amount", 0.0)), "single")
	if delayed > 0:
		battle_state.add_log(Localization.get_textf("battle.log.twisted_timeline", "{unit_name} twisted the timeline", {
			"unit_name": battle_state.enemy.display_name,
		}))
		AudioManager.play_sfx("battle_time", 0.88)
		_record_event(_build_basic_event(
			"boss_passive",
			battle_state.enemy.unit_id,
			"",
			battle_state.player.unit_id,
			{
				"passive_type": passive_type,
				"amount": float(passive.get("amount", 0.0)),
				"affected_cards": delayed,
				"player": _snapshot_unit(battle_state.player),
				"enemy": _snapshot_unit(battle_state.enemy),
			},
			0,
			0,
			timeline_before,
			_snapshot_timeline()
		))


func _resolve_due_entries() -> void:
	_timeline_resolver.rebuild_timeline(battle_state)
	while not battle_state.timeline.is_empty():
		var next_entry := battle_state.timeline[0]
		if next_entry.scheduled_time > battle_state.battle_time:
			return

		var instance := battle_state.get_active_instance_by_id(next_entry.instance_id)
		if instance == null:
			_timeline_resolver.rebuild_timeline(battle_state)
			continue

		var unit := battle_state.get_unit(instance.owner_side)
		var runtime_state := unit.get_runtime_state(instance.runtime_id)
		var card_def: CardDef = _get_card_def(instance.owner_side, instance.card_id)
		if runtime_state == null or card_def == null:
			battle_state.remove_active_instance(instance.instance_id)
			_timeline_resolver.rebuild_timeline(battle_state)
			continue

		runtime_state.begin_resolve()
		var timeline_before := _snapshot_timeline()
		var target_unit: UnitState = battle_state.get_opponent(instance.owner_side)
		var player_before: Dictionary = _snapshot_unit(battle_state.player)
		var enemy_before: Dictionary = _snapshot_unit(battle_state.enemy)
		var target_hp_before: int = target_unit.hp
		var target_shield_before: int = target_unit.shield
		var messages := CardEffectResolver.resolve(self, battle_state, instance, card_def)
		var resolved_instance := battle_state.remove_active_instance(instance.instance_id)
		if resolved_instance != null:
			unit.active_slots_used = max(0, unit.active_slots_used - resolved_instance.slot_cost)
		runtime_state.begin_cooldown(card_def.recast_time)
		_timeline_resolver.rebuild_timeline(battle_state)
		var timeline_after := _snapshot_timeline()
		for message in messages:
			battle_state.add_log("%s" % message)
		AudioManager.play_card_resolution(card_def)
		_record_event(_build_basic_event(
			"resolve_card",
			unit.unit_id,
			card_def.id,
			target_unit.unit_id,
			{
				"card_name": card_def.name,
				"messages": messages,
				"player_before": player_before,
				"player_after": _snapshot_unit(battle_state.player),
				"enemy_before": enemy_before,
				"enemy_after": _snapshot_unit(battle_state.enemy),
				"target_hp_before": target_hp_before,
				"target_hp_after": target_unit.hp,
				"target_shield_before": target_shield_before,
				"target_shield_after": target_unit.shield,
			},
			target_unit.hp - target_hp_before,
			target_unit.shield - target_shield_before,
			timeline_before,
			timeline_after
		))
		_check_victory()
		if battle_state.winner != "":
			return


func _snapshot_timeline() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for entry in battle_state.timeline:
		snapshot.append({
			"instance_id": entry.instance_id,
			"owner_side": entry.owner_side,
			"card_id": entry.card_id,
			"scheduled_time": entry.scheduled_time,
		})
	return snapshot


func _force_interrupt(instance: ActiveCardInstance) -> void:
	var unit := battle_state.get_unit(instance.owner_side)
	var runtime_state := unit.get_runtime_state(instance.runtime_id)
	var card_def: CardDef = _get_card_def(instance.owner_side, instance.card_id)
	if runtime_state == null or card_def == null:
		return
	var timeline_before: Array[Dictionary] = _snapshot_timeline()
	battle_state.remove_active_instance(instance.instance_id)
	unit.active_slots_used = max(0, unit.active_slots_used - instance.slot_cost)
	runtime_state.state = CardRuntimeState.CardState.INTERRUPTED
	runtime_state.begin_cooldown(card_def.recast_time)
	battle_state.add_log(Localization.get_textf("battle.log.card_was_interrupted", "{unit_name}'s {card_name} was interrupted", {
		"unit_name": unit.display_name,
		"card_name": card_def.name,
	}))
	AudioManager.play_sfx("battle_interrupt", 0.92)
	_timeline_resolver.rebuild_timeline(battle_state)
	_record_event(_build_basic_event(
		"interrupt_card",
		battle_state.get_opponent(instance.owner_side).unit_id,
		card_def.id,
		unit.unit_id,
		{
			"card_name": card_def.name,
			"player": _snapshot_unit(battle_state.player),
			"enemy": _snapshot_unit(battle_state.enemy),
		},
		0,
		0,
		timeline_before,
		_snapshot_timeline()
	))


func _shift_active_cards(side: String, delta_amount: float, scope: String, exclude_instance_id: int) -> int:
	var targets := battle_state.get_active_instances_for_side(side, exclude_instance_id)
	if targets.is_empty():
		return 0
	targets.sort_custom(func(a: ActiveCardInstance, b: ActiveCardInstance) -> bool:
		return a.scheduled_time < b.scheduled_time
	)
	var count := 0
	for instance in targets:
		instance.shift_schedule(delta_amount, battle_state.battle_time)
		count += 1
		if scope != "all":
			break
	_timeline_resolver.rebuild_timeline(battle_state)
	return count


func _check_victory() -> void:
	var previous_winner := battle_state.winner
	if battle_state.player.hp <= 0 and battle_state.enemy.hp <= 0:
		battle_state.winner = "draw"
	elif battle_state.enemy.hp <= 0:
		battle_state.winner = "player"
	elif battle_state.player.hp <= 0:
		battle_state.winner = "enemy"

	if previous_winner == "" and battle_state.winner != "":
		battle_state.add_log(Localization.get_textf("battle.log.winner", "Winner: {winner_name}", {
			"winner_name": Localization.get_winner_name(battle_state.winner),
		}))
		_record_event(_build_basic_event(
			"battle_end",
			battle_state.winner,
			"",
			"",
			{
				"winner": battle_state.winner,
				"player": _snapshot_unit(battle_state.player),
				"enemy": _snapshot_unit(battle_state.enemy),
			}
		))


func _get_card_def(side: String, card_id: String) -> CardDef:
	if side == "player":
		return CardUpgradeResolver.build_effective_card(card_id, _player_run)
	return Database.get_card(card_id)


func _record_event(record: BattleEventRecord) -> void:
	if battle_state == null or record == null:
		return
	battle_state.record_event(record.to_dict())


func _build_basic_event(
	event_type: String,
	actor_id: String,
	card_id: String,
	target_id: String,
	result: Dictionary,
	hp_delta: int = 0,
	shield_delta: int = 0,
	timeline_before: Array[Dictionary] = [],
	timeline_after: Array[Dictionary] = []
) -> BattleEventRecord:
	var record: BattleEventRecord = BattleEventRecord.new()
	record.time = battle_state.battle_time
	record.event_type = event_type
	record.actor_id = actor_id
	record.card_id = card_id
	record.target_id = target_id
	record.result = result.duplicate(true)
	record.hp_delta = hp_delta
	record.shield_delta = shield_delta
	record.timeline_before = timeline_before.duplicate(true)
	record.timeline_after = timeline_after.duplicate(true)
	return record


func _snapshot_unit(unit: UnitState) -> Dictionary:
	return {
		"unit_id": unit.unit_id,
		"display_name": unit.display_name,
		"hp": unit.hp,
		"max_hp": unit.max_hp,
		"shield": unit.shield,
		"attack": unit.attack,
		"defense": unit.defense,
		"speed": unit.speed,
		"statuses": unit.statuses.duplicate(true),
		"active_slots_used": unit.active_slots_used,
		"active_slot_max": unit.active_slot_max,
		"cooldowns": _snapshot_runtime_states(unit),
	}


func _snapshot_runtime_states(unit: UnitState) -> Array[Dictionary]:
	var runtime_states: Array[Dictionary] = []
	for runtime_state in unit.get_sorted_runtime_states():
		runtime_states.append({
			"runtime_id": runtime_state.runtime_id,
			"card_id": runtime_state.card_id,
			"state": runtime_state.get_state_name(),
			"cooldown_remaining": runtime_state.cooldown_remaining,
		})
	return runtime_states


func _build_battle_id() -> String:
	if battle_state == null:
		return ""
	var seed_value: int = 0
	if _player_run != null:
		seed_value = _player_run.seed
	return "%s_%s_%d" % [
		battle_state.enemy.unit_id,
		str(seed_value),
		int(round(battle_state.battle_time * 100.0)),
	]
