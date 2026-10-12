extends Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("Inventory grid: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _settle() -> void:
	for _frame: int in 6:
		await get_tree().process_frame


func _run() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size = Vector2(800, 210)
	add_child(scroll)
	var grid: LoadoutInventoryGrid = LoadoutInventoryGrid.new()
	scroll.add_child(grid)
	for index: int in 12:
		var cell: PanelContainer = PanelContainer.new()
		cell.custom_minimum_size = Vector2(156, 150)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
	await _settle()
	var wide_columns: int = grid.columns
	_check(wide_columns > 1, "Wide inventories did not form multiple columns")
	scroll.size.x = 220.0
	await _settle()
	_check(grid.columns == 1, "Narrow inventories did not collapse to one column")
	scroll.size.x = 800.0
	await _settle()
	_check(grid.columns == wide_columns, "Growing did not restore the previous column count")
	(grid.get_child(0) as Control).custom_minimum_size.x = 360.0
	await _settle()
	_check(grid.columns < wide_columns, "Actual cell minimum widths were ignored")
	_check(grid.size.x <= scroll.size.x, "Inventory introduced horizontal overflow")
	var stable_columns: int = grid.columns
	for _frame: int in 20:
		await get_tree().process_frame
		_check(grid.columns == stable_columns, "Scrollbar/layout changes oscillated the grid")
	scroll.remove_child(grid)
	grid.update_columns()
	grid.free()
	scroll.queue_free()
	await get_tree().process_frame
	print("LOADOUT_INVENTORY_GRID_SMOKE_OK adaptive columns, grow/shrink, real minimum sizes, no horizontal overflow or oscillation")
	get_tree().quit()
