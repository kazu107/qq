extends Node

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)


func _run() -> void:
	Database.load_all()
	var run: RunState = RunState.new()
	run.map_state = {"current_step": 0}
	for step: int in 84:
		run.map_state["current_step"] = step
		run.infinite_mode = true
		var before: String = JSON.stringify(run.to_dict())
		var context: Dictionary = BattleEnvironmentArt.get_context(run, "scout_ascended")
		_check(context["id"] == BattleEnvironmentArt.REGIONS[(step % 28) / 7], "Incorrect regional field at %d" % step)
		_check(context["infinite"] == (step >= 28), "Incorrect Infinite preset")
		_check(before == JSON.stringify(run.to_dict()), "Visual selection modified progress")
	for enemy_id: String in BattleEnvironmentArt.BOSSES:
		_check(BattleEnvironmentArt.get_context(run, enemy_id)["id"] == BattleEnvironmentArt.BOSSES[enemy_id], "Missing boss field")
		_check(BattleEnvironmentArt.get_context(run, enemy_id + "_ascended")["id"] == BattleEnvironmentArt.BOSSES[enemy_id], "Missing ascended boss field")
	_check(BattleEnvironmentArt.get_context(run, "boss_timekeeper", true) == {"id":"clock_ruins", "infinite":false}, "Tutorial field must remain stable")
	run.arena_mode = true
	run.infinite_mode = false
	for round_number: int in range(1, 25):
		run.arena_round = round_number
		_check(BattleEnvironmentArt.get_context(run, "boss_timekeeper")["id"] == BattleEnvironmentArt.REGIONS[((round_number-1)/3)%4], "Arena field must follow round, not opponent or POV")
	var warmed: int = await BattleEnvironmentArt.warm_biomes_async(get_tree())
	_check(warmed == 12, "Expected eight cached fields and four overlays")
	var stage: BattleStage3D = BattleStage3D.new()
	add_child(stage)
	await get_tree().process_frame
	stage.configure_combatants("player", "scout", "player", "balanced", "scout")
	var actor: Node3D = stage.find_child("PlayerBattleActor3D", true, false) as Node3D
	var actor_transform: Transform3D = actor.transform
	var camera: Camera3D = stage.get("_camera") as Camera3D
	var camera_transform: Transform3D = camera.transform
	var original_scene: PackedScene = BattleEnvironmentArt.get_scene("clock_ruins")
	for field: Dictionary in BattleEnvironmentArt.FIELDS:
		for variant: bool in [false, true, false]:
			var id: String = String(field["id"])
			stage.configure_environment(id, variant)
			_check(stage.get_environment_context()["id"] == id, "Field failed to switch: " + id)
			_check(stage.get_environment_context()["infinite"] == variant, "Variant failed to reset")
			_check(actor.transform == actor_transform and camera.transform == camera_transform, "Scenery moved actors/camera")
			var active: Node3D = (stage.get("_field_cache") as Dictionary)[id] as Node3D
			_check(active.visible, "Active field hidden")
			for name: String in ["ArenaTiles", "ArenaBase", "BattleWorldGround", "ArenaLaneLines"]:
				_check(active.find_child(name, true, false) != null, "Missing shared board geometry")
			var ground: MeshInstance3D = active.find_child("BattleWorldGround", true, false) as MeshInstance3D
			_check(ground.get_aabb().size.x >= 42.0 and ground.get_aabb().size.z >= 38.0, "Ground does not cover the viewport")
	stage.configure_environment("clock_ruins", false)
	var instance_id: int = ((stage.get("_field_cache") as Dictionary)["clock_ruins"] as Node3D).get_instance_id()
	stage.configure_environment("paradox_reactor", true)
	stage.configure_environment("clock_ruins", false)
	_check(((stage.get("_field_cache") as Dictionary)["clock_ruins"] as Node3D).get_instance_id() == instance_id, "Repeated transitions rebuilt field nodes")
	_check(BattleEnvironmentArt.get_scene("clock_ruins") == original_scene, "PackedScene cache was not retained")
	stage.suspend_for_cache()
	var ambient: float = stage.get("_ambient_time")
	for index: int in 3: await get_tree().process_frame
	_check(is_equal_approx(float(stage.get("_ambient_time")), ambient), "Cached field animation kept running")
	stage.resume_from_cache()
	for region: String in BattleEnvironmentArt.REGIONS:
		for facility: String in ["shop", "forge", "heal"]:
			_check(ArtCatalog.get_texture(BattleEnvironmentArt.BACKGROUND_ROOT + region + "_" + facility + ".png") != null, "Facility render missing")
	stage.queue_free()
	Game.settings["developer_mode"] = true
	var lab: Control = load("res://scenes/debug/BattleAnimationLab.tscn").instantiate() as Control
	add_child(lab)
	for index: int in 2: await get_tree().process_frame
	var selector: OptionButton = lab.find_child("BattleEnvironmentSelect", true, false) as OptionButton
	var toggle: CheckButton = lab.find_child("BattleEnvironmentInfinite", true, false) as CheckButton
	var lab_stage: BattleStage3D = lab.get("_stage") as BattleStage3D
	_check(selector.item_count == 8, "Developer selector did not expose all fields")
	selector.select(7)
	selector.item_selected.emit(7)
	toggle.button_pressed = true
	_check(lab_stage.get_environment_context()["id"] == "eternity_temple" and lab_stage.get_environment_context()["infinite"], "Developer controls did not update the 3D field")
	lab.queue_free()
	if not _failures.is_empty():
		for message: String in _failures: push_error(message)
		get_tree().quit(1)
		return
	print("BATTLE_BIOMES_SMOKE_OK: 84 steps, arena, bosses, 16 appearances, 12 facility backgrounds, cache/pause/layout invariants")
	get_tree().quit()
