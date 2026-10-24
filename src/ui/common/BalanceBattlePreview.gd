extends PanelContainer
class_name BalanceBattlePreview

signal closed

var engine: RealtimeBattleEngine
var _draft: BalanceDraft
var _config: Dictionary
var _stage: BattleStage3D
var _timeline: TimelinePanel
var _hand: HFlowContainer
var _cards: Array[CardButton] = []
var _status: Label
var _step: float = 0.0
var _ui_time: float = 0.0
var _event_cursor: int = 0
var _started: bool = false


func open(config: Dictionary, draft: BalanceDraft) -> void:
	_config = config.duplicate(true)
	_draft = draft.frozen()
	name = "BalanceBattlePreview"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "top", "right", "bottom"]: add_theme_constant_override("margin_" + edge, 20)
	var root: VBoxContainer = VBoxContainer.new()
	add_child(root)
	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_status)
	var start: Button = Button.new()
	start.name = "BalanceManualStart"
	start.text = "戦闘開始" if Localization.get_language() == "ja" else "Start"
	start.pressed.connect(func() -> void: _started = true; engine.start_battle(); start.disabled = true)
	header.add_child(start)
	var close: Button = Button.new()
	close.name = "BalanceManualClose"
	close.text = "閉じる" if Localization.get_language() == "ja" else "Close"
	close.pressed.connect(_close)
	header.add_child(close)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_stage = BattleStage3D.new()
	_stage.custom_minimum_size = Vector2(0, 360)
	body.add_child(_stage)
	_timeline = TimelinePanel.new()
	_timeline.custom_minimum_size = Vector2(0, 220)
	body.add_child(_timeline)
	_hand = HFlowContainer.new()
	body.add_child(_hand)
	engine = RealtimeBattleEngine.new()
	engine.set_audio_enabled(false)
	if not engine.setup_sandbox(BalanceTrialRunner.make_run(_config, _draft), String(_config["enemy"]), _draft): _close(); return
	_timeline.balance_engine = engine
	_stage.configure_combatants(engine.battle_state.player.unit_id, engine.battle_state.enemy.unit_id, "player", String(_config["starter"]), String(_config["enemy"]))
	var horizon: float = 4.0
	for side: String in ["player", "enemy"]:
		for state: CardRuntimeState in engine.battle_state.get_unit(side).card_runtime_states:
			var definition: CardDef = engine._get_card_def(side, state.card_id)
			if not definition.timeline_scale_excluded: horizon = maxf(horizon, definition.cast_time)
	_timeline.set_fixed_horizon(horizon)
	for state: CardRuntimeState in engine.battle_state.player.card_runtime_states:
		var card: CardButton = CardButton.new()
		card.name = "BalanceManualCard_" + state.card_id
		card.set_tile_size(Vector2(76, 76))
		card.card_requested.connect(func(id: String) -> void:
			if not _started: _started = true; engine.start_battle(); start.disabled = true
			engine.request_use_card("player", id)
		)
		_hand.add_child(card)
		_cards.append(card)
	_refresh()


func _process(delta: float) -> void:
	if engine == null: return
	if not Game.is_developer_mode_enabled() or NetworkManager.is_session_connected(): _close(); return
	if _started and engine.battle_state.winner == "":
		_step += minf(delta, 0.15)
		while _step >= BattleSimulation.STEP:
			engine.update(BattleSimulation.STEP)
			_step -= BattleSimulation.STEP
			if engine.balance_limit_reached: _started = false; break
	var events: Array = engine.battle_state.battle_events
	while _event_cursor < events.size():
		_stage.play_battle_event(events[_event_cursor])
		_event_cursor += 1
	_ui_time -= delta
	if _ui_time <= 0.0:
		_refresh()
		_ui_time = 0.1


func _refresh() -> void:
	var state: BattleState = engine.battle_state
	_status.text = "%s | %.1fs | HP %d/%d : %d/%d | %s" % ["模擬戦・保存/報酬なし" if Localization.get_language() == "ja" else "Sandbox / no rewards", state.battle_time, state.player.hp, state.player.max_hp, state.enemy.hp, state.enemy.max_hp, state.winner]
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if engine.balance_limit_reached: _status.text += " / sandbox safety limit (256); stopped"
	_stage.refresh_unit_status(state.player, state.enemy)
	_timeline.refresh_timeline(state.timeline, state.battle_time)
	for index: int in _cards.size():
		var runtime: CardRuntimeState = state.player.card_runtime_states[index]
		var card: CardDef = engine._get_card_def("player", runtime.card_id)
		var tooltip: CardDef = CardDef.from_dict(card.to_dict())
		CardTooltipResolver._apply_attack_to_damage(tooltip, state.player.get_attack_value())
		tooltip.cast_time *= state.player.get_cast_time_multiplier()
		var usable: bool = runtime.can_use() and state.player.active_slots_used + card.active_slot_cost <= state.player.active_slot_max and CardEffectResolver.can_pay_shield_cost(state.player, card)
		_cards[index].bind(tooltip, runtime, usable, true, "", card)


func _close() -> void:
	if engine != null: engine.dispose(); engine = null
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	if engine != null: engine.dispose()
