extends Control


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	get_window().content_scale_size = Vector2i(1600, 1000)
	Game.ensure_meta_initialized()
	Localization.set_language("ja", false)
	Database.load_all()
	Game.settings["developer_mode"] = true
	Game.start_new_run("balanced")
	call_deferred("_run")


func _run() -> void:
	var scene: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(scene)
	scene.set_process(false)
	var engine: RealtimeBattleEngine = scene.get("_engine") as RealtimeBattleEngine
	engine.set("_pvp_mode", true)
	engine.battle_state.player.hp = 60
	engine.battle_state.player.max_hp = 60
	engine.battle_state.enemy.hp = 60
	engine.battle_state.enemy.max_hp = 60
	engine.start_battle()
	scene.call("_on_dev_fatigue")
	engine.update(2.5)
	scene.call("_refresh_ui", 1.0)
	await get_tree().create_timer(1.0).timeout
	_capture("build/fatigue_timeline.png")
	var timeline: TimelinePanel = scene.get("_timeline_panel") as TimelinePanel
	var cards: Array[CardButton] = timeline.get("_cards")
	var tooltip: Control = cards[0].call("_make_custom_tooltip", cards[0].tooltip_text) as Control
	add_child(tooltip)
	tooltip.z_index = 2000
	tooltip.position = Vector2(540, 500)
	await get_tree().create_timer(0.2).timeout
	_capture("build/fatigue_tooltip.png")
	tooltip.queue_free()
	engine.battle_state.player.shield = 20
	engine.update(3.5)
	scene.call("_refresh_ui", 1.0)
	await get_tree().create_timer(0.1).timeout
	_capture("build/fatigue_impact.png")
	print("FATIGUE_REVIEW_OK")
	get_tree().quit()


func _capture(path: String) -> void:
	RenderingServer.force_draw(false, 0.0)
	var frame: Image = get_viewport().get_texture().get_image()
	if frame == null or frame.save_png(path) != OK:
		push_error("Could not capture fatigue review: " + path)
		get_tree().quit(1)
