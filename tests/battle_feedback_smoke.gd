extends Node

var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		push_error("Battle feedback: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _run() -> void:
	Database.load_all()
	var animation: HpBarAnimation = HpBarAnimation.new()
	animation.set_value("player", 100, 100)
	animation.set_value("player", 60, 100)
	_check(is_equal_approx(animation.displayed_ratio, 1.0), "damage should not jump the fill")
	animation.advance(0.1)
	_check(is_equal_approx(animation.displayed_ratio, 0.8), "100ms should be halfway")
	animation.set_value("player", 60, 100)
	animation.advance(0.1)
	_check(is_equal_approx(animation.displayed_ratio, 0.6), "identical snapshots must finish at 200ms")
	animation.set_value("player", 20, 100)
	animation.advance(0.1)
	animation.set_value("player", 0, 100)
	_check(is_equal_approx(animation.displayed_ratio, 0.4), "a second hit must keep the displayed fill")
	animation.advance(0.1)
	_check(is_equal_approx(animation.displayed_ratio, 0.2), "a second hit must retarget from the visible fill")
	animation.advance(0.1)
	_check(is_zero_approx(animation.displayed_ratio), "lethal damage must finish at zero")
	animation.set_value("player", 100, 100)
	animation.advance(0.2)
	_check(is_equal_approx(animation.displayed_ratio, 1.0), "healing must reach its target")
	animation.set_value("player", 50, 200)
	_check(is_equal_approx(animation.displayed_ratio, 0.25), "max HP changes must snap")
	animation.set_value("other", 150, 200)
	_check(is_equal_approx(animation.displayed_ratio, 0.75), "new units must snap")
	animation.reset()
	animation.set_value("other", 0, 200)
	_check(is_zero_approx(animation.displayed_ratio), "seek/reconnect reset must snap")

	var stage: BattleStage3D = BattleStage3D.new()
	add_child(stage)
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	stage.configure_combatants("player", "scout")
	var player: UnitState = UnitState.new()
	player.unit_id = "player"
	player.hp = 100
	player.max_hp = 100
	var enemy: UnitState = UnitState.new()
	enemy.unit_id = "scout"
	enemy.hp = 50
	enemy.max_hp = 50
	stage.refresh_unit_status(player, enemy)
	var plate: BattleUnitStatus3D = stage.get_player_status_model()
	var fill: MeshInstance3D = plate.get_node("HpBarFill3D") as MeshInstance3D
	player.hp = 0
	stage.refresh_unit_status(player, enemy)
	_check(plate.get_hp_text() == "0 / 100" and fill.visible, "number must update before lethal fill disappears")
	plate._process(0.1)
	var mesh: QuadMesh = fill.mesh as QuadMesh
	_check(is_equal_approx(mesh.size.x, BattleUnitStatus3D.HP_BAR_SIZE.x * 0.5), "3D fill should be halfway at 100ms")
	_check(is_equal_approx(fill.position.x - mesh.size.x * 0.5, BattleUnitStatus3D.HP_BAR_CENTER_X - BattleUnitStatus3D.HP_BAR_SIZE.x * 0.5), "3D fill left edge must stay fixed")
	plate._process(0.1)
	_check(not fill.visible, "zero fill must hide only after 200ms")
	stage.reset_replay_pose([], 75, 50)
	player.hp = 75
	stage.refresh_unit_status(player, enemy)
	_check(is_equal_approx(plate.get_displayed_hp_ratio(), 0.75), "replay seek must snap")
	stage.configure_combatants("player", "scout")
	player.hp = 30
	stage.refresh_unit_status(player, enemy)
	_check(is_equal_approx(plate.get_displayed_hp_ratio(), 0.3), "cached stage reconfiguration must snap")
	stage.set_playback_speed(0.0)
	player.hp = 10
	stage.refresh_unit_status(player, enemy)
	plate._process(0.2)
	_check(is_equal_approx(plate.get_displayed_hp_ratio(), 0.1), "HP transition must not depend on animation speed")

	var panel: UnitPanel = UnitPanel.new()
	add_child(panel)
	panel.set_process(false)
	player.hp = 100
	panel.refresh_unit(player)
	player.hp = 50
	panel.refresh_unit(player)
	panel._process(0.1)
	var bar: ProgressBar = panel.find_child("HpBar", true, false) as ProgressBar
	_check(is_equal_approx(bar.value, 75.0), "2D fallback must also animate over 200ms")
	panel.refresh_unit(player)
	panel._process(0.1)
	_check(is_equal_approx(bar.value, 50.0), "2D repeated refresh must not restart")
	panel.configure_visual("player", "balanced")
	player.hp = 25
	panel.refresh_unit(player)
	_check(is_equal_approx(bar.value, 25.0), "2D new combatant must snap")

	stage.configure_combatants("player", "scout")
	stage.set_playback_speed(1.0)
	stage.play_battle_event({"event_type": "battle_start"})
	AudioManager.clear_play_history()
	var event: Dictionary = _resolution()
	stage.play_battle_event(event)
	_check(AudioManager.get_play_history() == ["card_strike"], "SE must play even while another visual is active")
	_advance_visuals(stage, 2.0)
	_check(AudioManager.get_play_history() == ["card_strike"], "impact marker must not duplicate SE")
	var blocked: Dictionary = _resolution()
	blocked["result"]["enemy_after"] = {"hp": 50, "shield": 5}
	blocked["result"]["enemy_before"] = {"hp": 50, "shield": 15}
	blocked["result"]["fully_blocked"] = true
	var compact: Dictionary = BattleStateCodec._encode_network_result(blocked["result"])
	_check(compact.get("fully_blocked", false), "compact snapshot must retain shield block result")
	blocked["result"] = compact
	AudioManager.clear_play_history()
	stage.play_battle_event(blocked)
	_check(AudioManager.get_play_history() == ["battle_full_block"], "compact shield block SE must be immediate")
	_advance_visuals(stage, 2.0)
	_check(AudioManager.get_play_history() == ["battle_full_block"], "compact impact must not duplicate SE")
	blocked["result"].erase("fully_blocked")
	AudioManager.clear_play_history()
	stage.play_battle_event(blocked)
	_check(AudioManager.get_last_sfx_id() == "battle_full_block", "old compact events must infer shield blocking")
	var fatigue: Dictionary = _resolution()
	fatigue["event_type"] = "fatigue_card"
	AudioManager.clear_play_history()
	stage.play_battle_event(fatigue)
	_check(AudioManager.get_play_history() == ["status_bleed_tick"], "fatigue SE must play before its visual begins")
	_advance_visuals(stage, 3.0)
	_check(AudioManager.get_play_history() == ["status_bleed_tick"], "fatigue animation must not repeat audio")

	# Exercise the screen's local and compact-network event cursors without a live connection.
	var screen: Control = load("res://src/ui/battle/BattleScreen.gd").new() as Control
	screen.set("_battle_stage", stage)
	var state: BattleState = BattleState.new()
	state.battle_events.append(event)
	AudioManager.clear_play_history()
	screen.call("_process_resolution_vfx", state)
	screen.call("_process_resolution_vfx", state)
	_check(AudioManager.get_play_history() == ["card_strike"], "local refresh must consume SE exactly once")
	screen.set("_lan_mode", true)
	screen.set("_processed_vfx_event_count", 5)
	screen.set("_lan_battle_event_total", 6)
	state.battle_events[0]["_event_index"] = 5
	AudioManager.clear_play_history()
	screen.call("_process_resolution_vfx", state)
	screen.call("_process_resolution_vfx", state)
	_check(AudioManager.get_play_history() == ["card_strike"], "compact snapshots must not double-play sound")
	(screen.get("_engine") as RealtimeBattleEngine).dispose()
	screen.free()
	print("BATTLE_FEEDBACK_SMOKE_OK %d checks: immediate audio, deduplication, compact blocks, 200ms HP" % _checks)
	get_tree().quit(0)


func _advance_visuals(stage: BattleStage3D, seconds: float) -> void:
	for frame: int in int(ceilf(seconds / 0.02)):
		stage._process(0.02)
		stage.get_combat_actor("player")._process(0.02)
		stage.get_combat_actor("scout")._process(0.02)


func _resolution() -> Dictionary:
	return {"event_type": "resolve_card", "actor_id": "player", "target_id": "scout", "card_id": "strike",
		"result": {"player_before": {"hp": 100, "shield": 0}, "player_after": {"hp": 100, "shield": 0},
			"enemy_before": {"hp": 50, "shield": 0}, "enemy_after": {"hp": 40, "shield": 0}}}
