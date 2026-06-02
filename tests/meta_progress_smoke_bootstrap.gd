extends Node


func _ready() -> void:
	var driver_script: Script = load("res://tests/meta_progress_smoke.gd")
	var driver: Node = Node.new()
	driver.set_script(driver_script)
	get_tree().root.add_child.call_deferred(driver)
	queue_free()
