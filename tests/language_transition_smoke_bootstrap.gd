extends Node


func _ready() -> void:
	var driver: Node = Node.new()
	driver.set_script(load("res://tests/language_transition_smoke.gd"))
	get_tree().root.add_child.call_deferred(driver)
	queue_free()
