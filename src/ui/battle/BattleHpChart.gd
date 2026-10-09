extends Control
class_name BattleHpChart

var _samples: Array[Dictionary] = []
var _local_side: String = "player"
var _duration: float = 1.0
var _maximum: float = 1.0
var _hover_time: float = -1.0
var _background_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_exited.connect(func() -> void:
		_hover_time = -1.0
		queue_redraw()
	)


func set_history(samples: Array, local_side: String, duration: float) -> void:
	_samples.clear()
	_local_side = local_side
	_duration = maxf(1.0, duration)
	_maximum = 1.0
	for sample: Dictionary in samples:
		_samples.append(sample)
		_maximum = maxf(_maximum, maxf(float(sample.get("player", 0)), float(sample.get("enemy", 0))))
		_duration = maxf(_duration, float(sample.get("time", 0.0)))
	_hover_time = -1.0
	queue_redraw()


func _plot_rect() -> Rect2:
	return Rect2(52.0, 28.0, maxf(1.0, size.x - 74.0), maxf(1.0, size.y - 66.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var plot: Rect2 = _plot_rect()
		_hover_time = clampf((event.position.x - plot.position.x) / plot.size.x, 0.0, 1.0) * _duration
		queue_redraw()


func _draw() -> void:
	var font: Font = UiTheme.GAME_FONT
	var plot: Rect2 = _plot_rect()
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	for index: int in range(5):
		var ratio: float = index / 4.0
		var y: float = plot.end.y - plot.size.y * ratio
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(0.22, 0.34, 0.42, 0.55))
		draw_string(font, Vector2(8.0, y + 5.0), str(roundi(_maximum * ratio)), HORIZONTAL_ALIGNMENT_RIGHT, 36.0, 15, UiTheme.TEXT_MUTED)
		var x: float = plot.position.x + plot.size.x * ratio
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(0.22, 0.34, 0.42, 0.35))
		draw_string(font, Vector2(x - 24.0, plot.end.y + 25.0), "%.1fs" % (_duration * ratio), HORIZONTAL_ALIGNMENT_CENTER, 48.0, 15, UiTheme.TEXT_MUTED)
	if _samples.is_empty():
		draw_string(font, Vector2(plot.position.x, plot.get_center().y), Localization.get_text("battle.analysis.no_history", "No HP history was recorded."), HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, 18, UiTheme.TEXT_MUTED)
		return
	for side: String in ["player", "enemy"]:
		var points: PackedVector2Array = []
		for sample: Dictionary in _samples:
			points.append(Vector2(plot.position.x + float(sample.get("time", 0.0)) / _duration * plot.size.x, plot.end.y - float(sample.get(side, 0)) / _maximum * plot.size.y))
		var tint: Color = BattleResultAnalysisPanel.LOCAL_COLOR if side == _local_side else BattleResultAnalysisPanel.OPPONENT_COLOR
		if points.size() > 1:
			draw_polyline(points, tint, 2.5, true)
		draw_circle(points[0], 3.5, tint)
		draw_circle(points[-1], 3.5, tint)
	if _hover_time >= 0.0:
		var nearest: Dictionary = _samples[0]
		for sample: Dictionary in _samples:
			if absf(float(sample["time"]) - _hover_time) < absf(float(nearest["time"]) - _hover_time):
				nearest = sample
		var x: float = plot.position.x + float(nearest["time"]) / _duration * plot.size.x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(1.0, 1.0, 1.0, 0.7), 1.0)
		var opponent: String = "enemy" if _local_side == "player" else "player"
		draw_string(font, Vector2(plot.position.x, 20.0), "%.1fs   HP %d / %d" % [float(nearest["time"]), int(nearest[_local_side]), int(nearest[opponent])], HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, 16, Color.WHITE)


func _background() -> StyleBoxFlat:
	if _background_style == null:
		_background_style = StyleBoxFlat.new()
		_background_style.bg_color = Color(0.025, 0.055, 0.078)
		_background_style.set_corner_radius_all(8)
	return _background_style
