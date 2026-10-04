extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _check(String(ProjectSettings.get_setting("display/window/stretch/aspect.web", "")) == "expand", "Web does not expand to browser aspect ratios"):
		return
	if not _check(get_window().content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "native resolution settings were changed"):
		return
	var font: FontFile = load("res://assets/fonts/NotoSansJP-GameSubset.ttf") as FontFile
	var automatic_text: String = Localization.get_text("settings.browser_resolution", "")
	for index: int in range(automatic_text.length()):
		if not _check(font.has_char(automatic_text.unicode_at(index)), "automatic resolution text has a missing glyph"):
			return
	var stage: BattleStage3D = BattleStage3D.new()
	stage.size = Vector2(960.0, 540.0)
	add_child(stage)
	var camera: Camera3D = stage.find_child("BattleStageCamera", true, false) as Camera3D
	if not _check(is_equal_approx(camera.fov, 40.0), "16:9 battle framing changed"):
		return
	stage.size = Vector2(960.0, 1280.0)
	await get_tree().process_frame
	if not _check(camera.fov > 70.0, "narrow battle framing did not expand vertically"):
		return
	stage.size = Vector2(1296.0, 540.0)
	await get_tree().process_frame
	if not _check(is_equal_approx(camera.fov, 40.0), "wide battle framing did not reset"):
		return
	stage.queue_free()
	print("RESPONSIVE_DISPLAY_SMOKE_OK Web expand, unchanged desktop, font, and camera framing")
	get_tree().quit()


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Responsive display smoke failed: %s" % message)
	get_tree().quit(1)
	return false
