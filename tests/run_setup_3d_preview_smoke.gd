extends Node

const RUN_SETUP_SCENE: PackedScene = preload("res://scenes/run_setup/RunSetup.tscn")


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.developer_unlock_all_meta()
	Game.settings["developer_mode"] = false
	Game.prepare_run_setup(Game.RUN_SETUP_MODE_NORMAL)
	call_deferred("_run")


func _run() -> void:
	var screen: Control = RUN_SETUP_SCENE.instantiate() as Control
	if screen == null:
		_fail("Run setup 3D preview smoke failed: scene could not be instantiated")
		return
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var columns: HBoxContainer = screen.find_child("RunSetupColumns", true, false) as HBoxContainer
	var scroll: ScrollContainer = screen.find_child("StarterSelectionScroll", true, false) as ScrollContainer
	var deck_grid: GridContainer = screen.find_child("StarterDeckGrid", true, false) as GridContainer
	var preview: StarterModelPreview = screen.find_child("StarterModelPreview", true, false) as StarterModelPreview
	var name_label: Label = screen.find_child("StarterNameLabel", true, false) as Label
	var description_label: RichTextLabel = screen.find_child("StarterDescriptionLabel", true, false) as RichTextLabel
	var stats_grid: GridContainer = screen.find_child("StarterStatsGrid", true, false) as GridContainer
	var cards_panel: CardHandPanel = screen.find_child("StarterCards", true, false) as CardHandPanel
	var start_button: Button = screen.find_child("RunStartSelectedButton", true, false) as Button
	if columns == null \
	or scroll == null \
	or deck_grid == null \
	or preview == null \
	or name_label == null \
	or description_label == null \
	or stats_grid == null \
	or cards_panel == null \
	or start_button == null:
		_fail("Run setup 3D preview smoke failed: redesigned layout controls were missing")
		return

	if columns.get_child_count() != 3 or deck_grid.columns != 1 or stats_grid.columns != 3:
		_fail("Run setup 3D preview smoke failed: selection, model, and detail columns were not preserved")
		return
	if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_fail("Run setup 3D preview smoke failed: deck list should not use a horizontal scrollbar")
		return

	for starter: Dictionary in Database.starters:
		var starter_id: String = String(starter.get("id", ""))
		if screen.find_child("StarterButton_%s" % starter_id, true, false) == null:
			_fail("Run setup 3D preview smoke failed: missing starter button %s" % starter_id)
			return

	if screen.find_child("StarterPortrait", true, false) != null:
		_fail("Run setup 3D preview smoke failed: legacy portrait remained in the redesigned screen")
		return
	if not preview.is_preview_ready():
		_fail("Run setup 3D preview smoke failed: animated 3D viewport was not ready")
		return
	var viewport: SubViewport = preview.get_preview_viewport()
	var actor: BattleActor3D = preview.get_preview_actor()
	if viewport == null \
	or viewport.size.x < 320 \
	or viewport.size.y < 320 \
	or viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS \
	or actor == null:
		_fail("Run setup 3D preview smoke failed: viewport or actor configuration was incomplete")
		return
	if preview.get_selected_starter_id() != "balanced" \
	or actor.get_visual_profile_id() != "balanced" \
	or actor.get_action_name() != "ready" \
	or not actor.get_active_animation_clip().begins_with("ready"):
		_fail("Run setup 3D preview smoke failed: initial model did not use an animated ready stance")
		return

	var chrono_button: Button = screen.find_child("StarterButton_chrono", true, false) as Button
	chrono_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	actor = preview.get_preview_actor()
	var chrono: Dictionary = Database.get_starter("chrono")
	var selected_indicator: Label = screen.find_child("StarterDeckSelected_chrono", true, false) as Label
	if preview.get_selected_starter_id() != "chrono" \
	or actor == null \
	or actor.get_visual_profile_id() != "chrono" \
	or actor.get_weapon_type() != "staff" \
	or actor.get_action_name() != "ready":
		_fail("Run setup 3D preview smoke failed: changing decks did not update the animated model")
		return
	if name_label.text != String(chrono.get("name", "")) \
	or description_label.text != String(chrono.get("description", "")) \
	or selected_indicator == null \
	or not selected_indicator.visible:
		_fail("Run setup 3D preview smoke failed: selected deck details were not synchronized")
		return
	var expected_cards: Array[String] = _to_string_array(chrono.get("cards", []))
	if _visible_control_count(cards_panel) != expected_cards.size():
		_fail("Run setup 3D preview smoke failed: opening card count did not follow the selected deck")
		return
	if start_button.disabled or start_button.custom_minimum_size.y < 54.0:
		_fail("Run setup 3D preview smoke failed: primary start action was not stable and available")
		return
	for starter_id: String in ["balanced", "tempo", "fortress", "vanguard", "aegis", "chrono", "turret"]:
		var starter_button: Button = screen.find_child("StarterButton_" + starter_id, true, false) as Button
		starter_button.pressed.emit()
		await get_tree().process_frame
		actor = preview.get_preview_actor()
		if not actor.is_using_authored_model() or actor.get_authored_model_path() != "res://assets/models/battle/%s.glb" % starter_id:
			_fail("Run setup 3D preview smoke failed: starter still uses procedural geometry: " + starter_id)
			return
	chrono_button.pressed.emit()
	await get_tree().process_frame

	var capture_path: String = OS.get_environment("QQ_RUN_SETUP_CAPTURE")
	if capture_path != "":
		RenderingServer.force_draw(false, 0.0)
		var image: Image = get_viewport().get_texture().get_image()
		if image == null:
			_fail("Run setup 3D preview smoke failed: renderer did not provide a visual capture")
			return
		var save_error: Error = image.save_png(capture_path)
		if save_error != OK:
			_fail("Run setup 3D preview smoke failed: visual capture could not be saved")
			return

	print("RUN_SETUP_3D_PREVIEW_SMOKE_OK 3-column layout, 7 decks, animated model switching, stats, and cards validated")
	get_tree().quit()


func _visible_control_count(parent: Control) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		var control: Control = child as Control
		if control != null and control.visible:
			count += 1
	return count


func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item: Variant in value:
		result.append(String(item))
	return result


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
