extends Control
class_name MapRouteCanvas

signal node_selected(node_id: String)

const ROW_PITCH: float = 128.0
var _map: Dictionary = {}
var _steps: Array = []
var _chapter_start: int = 0
var _signature: String = ""
var _buttons: Dictionary = {}
var _points: Dictionary = {}
var _edges: Array[Dictionary] = []
var _hover_id: String = ""
var _highlighted: Dictionary = {}
var _current_id: String = ""
var _marker_visible: bool = true
var _marker: Vector2 = Vector2.ZERO
var _traveling: bool = false
var _density: float = 1.0
var _pitch: float = ROW_PITCH


func _ready() -> void:
	name = "MapRoutes"
	custom_minimum_size.x = 480
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	resized.connect(_layout)
	get_window().size_changed.connect(_layout)
	set_process(false)


func configure(map: Dictionary, chapter_start: int) -> void:
	var steps: Array = map.get("steps", [])
	var slice: Array = steps.slice(chapter_start, mini(chapter_start + 7, steps.size()))
	var signature: String = "%d:%d:%s" % [chapter_start, int(map.get("current_step", 0)), JSON.stringify(slice)]
	if signature == _signature: return
	_signature = signature
	_map = map.duplicate(true)
	_steps = slice.duplicate(true)
	_chapter_start = chapter_start
	for button: MapNodeButton in _buttons.values():
		remove_child(button)
		button.queue_free()
	_buttons.clear()
	custom_minimum_size.y = maxf(300.0, float(_steps.size() - 1) * ROW_PITCH + 144.0)
	for index: int in _steps.size():
		for node: Dictionary in _steps[index].get("nodes", []):
			var button: MapNodeButton = MapNodeButton.new()
			button.graph_mode = true
			button.name = String(node["id"])
			add_child(button)
			button.bind(node, Localization.get_step_label(_steps[index]), index + _chapter_start == int(map.get("current_step", 0)))
			button.node_selected.connect(func(id: String) -> void:
				if not _traveling: node_selected.emit(id)
			)
			button.mouse_entered.connect(_hover.bind(String(node["id"])))
			button.mouse_exited.connect(_hover.bind(""))
			_buttons[String(node["id"])] = button
	call_deferred("_layout")


func _layout() -> void:
	if not is_inside_tree() or _steps.is_empty(): return
	_density = 1.0 if DisplayServer.get_name() == "headless" else clampf(get_viewport_rect().size.x / maxf(1.0, get_window().size.x), 0.75, 3.0)
	custom_minimum_size = Vector2(480, maxf(300.0, float(_steps.size() - 1) * ROW_PITCH + 144.0)) * _density
	_pitch = maxf(ROW_PITCH * _density, (size.y - 144.0 * _density) / maxf(1.0, _steps.size() - 1))
	_points.clear()
	_current_id = ""
	var current_step: int = int(_map.get("current_step", 0))
	_marker_visible = current_step >= _chapter_start and current_step <= _chapter_start + _steps.size()
	for index: int in _steps.size():
		for node: Dictionary in _steps[index].get("nodes", []):
			var id: String = String(node["id"])
			var button: MapNodeButton = _buttons[id]
			button.size = button.custom_minimum_size
			button.scale = Vector2.ONE * _density
			var route_width: float = minf(720.0 * _density, size.x - 140.0 * _density)
			var center_x: float = size.x * 0.5 + (float(node.get("map_x", 0.5)) - 0.5) * route_width
			button.position = Vector2(center_x - button.size.x * _density * 0.5, 22.0 * _density + float(_steps.size() - 1 - index) * _pitch)
			_points[id] = button.position + Vector2(button.size.x * 0.5, 34.0 if node.get("type", "") != "boss" else 42.0) * _density
			if String(node.get("status", "")) == "completed" and index + _chapter_start == current_step - 1: _current_id = id
	_edges.clear()
	for id: String in _buttons:
		(_buttons[id] as MapNodeButton).graph_current = id == _current_id
		(_buttons[id] as MapNodeButton).queue_redraw()
	for step: Dictionary in _steps:
		for node: Dictionary in step.get("nodes", []):
			var from: String = String(node["id"])
			for raw_id: Variant in node.get("next_ids", []):
				var to: String = String(raw_id)
				if not _points.has(to): continue
				var start: Vector2 = _points[from] - Vector2(0, 34) * _density
				var end: Vector2 = _points[to] + Vector2(0, 34) * _density
				var middle: float = (start.y + end.y) * 0.5
				var points: PackedVector2Array = PackedVector2Array()
				for sample: int in 17: points.append(start.bezier_interpolate(Vector2(start.x, middle), Vector2(end.x, middle), end, float(sample) / 16.0))
				_edges.append({"from": from, "to": to, "points": points, "visited": node.get("status", "") == "completed" and _node_status(to) in ["completed", "selected"]})
	var entry: Vector2 = Vector2(size.x * 0.5, size.y - 22 * _density)
	for node: Dictionary in _steps[0].get("nodes", []):
		var target: String = String(node["id"])
		_edges.append({"from": "entry", "to": target, "points": PackedVector2Array([entry, _points[target] + Vector2(0, 34) * _density]), "visited": false})
	if not _traveling: _marker = _points.get(_current_id, entry)
	queue_redraw()


func _node_status(id: String) -> String:
	for step: Dictionary in _steps:
		for node: Dictionary in step.get("nodes", []):
			if String(node["id"]) == id: return String(node.get("status", ""))
	return ""


func _hover(id: String) -> void:
	_hover_id = id
	_highlighted.clear()
	var pending: Array[String] = [id] if id != "" else []
	while not pending.is_empty():
		var source: String = pending.pop_back()
		if _highlighted.has(source): continue
		_highlighted[source] = true
		for edge: Dictionary in _edges:
			if edge["from"] == source: pending.append(String(edge["to"]))
	queue_redraw()


func get_focus_y() -> float:
	var index: int = clampi(int(_map.get("current_step", 0)) - _chapter_start, 0, maxi(0, _steps.size() - 1))
	return 56.0 * _density + float(_steps.size() - 1 - index) * _pitch


func animate_travel(id: String) -> void:
	if _traveling or not _points.has(id): return
	_traveling = true
	var from: Vector2 = _marker
	var to: Vector2 = _points[id]
	var tween: Tween = create_tween()
	tween.tween_method(func(t: float) -> void:
		_marker = from.bezier_interpolate(Vector2(from.x, (from.y + to.y) * 0.5), Vector2(to.x, (from.y + to.y) * 0.5), to, t)
		queue_redraw(), 0.0, 1.0, 0.28).set_trans(Tween.TRANS_SINE)
	await tween.finished
	_traveling = false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("08151c"))
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.48)
	for radius: float in [size.x * 0.35, size.x * 0.45]:
		draw_arc(center, radius, 0, TAU, 96, Color(0.52, 0.65, 0.61, 0.065), 1, true)
	for tick: int in 24:
		var direction: Vector2 = Vector2.from_angle(float(tick) / 24.0 * TAU)
		draw_line(center + direction * size.x * 0.43, center + direction * size.x * 0.45, Color(0.73, 0.62, 0.38, 0.10), 2, true)
	for edge: Dictionary in _edges:
		var color: Color = Color("34464e")
		var width: float = 2.0 * _density
		if bool(edge["visited"]):
			color = Color("cda75b")
			width = 3.0 * _density
		elif _highlighted.has(String(edge["from"])) or ((_current_id == String(edge["from"]) or (_current_id == "" and edge["from"] == "entry")) and _node_status(String(edge["to"])) == "available"):
			color = Color("74cbd8")
			width = 3.0 * _density
		draw_polyline(edge["points"], Color(0, 0, 0, 0.5), width + 4 * _density, true)
		draw_polyline(edge["points"], color, width, true)
	for index: int in _steps.size():
		var y: float = 62.0 * _density + float(_steps.size() - 1 - index) * _pitch
		draw_string(UiTheme.GAME_FONT, Vector2(12 * _density, y), "%02d" % (_chapter_start + index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, ceili(13 * _density), Color("7c9298"))
	if _marker_visible:
		draw_circle(_marker, 15 * _density, Color(0.94, 0.72, 0.28, 0.18))
		draw_circle(_marker, 7 * _density, Color("f6cc69"))
		draw_arc(_marker, 11 * _density, 0, TAU, 24, Color("ffe5a1"), 1.5 * _density, true)
