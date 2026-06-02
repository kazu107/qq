extends Node

var _engine := RealtimeBattleEngine.new()
var _elapsed: float = 0.0


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.start_new_run("balanced")
	Game.current_run.player_hp = Game.current_run.max_hp
	Game.current_run.attack += 6
	Game.current_run.speed += 2
	_engine.setup(Game.current_run, "scout")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 90.0:
		push_error("Battle engine smoke timed out")
		if _engine.battle_state != null:
			print("Player HP=%d Enemy HP=%d Time=%.2f Logs=%d" % [
				_engine.battle_state.player.hp,
				_engine.battle_state.enemy.hp,
				_engine.battle_state.battle_time,
				_engine.battle_state.logs.size(),
			])
		get_tree().quit(1)
		return

	var battle_state := _engine.battle_state
	if battle_state == null:
		push_error("Battle state was not created")
		get_tree().quit(1)
		return

	for runtime_state in battle_state.player.get_sorted_runtime_states():
		if not runtime_state.can_use():
			continue
		var card_def := Database.get_card(runtime_state.card_id)
		if card_def == null:
			continue
		if battle_state.player.active_slots_used + card_def.active_slot_cost > battle_state.player.active_slot_max:
			continue
		_engine.request_use_card("player", runtime_state.runtime_id)
		break

	_engine.update(delta)

	if battle_state.winner != "":
		print("Battle engine smoke passed: winner=%s time=%.2f" % [battle_state.winner, battle_state.battle_time])
		get_tree().quit()
