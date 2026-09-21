extends Control

const STEPS: Array[String] = ["quick_slash", "guard", "delay_step"]

var _engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
var _run: RunState
var _instruction: Label
var _step_label: Label
var _player_panel: UnitPanel
var _enemy_panel: UnitPanel
var _hand: CardHandPanel
var _timeline: TimelinePanel
var _step: int = 0
var _observe_elapsed: float = 0.0


func _ready() -> void:
	Database.load_all()
	_build_ui()
	_run = RunState.from_starter(Database.get_starter("balanced"), 4242)
	_run.player_cards = STEPS.duplicate()
	_run.equipped_cards = STEPS.duplicate()
	_engine.setup(_run, "scout")
	_engine.start_battle()
	_refresh_instruction()
	_refresh()


func _exit_tree() -> void:
	_engine.dispose()


func _process(delta: float) -> void:
	if _engine.battle_state == null:
		return
	_engine.update(delta)
	if _step >= STEPS.size():
		_observe_elapsed += delta
		if _observe_elapsed >= 7.0:
			_instruction.text = Localization.get_text("tutorial.complete", "Tutorial complete. You used attack, defense, timing control, and observed fatigue on the real timeline.")
	_refresh()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)
	var title: Label = Label.new()
	title.text = Localization.get_text("tutorial.title", "PRACTICAL BATTLE TUTORIAL")
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back: Button = Button.new()
	back.text = Localization.get_text("common.back_hub", "BACK TO HUB")
	back.pressed.connect(SceneRouter.go_to_hub)
	header.add_child(back)
	var guide: PanelContainer = PanelContainer.new()
	root.add_child(guide)
	var guide_box: VBoxContainer = VBoxContainer.new()
	guide_box.add_theme_constant_override("separation", 6)
	guide.add_child(guide_box)
	_step_label = Label.new()
	_step_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28))
	guide_box.add_child(_step_label)
	_instruction = Label.new()
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instruction.add_theme_font_size_override("font_size", 20)
	guide_box.add_child(_instruction)
	var units: HBoxContainer = HBoxContainer.new()
	units.add_theme_constant_override("separation", 18)
	units.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(units)
	_player_panel = UnitPanel.new()
	_player_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	units.add_child(_player_panel)
	_enemy_panel = UnitPanel.new()
	_enemy_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	units.add_child(_enemy_panel)
	_timeline = TimelinePanel.new()
	_timeline.custom_minimum_size = Vector2(0.0, 255.0)
	_timeline.set_fixed_horizon(16.0)
	root.add_child(_timeline)
	_hand = CardHandPanel.new()
	_hand.set_tile_size(Vector2(116.0, 116.0))
	_hand.card_requested.connect(_on_card_requested)
	root.add_child(_hand)


func _on_card_requested(runtime_id: String) -> void:
	if _step >= STEPS.size() or _engine.battle_state == null:
		return
	var runtime_state: CardRuntimeState = _engine.battle_state.player.get_runtime_state(runtime_id)
	if runtime_state == null:
		return
	if runtime_state.card_id != STEPS[_step]:
		_instruction.text = Localization.get_textf("tutorial.wrong_card", "Use {card} for this step. You can inspect every card by hovering it.", {
			"card": Database.get_card(STEPS[_step]).name,
		})
		AudioManager.play_sfx("ui_error")
		return
	if not _engine.request_use_card("player", runtime_id):
		return
	_step += 1
	if _step == STEPS.size():
		_engine.debug_schedule_fatigue()
	_refresh_instruction()


func _refresh_instruction() -> void:
	if _step < STEPS.size():
		var card: CardDef = Database.get_card(STEPS[_step])
		_step_label.text = Localization.get_textf("tutorial.step", "STEP {current}/{total}", {
			"current": _step + 1,
			"total": STEPS.size() + 1,
		})
		var descriptions: Array[String] = [
			Localization.get_text("tutorial.attack", "Use Quick Slash. The card enters the timeline and resolves after its cast time."),
			Localization.get_text("tutorial.guard", "Use Guard. Shield absorbs incoming damage before HP."),
			Localization.get_text("tutorial.delay", "Use Delay Step. Timing-control cards push an enemy card back on the timeline."),
		]
		_instruction.text = descriptions[_step] + "  [" + (card.name if card != null else STEPS[_step]) + "]"
	else:
		_step_label.text = Localization.get_textf("tutorial.step", "STEP {current}/{total}", {
			"current": STEPS.size() + 1,
			"total": STEPS.size() + 1,
		})
		_instruction.text = Localization.get_text("tutorial.observe", "Observe the neutral Fatigue card. It advances on the same timeline and deals increasing fixed damage to both sides.")


func _refresh() -> void:
	var state: BattleState = _engine.battle_state
	if state == null:
		return
	_player_panel.refresh_unit(state.player)
	_enemy_panel.refresh_unit(state.enemy)
	_hand.refresh_cards(state.player, _run, "player")
	_timeline.refresh_timeline(state.timeline, state.battle_time, _run, null, null, "player", null, state.player, state.enemy)
