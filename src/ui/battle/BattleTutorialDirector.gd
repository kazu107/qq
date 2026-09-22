extends Node
class_name BattleTutorialDirector

signal exit_requested
signal restart_requested
signal presentation_changed

var _tutorial_id: String = ""
var _engine: RealtimeBattleEngine
var _overlay: BattleTutorialOverlay
var _steps: Array[Dictionary] = []
var _step_index: int = 0
var _event_cursor: int = 0
var _step_elapsed: float = 0.0
var _time_paused: bool = true
var _failed: bool = false


func configure(tutorial_id: String, engine: RealtimeBattleEngine, overlay: BattleTutorialOverlay) -> bool:
	_tutorial_id = tutorial_id
	_engine = engine
	_overlay = overlay
	_steps = _build_steps(tutorial_id)
	if _engine == null or _overlay == null or _steps.is_empty():
		return false
	_overlay.continued.connect(_on_continued)
	_overlay.exit_requested.connect(func() -> void: exit_requested.emit())
	_event_cursor = _engine.battle_state.battle_events.size() if _engine.battle_state != null else 0
	_enter_step(0)
	return true


func process(delta: float) -> void:
	if _engine == null or _engine.battle_state == null or _failed:
		return
	_step_elapsed += maxf(0.0, delta)
	_scan_events()
	_check_condition()


func is_time_paused() -> bool:
	return _time_paused


func get_target_kind() -> String:
	if _failed:
		return "battle_sign"
	if _steps.is_empty():
		return ""
	return String(_steps[_step_index].get("target", ""))


func get_step_index() -> int:
	return _step_index


func get_step_count() -> int:
	return _steps.size()


func get_current_step_data() -> Dictionary:
	if _steps.is_empty():
		return {}
	return _steps[_step_index].duplicate(true)


func allows_card(card_id: String) -> bool:
	if _failed or _steps.is_empty():
		return false
	var step: Dictionary = _steps[_step_index]
	var mode: String = String(step.get("mode", ""))
	if mode == "free_battle":
		return true
	return mode == "queue_card" and card_id == String(step.get("card_id", ""))


func on_card_committed(card_id: String) -> void:
	if not allows_card(card_id):
		return
	if String(_steps[_step_index].get("mode", "")) == "queue_card":
		_advance()


func debug_continue() -> void:
	_on_continued()


func _on_continued() -> void:
	if _failed:
		restart_requested.emit()
		return
	if _steps.is_empty():
		return
	var mode: String = String(_steps[_step_index].get("mode", ""))
	if mode == "complete":
		exit_requested.emit()
	elif mode == "continue":
		_advance()


func _enter_step(index: int) -> void:
	if index < 0 or index >= _steps.size():
		return
	_step_index = index
	_step_elapsed = 0.0
	var step: Dictionary = _steps[_step_index]
	var mode: String = String(step.get("mode", "continue"))
	_time_paused = mode in ["continue", "queue_card", "complete"]
	_run_action(String(step.get("action", "")))
	_show_step(step)
	presentation_changed.emit()


func _advance() -> void:
	_enter_step(mini(_step_index + 1, _steps.size() - 1))


func _show_step(step: Dictionary) -> void:
	var key: String = String(step.get("key", ""))
	var title: String = Localization.get_text("tutorial.flow.%s.title" % key, String(step.get("title", "")))
	var body: String = Localization.get_text("tutorial.flow.%s.body" % key, String(step.get("body", "")))
	var progress: String = Localization.get_textf("tutorial.guide.progress", "LESSON {current}/{total}", {
		"current": int(step.get("progress", 1)),
		"total": int(step.get("total", 1)),
	})
	var mode: String = String(step.get("mode", "continue"))
	var button: String = ""
	var waiting: String = ""
	if mode == "continue":
		button = Localization.get_text(String(step.get("button_key", "tutorial.guide.next")), String(step.get("button", "Next")))
	elif mode == "complete":
		button = Localization.get_text("tutorial.guide.return_list", "Return to tutorials")
	elif mode == "queue_card":
		waiting = Localization.get_text("tutorial.guide.wait_card", "Waiting for the highlighted card...")
	else:
		waiting = Localization.get_text(String(step.get("waiting_key", "tutorial.guide.wait_resolution")), String(step.get("waiting", "Waiting...")))
	_overlay.show_step(progress, title, body, Rect2(), button, waiting)


func _scan_events() -> void:
	var events: Array[Dictionary] = _engine.battle_state.battle_events
	for event_index: int in range(_event_cursor, events.size()):
		var event_data: Dictionary = events[event_index]
		if _matches_event(event_data):
			_event_cursor = events.size()
			_advance()
			return
	_event_cursor = events.size()


func _matches_event(event_data: Dictionary) -> bool:
	if _steps.is_empty():
		return false
	var step: Dictionary = _steps[_step_index]
	if String(step.get("mode", "")) != "wait_event":
		return false
	if String(event_data.get("event_type", "")) != String(step.get("event_type", "")):
		return false
	var expected_card: String = String(step.get("event_card_id", ""))
	return expected_card == "" or String(event_data.get("card_id", "")) == expected_card


func _check_condition() -> void:
	if _steps.is_empty():
		return
	var step: Dictionary = _steps[_step_index]
	var mode: String = String(step.get("mode", ""))
	if mode == "wait_condition":
		var condition: String = String(step.get("condition", ""))
		if _condition_met(condition, step):
			_advance()
	elif mode == "free_battle" and _engine.battle_state.winner != "":
		if _engine.battle_state.winner == "player":
			_advance()
		else:
			_show_failure()


func _condition_met(condition: String, step: Dictionary) -> bool:
	var state: BattleState = _engine.battle_state
	match condition:
		"fatigue_queued":
			for entry: TimelineEntry in state.timeline:
				if entry.owner_side == FatigueRules.SIDE:
					return true
		"card_ready":
			for runtime_state: CardRuntimeState in state.player.card_runtime_states:
				if runtime_state.card_id == String(step.get("card_id", "")) and runtime_state.can_use():
					return true
		"auto_queued":
			for instance: ActiveCardInstance in state.active_instances:
				if not instance.is_auto_queued:
					continue
				var card_id: String = String(step.get("card_id", ""))
				if card_id == "" or instance.card_id == card_id:
					return true
		"wait_seconds":
			return _step_elapsed >= float(step.get("seconds", 1.0))
	return false


func _run_action(action: String) -> void:
	if action == "" or _engine == null or _engine.battle_state == null:
		return
	if action == "debug_fatigue":
		_engine.debug_schedule_fatigue()
		return
	if action == "apply_statuses":
		_engine.start_battle()
		var player: UnitState = _engine.battle_state.player
		player.hp = maxi(1, player.max_hp - 10)
		_engine.apply_status_from_card("enemy", "player", "bleed", 30.0)
		_engine.apply_status_from_card("enemy", "player", "weak", 30.0)
		return
	if action == "start_battle" or action == "start_exam":
		_engine.start_battle()
		return
	if action.begins_with("queue_enemy:"):
		_queue_card_for_side("enemy", action.trim_prefix("queue_enemy:"))


func _queue_card_for_side(side: String, card_id: String) -> bool:
	var unit: UnitState = _engine.battle_state.get_unit(side)
	for runtime_state: CardRuntimeState in unit.card_runtime_states:
		if runtime_state.card_id == card_id and runtime_state.can_use():
			return _engine.request_use_card(side, runtime_state.runtime_id)
	return false


func _show_failure() -> void:
	_failed = true
	_time_paused = true
	_overlay.show_step(
		Localization.get_text("tutorial.exam.failed_progress", "PRACTICE"),
		Localization.get_text("tutorial.exam.failed_title", "Exercise failed"),
		Localization.get_text("tutorial.exam.failed_body", "Review the timeline and try the exercise again. Your normal run is not affected."),
		Rect2(),
		Localization.get_text("tutorial.exam.retry", "Retry"),
		""
	)
	presentation_changed.emit()


func _s(
	key: String,
	mode: String,
	progress: int,
	total: int,
	title: String,
	body: String,
	target: String,
	extra: Dictionary = {}
) -> Dictionary:
	var step: Dictionary = {
		"key": key,
		"mode": mode,
		"progress": progress,
		"total": total,
		"title": title,
		"body": body,
		"target": target,
	}
	step.merge(extra, true)
	return step


func _build_steps(tutorial_id: String) -> Array[Dictionary]:
	match tutorial_id:
		"battle_basics":
			return _basic_steps()
		"slots_recast":
			return _slot_steps()
		"interrupts":
			return _interrupt_steps()
		"statuses":
			return _status_steps()
		"shield_resource":
			return _shield_steps()
		"timeline_control":
			return _timeline_steps()
		"recast_combo":
			return _recast_steps()
		"battle_growth":
			return _growth_steps()
		"auto_queue":
			return _auto_queue_steps()
		"combat_exam":
			return _exam_steps()
	return []


func _basic_steps() -> Array[Dictionary]:
	return [
		_s("basic_intro", "continue", 1, 8, "The real battle screen", "This lesson uses the normal battle screen. Time pauses while a control is explained.", "start"),
		_s("basic_queue_attack", "queue_card", 2, 8, "Queue an attack", "Select Quick Slash. Time stays paused until it enters the timeline.", "card:quick_slash", {"card_id": "quick_slash"}),
		_s("basic_timeline", "continue", 2, 8, "Read the timeline", "Cards move right to left and activate at 0 seconds.", "timeline", {"button_key": "tutorial.guide.resume", "button": "Resume time"}),
		_s("basic_wait_attack", "wait_event", 2, 8, "Watch it resolve", "Watch Quick Slash reach 0 seconds.", "timeline", {"event_type": "resolve_card", "event_card_id": "quick_slash"}),
		_s("basic_damage", "continue", 3, 8, "Damage and recast", "Damage updates the enemy plate. The used card now enters recast.", "enemy_status"),
		_s("basic_queue_guard", "queue_card", 4, 8, "Prepare shield", "Select Guard to protect HP.", "card:guard", {"card_id": "guard"}),
		_s("basic_guard_timeline", "continue", 4, 8, "Defense also casts", "Guard uses the same timeline as attacks.", "timeline", {"button_key": "tutorial.guide.resume", "button": "Resume time"}),
		_s("basic_wait_guard", "wait_event", 4, 8, "Watch Guard resolve", "The guide pauses when Guard activates.", "timeline", {"event_type": "resolve_card", "event_card_id": "guard"}),
		_s("basic_shield", "continue", 5, 8, "Check shield", "Shield appears on your 3D status plate and slowly decays.", "player_status"),
		_s("basic_queue_delay", "queue_card", 6, 8, "Delay an enemy card", "Select Delay Step to push enemy timing back.", "card:delay_step", {"card_id": "delay_step", "action": "queue_enemy:quick_slash"}),
		_s("basic_delay_timeline", "continue", 6, 8, "Watch the target move", "The enemy card slides right when Delay Step resolves.", "timeline", {"button_key": "tutorial.guide.resume", "button": "Resume time"}),
		_s("basic_wait_delay", "wait_event", 6, 8, "Resolve Delay Step", "Watch Delay Step approach 0 seconds.", "timeline", {"event_type": "resolve_card", "event_card_id": "delay_step"}),
		_s("basic_delay_result", "continue", 7, 8, "Timeline changed", "Delay creates time for another action. Next, observe the neutral fatigue card.", "timeline", {"button": "Show fatigue"}),
		_s("basic_wait_fatigue", "wait_condition", 8, 8, "Fatigue is approaching", "Fatigue belongs to the battlefield and prevents endless battles.", "timeline", {"condition": "fatigue_queued", "action": "debug_fatigue", "waiting_key": "tutorial.guide.wait_fatigue"}),
		_complete("basic_complete", 8, "Battle basics complete", "You used attack, shield and delay, then found fatigue on the real timeline."),
	]


func _slot_steps() -> Array[Dictionary]:
	return [
		_s("slots_intro", "continue", 1, 6, "Three active slots", "The battery cells show how many active slots are occupied. Card cost is shown at the upper-left.", "player_status"),
		_s("slots_heavy", "queue_card", 2, 6, "Spend two slots", "Queue Heavy Swing. Its cost of 2 fills two battery cells.", "card:heavy_swing", {"card_id": "heavy_swing"}),
		_s("slots_guard", "queue_card", 3, 6, "Fill the last slot", "Queue Guard to use the third slot.", "card:guard", {"card_id": "guard"}),
		_s("slots_full", "continue", 4, 6, "No slots remain", "All three cells are occupied. Cards that would overflow the limit cannot be committed.", "player_status", {"button_key": "tutorial.guide.resume", "button": "Wait for Guard"}),
		_s("slots_wait_open", "wait_event", 4, 6, "A slot opens on resolution", "Guard releases its slot when it resolves.", "timeline", {"event_type": "resolve_card", "event_card_id": "guard"}),
		_s("slots_quick", "queue_card", 5, 6, "Use the open slot", "Queue Quick Slash in the newly opened slot.", "card:quick_slash", {"card_id": "quick_slash"}),
		_s("slots_wait_quick", "wait_event", 5, 6, "Resolve Quick Slash", "After activation the card changes from casting to a recast countdown.", "timeline", {"event_type": "resolve_card", "event_card_id": "quick_slash"}),
		_s("slots_recast", "continue", 6, 6, "Wait until Ready", "The card becomes Ready when its recast reaches 0 seconds.", "card:quick_slash", {"button_key": "tutorial.guide.resume", "button": "Run recast"}),
		_s("slots_wait_ready", "wait_condition", 6, 6, "Recast is running", "Watch the number reach Ready.", "card:quick_slash", {"condition": "card_ready", "card_id": "quick_slash"}),
		_complete("slots_complete", 6, "Slots and recast complete", "You filled the slot limit, released a slot and waited for a card to become Ready."),
	]


func _interrupt_steps() -> Array[Dictionary]:
	return [
		_s("interrupt_intro", "continue", 1, 4, "Interruptible casts", "Some long casts can be cancelled. Their tooltip marks them as interruptible.", "timeline"),
		_s("interrupt_enemy", "continue", 2, 4, "Enemy Heavy Swing", "Heavy Swing is now on the enemy timeline. Cancel it before it reaches 0 seconds.", "timeline", {"action": "queue_enemy:heavy_swing"}),
		_s("interrupt_queue", "queue_card", 3, 4, "Fire Interrupt Shot", "Queue Interrupt Shot while Heavy Swing is still casting.", "card:interrupt_shot", {"card_id": "interrupt_shot"}),
		_s("interrupt_wait", "wait_event", 3, 4, "Wait for the interrupt", "Interrupt Shot must resolve before Heavy Swing.", "timeline", {"event_type": "interrupt_card", "event_card_id": "heavy_swing"}),
		_complete("interrupt_complete", 4, "Interrupt successful", "The enemy card disappeared, its slot was released, and it entered recast."),
	]


func _status_steps() -> Array[Dictionary]:
	return [
		_s("status_intro", "continue", 1, 5, "Negative statuses", "Bleed and Weak were applied. Hover their icons to inspect the live duration and effect.", "player_status", {"action": "apply_statuses", "button_key": "tutorial.guide.resume", "button": "Observe bleed"}),
		_s("status_tick", "wait_event", 2, 5, "Bleed deals periodic damage", "Time is moving until the next bleed tick.", "player_status", {"event_type": "status_damage"}),
		_s("status_result", "continue", 3, 5, "Read the remaining time", "The seconds beside each icon show how long the status remains.", "player_status"),
		_s("status_cleanse", "queue_card", 4, 5, "Cleanse the statuses", "Use Field Medic to remove Bleed and Weak while healing HP.", "card:field_medic", {"card_id": "field_medic"}),
		_s("status_wait_cleanse", "wait_event", 4, 5, "Wait for the cleanse", "Field Medic removes the negative statuses when it resolves.", "timeline", {"event_type": "resolve_card", "event_card_id": "field_medic"}),
		_complete("status_complete", 5, "Status lesson complete", "You inspected status duration, observed bleed damage and cleansed negative effects."),
	]


func _shield_steps() -> Array[Dictionary]:
	return [
		_s("shield_resource_intro", "continue", 1, 5, "Shield can be spent", "Aegis Ram is unavailable without enough shield. First build the required resource.", "card:aegis_ram"),
		_s("shield_resource_guard", "queue_card", 2, 5, "Build shield", "Queue Guard.", "card:guard", {"card_id": "guard"}),
		_s("shield_resource_wait_guard", "wait_event", 2, 5, "Wait for Guard", "Guard grants shield when it resolves.", "timeline", {"event_type": "resolve_card", "event_card_id": "guard"}),
		_s("shield_resource_value", "continue", 3, 5, "Shield requirement met", "Aegis Ram is now usable. Its shield cost is paid immediately when committed.", "player_status"),
		_s("shield_resource_ram", "queue_card", 4, 5, "Spend shield", "Queue Aegis Ram and watch the shield value decrease.", "card:aegis_ram", {"card_id": "aegis_ram"}),
		_s("shield_resource_wait_ram", "wait_event", 4, 5, "Resolve the attack", "The paid shield powers Aegis Ram's damage.", "timeline", {"event_type": "resolve_card", "event_card_id": "aegis_ram"}),
		_complete("shield_resource_complete", 5, "Shield resource complete", "You built shield, paid a shield cost and converted defense into an attack."),
	]


func _timeline_steps() -> Array[Dictionary]:
	return [
		_s("timeline_control_intro", "continue", 1, 7, "Control the whole timeline", "Stop and reverse affect cards continuously, unlike a one-time delay.", "timeline", {"action": "queue_enemy:heavy_swing"}),
		_s("timeline_control_stop", "queue_card", 2, 7, "Stop enemy time", "Queue Chronostasis while Heavy Swing is active.", "card:chronostasis", {"card_id": "chronostasis"}),
		_s("timeline_control_wait_stop", "wait_event", 2, 7, "Activate Chronostasis", "When it resolves, enemy cards stop moving left.", "timeline", {"event_type": "resolve_card", "event_card_id": "chronostasis"}),
		_s("timeline_control_observe_stop", "continue", 3, 7, "Enemy timeline stopped", "Resume briefly and watch the enemy card hold its position.", "timeline", {"button_key": "tutorial.guide.resume", "button": "Observe stop"}),
		_s("timeline_control_stop_time", "wait_condition", 3, 7, "Stop is active", "The enemy card remains in place while your timeline advances.", "timeline", {"condition": "wait_seconds", "seconds": 1.2}),
		_s("timeline_control_reverse", "queue_card", 4, 7, "Reverse enemy time", "Queue Entropy Reversal.", "card:entropy_reversal", {"card_id": "entropy_reversal"}),
		_s("timeline_control_wait_reverse", "wait_event", 4, 7, "Activate reversal", "The enemy card begins moving right when this resolves.", "timeline", {"event_type": "resolve_card", "event_card_id": "entropy_reversal"}),
		_s("timeline_control_observe_reverse", "continue", 5, 7, "Enemy card moves backward", "Resume briefly to observe equal-speed movement to the right.", "timeline", {"button_key": "tutorial.guide.resume", "button": "Observe reverse"}),
		_s("timeline_control_reverse_time", "wait_condition", 5, 7, "Reversal is active", "The cast time grows while the flow is reversed.", "timeline", {"condition": "wait_seconds", "seconds": 1.2}),
		_s("timeline_control_heavy", "queue_card", 6, 7, "Prepare your long cast", "Queue Heavy Swing.", "card:heavy_swing", {"card_id": "heavy_swing"}),
		_s("timeline_control_haste", "queue_card", 6, 7, "Accelerate your card", "Queue Haste Focus to pull Heavy Swing toward 0 seconds.", "card:haste_focus", {"card_id": "haste_focus"}),
		_s("timeline_control_wait_haste", "wait_event", 6, 7, "Resolve Haste Focus", "Watch your Heavy Swing slide left when haste resolves.", "timeline", {"event_type": "resolve_card", "event_card_id": "haste_focus"}),
		_complete("timeline_control_complete", 7, "Timeline control complete", "You stopped, reversed and accelerated cards on the same timeline."),
	]


func _recast_steps() -> Array[Dictionary]:
	return [
		_s("recast_combo_intro", "continue", 1, 5, "Build a recast combo", "Use an attack, then shorten its cooldown with Reload.", "card:quick_slash"),
		_s("recast_combo_attack", "queue_card", 2, 5, "Use Quick Slash", "Queue Quick Slash.", "card:quick_slash", {"card_id": "quick_slash"}),
		_s("recast_combo_wait_attack", "wait_event", 2, 5, "Put it on cooldown", "Quick Slash enters recast after activation.", "timeline", {"event_type": "resolve_card", "event_card_id": "quick_slash"}),
		_s("recast_combo_reload", "queue_card", 3, 5, "Use Reload", "Reload reduces the card with the highest remaining cooldown.", "card:reload", {"card_id": "reload"}),
		_s("recast_combo_wait_reload", "wait_event", 3, 5, "Resolve Reload", "Watch Quick Slash's remaining seconds drop.", "timeline", {"event_type": "resolve_card", "event_card_id": "reload"}),
		_s("recast_combo_ready", "wait_condition", 4, 5, "Wait for Ready", "The shortened cooldown reaches Ready sooner.", "card:quick_slash", {"condition": "card_ready", "card_id": "quick_slash"}),
		_s("recast_combo_reuse", "queue_card", 5, 5, "Use it again", "Queue Quick Slash a second time to finish the combo.", "card:quick_slash", {"card_id": "quick_slash"}),
		_complete("recast_combo_complete", 5, "Recast combo complete", "You shortened a spent card's recast and committed it again."),
	]


func _growth_steps() -> Array[Dictionary]:
	return [
		_s("growth_intro", "continue", 1, 4, "Cards can grow during battle", "Self Tuning Edge permanently increases its own damage for the rest of this battle.", "card:self_tuning_edge"),
		_s("growth_first", "queue_card", 2, 4, "Trigger the first upgrade", "Queue the first Self Tuning Edge.", "card:self_tuning_edge", {"card_id": "self_tuning_edge"}),
		_s("growth_wait_first", "wait_event", 2, 4, "Resolve the first copy", "Its damage modifier is applied after resolution.", "timeline", {"event_type": "resolve_card", "event_card_id": "self_tuning_edge"}),
		_s("growth_compare", "continue", 3, 4, "Read the green value", "Hover the ready copy. The current value is green and shows the increase in parentheses.", "card:self_tuning_edge"),
		_s("growth_second", "queue_card", 4, 4, "Use the stronger copy", "Queue the second Self Tuning Edge and compare its damage.", "card:self_tuning_edge", {"card_id": "self_tuning_edge"}),
		_s("growth_wait_second", "wait_event", 4, 4, "Resolve the stronger card", "The increased value is used by the actual battle calculation.", "timeline", {"event_type": "resolve_card", "event_card_id": "self_tuning_edge"}),
		_complete("growth_complete", 4, "Card growth complete", "You triggered an in-battle modifier and used the updated live value."),
	]


func _auto_queue_steps() -> Array[Dictionary]:
	return [
		_s("auto_queue_intro", "continue", 1, 5, "Cards can create timeline entries", "Generated cards are inserted automatically and use no normal active slot.", "timeline"),
		_s("auto_queue_sequence", "queue_card", 2, 5, "Use Sequence Loader", "Queue Sequence Loader. It creates a Quick Slash after resolving.", "card:sequence_loader", {"card_id": "sequence_loader"}),
		_s("auto_queue_wait_sequence", "wait_event", 2, 5, "Resolve Sequence Loader", "Its generated card will appear immediately afterward.", "timeline", {"event_type": "resolve_card", "event_card_id": "sequence_loader"}),
		_s("auto_queue_find_slash", "wait_condition", 3, 5, "Generated Quick Slash", "The new timeline entry was created automatically.", "timeline", {"condition": "auto_queued", "card_id": "quick_slash"}),
		_s("auto_queue_explain", "continue", 3, 5, "Automatic entries", "They still obey cast time and timeline-wide stop or reverse effects.", "timeline"),
		_s("auto_queue_turret", "queue_card", 4, 5, "Start Auto Turret", "Queue Auto Turret. It can create another copy of itself without a chain limit.", "card:auto_turret", {"card_id": "auto_turret"}),
		_s("auto_queue_wait_turret", "wait_event", 4, 5, "Resolve Auto Turret", "The first turret creates the next one.", "timeline", {"event_type": "resolve_card", "event_card_id": "auto_turret"}),
		_s("auto_queue_find_turret", "wait_condition", 5, 5, "Recursive copy found", "The highlighted timeline now contains an automatically queued Auto Turret.", "timeline", {"condition": "auto_queued", "card_id": "auto_turret"}),
		_complete("auto_queue_complete", 5, "Automatic queues complete", "You created both a different card and a recursive copy automatically."),
	]


func _exam_steps() -> Array[Dictionary]:
	return [
		_s("exam_intro", "continue", 1, 2, "Final combat exercise", "Defeat the Brute without step-by-step prompts. Use shield, delay, cleanse and interrupts as needed.", "battle_sign", {"button": "Start exercise"}),
		_s("exam_battle", "free_battle", 1, 2, "Win the battle", "All cards are available. Read the enemy timeline and manage your three slots.", "battle_sign", {"action": "start_exam", "waiting": "Battle in progress..."}),
		_complete("exam_complete", 2, "Exercise complete", "You won a normal battle using the systems from the previous lessons."),
	]


func _complete(key: String, progress: int, title: String, body: String) -> Dictionary:
	return _s(key, "complete", progress, progress, title, body, "battle_sign")
