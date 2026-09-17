extends RefCounted
class_name BattleSimulation

const STEP: float = 0.05
var engine: RealtimeBattleEngine
var bot: EnemyAI = EnemyAI.new()
var limit: float = 300.0
var finished: bool = false


func setup(run: RunState, enemy_id: String, time_limit: float = 300.0, phase: float = 0.0, record: bool = true) -> void:
	dispose()
	limit = clampf(time_limit, 1.0, 3600.0)
	finished = false
	bot = EnemyAI.new()
	bot.side = "player"
	bot._think_timer = phase
	engine = RealtimeBattleEngine.new()
	engine.set_audio_enabled(false)
	engine.record_visuals = record
	engine.setup(RunState.from_dict(run.to_dict()), enemy_id)
	engine.start_battle()


func advance(steps: int = 100) -> void:
	if finished or engine == null:
		return
	for _step in range(steps):
		bot.update(engine, STEP)
		engine.update(STEP)
		if engine.battle_state.winner != "" or engine.battle_state.battle_time >= limit:
			finished = true
			break


func result() -> Dictionary:
	if engine == null:
		return {}
	var summary: Dictionary = engine.build_summary()
	summary["simulation"] = true
	summary["unresolved"] = engine.battle_state.winner == ""
	summary["simulation_limit"] = limit
	return summary


func dispose() -> void:
	if engine != null:
		engine.dispose()
		engine = null
