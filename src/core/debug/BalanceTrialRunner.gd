extends RefCounted
class_name BalanceTrialRunner

var running: bool = false
var reports: Array[Dictionary] = []
var error_text: String = ""
var _config: Dictionary
var _draft: BalanceDraft
var _simulation: BattleSimulation
var _variant: int = 0
var _match: int = 0


static func make_run(config: Dictionary, draft: BalanceDraft) -> RunState:
	var run: RunState = RunState.from_starter(Database.get_starter(String(config.get("starter", "balanced"))), int(config.get("seed", 12345)))
	run.max_hp = int(config.get("hp", run.max_hp))
	run.player_hp = run.max_hp
	run.attack = int(config.get("attack", run.attack))
	run.speed = int(config.get("speed", run.speed))
	run.player_cards.clear()
	run.equipped_cards.clear()
	for id: String in config.get("cards", []):
		run.player_cards.append(id)
		run.equipped_cards.append(id)
		run.card_upgrades[id] = int(config.get("grade", 0))
	var mode: int = int(config.get("mode", 0))
	run.arena_mode = mode == 2
	run.infinite_mode = mode == 3
	run.relic_state["arena_lost_last_battle"] = true
	run.map_state = {"current_step": 0, "active_node_id": "balance", "steps": [{"nodes": [{"id": "balance", "type": "hazard" if mode == 1 else "normal_battle", "hazard_cleared_waves": int(config.get("power", 1)) - 1, "infinite_power": int(config.get("power", 1))}]}]}
	for id: String in config.get("relics", []): RelicService.new().grant_relic(run, id, draft)
	return run


func begin(config: Dictionary, draft: BalanceDraft) -> bool:
	if not Game.is_developer_mode_enabled() or NetworkManager.is_session_connected() or config.get("cards", []).is_empty(): return false
	cancel()
	_config = config.duplicate(true)
	_config["count"] = clampi(int(config.get("count", 10)), 1, 200)
	_draft = draft.frozen()
	reports = []
	for label: String in ["A", "B"]: reports.append({"label": label, "completed": 0, "wins": 0, "draws": 0, "unresolved": 0, "time": 0.0, "damage": 0.0, "shield": 0.0, "heal": 0.0})
	_variant = 0
	_match = 0
	error_text = ""
	running = true
	_start_match()
	return true


func _start_match() -> void:
	var context: BalanceDraft = BalanceDraft.new() if _variant == 0 else _draft
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(_config.get("seed", 12345)) + _match
	_simulation = BattleSimulation.new()
	_simulation.setup(make_run(_config, context), String(_config.get("enemy", "scout")), float(_config.get("limit", 180.0)), rng.randf_range(0.0, 2.4), false, context)


func advance(budget_usec: int = 5000) -> void:
	if not running: return
	if not Game.is_developer_mode_enabled() or NetworkManager.is_session_connected():
		error_text = "Development permission/session changed."
		cancel()
		return
	var deadline: int = Time.get_ticks_usec() + budget_usec
	while running and Time.get_ticks_usec() < deadline:
		_simulation.advance(1)
		if not _simulation.finished: continue
		var summary: Dictionary = _simulation.result()
		var report: Dictionary = reports[_variant]
		report["completed"] += 1
		report["wins"] += 1 if summary.get("winner", "") == "player" else 0
		report["draws"] += 1 if summary.get("winner", "") == "draw" else 0
		report["unresolved"] += 1 if summary.get("unresolved", false) else 0
		report["time"] += float(summary.get("battle_time", 0.0))
		var totals: Dictionary = Dictionary(Dictionary(summary.get("analysis", {})).get("totals", {})).get("player", {})
		for key: String in ["damage", "shield", "heal"]: report[key] += float(totals.get(key, 0))
		_simulation.dispose()
		_match += 1
		if _match >= int(_config["count"]):
			if _variant == 1:
				running = false
				return
			_variant = 1
			_match = 0
		_start_match()


func progress() -> float:
	if reports.is_empty(): return 0.0
	return float(int(reports[0]["completed"]) + int(reports[1]["completed"])) / (2.0 * float(_config["count"]))


func cancel() -> void:
	running = false
	if _simulation != null:
		_simulation.dispose()
		_simulation = null
