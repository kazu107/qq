extends Node

const MAX_LEVELS: Dictionary = {"max_hp": 10, "attack": 8, "speed": 8, "loadout_limit": 5}
const MAX_BONUSES: Dictionary = {"max_hp": 50, "attack": 8, "speed": 8, "loadout_limit": 5}
const TOTAL_COSTS: Dictionary = {"max_hp": 279, "attack": 304, "speed": 221, "loadout_limit": 138}
var _service: MetaProgressService = MetaProgressService.new()
var _checks: int = 0
var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error("Meta stat upgrade: " + message)


func _fresh(points: int = 0) -> Dictionary:
	var meta: Dictionary = Database.meta_progress_template.duplicate(true)
	meta["points"] = points
	_service.ensure_defaults(meta)
	return meta


func _entry(meta: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in _service.build_stat_upgrade_entries(meta):
		if entry["id"] == id: return entry
	return {}


func _run() -> void:
	_check(Database.load_errors.is_empty() and Database.meta_stat_upgrades.size() == 4, "upgrade database invalid")
	for data: Dictionary in Database.meta_stat_upgrades:
		var id: String = String(data["id"])
		var meta: Dictionary = _fresh()
		var total: int = 0
		var last_cost: int = 0
		_check(data["tiers"].size() == MAX_LEVELS[id], "wrong number of upgrade stages")
		for index: int in Array(data["tiers"]).size():
			var cost: int = int(data["tiers"][index]["cost"])
			_check(cost > last_cost and int(data["tiers"][index]["amount"]) > 0, "costs must grow and bonuses must be positive")
			last_cost = cost
			meta["points"] = cost - 1
			_check(not _service.purchase_stat_upgrade(meta, id) and _entry(meta, id)["level"] == index, "insufficient points accepted")
			meta["points"] = cost
			_check(_service.purchase_stat_upgrade(meta, id), "stage purchase failed")
			_check(meta["points"] == 0 and _entry(meta, id)["level"] == index + 1, "wrong charge/level")
			total += cost
			_check(int(_service.get_permanent_bonuses(meta)[id]) == int(_entry(meta, id)["current_bonus"]), "computed permanent bonus differs from UI")
		_check(total == TOTAL_COSTS[id] and _service.get_permanent_bonuses(meta)[id] == MAX_BONUSES[id], "wrong total cost or maximum effect")
		meta["points"] = 1000
		_check(not _service.purchase_stat_upgrade(meta, id) and meta["points"] == 1000, "maximum level can be purchased again")
		var snapshot: String = JSON.stringify(meta)
		for repeat: int in 5: _service.get_permanent_bonuses(meta)
		_check(JSON.stringify(meta) == snapshot, "reading bonuses modifies purchased/achievement bonuses")
		_check(_service.reset_stat_upgrades(meta) == total and meta["points"] == 1000 + total, "developer refund does not match configured purchases")
		_check(_service.reset_stat_upgrades(meta) == 0 and meta["points"] == 1000 + total, "repeated reset creates free points")
	var legacy: Dictionary = _fresh(50)
	legacy.erase("permanent_upgrade_levels")
	legacy["permanent_bonuses"]["max_hp"] = 5
	_service.ensure_defaults(legacy)
	_check(_entry(legacy, "max_hp")["level"] == 0 and _service.get_permanent_bonuses(legacy)["max_hp"] == 5 and legacy["points"] == 50, "old bonuses or points changed during migration")
	_service.purchase_stat_upgrade(legacy, "max_hp")
	legacy["achievement_stats"]["victories"] = 1
	_check(_service.claim_achievement(legacy, "first_victory"), "achievement claim after purchase failed")
	_check(legacy["permanent_bonuses"]["max_hp"] == 10 and _service.get_permanent_bonuses(legacy)["max_hp"] == 15, "achievement folded purchased HP into reward bucket")
	_check(not _service.purchase_stat_upgrade(legacy, "defense") and not _service.purchase_stat_upgrade(legacy, "unknown"), "invalid stat accepted")
	legacy["permanent_upgrade_levels"]["attack"] = 999
	legacy["permanent_upgrade_levels"]["speed"] = -4
	_service.ensure_defaults(legacy)
	_check(legacy["permanent_upgrade_levels"]["attack"] == 8 and legacy["permanent_upgrade_levels"]["speed"] == 0, "saved upgrade levels not clamped")
	_test_run_and_save()
	await _test_ui()
	if _failed: get_tree().quit(1)
	else:
		print("META_STAT_UPGRADE_SMOKE_OK checks=%d" % _checks)
		get_tree().quit()


func _test_run_and_save() -> void:
	Game.meta_progress = _fresh(100)
	Game.start_new_run("balanced", 4242)
	var base: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	_check(Game.purchase_meta_stat_upgrade("max_hp") and Game.purchase_meta_stat_upgrade("attack"), "Game purchase API failed")
	_check(Game.current_run.max_hp == base.max_hp and Game.current_run.attack == base.attack, "active run was retroactively upgraded")
	_check(SaveManager.has_pending_save(), "purchase did not request save")
	SaveManager.flush_requested_save()
	var save: SaveData = SaveManager.load_save()
	Game.meta_progress = _fresh()
	Game.apply_loaded_save(save)
	_check(Game.get_meta_points() == 94 and _entry(Game.meta_progress, "max_hp")["level"] == 1 and _entry(Game.meta_progress, "attack")["level"] == 1, "purchase save/load failed")
	Game.stash_active_run_for_hub()
	Game.purchase_meta_stat_upgrade("speed")
	Game.resume_suspended_run(Game.RUN_SETUP_MODE_NORMAL)
	_check(Game.current_run.max_hp == base.max_hp and Game.current_run.attack == base.attack and Game.current_run.speed == base.speed, "suspended run was changed on resume")
	Game.start_new_run("balanced", 4242)
	_check(Game.current_run.max_hp == base.max_hp + 5 and Game.current_run.attack == base.attack + 1 and Game.current_run.speed == base.speed + 1, "new normal run did not apply bonuses")
	Game.purchase_meta_stat_upgrade("loadout_limit")
	Game.start_new_run("balanced", 4242)
	_check(Game.current_run.loadout_limit == base.loadout_limit + 1, "loadout upgrade reduces card costs instead of increasing cap")
	Game.meta_progress["infinite_mode_unlocked"] = true
	Game.start_infinite_run("balanced", 4242)
	_check(Game.current_run.max_hp == base.max_hp + 5 + 18 and Game.current_run.attack == base.attack + 1 + 2 and Game.current_run.speed == base.speed + 1 + 2 and Game.current_run.loadout_limit == base.loadout_limit + 1 + 2, "infinite boost and purchases did not stack once")
	Game.start_arena_run("balanced", 4242)
	_check(Game.current_run.max_hp == ArenaService.INITIAL_MAX_HP and Game.current_run.attack == base.attack and Game.current_run.speed == base.speed and Game.current_run.loadout_limit == base.loadout_limit, "solo arena inherited permanent upgrades")
	var online: RunState = LanArenaCoordinator.new().create_run(LanProtocol.build_profile("Test", "balanced"), 4242)
	_check(online.max_hp == ArenaService.INITIAL_MAX_HP and online.attack == base.attack and online.speed == base.speed and online.loadout_limit == base.loadout_limit, "Web arena inherited permanent upgrades")
	Game.settings["developer_mode"] = false
	_check(not Game.developer_reset_stat_upgrades(), "normal player can refund permanent upgrades")
	Game.settings["developer_mode"] = true
	var points: int = Game.get_meta_points()
	_check(Game.developer_reset_stat_upgrades() and Game.get_meta_points() == points + 15, "developer reset/refund failed")
	_check(Game.get_permanent_bonuses()["max_hp"] == 0, "developer reset left purchase effects")
	Game.developer_reset_meta_progress()
	_check(_entry(Game.meta_progress, "attack")["level"] == 0, "full meta reset did not reset upgrades")


func _test_ui() -> void:
	Game.current_run = null
	Game.meta_progress = _fresh(6)
	Game.settings["developer_mode"] = true
	Game.set_language("ja")
	var scene: Control = load("res://scenes/meta/MetaProgress.tscn").instantiate() as Control
	add_child(scene)
	for frame: int in 180:
		if scene.call("is_content_ready"): break
		await get_tree().process_frame
	var grid: GridContainer = scene.find_child("MetaStatUpgradeGrid", true, false) as GridContainer
	_check(grid != null and grid.get_child_count() == 4, "four upgrade cards not rendered")
	var button: Button = scene.find_child("BuyMetaStatUpgrade_max_hp", true, false) as Button
	var frame: Control = scene.find_child("MetaStatUpgradeFrame_max_hp", true, false) as Control
	var identity: int = frame.get_instance_id()
	_check(button != null and not button.disabled and button.text == "2   強化+5", "purchase button must show cost, gap, action and next bonus")
	_check(button.icon != null and button.icon.resource_path == "res://assets/icons/ui/meta_points.png", "purchase button point icon missing")
	_check(button.icon_alignment == HORIZONTAL_ALIGNMENT_LEFT and button.alignment == HORIZONTAL_ALIGNMENT_LEFT and button.get_theme_constant("h_separation") == 4, "point icon must precede the cost without overlapping the action")
	_check((scene.find_child("MetaStatUpgradeLevel_max_hp", true, false) as Label).text == "Lv. 0/10", "purchase bonus text should be removed")
	_check((scene.find_child("MetaStatUpgradeTotal_max_hp", true, false) as Label).text == "合計永続補正 +0", "only the total permanent bonus should remain")
	for id: String in ["attack", "speed", "loadout_limit"]:
		_check((scene.find_child("BuyMetaStatUpgrade_" + id, true, false) as Button).text.ends_with("強化+1"), "upgrade gain must match stat tier")
	button.pressed.emit()
	_check(Game.get_meta_points() == 4 and button.text == "4   強化+5" and not button.disabled, "next cost/order was not refreshed")
	button.pressed.emit()
	_check(Game.get_meta_points() == 0 and button.disabled and button.text == "7   強化+5", "unaffordable next stage must retain cost/action/gain order")
	_check((scene.find_child("MetaStatUpgradeFrame_max_hp", true, false) as Control).get_instance_id() == identity, "purchase rebuilt stat cards")
	var bar: ProgressBar = scene.find_child("MetaStatUpgradeBar_max_hp", true, false) as ProgressBar
	_check(bar.value == 2 and bar.max_value == 10 and bar.has_theme_stylebox_override("background"), "level bar or zero background missing")
	var dev_points: Button = scene.find_child("DevMetaUpgradePoints", true, false) as Button
	dev_points.pressed.emit()
	_check(Game.get_meta_points() == 100 and not button.disabled, "developer funding did not update availability")
	(scene.find_child("DevMetaResetStatUpgrades", true, false) as Button).pressed.emit()
	_check(Game.get_meta_points() == 106 and bar.value == 0, "developer reset did not refresh cards")
	SaveManager.flush_requested_save()
	_check(SaveManager.load_save().meta_progress["permanent_upgrade_levels"]["max_hp"] == 0, "reset did not persist")
