extends Node

var _elapsed: float = 0.0
var _input_interval: float = 0.0
var _battle_seen: bool = false
var _last_scene_name: String = ""


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.start_new_run("balanced")

	var battle_node: Dictionary = _find_available_node("normal_battle")
	if battle_node.is_empty():
		_fail("Flow smoke failed: no available normal battle node found")
		return
	if Game.select_map_node(String(battle_node.get("id", ""))) != "battle":
		_fail("Flow smoke failed: selecting a battle node did not route to battle")
		return

	# Keep this smoke focused on transition correctness instead of encounter balance variance.
	Game.current_run.player_hp = Game.current_run.max_hp
	Game.current_run.attack += 2
	Game.current_run.speed += 1

	SceneRouter.go_to_battle()


func _process(delta: float) -> void:
	_elapsed += delta
	_input_interval -= delta

	if _elapsed > 60.0:
		_fail("Flow smoke timed out")
		return

	var scene: Node = get_tree().current_scene
	if scene == null:
		return

	var scene_name: String = String(scene.name)
	if scene_name != _last_scene_name:
		print("Flow smoke scene: %s" % scene_name)
		_last_scene_name = scene_name

	match scene_name:
		"Battle":
			_process_battle(scene)
		"Reward":
			if not _battle_seen:
				_fail("Flow smoke failed: reached reward without completing a battle")
				return
			print("Flow smoke passed: reached Reward after opening battle from map")
			get_tree().quit()
		"RunResult":
			_fail("Flow smoke failed: battle flow reached RunResult instead of Reward")


func _process_battle(scene: Node) -> void:
	if _input_interval > 0.0:
		return
	_input_interval = 0.1

	var battle_screen: Control = scene as Control
	var engine: RealtimeBattleEngine = battle_screen.get("_engine") as RealtimeBattleEngine
	if engine == null or engine.battle_state == null:
		return
	if engine.battle_state.winner != "":
		return

	_battle_seen = true
	battle_screen.call("_on_dev_force_victory")


func _find_available_node(node_type: String) -> Dictionary:
	var current_step: Dictionary = Game.get_current_step_data()
	var nodes: Array = Array(current_step.get("nodes", []))
	for raw_node in nodes:
		var node_data: Dictionary = Dictionary(raw_node)
		if String(node_data.get("type", "")) == node_type and String(node_data.get("status", "")) == "available":
			return node_data
	return {}


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
