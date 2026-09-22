extends Node

const WARMUP: GDScript = preload("res://src/core/services/StartupWarmupService.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	if OS.get_environment("QQ_PROFILE_WARM") == "1":
		await WARMUP.warm_all_async()
	for iteration: int in range(2):
		Game.begin_battle_tutorial("battle_basics")
		var start_us: int = Time.get_ticks_usec()
		var scene: PackedScene = load("res://scenes/battle/Battle.tscn") as PackedScene
		var loaded_us: int = Time.get_ticks_usec()
		var battle: Node = scene.instantiate()
		var instantiated_us: int = Time.get_ticks_usec()
		add_child(battle)
		var added_us: int = Time.get_ticks_usec()
		await get_tree().process_frame
		var first_frame_us: int = Time.get_ticks_usec()
		await get_tree().process_frame
		var second_frame_us: int = Time.get_ticks_usec()
		var stage: BattleStage3D = battle.get("_battle_stage") as BattleStage3D
		print("BATTLE_LOAD_PROFILE %s" % JSON.stringify({
			"warm": OS.get_environment("QQ_PROFILE_WARM") == "1",
			"iteration": iteration,
			"load_ms": (loaded_us - start_us) / 1000.0,
			"instantiate_ms": (instantiated_us - loaded_us) / 1000.0,
			"add_ms": (added_us - instantiated_us) / 1000.0,
			"first_frame_ms": (first_frame_us - added_us) / 1000.0,
			"second_frame_ms": (second_frame_us - first_frame_us) / 1000.0,
			"stage_id": stage.get_instance_id(),
		}))
		SceneRouter.call("_store_battle_stage", battle.call("detach_battle_stage_for_cache"))
		battle.queue_free()
		await get_tree().process_frame
		Game.clear_battle_tutorial()
	get_tree().quit()
