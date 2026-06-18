extends Control
class_name AtmosphereBackground

const BASE_TOP: Color = Color(0.035, 0.047, 0.065, 1.0)
const BASE_BOTTOM: Color = Color(0.010, 0.014, 0.022, 1.0)
const GLOW_BLUE: Color = Color(0.13, 0.55, 0.88, 0.20)
const GLOW_GOLD: Color = Color(0.95, 0.65, 0.22, 0.13)
const GLOW_RED: Color = Color(0.85, 0.20, 0.23, 0.10)
const GRID_COLOR: Color = Color(0.55, 0.78, 0.95, 0.035)
const PANEL_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.22)


func _ready() -> void:
	name = "GameAtmosphereBackground"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = -4096
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var draw_size: Vector2 = size
	if draw_size.x <= 1.0 or draw_size.y <= 1.0:
		draw_size = get_viewport_rect().size

	_draw_vertical_gradient(draw_size)
	_draw_glow(Vector2(draw_size.x * 0.14, draw_size.y * 0.12), draw_size.x * 0.34, GLOW_BLUE)
	_draw_glow(Vector2(draw_size.x * 0.82, draw_size.y * 0.18), draw_size.x * 0.25, GLOW_GOLD)
	_draw_glow(Vector2(draw_size.x * 0.56, draw_size.y * 0.90), draw_size.x * 0.32, GLOW_RED)
	_draw_diagonal_panels(draw_size)
	_draw_grid(draw_size)
	_draw_vignette(draw_size)


func _draw_vertical_gradient(draw_size: Vector2) -> void:
	var band_count: int = 18
	var band_height: float = draw_size.y / float(band_count)
	for band_index in range(band_count):
		var ratio: float = float(band_index) / float(maxi(1, band_count - 1))
		var color: Color = BASE_TOP.lerp(BASE_BOTTOM, ratio)
		draw_rect(Rect2(0.0, band_height * float(band_index), draw_size.x, band_height + 1.0), color)


func _draw_glow(center: Vector2, radius: float, color: Color) -> void:
	var ring_count: int = 9
	for ring_index in range(ring_count, 0, -1):
		var ratio: float = float(ring_index) / float(ring_count)
		var ring_color: Color = color
		ring_color.a *= pow(1.0 - ratio, 1.35)
		draw_circle(center, radius * ratio, ring_color)


func _draw_diagonal_panels(draw_size: Vector2) -> void:
	var first_band: PackedVector2Array = PackedVector2Array([
		Vector2(draw_size.x * 0.08, 0.0),
		Vector2(draw_size.x * 0.40, 0.0),
		Vector2(draw_size.x * 0.23, draw_size.y),
		Vector2(0.0, draw_size.y),
	])
	draw_colored_polygon(first_band, Color(0.22, 0.34, 0.45, 0.055))

	var second_band: PackedVector2Array = PackedVector2Array([
		Vector2(draw_size.x * 0.74, 0.0),
		Vector2(draw_size.x, 0.0),
		Vector2(draw_size.x, draw_size.y),
		Vector2(draw_size.x * 0.58, draw_size.y),
	])
	draw_colored_polygon(second_band, Color(0.42, 0.26, 0.16, 0.060))

	var horizon_panel: Rect2 = Rect2(0.0, draw_size.y * 0.70, draw_size.x, draw_size.y * 0.30)
	draw_rect(horizon_panel, PANEL_SHADOW)


func _draw_grid(draw_size: Vector2) -> void:
	var step: float = 72.0
	var x_position: float = 0.0
	while x_position <= draw_size.x:
		draw_line(Vector2(x_position, 0.0), Vector2(x_position + draw_size.y * 0.18, draw_size.y), GRID_COLOR, 1.0)
		x_position += step

	var y_position: float = 0.0
	while y_position <= draw_size.y:
		draw_line(Vector2(0.0, y_position), Vector2(draw_size.x, y_position), GRID_COLOR, 1.0)
		y_position += step


func _draw_vignette(draw_size: Vector2) -> void:
	var edge_width: float = maxf(80.0, minf(draw_size.x, draw_size.y) * 0.12)
	draw_rect(Rect2(0.0, 0.0, draw_size.x, edge_width), Color(0.0, 0.0, 0.0, 0.18))
	draw_rect(Rect2(0.0, draw_size.y - edge_width, draw_size.x, edge_width), Color(0.0, 0.0, 0.0, 0.24))
	draw_rect(Rect2(0.0, 0.0, edge_width, draw_size.y), Color(0.0, 0.0, 0.0, 0.16))
	draw_rect(Rect2(draw_size.x - edge_width, 0.0, edge_width, draw_size.y), Color(0.0, 0.0, 0.0, 0.18))
