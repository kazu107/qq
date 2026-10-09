extends Node


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	Game.settings["developer_mode"] = true
	var screen: Control = load("res://scenes/debug/ArtLab.tscn").instantiate() as Control
	add_child(screen)
	for frame: int in 10:
		await get_tree().process_frame
	var catalog: Array = screen.get("_catalog")
	var grid: GridContainer = screen.find_child("ArtLabGrid", true, false) as GridContainer
	if catalog.size() < 37 or grid == null or grid.get_child_count() > 24 or grid.get_child_count() == 0:
		_fail("Art lab did not build a bounded page of registered assets")
		return
	screen.call("_open_preview", catalog[0])
	if screen.find_child("ArtPreviewOverlay", true, false) == null:
		_fail("Art preview did not open")
		return
	screen.call("_close_preview")
	if screen.find_child("ArtPreviewOverlay", true, false) != null:
		_fail("Art preview was left in the input tree after closing")
		return
	var filter: OptionButton = screen.find_child("ArtLabCategory", true, false) as OptionButton
	for index: int in filter.item_count:
		if String(filter.get_item_metadata(index)) == "card":
			filter.select(index)
			break
	screen.call("_apply_filter")
	for frame: int in 10:
		await get_tree().process_frame
	for raw: Variant in Array(screen.get("_filtered")):
		if String(Dictionary(raw).get("category", "")) != "card":
			_fail("Category filter mixed non-card assets")
			return
	var fatigue: CardDef = screen.call("_card_definition", FatigueRules.CARD_ID) as CardDef
	if fatigue == null or fatigue.id != FatigueRules.CARD_ID:
		_fail("Environment card was not resolved outside the collectible database")
		return
	var search: LineEdit = screen.find_child("ArtLabSearch", true, false) as LineEdit
	search.grab_focus()
	screen.call("_open_preview", catalog[0])
	var close: Button = screen.find_child("ArtPreviewClose", true, false) as Button
	if get_viewport().gui_get_focus_owner() != close or close.focus_next != close.get_path():
		_fail("Modal did not capture keyboard focus")
		return
	screen.call("_close_preview")
	if get_viewport().gui_get_focus_owner() != search:
		_fail("Modal did not restore previous keyboard focus")
		return
	search.text = "no_matching_asset_exists"
	screen.call("_apply_filter")
	if not Array(screen.get("_filtered")).is_empty():
		_fail("Search did not filter its entries")
		return
	screen.queue_free()
	await get_tree().process_frame
	print("ART_LAB_SMOKE_OK developer gate, paged thumbnails, category/search, preview close")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
