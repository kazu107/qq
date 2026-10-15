extends Control


func _ready() -> void:
	Database.load_all()
	size = Vector2(1600, 1000)
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		push_error("Timeline overflow: " + message)
		get_tree().quit(1)
		assert(value, message)


func _entry(card_id: String, remaining: float, id: int = 1, side: String = "enemy") -> TimelineEntry:
	var entry: TimelineEntry = TimelineEntry.new()
	entry.card_id = card_id
	entry.card_name = Database.get_card(card_id).name if card_id != FatigueRules.CARD_ID else "Fatigue"
	entry.runtime_id = "overflow_%d" % id
	entry.instance_id = id
	entry.owner_side = side
	entry.scheduled_time = remaining
	entry.fatigue_damage = 10 if card_id == FatigueRules.CARD_ID else 0
	return entry


func _visible_rect(card: CardButton) -> Rect2:
	return card.get_global_transform() * Rect2(Vector2.ZERO, card.size)


func _run() -> void:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
	engine.set_audio_enabled(false)
	engine.setup(run, "boss_timekeeper")
	var state: BattleState = engine.battle_state
	var horizon: float = TimelinePanel.compute_loadout_horizon(state.player, state.enemy, run)
	_check(horizon < 10.0, "40-second strike expanded the loadout horizon")
	for tier: int in range(CardUpgradeResolver.MAX_TIER + 1):
		_check(CardUpgradeResolver.build_card_at_tier("timekeeper_final_strike", tier).timeline_scale_excluded, "Grade clone lost the exclusion flag")
	_check(not Database.get_card("fortify").timeline_scale_excluded, "Ordinary long-cast cards were excluded")
	var long_runtime: CardRuntimeState = CardRuntimeState.new()
	long_runtime.card_id = "fortify"
	state.player.card_runtime_states.append(long_runtime)
	_check(is_equal_approx(TimelinePanel.compute_loadout_horizon(state.player, state.enemy, run), Database.get_card("fortify").cast_time), "Ordinary long cast stopped contributing to the fixed scale")
	state.player.card_runtime_states.erase(long_runtime)
	var panel: TimelinePanel = TimelinePanel.new()
	panel.size = Vector2(1000, 340)
	panel.set_fixed_horizon(horizon)
	add_child(panel)
	await get_tree().process_frame
	var fixed_size: Vector2 = panel.size
	var fixed_ticks: Array = panel._scale_row.get_children().map(func(label: Label) -> String: return label.text)
	_check(fixed_ticks == ["0s", "2s", "4s", "6s", "8s"], "Timekeeper scale was not 0..8 seconds")
	var strike: TimelineEntry = _entry("timekeeper_final_strike", 40)
	var previous_scale: float = 0.0
	var boundary_rect: Rect2
	for remaining: float in [40.0, 24.0, 16.0, 8.001, 8.0, 7.999, 4.0, 0.0]:
		panel.refresh_timeline([strike], 40.0 - remaining)
		var card: CardButton = panel._cards[0]
		var rect: Rect2 = _visible_rect(card)
		_check(card.scale.x >= previous_scale and card.scale.x <= 1.0, "Card did not grow monotonically")
		_check(panel._cards_scroll.get_global_rect().grow(1.0).encloses(rect), "Scaled card escaped its track")
		_check(panel.size.is_equal_approx(fixed_size), "Card growth resized the timeline")
		_check(card.size.is_equal_approx(CardButton.get_tile_extent(TimelinePanel.TIMELINE_TILE_SIZE)), "Scaling changed the logical card layout")
		if remaining > 8.0:
			_check(card.scale.x < 1.0, "Overflow card was full size too early")
		else:
			_check(is_equal_approx(card.scale.x, 1.0), "In-range card did not restore normal scale")
		if remaining == 8.001:
			boundary_rect = rect
		elif remaining == 8.0:
			_check(rect.position.distance_to(boundary_rect.position) < 0.1 and rect.size.distance_to(boundary_rect.size) < 0.1, "Card jumped at the maximum tick")
		previous_scale = card.scale.x
	var delayed: TimelineEntry = _entry("guard", 6.0, 2, "player")
	panel.clear_display_history()
	panel.refresh_timeline([delayed], 0)
	var before: Rect2 = _visible_rect(panel._cards[0])
	delayed.scheduled_time = 22.0
	panel.refresh_timeline([delayed], 0)
	_check(_visible_rect(panel._cards[0]).is_equal_approx(before), "Delay snapped immediately to its target")
	panel.refresh_timeline([delayed], 0.25)
	_check(is_equal_approx(panel._cards[0].scale.x, TimelinePanel.get_overflow_scale(13.75, 8)), "Delay midpoint did not account for elapsed time")
	panel.refresh_timeline([delayed], 0.5)
	_check(is_equal_approx(panel._cards[0].scale.x, TimelinePanel.get_overflow_scale(21.5, 8)), "Delayed ordinary card did not use overflow scaling")
	_check(not panel.has_pending_delay_animation(), "Delay animation never completed")
	var reversed: TimelineEntry = _entry("guard", 8.0, 3)
	panel.clear_display_history()
	panel.refresh_timeline([reversed], 0)
	reversed.scheduled_time = 8.4
	reversed.continuous_shift_battle_time = 0.2
	reversed.continuous_shift_amount = 0.4
	panel.refresh_timeline([reversed], 0.2)
	_check(not panel.has_pending_delay_animation() and is_equal_approx(panel._cards[0].scale.x, TimelinePanel.get_overflow_scale(8.2, 8)), "Reverse flow used lagging delay interpolation")
	var reverse_scale: float = panel._cards[0].scale.x
	reversed.scheduled_time = 8.6
	reversed.continuous_shift_battle_time = 0.4
	reversed.continuous_shift_amount = 0.2
	panel.refresh_timeline([reversed], 0.4)
	_check(is_equal_approx(panel._cards[0].scale.x, reverse_scale), "Stopped out-of-range card changed size")
	var preview: TimelineEntry = _entry("quick_slash", 16, 900, "player")
	panel.clear_display_history()
	panel.refresh_timeline([_entry(FatigueRules.CARD_ID, 20, 5, FatigueRules.SIDE)], 0, null, preview, Database.get_card("quick_slash"))
	_check(panel._cards[0].scale.x < 1.0, "Fatigue did not use generic overflow scaling")
	_check(is_equal_approx(panel._preview_button.scale.x, TimelinePanel.get_overflow_scale(16, 8)), "Preview did not use overflow scaling")
	panel._process(0.5)
	_check(absf(panel._preview_button.modulate.a - 0.32) < 0.02, "Overflow scaling broke preview alpha animation")
	_check(panel._scale_row.get_children().map(func(label: Label) -> String: return label.text) == fixed_ticks, "Delay/preview changed fixed ticks")
	panel.refresh_timeline([_entry("guard", 4, 6)], 0)
	_check(panel._cards[0].scale == Vector2.ONE, "Reused card retained overflow scale")
	engine.start_battle()
	engine.update(1.0)
	var replay: ReplayVisualPlayer = ReplayVisualPlayer.new()
	add_child(replay)
	replay.load_replay(ReplayData.from_summary(engine.build_summary()).to_dict())
	_check(is_equal_approx(replay._timeline._rendered_scale_horizon, 8), "Replay restored the excluded 40-second scale")
	_check(replay._timeline._cards[0].scale.x < 1.0, "Replay did not scale its opening strike")
	replay.queue_free()
	panel.queue_free()
	engine.dispose()
	await get_tree().process_frame
	print("TIMELINE_OVERFLOW_SMOKE_OK excluded scale, grades, gradual growth, boundary continuity, delay/reverse/stop, preview/fatigue, reuse, stable frame and replay")
	get_tree().quit()
