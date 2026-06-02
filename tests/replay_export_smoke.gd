extends Node

var _engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
var _elapsed: float = 0.0


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.set_replay_auto_export_enabled(true)
	Game.start_new_run("balanced")
	Game.current_run.player_hp = Game.current_run.max_hp
	Game.current_run.attack += 6
	Game.current_run.speed += 2
	_engine.setup(Game.current_run, "scout")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 90.0:
		_fail("Replay export smoke timed out")
		return

	var battle_state: BattleState = _engine.battle_state
	if battle_state == null:
		_fail("Replay export smoke failed: battle state was not created")
		return

	for runtime_state in battle_state.player.get_sorted_runtime_states():
		if not runtime_state.can_use():
			continue
		var card_def: CardDef = Database.get_card(runtime_state.card_id)
		if card_def == null:
			continue
		if battle_state.player.active_slots_used + card_def.active_slot_cost > battle_state.player.active_slot_max:
			continue
		_engine.request_use_card("player", runtime_state.runtime_id)
		break

	_engine.update(delta)
	if battle_state.winner == "":
		return

	Game.complete_battle(_engine.build_summary())
	var replay_path: String = Game.get_last_replay_export_path()
	if replay_path == "" or not FileAccess.file_exists(replay_path):
		_fail("Replay export smoke failed: replay JSON was not written")
		return

	var file: FileAccess = FileAccess.open(replay_path, FileAccess.READ)
	if file == null:
		_fail("Replay export smoke failed: replay JSON could not be opened")
		return

	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		_fail("Replay export smoke failed: replay JSON could not be parsed")
		return

	var data: Dictionary = Dictionary(json.data)
	var summary: Dictionary = Dictionary(data.get("summary", {}))
	var battle_events: Array = Array(data.get("battle_events", []))
	if String(summary.get("battle_id", "")) == "":
		_fail("Replay export smoke failed: exported summary was missing battle_id")
		return
	if battle_events.is_empty():
		_fail("Replay export smoke failed: exported replay had no battle events")
		return
	if not _has_event_type(battle_events, "resolve_card") or not _has_event_type(battle_events, "battle_end"):
		_fail("Replay export smoke failed: exported replay missed key event types")
		return

	DirAccess.remove_absolute(replay_path)
	print("Replay export smoke passed")
	get_tree().quit()


func _has_event_type(battle_events: Array, event_type: String) -> bool:
	for raw_event in battle_events:
		var event_data: Dictionary = Dictionary(raw_event)
		if String(event_data.get("event_type", "")) == event_type:
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
