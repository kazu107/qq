extends HBoxContainer
class_name RelicIconRow

var _icon_size: Vector2 = Vector2(48.0, 48.0)


func _ready() -> void:
	add_theme_constant_override("separation", 8)


func set_icon_size(size: Vector2) -> void:
	_icon_size = size


func refresh_relic_ids(relic_ids: Array[String], empty_text: String = "") -> void:
	_clear()
	if relic_ids.is_empty():
		if empty_text != "":
			var empty_label: Label = Label.new()
			empty_label.name = "RelicIconRowEmpty"
			empty_label.text = empty_text
			add_child(empty_label)
		return

	for relic_id in relic_ids:
		var icon: RelicIcon = RelicIcon.new()
		icon.set_icon_size(_icon_size)
		icon.bind_relic_id(relic_id)
		add_child(icon)


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
