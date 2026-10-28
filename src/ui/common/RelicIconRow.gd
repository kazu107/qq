extends HBoxContainer
class_name RelicIconRow

var _icon_size: Vector2 = Vector2(48.0, 48.0)
var _icons: Array[RelicIcon] = []
var _empty_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)


func set_icon_size(size: Vector2) -> void:
	if _icon_size == size:
		return
	_icon_size = size
	for icon: RelicIcon in _icons:
		icon.set_icon_size(size)


func refresh_relic_ids(relic_ids: Array[String], empty_text: String = "") -> void:
	# Keep the controls alive: this row is refreshed on every battle frame.
	while _icons.size() > relic_ids.size():
		var removed: RelicIcon = _icons.pop_back()
		remove_child(removed)
		removed.queue_free()
	if _empty_label != null:
		_empty_label.visible = relic_ids.is_empty() and empty_text != ""
		_empty_label.text = empty_text
	if relic_ids.is_empty():
		if empty_text != "" and _empty_label == null:
			_empty_label = Label.new()
			_empty_label.name = "RelicIconRowEmpty"
			_empty_label.text = empty_text
			add_child(_empty_label)
		return

	for index: int in relic_ids.size():
		if index == _icons.size():
			var icon: RelicIcon = RelicIcon.new()
			icon.set_icon_size(_icon_size)
			_icons.append(icon)
			add_child(icon)
		_icons[index].bind_relic_id(relic_ids[index])
