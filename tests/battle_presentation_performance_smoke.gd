extends Control

var _checks: int = 0


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.set_language("en")
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Battle presentation cache: " + message)
		get_tree().quit(1)
		assert(value, message)


func _verify_text(button: CardButton, card: CardDef) -> void:
	_check(button.get("_simple_tooltip_text") == button.call("_build_preview_simple_tooltip", card, false), "compact tooltip matches live formatter: " + card.id)
	_check(button.get("_simple_tooltip_bbcode") == button.call("_build_preview_simple_tooltip", card, true), "colored tooltip matches live formatter: " + card.id)
	_check(button.get("_legacy_tooltip_text") == button.call("_build_legacy_tooltip", card, "", false), "legacy grades match live formatter: " + card.id)
	_check(button.get("_legacy_tooltip_bbcode") == button.call("_build_legacy_tooltip", card, "", true), "legacy colors match live formatter: " + card.id)


func _run() -> void:
	Game.start_new_run("balanced", 4242)
	var run: RunState = Game.current_run
	var button: CardButton = CardButton.new()
	add_child(button)
	var card: CardDef = CardDef.from_dict(Database.get_card("quick_slash").to_dict())
	button.bind_preview(card, card.id)
	await get_tree().process_frame
	var frame_style: StyleBox = button.get_theme_stylebox("normal")
	var border_style: StyleBox = (button.get("_frame_overlay") as Panel).get_theme_stylebox("panel")
	var revision: int = int(button.get("_face_revision"))
	for index: int in 100:
		button.bind_preview(CardDef.from_dict(card.to_dict()), card.id)
	_check(button.get_theme_stylebox("normal") == frame_style, "unchanged cards reuse frame styles")
	_check((button.get("_frame_overlay") as Panel).get_theme_stylebox("panel") == border_style, "unchanged cards reuse border styles")
	_check(button.get("_face_revision") == revision, "fresh equal definitions reuse face summaries")
	_verify_text(button, card)
	card.effects[0]["amount"] = int(card.effects[0]["amount"]) + 4
	card.cast_time += 1.5
	card.loadout_cost += 2
	button.bind_preview(card, card.id)
	_check(int(button.get("_face_revision")) > revision, "in-place effect changes invalidate the face")
	_verify_text(button, card)
	card.effects[0]["amount"] = 1
	button.bind_preview(card, card.id)
	_verify_text(button, card)
	_check(String(button.get("_simple_tooltip_bbcode")).contains(CardButton.TOOLTIP_NERF_COLOR), "debuff remains red")
	var baseline: CardDef = CardDef.from_dict(card.to_dict())
	baseline.effects[0]["amount"] = 0
	button.bind_preview(card, card.id, false, "", baseline)
	_verify_text(button, card)
	_check(String(button.get("_simple_tooltip_bbcode")).contains(CardButton.TOOLTIP_BUFF_COLOR), "comparison-only changes remain green")
	button.append_tooltip_line("reservation marker")
	button.bind_preview(card, card.id, false, "", baseline)
	_check(not button.tooltip_text.contains("reservation marker"), "cached base resets appended reservation text")
	button.bind_balance_preview(card, baseline)
	_check(button.get("_simple_tooltip_text") == button.get("_legacy_tooltip_text"), "drafts do not expose published grade tables")
	var runtime: CardRuntimeState = CardRuntimeState.new()
	runtime.runtime_id = "cache_test"
	runtime.card_id = card.id
	button.bind(card, runtime, false, true, "blocked one")
	_check(button.tooltip_text.ends_with("blocked one"), "blocked reason appears")
	button.bind(card, runtime, false, true, "blocked two")
	_check(button.tooltip_text.ends_with("blocked two") and not button.tooltip_text.contains("blocked one"), "blocked reason updates without stale suffix")
	runtime.begin_cooldown(2.0)
	button.bind(card, runtime, false)
	var timer_label: Label = button.get("_meta_label") as Label
	var old_timer: String = timer_label.text
	runtime.cooldown_remaining = 1.0
	button.bind(card, runtime, false)
	_check(old_timer != timer_label.text, "countdown still updates every bind")
	var entry: TimelineEntry = TimelineEntry.new()
	entry.runtime_id = runtime.runtime_id
	entry.owner_side = "enemy"
	entry.scheduled_time = 10.0
	button.bind_timeline(card, entry, 1.0)
	var normal_border: StyleBox = (button.get("_frame_overlay") as Panel).get_theme_stylebox("panel")
	button.bind_timeline(card, entry, 2.0, true)
	_check((button.get("_frame_overlay") as Panel).get_theme_stylebox("panel") != normal_border, "NEXT border invalidates styles")
	_check(timer_label.text == "8.0s", "timeline countdown continues")
	button.set_tile_size(Vector2(168, 168))
	await get_tree().process_frame
	_check(button.get_art_rect().size == Vector2(168, 168), "cached cards still resize")
	for id: String in Database.get_all_card_ids():
		for tier: int in [0, 3, 5]:
			var grade: CardDef = CardUpgradeResolver.build_card_at_tier(id, tier)
			button.bind_preview(grade, id)
			_verify_text(button, grade)
	var unit: UnitState = UnitState.new()
	unit.unit_id = "player"
	unit.attack = run.attack
	unit.hp = 20
	unit.max_hp = 60
	for attack: int in [run.attack + 3, 0, run.attack]:
		unit.attack = attack
		var context: Dictionary = CardTooltipResolver.build_context("quick_slash", run, unit)
		button.bind_preview(context.card, "test", false, "", context.comparison)
		_verify_text(button, context.card)
	var original: String = button.tooltip_text
	Game.set_language("ja")
	var context: Dictionary = CardTooltipResolver.build_context("quick_slash", run, unit)
	button.bind_preview(context.card, "test", false, "", context.comparison)
	_verify_text(button, context.card)
	_check(button.tooltip_text != original, "locale and database reload invalidate cache")
	Game.set_language("en")
	var row: RelicIconRow = RelicIconRow.new()
	add_child(row)
	var ids: Array[String] = []
	ids.assign(Database.get_all_relic_ids().slice(0, 3))
	row.refresh_relic_ids(ids)
	var icons: Array = row.get("_icons")
	var first: RelicIcon = icons[0]
	var relic_style: StyleBox = first.get_theme_stylebox("panel")
	for index: int in 100:
		row.refresh_relic_ids(ids)
	_check(icons[0] == first and first.get_theme_stylebox("panel") == relic_style, "relic nodes/styles persist for repeated refreshes")
	ids.reverse()
	row.refresh_relic_ids(ids)
	_check(icons[0] == first and first.relic_id == ids[0], "reordered relics update existing icons")
	row.set_icon_size(Vector2(30, 30))
	_check(first.custom_minimum_size == Vector2(30, 30), "reused relic icons resize")
	var relic: RelicDef = Database.get_relic(ids[0])
	var description: String = relic.description
	relic.description = "changed relic tooltip"
	row.refresh_relic_ids(ids)
	_check(first.tooltip_text.contains("changed relic tooltip"), "in-place relic description invalidates tooltip")
	relic.description = description
	run.relic_state[ids[0]] = {"card_id": "quick_slash"}
	row.refresh_relic_ids(ids)
	_check(first.tooltip_text.contains(Database.get_card("quick_slash").name), "engraved-card state invalidates tooltip")
	row.refresh_relic_ids([], "empty")
	_check(icons.is_empty() and (row.get_node("RelicIconRowEmpty") as Label).text == "empty", "empty relic list releases icons")
	row.refresh_relic_ids(ids)
	_check(not (row.get_node("RelicIconRowEmpty") as Label).visible and icons.size() == 3, "empty placeholder hides when relics return")
	var log_panel: LogPanel = LogPanel.new()
	add_child(log_panel)
	var logs: Array[String] = ["first", "second"]
	log_panel.refresh_logs(logs)
	logs[1] = "replacement"
	log_panel.refresh_logs(logs)
	_check((log_panel.get("_body_label") as RichTextLabel).text == "first\nreplacement", "same-sized replaced logs invalidate text")
	logs.clear()
	log_panel.refresh_logs(logs)
	_check((log_panel.get("_body_label") as RichTextLabel).text.is_empty(), "log clear updates text")
	var profiler: BattleFrameProfiler = BattleFrameProfiler.new()
	add_child(profiler)
	_check(not profiler.is_processing(), "profiler does no idle work")
	var statistics: Dictionary = BattleFrameProfiler.summarize([10.0, 20.0, 40.0])
	_check(statistics.p95_ms == 40.0 and statistics.over_33ms == 1 and statistics.count == 3, "profiler summary reports tail latency")
	profiler.start_capture(0.1)
	profiler.record_ui_time(2.0)
	await profiler.capture_finished
	_check(not profiler.is_processing() and int(profiler.last_report.frame.count) > 0, "capture stops and stores a bounded report")
	_check(int(profiler.last_report.ui.count) == 1, "UI samples are recorded once, not reused across frames")
	print("BATTLE_PRESENTATION_PERFORMANCE_SMOKE_OK checks=%d" % _checks)
	get_tree().quit()
