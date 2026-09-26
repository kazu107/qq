extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	SceneRouter.set("_warming_ui_scene", true)
	var screen: Control = load("res://scenes/library/CardLibrary.tscn").instantiate() as Control
	add_child(screen)
	SceneRouter.set("_warming_ui_scene", false)
	if not await _wait_ready(screen):
		_fail("initial page did not complete")
		return
	var grid: GridContainer = screen.get("_cards_grid") as GridContainer
	var first_page_count: int = grid.get_child_count()
	var total_count: int = Game.get_meta_card_entries().size()
	if not _check(first_page_count >= 12 and first_page_count < total_count, "first page eagerly built every card"):
		return

	var rarity_filter: OptionButton = screen.get("_rarity_filter") as OptionButton
	var legendary_index: int = _find_option(rarity_filter, "legendary")
	if not _check(legendary_index >= 0, "legendary filter is missing"):
		return
	rarity_filter.select(legendary_index)
	screen.call("_on_rarity_filter_selected", legendary_index)
	if not await _wait_ready(screen):
		_fail("filtered page did not complete")
		return
	if not _check(grid.get_child_count() <= 12, "filter rebuilt too many cards immediately"):
		return
	var legendary_count: int = 0
	for entry: Dictionary in Game.get_meta_card_entries():
		if String(entry.get("rarity", "")) == "legendary":
			legendary_count += 1
	if not await _scroll_until_complete(screen, grid, legendary_count):
		_fail("scrolling did not load all legendary cards")
		return
	for raw_widgets: Variant in Dictionary(screen.get("_card_widgets")).values():
		if not _check(String(Dictionary(raw_widgets).get("rarity", "")) == "legendary", "rarity filter showed a wrong card"):
			return
	print("LIBRARY_LAZY_SMOKE_OK first=%d total=%d legendary=%d" % [first_page_count, total_count, legendary_count])
	get_tree().quit(0)


func _scroll_until_complete(screen: Control, grid: GridContainer, expected: int) -> bool:
	var scroll: ScrollContainer = screen.get("_cards_scroll") as ScrollContainer
	for _attempt: int in range(30):
		if grid.get_child_count() >= expected:
			return true
		var bar: ScrollBar = scroll.get_v_scroll_bar()
		bar.value = bar.max_value
		for _frame: int in range(6):
			await get_tree().process_frame
	return grid.get_child_count() == expected


func _wait_ready(screen: Control) -> bool:
	for _frame: int in range(120):
		if bool(screen.call("is_content_ready")):
			return true
		await get_tree().process_frame
	return false


func _find_option(option: OptionButton, value: String) -> int:
	for index: int in range(option.item_count):
		if String(option.get_item_metadata(index)) == value:
			return index
	return -1


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error("Library lazy smoke failed: %s" % message)
	get_tree().quit(1)
