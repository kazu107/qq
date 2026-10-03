extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	var boot: Control = load("res://scenes/boot/Boot.tscn").instantiate() as Control
	boot.call("_build_loading_screen")
	var content: Control = boot.find_child("BootLoadingContent", true, false) as Control
	var progress_bar: ProgressBar = boot.find_child("BootLoadingProgress", true, false) as ProgressBar
	var percent_label: Label = boot.find_child("BootLoadingPercent", true, false) as Label
	boot.call("_set_loading_status", "Preparing", 0.5)
	if not _check(percent_label.text == "50%" and is_equal_approx(progress_bar.value, 0.5), "progress text and bar did not agree"):
		boot.free()
		return
	boot.call("_set_loading_status", "Late callback", 0.2)
	if not _check(percent_label.text == "50%", "progress went backwards"):
		boot.free()
		return
	boot.call("_set_loading_status", "Prepared", 1.0)
	if not _check(percent_label.text == "99%", "100% was shown before Hub rendering"):
		boot.free()
		return
	boot.remove_child(content)
	add_child(content)
	boot.free()
	SceneRouter.retain_boot_loading_overlay(content)
	var logo: LoadingLogo = content.find_child("BootLoadingLogo", true, false) as LoadingLogo
	if not _check(logo != null and logo.find_child("card-front", true, false) != null, "native SVG layers were not created"):
		return
	await get_tree().create_timer(0.8).timeout
	var front_card: TextureRect = logo.find_child("card-front", true, false) as TextureRect
	if not _check(is_equal_approx(front_card.modulate.a, 1.0) and front_card.position.is_zero_approx(), "native logo entry did not settle"):
		return
	var initial_phase: float = float(logo.get("_light_phase"))
	await get_tree().create_timer(0.3).timeout
	var phase_advance: float = float(logo.get("_light_phase")) - initial_phase
	if not _check(phase_advance > 0.13 and phase_advance < 0.18, "native timeline light did not use a two-second loop"):
		return
	# Keep the probe alive while the real scene swap frees the old Boot scene.
	get_tree().current_scene = null
	reparent(SceneRouter)
	SceneRouter.go_to_hub()
	await get_tree().create_timer(0.55).timeout
	if not _check(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == SceneRouter.HUB_SCENE, "Hub was not behind the completion overlay"):
		return
	if not _check(is_instance_valid(content) and content.modulate.a > 0.0 and content.modulate.a < 1.0, "completion did not gradually fade"):
		return
	if not _check(percent_label.text == "100%" and is_equal_approx(progress_bar.value, 1.0), "completion did not display 100%"):
		return
	if not _check(not logo.is_processing(), "completion did not stop the waiting loop"):
		return
	await get_tree().create_timer(0.8).timeout
	if not _check(not is_instance_valid(content) and SceneRouter.find_child("BootCompletionLayer", true, false) == null, "completion overlay was not cleaned up"):
		return
	print("BOOT_LOADING_SMOKE_OK progress, rendered Hub, fade, and cleanup")
	get_tree().quit()


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Boot loading smoke failed: %s" % message)
	get_tree().quit(1)
	return false
