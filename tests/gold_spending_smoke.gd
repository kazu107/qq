extends Node

const TARGETS: Array[int] = [25, 100, 300, 750, 1500, 3000, 6000, 10000, 20000, 50000, 100000, 250000, 500000, 1000000]
const REWARDS: Array[int] = [1, 2, 3, 5, 6, 8, 10, 12, 15, 18, 22, 26, 30, 40]
var _checks: int = 0
var _service: MetaProgressService = MetaProgressService.new()


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		push_error("Gold spending: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _fresh_meta() -> Dictionary:
	var meta: Dictionary = Database.meta_progress_template.duplicate(true)
	_service.ensure_defaults(meta)
	return meta


func _entry(meta: Dictionary) -> Dictionary:
	for entry: Dictionary in _service.build_achievement_entries(meta):
		if String(entry["id"]) == "big_spender":
			return entry
	return {}


func _spent() -> int:
	return int(Dictionary(Game.meta_progress["achievement_stats"]).get("gold_spent", 0))


func _run() -> void:
	var meta: Dictionary = _fresh_meta()
	for index: int in TARGETS.size():
		meta["achievement_stats"]["gold_spent"] = TARGETS[index] - 1
		_check(not _service.claim_achievement(meta, "big_spender"), "early tier claim accepted")
		_service.increment_achievement_stat(meta, "gold_spent", 1)
		var entry: Dictionary = _entry(meta)
		_check(int(entry["tier_count"]) == TARGETS.size() and int(entry["target"]) == TARGETS[index], "wrong tier threshold")
		var points: int = int(meta["points"])
		_check(_service.claim_achievement(meta, "big_spender"), "threshold claim failed")
		_check(int(meta["points"]) == points + REWARDS[index], "incorrect tier reward")
		_check(not _service.claim_achievement(meta, "big_spender"), "duplicate tier reward accepted")
	_check(bool(_entry(meta)["claimed"]), "last tier must finish the achievement")
	for with_counts: bool in [false, true]:
		var legacy: Dictionary = _fresh_meta()
		legacy["claimed_achievements"] = ["big_spender"]
		legacy["achievement_claim_counts"] = {"big_spender": 4} if with_counts else {}
		legacy["achievement_stats"]["gold_spent"] = 1600
		_service.ensure_defaults(legacy)
		var entry: Dictionary = _entry(legacy)
		_check(int(entry["claimed_count"]) == 4 and int(entry["target"]) == 1500, "legacy completion must resume at tier five")
		_check(not bool(entry["claimed"]) and bool(entry["claimable"]), "legacy completion hid the additional tiers")
		var points: int = int(legacy["points"])
		_check(_service.claim_achievement(legacy, "big_spender") and int(legacy["points"]) == points + 6, "legacy claims must grant only the new reward")
		_service.ensure_defaults(legacy)
		_check(int(_entry(legacy)["claimed_count"]) == 5, "normalization reverted the newly claimed tier")

	Game.meta_progress = _fresh_meta()
	Game.start_arena_run("balanced")
	Game.current_run.gold = 200
	Game.current_run.arena_shop["cards"] = [{"card_id": "strike", "price": 18, "bought": false}]
	Game.current_run.arena_shop["relics"] = [{"relic_id": "war_cache", "price": 50, "bought": false}]
	_check(Game.buy_arena_card_offer(0) and _spent() == 18, "solo card purchase was not counted")
	_check(not Game.buy_arena_card_offer(0) and _spent() == 18, "failed repeat purchase was counted")
	_check(Game.buy_arena_relic_offer(0) and _spent() == 68 and Game.current_run.gold == 167, "relic gold grant must not offset the actual price")
	Game.current_run.arena_reroll_cost = 7
	_check(Game.reroll_arena_shop_for_gold() and _spent() == 75, "solo reroll was not counted")
	Game.current_run.gold = 0
	_check(not Game.reroll_arena_shop_for_gold() and _spent() == 75, "unaffordable reroll was counted")
	Game.current_run.gold = 100
	_check(Game._apply_event_effect({"type": "lose_gold", "amount": 20}), "event payment failed")
	Game._apply_event_effect({"type": "grant_gold", "amount": 35})
	_check(_spent() == 95, "gold grants must not reduce event spending")
	_check(not Game._apply_event_effect({"type": "lose_gold", "amount": 500}) and _spent() == 95, "unaffordable event was counted")
	Game.start_new_run("balanced", 4242)
	_check(_spent() == 95, "new run reset lifetime spending")
	var save: SaveData = SaveData.from_dict(Game.build_save_data("hub").to_dict())
	Game.meta_progress = _fresh_meta()
	Game.apply_loaded_save(save)
	_check(_spent() == 95, "save/load lost lifetime spending")

	var coordinator: LanArenaCoordinator = LanArenaCoordinator.new()
	var run: RunState = coordinator.create_run(LanProtocol.build_profile("Spending test", "balanced"), 4242)
	run.gold = 300
	run.arena_shop["cards"] = [{"card_id": "strike", "price": 22, "bought": false}]
	run.arena_shop["relics"] = [{"relic_id": "war_cache", "price": 50, "bought": false}]
	var result: Dictionary = coordinator.apply_action(run, "buy_card", {"index": 0})
	_check(int(result.get("gold_spent", 0)) == 22 and _spent() == 95, "host simulation must not credit other players")
	NetworkManager._send_arena_action_result(1, "buy_card", true, result)
	_check(_spent() == 117, "host purchase acknowledgement was not counted")
	result = coordinator.apply_action(run, "buy_card", {"index": 0})
	NetworkManager._send_arena_action_result(1, "buy_card", false, result)
	_check(_spent() == 117, "rejected network purchase was counted")
	result = coordinator.apply_action(run, "buy_relic", {"index": 0})
	_check(int(result.get("gold_spent", 0)) == 50 and int(result["gold_delta"]) == -15, "network receipt must distinguish spending from net balance")
	NetworkManager._arena_action_result_rpc("buy_relic", true, result)
	_check(_spent() == 167, "guest purchase acknowledgement did not count the full price")
	run.arena_reroll_cost = 7
	result = coordinator.apply_action(run, "reroll", {})
	NetworkManager._arena_action_result_rpc("reroll", true, result)
	_check(_spent() == 174, "guest reroll was not counted")
	NetworkManager._receive_local_arena_action_result("sell", true, {"gold_spent": 999, "gold_delta": 9})
	NetworkManager._receive_local_arena_action_result("dev_add_gold", true, {"gold_spent": 999})
	_check(_spent() == 174, "sales or developer gold were counted as spending")
	_check(SaveManager.has_pending_save(), "network spending must request persistence")
	SaveManager.flush_requested_save()
	_check(int(SaveManager.load_save().meta_progress["achievement_stats"]["gold_spent"]) == 174, "network spending did not persist")

	Game.settings["developer_mode"] = true
	Localization.set_language("ja", false)
	var scene: Control = load("res://scenes/meta/MetaProgress.tscn").instantiate() as Control
	add_child(scene)
	for _frame: int in 180:
		if bool(scene.call("is_content_ready")):
			break
		await get_tree().process_frame
	var name_label: Label = scene.find_child("AchievementName_big_spender", true, false) as Label
	var progress_label: Label = scene.find_child("AchievementProgress_big_spender", true, false) as Label
	_check(name_label != null and name_label.text == "累計ゴールド使用額", "localized spending achievement did not render")
	_check(progress_label != null and progress_label.text.contains("174"), "UI did not show cumulative spending")
	var developer_button: Button = scene.find_child("DevMetaGoldSpent", true, false) as Button
	_check(developer_button != null, "developer spending action is missing")
	_check(developer_button.get_combined_minimum_size().x <= 240.0, "developer spending button is too wide")
	developer_button.pressed.emit()
	_check(_spent() == 274 and progress_label.text.contains("274"), "developer action did not refresh achievement progress")
	print("GOLD_SPENDING_SMOKE_OK %d checks: tiers, legacy claims, gross payments, Web acknowledgements, save/load, UI" % _checks)
	get_tree().quit(0)
