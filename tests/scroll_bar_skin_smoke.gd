extends Control

var _checks: int = 0


func _ready() -> void:
	theme = UiTheme.get_game_theme()
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Scroll bar skin: " + message)
		get_tree().quit(1)
		assert(value, message)


func _fixture(content_size: Vector2) -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size = Vector2(300, 150)
	add_child(scroll)
	var body: Control = Control.new()
	body.custom_minimum_size = content_size
	scroll.add_child(body)
	return scroll


func _settle() -> void:
	for frame: int in 5:
		await get_tree().process_frame


func _run() -> void:
	var skin: Theme = UiTheme.get_game_theme()
	for orientation: String in ["v", "h"]:
		var type_name: String = "VScrollBar" if orientation == "v" else "HScrollBar"
		for style_name: String in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
			var style: StyleBoxTexture = skin.get_stylebox(style_name, type_name) as StyleBoxTexture
			_check(style != null and style.texture != null, "authored style missing: " + type_name + "/" + style_name)
			var state: String = "track" if style_name.begins_with("scroll") else style_name.trim_prefix("grabber_")
			_check(style.texture.resource_path == "res://assets/icons/controls/scrollbar_%s_%s.png" % [orientation, state], "wrong Blender texture")
			var minimum: Vector2 = style.get_minimum_size()
			_check(is_equal_approx(minimum.x if orientation == "v" else minimum.y, 14.0), "track and thumb must reserve a slim 14px input lane")
	var vertical: ScrollContainer = _fixture(Vector2(200, 1200))
	var horizontal: ScrollContainer = _fixture(Vector2(1400, 80))
	var both: ScrollContainer = _fixture(Vector2(1400, 1200))
	var short_list: ScrollContainer = _fixture(Vector2(200, 80))
	await _settle()
	_check(vertical.get_v_scroll_bar().visible and not vertical.get_h_scroll_bar().visible, "vertical overflow visibility")
	_check(is_equal_approx(vertical.get_v_scroll_bar().size.x, 14.0), "vertical bar must not allocate zero width")
	_check(horizontal.get_h_scroll_bar().visible and not horizontal.get_v_scroll_bar().visible, "horizontal overflow visibility")
	_check(is_equal_approx(horizontal.get_h_scroll_bar().size.y, 14.0), "horizontal bar must not allocate zero height")
	_check(both.get_v_scroll_bar().visible and both.get_h_scroll_bar().visible, "two-axis overflow visibility")
	_check(not short_list.get_v_scroll_bar().visible and not short_list.get_h_scroll_bar().visible, "short lists must not show unnecessary bars")
	vertical.get_v_scroll_bar().value = 100
	_check(vertical.scroll_vertical == 100, "direct bar input must update scroll position")
	var text: RichTextLabel = RichTextLabel.new()
	text.size = Vector2(300, 150)
	text.text = "Long battle log\n".repeat(100)
	add_child(text)
	await _settle()
	_check(text.get_v_scroll_bar().visible and is_equal_approx(text.get_v_scroll_bar().size.x, 14.0), "rich text log scrollbar")
	var popup: PopupPanel = PopupPanel.new()
	add_child(popup)
	var popup_scroll: ScrollContainer = ScrollContainer.new()
	popup_scroll.custom_minimum_size = Vector2(300, 150)
	popup.add_child(popup_scroll)
	var tall: Control = Control.new()
	tall.custom_minimum_size = Vector2(200, 1200)
	popup_scroll.add_child(tall)
	popup.popup_centered(Vector2i(340, 200))
	await _settle()
	_check(popup_scroll.get_v_scroll_bar().theme == skin and popup_scroll.get_v_scroll_bar().visible, "native popup must receive the same skin")
	popup.hide()
	for scroll: ScrollContainer in [vertical, horizontal, both]:
		var bar: ScrollBar = scroll.get_v_scroll_bar() if scroll == vertical else scroll.get_h_scroll_bar()
		var original: StyleBox = bar.get_theme_stylebox("grabber")
		bar.value += 20
		_check(bar.get_theme_stylebox("grabber") == original, "scrolling must reuse style resources")
	print("SCROLL_BAR_SKIN_SMOKE_OK checks=%d Blender/textures/14px/overflow/both-axes/short-list/log/popup/cache" % _checks)
	get_tree().quit()
