extends PanelContainer
class_name Tooltip

var _label := Label.new()


func _ready() -> void:
	add_child(_label)


func set_text(value: String) -> void:
	_label.text = value
