extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _run() -> void:
	var host_profile: Dictionary = LanProtocol.build_profile("Host", "balanced", true, "host-token-12345")
	var guest_profile: Dictionary = LanProtocol.build_profile("Guest", "tempo", true, "guest-token-1234")
	if not _assert_valid_profile(host_profile):
		return
	if not _assert_valid_profile(guest_profile):
		return
	if LanProtocol.build_content_hash().length() != 64:
		_fail("LAN smoke failed: content hash was not SHA-256 length")
		return

	var mismatched_profile: Dictionary = host_profile.duplicate(true)
	mismatched_profile["content_hash"] = "different"
	var mismatch_result: Dictionary = LanProtocol.validate_profile(mismatched_profile)
	if bool(mismatch_result.get("valid", true)) or String(mismatch_result.get("error", "")) != "content_mismatch":
		_fail("LAN smoke failed: content mismatch was not rejected")
		return

	var invalid_card_profile: Dictionary = host_profile.duplicate(true)
	invalid_card_profile["deck"] = ["missing_network_card"]
	if bool(LanProtocol.validate_profile(invalid_card_profile).get("valid", true)):
		_fail("LAN smoke failed: unknown card was accepted")
		return

	var payload: Dictionary = LanProtocol.build_match_payload(host_profile, guest_profile, 246810, 1, 77)
	if payload.is_empty() or String(Dictionary(payload.get("peer_sides", {})).get("77", "")) != "enemy":
		_fail("LAN smoke failed: match payload did not assign canonical sides")
		return
	var player_run: RunState = RunState.from_dict(Dictionary(payload.get("player_run", {})))
	var enemy_run: RunState = RunState.from_dict(Dictionary(payload.get("enemy_run", {})))
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.setup_pvp(player_run, enemy_run, "Host", "Guest")
	if engine.battle_state == null or not engine.is_pvp_mode():
		_fail("LAN smoke failed: PvP engine did not initialize")
		return
	if engine.battle_state.player.display_name != "Host" or engine.battle_state.enemy.display_name != "Guest":
		_fail("LAN smoke failed: PvP player names were not retained")
		return
	engine.update(1.0)
	if not is_zero_approx(engine.battle_state.battle_time):
		_fail("LAN smoke failed: PvP battle advanced before either player started it")
		return
	if engine.request_use_card("player", "player_0"):
		_fail("LAN smoke failed: PvP card started before synchronized start")
		return
	if not engine.start_battle():
		_fail("LAN smoke failed: explicit PvP start was rejected")
		return
	if not engine.request_use_card("player", "player_0"):
		_fail("LAN smoke failed: host card command was rejected after start")
		return
	if not engine.request_use_card("enemy", "enemy_0"):
		_fail("LAN smoke failed: guest card command was rejected after start")
		return
	for _tick_index in range(120):
		engine.update(0.05)
		if engine.battle_state.battle_events.size() >= 4:
			break
	if not engine.has_battle_started() or engine.battle_state.battle_time <= 0.0:
		_fail("LAN smoke failed: authoritative PvP engine did not advance")
		return
	if engine.battle_state.battle_events.is_empty():
		_fail("LAN smoke failed: PvP engine did not record battle events")
		return

	var snapshot: Dictionary = BattleStateCodec.encode(engine.battle_state, engine.has_battle_started())
	var restored: BattleState = BattleStateCodec.decode(snapshot)
	if restored == null:
		_fail("LAN smoke failed: battle snapshot did not decode")
		return
	if restored.player.hp != engine.battle_state.player.hp or restored.enemy.hp != engine.battle_state.enemy.hp:
		_fail("LAN smoke failed: snapshot changed HP")
		return
	if restored.timeline.size() != engine.battle_state.timeline.size():
		_fail("LAN smoke failed: snapshot changed timeline entries")
		return
	if restored.battle_events.size() != engine.battle_state.battle_events.size():
		_fail("LAN smoke failed: snapshot changed battle event history")
		return
	if not _assert_compact_snapshot_budget(restored):
		return

	if not _assert_arena_coordinator(host_profile):
		return

	await _assert_web_lobby_scene()
	if _failed:
		return

	print("Web multiplayer protocol smoke passed: hash=%s events=%d" % [
		LanProtocol.build_content_hash().left(10),
		engine.battle_state.battle_events.size(),
	])
	get_tree().quit()


func _assert_valid_profile(profile: Dictionary) -> bool:
	var validation: Dictionary = LanProtocol.validate_profile(profile)
	if not bool(validation.get("valid", false)):
		_fail("LAN smoke failed: valid profile rejected (%s)" % String(validation.get("error", "unknown")))
		return false
	return true


func _assert_arena_coordinator(profile: Dictionary) -> bool:
	var coordinator: LanArenaCoordinator = LanArenaCoordinator.new()
	var run_state: RunState = coordinator.create_run(profile, 97531)
	if run_state == null or not run_state.arena_mode or run_state.gold <= 0:
		_fail("LAN smoke failed: arena preparation run was not configured")
		return false
	var status: Dictionary = coordinator.build_status(run_state, "Guest", "tempo", false, true)
	if int(status.get("target_wins", 0)) != LanArenaCoordinator.TARGET_WINS:
		_fail("LAN smoke failed: arena target wins were not configured")
		return false
	var entries: Array[Dictionary] = coordinator.get_loadout_entries(run_state)
	if entries.is_empty() or not coordinator.has_valid_loadout(run_state):
		_fail("LAN smoke failed: arena loadout was not available")
		return false
	var offers: Array[Dictionary] = []
	for raw_offer in Array(run_state.arena_shop.get("cards", [])):
		offers.append(Dictionary(raw_offer))
	if offers.is_empty():
		_fail("LAN smoke failed: arena card offers were not generated")
		return false
	var hold_result: Dictionary = coordinator.apply_action(run_state, "toggle_card_hold", {"index": 0})
	if not bool(hold_result.get("accepted", false)):
		_fail("LAN smoke failed: arena hold action was rejected")
		return false
	var progress: Dictionary = coordinator.apply_battle_result(run_state, true, run_state.player_hp)
	if bool(progress.get("finished", true)) or run_state.arena_wins != 1 or run_state.arena_pending_rewards.is_empty():
		_fail("LAN smoke failed: arena round progression was invalid")
		return false
	return true


func _assert_compact_snapshot_budget(state: BattleState) -> bool:
	var heavy_unit: Dictionary = _build_heavy_unit_snapshot()
	var heavy_timeline: Array[Dictionary] = []
	for timeline_index in range(12):
		heavy_timeline.append({
			"instance_id": timeline_index,
			"owner_side": "player" if timeline_index % 2 == 0 else "enemy",
			"runtime_id": "runtime_%d" % timeline_index,
			"card_id": "quick_slash",
			"scheduled_time": float(timeline_index) * 0.75,
		})
	_append_heavy_events(state, 40, heavy_unit, heavy_timeline)
	var first_snapshot: Dictionary = BattleStateCodec.encode(state, true, true)
	var first_size: int = var_to_bytes(first_snapshot).size()
	_append_heavy_events(state, 400, heavy_unit, heavy_timeline)
	var final_snapshot: Dictionary = BattleStateCodec.encode(state, true, true)
	var final_size: int = var_to_bytes(final_snapshot).size()
	var compact_events: Array = Array(final_snapshot.get("battle_events", []))
	if compact_events.size() != BattleStateCodec.NETWORK_EVENT_WINDOW:
		_fail("LAN smoke failed: compact snapshot did not cap event history")
		return false
	if int(final_snapshot.get("battle_event_total", 0)) != state.battle_events.size():
		_fail("LAN smoke failed: compact snapshot lost the event stream total")
		return false
	if final_size > 32768 or final_size > first_size + 1024:
		_fail("LAN smoke failed: compact snapshot grew with history (%d -> %d bytes)" % [first_size, final_size])
		return false
	var newest_event: Dictionary = Dictionary(compact_events.back())
	if int(newest_event.get("_event_index", -1)) != state.battle_events.size() - 1:
		_fail("LAN smoke failed: compact snapshot event sequence was invalid")
		return false
	var newest_result: Dictionary = Dictionary(newest_event.get("result", {}))
	var player_before: Dictionary = Dictionary(newest_result.get("player_before", {}))
	if player_before.keys().size() != 2 or not player_before.has("hp") or not player_before.has("shield"):
		_fail("LAN smoke failed: compact snapshot retained oversized unit event data")
		return false
	print("LAN compact snapshot budget passed: %d -> %d bytes across %d events" % [
		first_size,
		final_size,
		state.battle_events.size(),
	])
	return true


func _append_heavy_events(
	state: BattleState,
	count: int,
	heavy_unit: Dictionary,
	heavy_timeline: Array[Dictionary]
) -> void:
	for _event_offset in range(count):
		var event_index: int = state.battle_events.size()
		state.record_event({
			"time": float(event_index) * 0.1,
			"event_type": "resolve_card",
			"actor_id": "player",
			"card_id": "quick_slash",
			"target_id": "enemy",
			"result": {
				"player_before": heavy_unit,
				"player_after": heavy_unit,
				"enemy_before": heavy_unit,
				"enemy_after": heavy_unit,
			},
			"hp_delta": -4,
			"shield_delta": 0,
			"timeline_before": heavy_timeline,
			"timeline_after": heavy_timeline,
		})


func _build_heavy_unit_snapshot() -> Dictionary:
	var runtime_states: Array[Dictionary] = []
	for runtime_index in range(16):
		runtime_states.append({
			"runtime_id": "player_%d" % runtime_index,
			"card_id": "quick_slash",
			"loadout_index": runtime_index,
			"state": CardRuntimeState.CardState.READY,
			"cooldown_remaining": float(runtime_index) * 0.1,
		})
	return {
		"hp": 50,
		"max_hp": 60,
		"shield": 12,
		"attack": 4,
		"speed": 7,
		"statuses": {"bleed": {"remaining": 8.0, "stacks": 3}},
		"runtime_states": runtime_states,
		"temporary_card_modifiers": {
			"quick_slash": {"damage": 12.0, "cast_time": -0.6, "recast_time": -1.2},
		},
	}


func _assert_web_lobby_scene() -> void:
	var packed_scene: PackedScene = load("res://scenes/online/OnlineLobby.tscn") as PackedScene
	if packed_scene == null:
		_fail("Web multiplayer smoke failed: lobby scene could not be loaded")
		return
	var lobby: Control = packed_scene.instantiate() as Control
	add_child(lobby)
	await get_tree().process_frame
	var host_button: Button = lobby.find_child("LanHostButton", true, false) as Button
	var join_button: Button = lobby.find_child("LanJoinButton", true, false) as Button
	var discovered_list: ItemList = lobby.find_child("LanDiscoveredList", true, false) as ItemList
	var room_code_edit: LineEdit = lobby.find_child("OnlineRoomCodeEdit", true, false) as LineEdit
	var starter_option: OptionButton = lobby.find_child("LanStarterOption", true, false) as OptionButton
	var ready_button: Button = lobby.find_child("LanReadyButton", true, false) as Button
	var start_button: Button = lobby.find_child("LanStartMatchButton", true, false) as Button
	if host_button == null or join_button == null or room_code_edit == null:
		_fail("Web multiplayer smoke failed: room controls were missing")
	elif discovered_list == null or discovered_list.visible:
		_fail("Web multiplayer smoke failed: LAN discovery is still visible")
	elif starter_option == null or starter_option.item_count != Database.starters.size():
		_fail("LAN smoke failed: lobby did not expose every starter")
	elif ready_button == null or start_button == null:
		_fail("LAN smoke failed: lobby ready/start controls were missing")
	lobby.queue_free()
	await get_tree().process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
