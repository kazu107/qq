extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Database.load_all()
	if not Database.load_errors.is_empty():
		_fail("3D battle stage smoke failed: database could not be loaded")
		return
	var stage := BattleStage3D.new()
	add_child(stage)
	await get_tree().process_frame
	stage.configure_combatants("player", "scout", "player")

	var player_actor: BattleActor3D = stage.find_child("PlayerBattleActor3D", true, false) as BattleActor3D
	var enemy_actor: BattleActor3D = stage.find_child("EnemyBattleActor3D", true, false) as BattleActor3D
	if player_actor == null or enemy_actor == null:
		_fail("3D battle stage smoke failed: combat actors are missing")
		return

	stage.play_battle_event({
		"event_type": "prepare_card",
		"actor_id": "player",
		"target_id": "scout",
		"card_id": "strike",
	})
	if player_actor.get_action_name() != "cast" or stage.get_active_effect_count() < 1:
		_fail("3D battle stage smoke failed: preparing a card should start casting VFX")
		return

	_advance(stage, player_actor, enemy_actor, 0.24)
	stage.play_battle_event(_resolution_event(
		"player",
		"scout",
		"strike",
		{"hp": 50, "shield": 0, "statuses": {}},
		{"hp": 50, "shield": 0, "statuses": {}},
		{"hp": 35, "shield": 3, "statuses": {}},
		{"hp": 29, "shield": 0, "statuses": {}}
	))
	if player_actor.get_action_name() != "attack" or enemy_actor.get_action_name() != "hit":
		_fail("3D battle stage smoke failed: damage resolution should animate attack and hit")
		return
	if stage.find_child("BattleProjectile3D", true, false) == null or stage.find_child("BattleImpact3D", true, false) == null:
		_fail("3D battle stage smoke failed: damage resolution should spawn projectile and impact VFX")
		return

	_advance(stage, player_actor, enemy_actor, 0.82)
	stage.play_battle_event(_resolution_event(
		"scout",
		"player",
		"strike",
		{"hp": 50, "shield": 5, "statuses": {}},
		{"hp": 50, "shield": 1, "statuses": {}},
		{"hp": 29, "shield": 0, "statuses": {}},
		{"hp": 29, "shield": 0, "statuses": {}}
	))
	if enemy_actor.get_action_name() != "attack" or player_actor.get_action_name() != "block":
		_fail("3D battle stage smoke failed: fully blocked damage should animate attack and guard")
		return

	_advance(stage, player_actor, enemy_actor, 0.82)
	stage.play_battle_event(_resolution_event(
		"player",
		"scout",
		"guard",
		{"hp": 50, "shield": 0, "statuses": {}},
		{"hp": 50, "shield": 8, "statuses": {}},
		{"hp": 29, "shield": 0, "statuses": {}},
		{"hp": 29, "shield": 0, "statuses": {}}
	))
	if player_actor.get_action_name() != "shield":
		_fail("3D battle stage smoke failed: shield gain should animate the caster")
		return

	_advance(stage, player_actor, enemy_actor, 0.82)
	stage.play_battle_event(_resolution_event(
		"player",
		"scout",
		"repair_burst",
		{"hp": 42, "shield": 0, "statuses": {}},
		{"hp": 48, "shield": 4, "statuses": {}},
		{"hp": 29, "shield": 0, "statuses": {}},
		{"hp": 29, "shield": 0, "statuses": {}}
	))
	if player_actor.get_action_name() != "heal":
		_fail("3D battle stage smoke failed: healing should take priority over shield pose")
		return

	_advance(stage, player_actor, enemy_actor, 0.82)
	stage.play_battle_event(_resolution_event(
		"scout",
		"player",
		"weak_shot",
		{"hp": 48, "shield": 4, "statuses": {}},
		{"hp": 48, "shield": 4, "statuses": {"weak": {"duration": 6.0}}},
		{"hp": 29, "shield": 0, "statuses": {}},
		{"hp": 29, "shield": 0, "statuses": {}}
	))
	if enemy_actor.get_action_name() != "attack" or player_actor.get_action_name() != "status":
		_fail("3D battle stage smoke failed: status cards should animate source and target (%s / %s, pending %d)" % [
			enemy_actor.get_action_name(),
			player_actor.get_action_name(),
			stage.get_pending_event_count(),
		])
		return

	_advance(stage, player_actor, enemy_actor, 0.82)
	stage.play_battle_event({
		"event_type": "prepare_card",
		"actor_id": "scout",
		"target_id": "player",
		"card_id": "strike",
	})
	_advance(stage, player_actor, enemy_actor, 0.24)
	stage.play_battle_event({
		"event_type": "interrupt_card",
		"actor_id": "player",
		"target_id": "scout",
		"card_id": "strike",
	})
	if enemy_actor.get_action_name() != "interrupt":
		_fail("3D battle stage smoke failed: interrupted casts should play a stagger animation")
		return

	_advance(stage, player_actor, enemy_actor, 0.68)
	stage.play_battle_event({
		"event_type": "battle_end",
		"actor_id": "player",
		"result": {"winner": "player"},
	})
	if player_actor.get_action_name() != "victory" or enemy_actor.get_action_name() != "defeat":
		_fail("3D battle stage smoke failed: battle end should animate winner and loser")
		return

	stage.configure_combatants("enemy", "player", "enemy")
	stage.play_battle_event({
		"event_type": "prepare_card",
		"actor_id": "enemy",
		"target_id": "player",
		"card_id": "strike",
	})
	if player_actor.get_action_name() != "cast" or enemy_actor.get_action_name() != "idle":
		_fail("3D battle stage smoke failed: Web opponent-side mapping should keep the local actor on the player side")
		return

	print("BATTLE_STAGE_3D_SMOKE_OK event-driven combat animation validated")
	get_tree().quit()


func _advance(stage: BattleStage3D, player_actor: BattleActor3D, enemy_actor: BattleActor3D, duration: float) -> void:
	var remaining: float = duration
	while remaining > 0.0:
		var step: float = minf(0.05, remaining)
		stage._process(step)
		player_actor._process(step)
		enemy_actor._process(step)
		remaining -= step


func _resolution_event(
	actor_id: String,
	target_id: String,
	card_id: String,
	player_before: Dictionary,
	player_after: Dictionary,
	enemy_before: Dictionary,
	enemy_after: Dictionary
) -> Dictionary:
	return {
		"event_type": "resolve_card",
		"actor_id": actor_id,
		"target_id": target_id,
		"card_id": card_id,
		"result": {
			"player_before": player_before,
			"player_after": player_after,
			"enemy_before": enemy_before,
			"enemy_after": enemy_after,
		},
	}


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
