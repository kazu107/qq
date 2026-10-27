extends Node

var _checks: int = 0
var _controller: SmoothWheelScroll


func _ready() -> void:
	Game.ensure_meta_initialized(); call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value: push_error("Smooth wheel: " + message); get_tree().quit(1); assert(value, message)


func _wheel(button: MouseButton = MOUSE_BUTTON_WHEEL_DOWN, factor: float = 1, shift: bool = false) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.pressed = true; event.button_index = button; event.factor = factor; event.shift_pressed = shift
	return event


func _run() -> void:
	var surface: Control = Control.new(); surface.size = Vector2(1000, 700); add_child(surface)
	var outer: ScrollContainer = ScrollContainer.new(); outer.size = Vector2(400, 300); surface.add_child(outer)
	var column: VBoxContainer = VBoxContainer.new(); column.custom_minimum_size = Vector2(380, 1800); outer.add_child(column)
	var inner: ScrollContainer = ScrollContainer.new(); inner.custom_minimum_size = Vector2(350, 180); column.add_child(inner)
	var contents: VBoxContainer = VBoxContainer.new(); contents.custom_minimum_size = Vector2(1200, 2400); inner.add_child(contents)
	var button: Button = Button.new(); button.text = "Scroll over a button"; contents.add_child(button)
	await get_tree().process_frame; await get_tree().process_frame
	_controller = SmoothWheelScroll.install(get_viewport()); _controller.cancel()
	_check(SmoothWheelScroll.install(get_viewport()) == _controller, "controller duplicated")
	var bar: ScrollBar = inner.get_v_scroll_bar(); var parent_bar: ScrollBar = outer.get_v_scroll_bar()
	var step: float = bar.page / 8
	_check(_controller.handle_wheel(button, _wheel()), "wheel over button was not handled")
	_check(bar.value == 0 and parent_bar.value == 0, "wheel jumped instantly")
	_controller._process(.04); _check(bar.value > 0 and bar.value < step, "missing intermediate movement")
	_controller._process(.12); _check(is_equal_approx(bar.value, step) and not _controller.is_processing(), "incorrect target or idle processing")
	_controller.handle_wheel(button, _wheel(MOUSE_BUTTON_WHEEL_DOWN, .5)); _controller.handle_wheel(button, _wheel(MOUSE_BUTTON_WHEEL_DOWN, .5))
	_controller._process(.16); _check(is_equal_approx(bar.value, step * 2), "fractional or repeated wheels were lost")
	_controller.animate(bar, inner, 300); _controller._process(.03)
	var before: float = bar.value
	_controller.handle_wheel(button, _wheel(MOUSE_BUTTON_WHEEL_UP)); _controller._process(.01)
	_check(bar.value < before, "reversal kept moving in old direction")
	_controller.cancel(); bar.value = 0
	_controller.handle_wheel(button, _wheel()); bar.value = 120; _controller._process(.16)
	_check(bar.value == 120 and not _controller.is_processing(), "programmatic jump was overridden")
	bar.value = bar.max_value - bar.page
	_check(_controller.handle_wheel(button, _wheel()), "edge did not chain to parent")
	_controller._process(.16); _check(parent_bar.value > 0, "parent did not scroll at child edge")
	_controller.cancel(); bar.value = 0
	inner.set_meta("wheel_scroll_step", 64.0); inner.set_meta("wheel_scroll_fixed_step", true)
	_controller.handle_wheel(button, _wheel(MOUSE_BUTTON_WHEEL_DOWN, 3.6)); _controller._process(.16)
	_check(is_equal_approx(bar.value, 64), "developer fixed wheel step changed")
	inner.remove_meta("wheel_scroll_step"); inner.remove_meta("wheel_scroll_fixed_step")
	_controller.cancel(); bar.value = 0
	_controller.handle_wheel(button, _wheel(MOUSE_BUTTON_WHEEL_DOWN, 1, true)); _controller._process(.16)
	_check(inner.get_h_scroll_bar().value > 0 and bar.value == 0, "Shift wheel did not scroll horizontally")
	_controller.handle_wheel(button, _wheel()); inner.hide(); _controller._process(.16)
	_check(bar.value == 0 and not _controller.is_processing(), "hidden cache kept scrolling")
	inner.show()
	for protected: Control in [SpinBox.new(), HSlider.new(), OptionButton.new()]:
		contents.add_child(protected)
		_check(not _controller.handle_wheel(protected, _wheel()), "wheel changed an input instead of preserving native behavior")
	var text: RichTextLabel = RichTextLabel.new(); text.size = Vector2(300, 160); text.position.x = 500
	text.text = "line\n".repeat(100); surface.add_child(text)
	var edit: TextEdit = TextEdit.new(); edit.size = Vector2(300, 160); edit.position = Vector2(500, 200)
	edit.text = "line\n".repeat(100); surface.add_child(edit)
	await get_tree().process_frame; await get_tree().process_frame
	_check(_controller.handle_wheel(text, _wheel()), "rich text not handled")
	_controller._process(.16); _check(is_equal_approx(text.get_v_scroll_bar().value, text.get_v_scroll_bar().page / 16), "rich text wheel amount changed")
	_check(_controller.handle_wheel(edit, _wheel()), "text editor not handled")
	_controller._process(.16); _check(is_equal_approx(edit.get_v_scroll_bar().value, 3), "text editor wheel amount changed")
	var log: LogPanel = LogPanel.new(); log.position = Vector2(500, 400); log.size = Vector2(300, 190); surface.add_child(log)
	var lines: Array[String] = []; for index: int in 100: lines.append("Log line %d" % index)
	log.refresh_logs(lines)
	await get_tree().process_frame; await get_tree().process_frame
	var log_text: RichTextLabel = log.get("_body_label") as RichTextLabel
	var log_bar: ScrollBar = log_text.get_v_scroll_bar()
	_controller.handle_wheel(log_text, _wheel(MOUSE_BUTTON_WHEEL_UP)); _controller._process(.04)
	lines.append("New log line"); log.refresh_logs(lines)
	await get_tree().process_frame
	_controller._process(.16)
	_check(is_equal_approx(log_bar.value, log_bar.max_value - log_bar.page), "wheel animation overrode the existing follow-log jump")
	bar.value = 0; _controller.animate(bar, inner, 50000); _controller._process(.16)
	_check(is_equal_approx(bar.value, bar.max_value - bar.page), "target overshot range")
	bar.value = 0; _controller.animate(bar, inner, 100)
	var click: InputEventMouseButton = InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	_controller._input(click); _controller._process(.16)
	_check(bar.value == 0 and not _controller.is_processing(), "drag did not cancel wheel")
	var popup: PopupPanel = PopupPanel.new(); add_child(popup)
	var popup_scroll: ScrollContainer = ScrollContainer.new(); popup.add_child(popup_scroll)
	await get_tree().process_frame; await get_tree().process_frame
	_check(popup.get_node_or_null(SmoothWheelScroll.NODE_NAME) != null, "popup viewport was not installed")
	bar.value = 0; _controller.animate(bar, inner, 100); outer.queue_free(); await get_tree().process_frame
	_controller._process(.16); _check(not _controller.is_processing(), "freed target leaked animation")
	popup.queue_free(); surface.queue_free(); await get_tree().process_frame
	print("SMOOTH_WHEEL_SMOKE_OK checks=%d interpolation/accumulation/fraction/reversal/nesting/horizontal/native-inputs/rich-text/edit/drag/hidden/freed/popup/idle" % _checks)
	get_tree().quit()
