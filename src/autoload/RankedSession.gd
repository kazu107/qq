extends Node

signal changed

const RULESET := "infinite-10"
const STEP := 1.0 / 60.0
const METHODS := ["select_map_node", "start_active_encounter", "prepare_next_battle", "choose_reward", "skip_reward", "reroll_rewards_for_gold", "equip_card", "unequip_card", "sell_loadout_card", "buy_shop_offer", "use_shop_service_choice", "upgrade_forge_card", "use_forge_service_choice", "use_heal_node_choice", "resolve_event_choice", "continue_hazard", "withdraw_hazard", "leave_facility"]
var verifying: bool = false
var dispatching: bool = false
var engine: Variant
var status_text: String = ""
var _tracked: RunState
var _bridge: JavaScriptObject
var _elapsed: float = 0.0
var _remainder: float = 0.0
var _sending: bool = false
var _finish_requested: bool = false
var _random_step: int = 0

class Reply extends RefCounted:
	signal completed(data: Dictionary)


func _ready() -> void:
	if OS.has_feature("web"): _bridge = JavaScriptBridge.get_interface("qqRanked")


func _process(delta: float) -> void:
	if verifying: return
	_elapsed += delta
	if _elapsed > 10.0:
		_elapsed = 0.0
		if active(): SaveManager.request_save(Game.current_screen_hint)
		flush()


func active() -> bool:
	return Game.current_run != null and not Game.current_run.ranking.is_empty()


func should_record() -> bool:
	return active() and not bool(Game.current_run.ranking.get("disqualified", false)) and not verifying and not dispatching


func tracks(value: Variant) -> bool:
	return should_record() and engine == value


func open_board() -> void:
	if _bridge != null: _bridge.open(Localization.get_language())
	else: OS.shell_open("https://masterqueue.kazu107.xyz/rankings")


func is_supported() -> bool:
	return _bridge != null


func request(method: String, path: String, body: Dictionary = {}) -> Dictionary:
	if _bridge == null: return {"error": "web_only"}
	var reply: Reply = Reply.new()
	var callback: JavaScriptObject = JavaScriptBridge.create_callback(func(arguments: Array) -> void:
		var parsed: Variant = JSON.parse_string(String(arguments[0]))
		reply.completed.emit(Dictionary(parsed) if parsed is Dictionary else {"error": "network_error"})
	)
	_bridge.request(method, path, JSON.stringify(body), callback)
	var result: Dictionary = await reply.completed
	return result


func start(starter_id: String) -> bool:
	var source_scene: Node = get_tree().current_scene
	var result: Dictionary = await request("POST", "/api/ranked/runs", {"starter_id": starter_id})
	if not is_instance_valid(source_scene) or get_tree().current_scene != source_scene: return false
	if result.has("error"):
		status_text = "ランキング開始不可: " + String(result["error"])
		changed.emit()
		return false
	if String(result.get("ticket", {}).get("ruleset", "")) != RULESET:
		status_text = "ルールが更新されています。ブラウザを再読み込みしてください。"
		changed.emit()
		return false
	initialize(Dictionary(result["ticket"]))
	SaveManager.save_game("map")
	return true


func initialize(ticket: Dictionary) -> void:
	if engine != null: engine.dispose()
	dispatching = true
	Game.settings["developer_mode"] = false
	Game.suspended_runs.erase("ranked")
	Game.current_run = RunState.from_starter(Database.get_starter(String(ticket["starter_id"])), int(ticket["seed"]))
	Game.current_run.infinite_mode = true
	Game.current_run.content_pool = ContentPoolService.build_snapshot({}, true)
	Game._apply_infinite_player_boost(Game.current_run)
	Game.current_run.map_state = MapGenerator.new().generate_infinite_run(int(ticket["seed"]))
	InfiniteScoreResolver.new().start_fresh(Game.current_run)
	Game.current_run.ranking = {"ticket": ticket.duplicate(true), "commands": [], "ack": 0, "disqualified": false, "status": "active"}
	Game.pending_enemy_id = ""
	Game.reward_options.clear()
	Game.last_reward_bundle.clear()
	Game.last_battle_summary.clear()
	Game.current_screen_hint = "map"
	_tracked = Game.current_run
	engine = null
	_remainder = 0.0
	_finish_requested = false
	_random_step = 0
	status_text = "ランキング対象 / 永続強化なし"
	dispatching = false
	changed.emit()


func _append(command: Dictionary) -> void:
	if not active(): return
	_tracked = Game.current_run
	var commands: Array = _tracked.ranking["commands"]
	commands.append(command)
	if commands.size() > 200000: disqualify("record_limit")


func _seed_services(_index: int, advance_rng: bool = true) -> void:
	if advance_rng: _random_step += 1
	var value: int = Game.current_run.seed ^ (_random_step * 7919)
	Game._rng.seed = value
	var services: Array = [Game._reward_resolver, Game._shop_service, Game._forge_service, Game._relic_service, Game._event_service]
	for i: int in services.size(): services[i]._rng.seed = value + i * 104729
	Game._event_service._reward_resolver._rng.seed = value + 999983


func _advances_rng(method: String) -> bool:
	return method not in ["equip_card", "unequip_card", "prepare_next_battle", "start_active_encounter", "continue_hazard"]


func restore_current() -> void:
	var ranking: Dictionary = Game.current_run.ranking.duplicate(true)
	var meta: Dictionary = Game.meta_progress.duplicate(true)
	var response: Dictionary = replay(Dictionary(ranking["ticket"]), Array(ranking["commands"]))
	Game.current_run.ranking = ranking
	Game.meta_progress = meta
	_tracked = Game.current_run
	verifying = false
	if response.has("error") and response["error"] != "battle_in_progress": disqualify("resume_mismatch")


func resume_saved() -> bool:
	var previous_run: RunState = Game.current_run
	var snapshot: Dictionary = Dictionary(Game.suspended_runs.get("ranked", {}))
	var run: Dictionary = Dictionary(snapshot.get("run", {}))
	var ranking: Dictionary = Dictionary(run.get("ranking", {}))
	if ranking.is_empty(): return false
	var commands: Array = Array(ranking.get("commands", [])).duplicate(true)
	var cursor: int = mini(int(ranking.get("ack", 0)), commands.size())
	var next: int = cursor
	var conflict: bool = false
	while true:
		var response: Dictionary = await request("GET", "/api/ranked/runs/%s/journal?from=%d" % [ranking["ticket"]["id"], cursor])
		if Game.current_run != previous_run: return false
		if response.has("error") or response.get("status", "active") != "active":
			status_text = "所有者のログインと接続を確認してください。記録は保持しています。"
			changed.emit()
			return false
		next = int(response["next_sequence"])
		var remote: Array = Array(response.get("commands", []))
		for index: int in remote.size():
			if cursor + index < commands.size():
				if commands[cursor + index] != remote[index]: conflict = true
				commands[cursor + index] = remote[index]
			else: commands.append(remote[index])
		cursor += remote.size()
		if cursor >= next: break
		if remote.is_empty(): return false
	if conflict: commands.resize(next)
	ranking["commands"] = commands
	ranking["ack"] = next
	run["ranking"] = ranking
	snapshot["run"] = run
	Game.suspended_runs["ranked"] = snapshot
	Game.resume_suspended_run("ranked")
	return true


func invoke(method: String, arguments: Array) -> Variant:
	_append({"kind": "game", "method": method, "args": arguments.duplicate(true)})
	_seed_services(Array(Game.current_run.ranking["commands"]).size(), _advances_rng(method))
	dispatching = true
	var result: Variant = Game.callv(method, arguments)
	dispatching = false
	SaveManager.request_save(Game.current_screen_hint)
	return result


func attach(value: Variant, run: RunState, enemy_id: String) -> void:
	if not active() or run != Game.current_run: return
	if not verifying and not dispatching:
		_append({"kind": "setup", "enemy_id": enemy_id})
	engine = value
	_remainder = 0.0


func battle_action(kind: String, runtime_id: String = "") -> Variant:
	_append({"kind": kind, "runtime_id": runtime_id})
	dispatching = true
	var result: Variant = engine.start_battle() if kind == "start" else engine.request_use_card("player", runtime_id)
	dispatching = false
	return result


func advance(value: Variant, delta: float) -> void:
	if value.battle_state.winner != "" or not value.has_battle_started(): return
	_remainder += clampf(delta, 0.0, 0.25)
	var ticks: int = mini(15, floori(_remainder / STEP))
	if ticks <= 0: return
	_remainder -= float(ticks) * STEP
	# Fixed ticks and run-length encoding make the same inputs reproducible without frame snapshots.
	var commands: Array = Game.current_run.ranking["commands"]
	var ack: int = int(Game.current_run.ranking.get("ack", 0))
	if not commands.is_empty() and commands.size() > ack and commands.back().get("kind", "") == "advance" and int(commands.back()["ticks"]) + ticks <= 3600:
		commands.back()["ticks"] = int(commands.back()["ticks"]) + ticks
	else: _append({"kind": "advance", "ticks": ticks})
	dispatching = true
	for _tick: int in ticks: value.update(STEP)
	dispatching = false


func complete() -> void:
	if engine == null or engine.battle_state.winner == "":
		disqualify("missing_battle")
		return
	_append({"kind": "complete"})
	_seed_services(Array(Game.current_run.ranking["commands"]).size())
	dispatching = true
	Game.complete_battle(engine.build_summary())
	dispatching = false
	engine = null
	SaveManager.request_save(Game.current_screen_hint)
	if Game.current_run.run_complete: finish()


func disqualify(reason: String) -> void:
	if not active(): return
	Game.current_run.ranking["disqualified"] = true
	Game.current_run.ranking["reason"] = reason
	_outbox()[String(Game.current_run.ranking["ticket"]["id"])] = Game.current_run.ranking
	SaveManager.request_save(Game.current_screen_hint)
	status_text = "ランキング対象外: " + reason
	changed.emit()


func finish() -> void:
	_finish_requested = true
	if active():
		Game.current_run.ranking["finish_requested"] = true
		_outbox()[String(Game.current_run.ranking["ticket"]["id"])] = Game.current_run.ranking
		SaveManager.request_save(Game.current_screen_hint)
	flush()


func _outbox() -> Dictionary:
	if not Game.settings.has("ranked_outbox"): Game.settings["ranked_outbox"] = {}
	return Dictionary(Game.settings["ranked_outbox"])


func _drop_terminal(ranking: Dictionary) -> void:
	if ranking.get("status", "active") not in ["active", "pending", "verifying"]: _outbox().erase(String(ranking["ticket"]["id"]))


func _upload_run() -> RunState:
	var user: Variant = AccountSession.snapshot.get("user")
	var owner: String = String(user.get("id", "")) if user is Dictionary else ""
	var queued: Array[Dictionary] = []
	for key: String in _outbox().keys():
		var entry: Dictionary = Dictionary(_outbox()[key])
		if entry.get("status", "active") not in ["active", "pending", "verifying"]:
			_outbox().erase(key)
			continue
		if entry.get("ticket", {}).get("user_id", "") != owner: continue
		if entry.get("status", "active") == "active":
			var run: RunState = RunState.new()
			run.ranking = entry
			return run
		queued.append(entry)
	if active() and Game.current_run.ranking.get("status", "active") == "active":
		var ranking: Dictionary = Game.current_run.ranking
		var sendable: int = Array(ranking["commands"]).size() - (1 if engine != null else 0)
		if sendable > int(ranking.get("ack", 0)) or bool(ranking.get("disqualified", false)): return Game.current_run
	if not queued.is_empty():
		var run: RunState = RunState.new()
		run.ranking = queued[0]
		return run
	return null


func flush() -> void:
	if _sending or verifying or _bridge == null: return
	var run: RunState = _upload_run()
	if run == null: return
	var ranking: Dictionary = run.ranking
	if ranking.get("status", "active") not in ["active", "pending", "verifying"]: return
	var user: Variant = AccountSession.snapshot.get("user")
	if user is not Dictionary or user.get("id", "") != ranking["ticket"].get("user_id", ""):
		status_text = "記録の所有者でログインすると送信を再開します"
		changed.emit()
		return
	_sending = true
	if bool(ranking.get("disqualified", false)):
		var receipt: Dictionary = await request("GET", "/api/ranked/runs/%s/journal?from=0" % ranking["ticket"]["id"])
		if not receipt.has("error"):
			var closed: Dictionary = await request("POST", "/api/ranked/runs/%s/finish" % ranking["ticket"]["id"], {"sequence": int(receipt.get("next_sequence", 0)), "disqualified": true})
			if not closed.has("error"):
				ranking["status"] = closed.get("status", "disqualified")
				status_text = "ランキング対象外 / ローカルプレイとして続行できます"
				if active() and Game.current_run.ranking.get("ticket", {}).get("id", "") == ranking["ticket"]["id"]: Game.current_run.ranking = {}
		_sending = false
		_drop_terminal(ranking)
		SaveManager.request_save(Game.current_screen_hint)
		changed.emit()
		return
	if ranking.get("status", "active") in ["pending", "verifying"]:
		var history: Dictionary = await request("GET", "/api/ranked/runs/%s" % ranking["ticket"]["id"])
		for record: Dictionary in ([] if history.has("error") else [history]):
			if record.get("id", "") != ranking["ticket"]["id"]: continue
			ranking["status"] = record.get("status", "pending")
			match String(ranking["status"]):
				"verified": status_text = "正式記録: %s点" % String.num(float(record.get("result", {}).get("total_score", 0)), 0)
				"rejected", "disqualified", "unverified": status_text = "ランキング対象外: " + String(record.get("reason", "unverified"))
				_: status_text = "サーバーで記録を検証しています"
			break
		_sending = false
		_drop_terminal(ranking)
		SaveManager.request_save(Game.current_screen_hint)
		changed.emit()
		return
	var commands: Array = ranking["commands"]
	var first: int = int(ranking.get("ack", 0))
	# Do not upload a mutable tail while its battle is advancing.
	var limit: int = commands.size() if engine == null or Game.current_run != run else maxi(0, commands.size() - 1)
	while first < limit:
		var last: int = mini(first + 250, limit)
		var response: Dictionary = await request("POST", "/api/ranked/runs/%s/commands" % ranking["ticket"]["id"], {"sequence": first, "commands": commands.slice(first, last).duplicate(true)})
		if response.has("error"):
			status_text = "記録を保留中: " + String(response["error"])
			_sending = false
			changed.emit()
			return
		first = int(response["next_sequence"])
		ranking["ack"] = first
	if bool(ranking.get("finish_requested", false)) and first == commands.size():
		var response: Dictionary = await request("POST", "/api/ranked/runs/%s/finish" % ranking["ticket"]["id"], {"sequence": first, "disqualified": bool(ranking.get("disqualified", false))})
		if not response.has("error"):
			ranking["status"] = response.get("status", "pending")
			status_text = "送信済み / サーバー検証待ち" if ranking["status"] in ["pending", "verifying"] else "記録を確定しました。ランキング履歴を確認してください。"
		else: status_text = "記録を保留中: " + String(response["error"])
	_sending = false
	_drop_terminal(ranking)
	SaveManager.request_save(Game.current_screen_hint)
	changed.emit()


func replay(ticket: Dictionary, commands: Array) -> Dictionary:
	verifying = true
	initialize(ticket)
	verifying = true
	var ticks_total: int = 0
	for index: int in commands.size():
		var command: Dictionary = Dictionary(commands[index])
		var kind: String = String(command.get("kind", ""))
		var phase: String = Game.current_screen_hint
		match kind:
			"game":
				var method: String = String(command.get("method", ""))
				var arguments: Array = Array(command.get("args", []))
				if not METHODS.has(method) or not _legal(method, arguments, phase): return {"error": "illegal_action", "sequence": index}
				_seed_services(index + 1, _advances_rng(method))
				if method == "start_active_encounter" and phase == "battle": Game.current_screen_hint = "map"
				var applied: Variant = Game.callv(method, arguments)
				if applied is bool and not applied: return {"error": "rejected_action", "sequence": index}
				if method == "select_map_node" and String(applied) == "": return {"error": "rejected_action", "sequence": index}
			"setup":
				if phase != "battle" or engine != null or Game.pending_enemy_id != command.get("enemy_id", ""): return {"error": "illegal_battle", "sequence": index}
				engine = RealtimeBattleEngine.new()
				engine.record_visuals = false
				engine.set_audio_enabled(false)
				engine.setup(Game.current_run, String(command["enemy_id"]))
			"start", "card":
				if engine == null or phase != "battle": return {"error": "missing_battle", "sequence": index}
				if kind == "start": engine.start_battle()
				else: engine.request_use_card("player", String(command.get("runtime_id", "")))
			"advance":
				if engine == null or phase != "battle": return {"error": "missing_battle", "sequence": index}
				var ticks: int = int(command.get("ticks", 0))
				if ticks <= 0 or ticks > 3600: return {"error": "invalid_ticks", "sequence": index}
				ticks_total += ticks
				if ticks_total > 20000000: return {"error": "verification_budget"}
				for _tick: int in ticks: engine.update(STEP)
			"complete":
				if engine == null or engine.battle_state.winner == "": return {"error": "unfinished_battle", "sequence": index}
				_seed_services(index + 1)
				Game.complete_battle(engine.build_summary(false))
				engine.dispose()
				engine = null
			_: return {"error": "unknown_command", "sequence": index}
	if engine != null: return {"error": "battle_in_progress"}
	var result: Dictionary = InfiniteScoreResolver.new().calculate(Game.current_run)
	result["starter_id"] = Game.current_run.starter_id
	result["cards"] = Game.current_run.equipped_cards.duplicate()
	result["relics"] = Game.current_run.relics.duplicate()
	result["battle_count"] = Game.current_run.battle_history.size()
	result["hp"] = Game.current_run.player_hp
	result["max_hp"] = Game.current_run.max_hp
	result["attack"] = Game.current_run.attack
	result["speed"] = Game.current_run.speed
	result["gold"] = Game.current_run.gold
	result["loadout_limit"] = Game.current_run.loadout_limit
	result["card_upgrades"] = Game.current_run.card_upgrades.duplicate(true)
	var owned: Dictionary = {}
	for id: String in Game.current_run.player_cards: owned[id] = int(owned.get(id, 0)) + 1
	result["owned_cards"] = owned
	result["ticks"] = ticks_total
	return {"result": result}


func _legal(method: String, arguments: Array, phase: String) -> bool:
	if Game.current_run.run_complete: return false
	var empty_args: bool = method in ["start_active_encounter", "prepare_next_battle", "skip_reward", "reroll_rewards_for_gold", "continue_hazard", "withdraw_hazard", "leave_facility"]
	if arguments.size() != (0 if empty_args else 1): return false
	if method == "prepare_next_battle": return phase == "battle" and engine == null and Game.pending_enemy_id != ""
	if method == "select_map_node": return phase == "map" and Game.get_active_map_node().is_empty() and arguments.size() == 1
	if method == "start_active_encounter": return phase in ["map", "facility", "battle"] and engine == null
	if method in ["choose_reward", "skip_reward", "reroll_rewards_for_gold"]:
		if phase != "reward": return false
		return method != "choose_reward" or (arguments.size() == 1 and Game.reward_options.has(String(arguments[0])))
	if method in ["equip_card", "unequip_card", "sell_loadout_card"]: return engine == null and phase in ["map", "facility"]
	return phase == "facility" and engine == null and not Game.get_active_map_node().is_empty()
