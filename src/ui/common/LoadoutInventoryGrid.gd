extends GridContainer
class_name LoadoutInventoryGrid

const MIN_CELL_WIDTH: float = 156.0
const MIN_RENDERED_CELL_WIDTH: float = 140.0
const MAX_COLUMNS: int = 6
var _layout_pending: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("h_separation", 10)
	add_theme_constant_override("v_separation", 10)
	resized.connect(_queue_layout)
	minimum_size_changed.connect(_queue_layout)
	get_window().size_changed.connect(_queue_layout)
	if get_parent() is ScrollContainer:
		(get_parent() as ScrollContainer).resized.connect(_queue_layout)
	_queue_layout()


func _queue_layout() -> void:
	if is_inside_tree() and not _layout_pending:
		_layout_pending = true
		call_deferred("update_columns")


func update_columns() -> void:
	_layout_pending = false
	if not is_inside_tree():
		return
	var scroll: ScrollContainer = get_parent() as ScrollContainer
	if scroll == null or scroll.size.x <= 1.0:
		return
	# Reserve scrollbar space even while hidden, avoiding resize/hover oscillation.
	var width: float = scroll.size.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var cell_width: float = MIN_CELL_WIDTH
	for child: Node in get_children():
		if child is Control and (child as Control).visible:
			cell_width = maxf(cell_width, (child as Control).get_combined_minimum_size().x)
	var gap: float = get_theme_constant("h_separation")
	var fitting: int = maxi(1, floori((width + gap) / (cell_width + gap)))
	var pixel_scale: float = float(get_window().size.x) / maxf(1.0, get_viewport_rect().size.x)
	if DisplayServer.get_name() == "headless":
		pixel_scale = 1.0
	var readable: int = maxi(1, floori((width + gap) * pixel_scale / (MIN_RENDERED_CELL_WIDTH + gap * pixel_scale)))
	var next_columns: int = mini(MAX_COLUMNS, mini(fitting, readable))
	if columns != next_columns:
		columns = next_columns
