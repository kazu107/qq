extends Node
class_name SmoothWheelScroll

const NODE_NAME := "SmoothWheelScroll"
const DURATION: float = 0.16
var _motions: Dictionary = {}


static func install(viewport: Viewport) -> SmoothWheelScroll:
	var existing: SmoothWheelScroll = viewport.get_node_or_null(NODE_NAME) as SmoothWheelScroll
	if existing != null: return existing
	var controller: SmoothWheelScroll = SmoothWheelScroll.new()
	controller.name = NODE_NAME
	viewport.add_child(controller)
	return controller


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var wheel: InputEventMouseButton = event as InputEventMouseButton
		if wheel.pressed and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			if wheel.ctrl_pressed or wheel.meta_pressed or wheel.alt_pressed: return
			if handle_wheel(get_viewport().gui_get_hovered_control(), wheel): get_viewport().set_input_as_handled()
		elif wheel.pressed: cancel()
	elif event is InputEventKey and event.pressed or event is InputEventPanGesture or event is InputEventScreenTouch or event is InputEventScreenDrag:
		cancel()


func handle_wheel(hovered: Control, event: InputEventMouseButton) -> bool:
	if not event.pressed or event.factor <= 0 or event.ctrl_pressed or event.meta_pressed or event.alt_pressed: return false
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]: return false
	var direction: float = -1.0 if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1.0
	var horizontal: bool = (event.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]) != event.shift_pressed
	var node: Node = hovered
	while node is Control:
		if node is SpinBox or node is Slider or node is OptionButton: return false
		if node is ScrollBar:
			var bar: ScrollBar = node as ScrollBar
			if _can_move(bar, direction): return animate(bar, node as Control, direction * _step(node, bar, node is HScrollBar) * event.factor)
		elif node is ScrollContainer or node is RichTextLabel or node is TextEdit or node is ItemList:
			var axes: Array[bool] = [horizontal, not horizontal]
			if node is RichTextLabel:
				axes.clear()
				if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: axes.append(false)
			for axis: bool in axes:
				var bar: ScrollBar = _bar(node as Control, axis)
				if bar == null or bar.max_value - bar.page <= bar.min_value: continue
				if _can_move(bar, direction):
					var factor: float = 1.0 if node.get_meta("wheel_scroll_fixed_step", false) else event.factor
					return animate(bar, node as Control, direction * _step(node, bar, axis) * factor)
				break
		# Do not continue into a different viewport or a behind-the-window control.
		node = node.get_parent()
	return false


func _bar(control: Control, horizontal: bool) -> ScrollBar:
	if control is ScrollContainer:
		var scroll: ScrollContainer = control as ScrollContainer
		if (scroll.horizontal_scroll_mode if horizontal else scroll.vertical_scroll_mode) == ScrollContainer.SCROLL_MODE_DISABLED: return null
	if control is RichTextLabel and not (control as RichTextLabel).scroll_active: return null
	var method: String = "get_h_scroll_bar" if horizontal else "get_v_scroll_bar"
	return control.call(method) as ScrollBar if control.has_method(method) else null


func _step(owner: Node, bar: ScrollBar, horizontal: bool) -> float:
	if owner.has_meta("wheel_scroll_step"): return float(owner.get_meta("wheel_scroll_step"))
	if owner is TextEdit: return 100.0 if horizontal else 3.0
	return maxf(bar.step, bar.page / (16.0 if owner is RichTextLabel else 8.0))


func _can_move(bar: ScrollBar, direction: float) -> bool:
	var edge: float = maxf(bar.min_value, bar.max_value - bar.page)
	return bar.value < edge - 0.001 if direction > 0 else bar.value > bar.min_value + 0.001


func animate(bar: ScrollBar, owner: Control, amount: float) -> bool:
	var id: int = bar.get_instance_id()
	var current: float = bar.value
	var motion: Dictionary = Dictionary(_motions.get(id, {}))
	var base: float = current
	if not motion.is_empty() and is_equal_approx(current, float(motion["last"])) and signf(float(motion["target"]) - current) == signf(amount): base = float(motion["target"])
	var target: float = clampf(base + amount, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
	if not motion.is_empty() and is_equal_approx(target, float(motion["target"])): return true
	if is_equal_approx(target, current): return false
	_motions[id] = {"bar": weakref(bar), "owner": weakref(owner), "from": current, "target": target, "last": current, "elapsed": 0.0}
	set_process(true)
	return true


func _process(delta: float) -> void:
	for id: int in _motions.keys():
		var motion: Dictionary = _motions[id]
		var bar: ScrollBar = motion["bar"].get_ref() as ScrollBar
		var owner: Control = motion["owner"].get_ref() as Control
		if bar == null or owner == null or not owner.is_inside_tree() or not owner.is_visible_in_tree():
			_motions.erase(id); continue
		# A map focus jump, filter reset, follow-log update or drag takes precedence.
		if not is_equal_approx(bar.value, float(motion["last"])):
			_motions.erase(id); continue
		motion["elapsed"] = float(motion["elapsed"]) + delta
		var ratio: float = clampf(float(motion["elapsed"]) / DURATION, 0, 1)
		var target: float = clampf(float(motion["target"]), bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
		bar.value = lerpf(float(motion["from"]), target, 1.0 - pow(1.0 - ratio, 3.0))
		bar.scrolling.emit()
		motion["last"] = bar.value
		if ratio >= 1.0: _motions.erase(id)
	set_process(not _motions.is_empty())


func cancel() -> void:
	_motions.clear()
	set_process(false)
