extends VBoxContainer
class_name LogPanel

var _title_label: Label
var _body_label: RichTextLabel


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 188.0)

	_title_label = Label.new()
	_title_label.text = Localization.get_text("battle.log", "Battle Log")
	add_child(_title_label)

	_body_label = RichTextLabel.new()
	_body_label.name = "BattleLogText"
	_body_label.fit_content = false
	_body_label.scroll_following = true
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.custom_minimum_size = Vector2(0.0, 112.0)
	add_child(_body_label)


func refresh_logs(logs: Array[String]) -> void:
	_body_label.text = "\n".join(logs)
