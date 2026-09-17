extends VBoxContainer
class_name ReplayVisualPlayer

var _stage: BattleStage3D
var _timeline: TimelinePanel
var _scrub: HSlider
var _status: Label
var _play_button: Button
var _frames: Array = []
var _events: Array = []
var _visual: Dictionary = {}
var _time: float = 0.0
var _duration: float = 0.0
var _speed: float = 1.0
var _playing: bool = false
var _event_index: int = 0
var _player_id: String = "player"
var _enemy_id: String = "enemy"


func _ready() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	add_child(row)
	_play_button = Button.new()
	_play_button.text = Localization.get_text("replay.play_pause", "Play / Pause")
	_play_button.pressed.connect(func() -> void:
		if _time >= _duration:
			seek(0.0)
		_playing = not _playing
		_update_speed()
	)
	row.add_child(_play_button)
	var next: Button = Button.new()
	next.text = Localization.get_text("replay.next_resolution", "Next resolution")
	next.pressed.connect(step_resolution)
	row.add_child(next)
	var speed: OptionButton = OptionButton.new()
	for value: float in [0.25, 0.5, 1.0, 2.0]:
		speed.add_item("%sx" % str(value))
		speed.set_item_metadata(speed.item_count - 1, value)
	speed.select(2)
	speed.item_selected.connect(func(i: int) -> void:
		_speed = float(speed.get_item_metadata(i))
		_update_speed()
	)
	row.add_child(speed)
	_scrub = HSlider.new()
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.step = 0.01
	_scrub.value_changed.connect(seek)
	row.add_child(_scrub)
	_status = Label.new()
	add_child(_status)
	_stage = BattleStage3D.new()
	_stage.custom_minimum_size = Vector2(0, 240)
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_stage)
	_timeline = TimelinePanel.new()
	_timeline.size_flags_vertical = Control.SIZE_FILL
	add_child(_timeline)
	_update_speed()


func load_replay(replay: Dictionary) -> void:
	_playing = false
	_update_speed()
	var summary: Dictionary = Dictionary(replay.get("summary", {}))
	_visual = Dictionary(summary.get("visual_replay", {}))
	_frames = Array(_visual.get("frames", []))
	_events = Array(replay.get("battle_events", []))
	_duration = float(summary.get("battle_time", 0.0))
	_scrub.max_value = maxf(0.01, _duration)
	_play_button.disabled = _frames.is_empty()
	_stage.visible = not _frames.is_empty()
	_timeline.visible = not _frames.is_empty()
	if _frames.is_empty():
		_status.text = Localization.get_text("replay.legacy", "This older replay contains event inspection only; visual recording is not available.")
		return
	_player_id = String(_frames[0]["player"].get("unit_id", "player"))
	_enemy_id = String(_frames[0]["enemy"].get("unit_id", "enemy"))
	_stage.configure_combatants(_player_id, _enemy_id, "player", String(_visual.get("player_visual", "balanced")), String(_visual.get("enemy_visual", "scout")))
	var horizon: float = FatigueRules.CAST_TIME
	for side: String in ["player", "enemy"]:
		for runtime: Dictionary in _frames[0][side].get("runtime_states", []):
			var card: CardDef = Database.get_card(String(runtime.get("card_id", "")))
			if card != null:
				horizon = maxf(horizon, card.cast_time)
	_timeline.set_fixed_horizon(horizon)
	seek(0.0)


func seek(time: float) -> void:
	_time = clampf(time, 0, _duration)
	_playing = false
	_event_index = 0
	while _event_index < _events.size() and float(_events[_event_index].get("time", 0.0)) <= _time:
		_event_index += 1
	_timeline.clear_display_history()
	var frame: Dictionary = BattleRecording.frame_at(_frames, _time)
	_stage.reset_replay_pose(Array(frame.get("timeline", [])), int(Dictionary(frame.get("player", {})).get("hp", 1)), int(Dictionary(frame.get("enemy", {})).get("hp", 1)))
	_update_speed()
	_render()


func step_resolution() -> void:
	for i in range(_event_index, _events.size()):
		var event: Dictionary = Dictionary(_events[i])
		if String(event.get("event_type", "")) in ["resolve_card", "fatigue_card"]:
			seek(float(event.get("time", 0.0)))
			_event_index = i + 1
			# A single impact can animate while the simulation clock remains paused.
			_stage.set_playback_speed(_speed)
			_stage.play_battle_event(event)
			return


func _process(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return
	_time = minf(_duration, _time + delta * _speed)
	while _event_index < _events.size() and float(_events[_event_index].get("time", 0.0)) <= _time:
		_stage.play_battle_event(Dictionary(_events[_event_index]))
		_event_index += 1
	_render()
	if _time >= _duration:
		_playing = false
		# Let the final impact finish; seeking or pausing explicitly freezes it.


func _update_speed() -> void:
	if _stage != null:
		_stage.set_playback_speed(_speed if _playing else 0.0)


func _render() -> void:
	var frame: Dictionary = BattleRecording.frame_at(_frames, _time)
	if frame.is_empty():
		return
	_scrub.set_value_no_signal(_time)
	var player: UnitState = BattleStateCodec._decode_unit(Dictionary(frame["player"]))
	var enemy: UnitState = BattleStateCodec._decode_unit(Dictionary(frame["enemy"]))
	_status.text = "%.2f / %.2fs    %s HP %d/%d  +%d    |    %s HP %d/%d  +%d" % [_time, _duration, player.display_name, player.hp, player.max_hp, player.shield, enemy.display_name, enemy.hp, enemy.max_hp, enemy.shield]
	var entries: Array[TimelineEntry] = []
	for raw: Dictionary in frame.get("timeline", []):
		var entry: TimelineEntry = BattleStateCodec._decode_timeline_entry(raw)
		# Extrapolate only continuous time manipulation, never discrete delay effects.
		var age: float = maxf(0.0, _time - float(frame["time"]))
		if entry.continuous_shift_amount > 0.0 and absf(entry.continuous_shift_battle_time - float(frame["time"])) < 0.06:
			var previous: Dictionary = BattleRecording.frame_at(_frames, maxf(0, float(frame["time"]) - 0.001))
			var span: float = float(frame["time"]) - float(previous.get("time", frame["time"]))
			if span > 0.0:
				for old: Dictionary in previous.get("timeline", []):
					if int(old.get("instance_id", -1)) == entry.instance_id:
						var rate: float = clampf((entry.scheduled_time - float(old.get("scheduled_time", entry.scheduled_time))) / span, 0.0, 2.0)
						entry.scheduled_time += rate * age
		entries.append(entry)
	_timeline.refresh_timeline(entries, _time, null, null, null, "player", null, player, enemy)
