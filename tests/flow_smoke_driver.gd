extends Node

var _elapsed: float = 0.0
var _input_interval: float = 0.0
var _battle_seen: bool = false
var _analysis_seen: bool = false
var _last_scene_name: String = ""


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.start_new_run("balanced", 4242)

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
		var battle: Node = get_tree().current_scene
		var context: String = "scene=%s" % (battle.name if battle != null else "none")
		if battle != null and battle.name == "Battle":
			var panel: Control = battle.get("_analysis_panel") as Control
			context += " pending_fields=%d analysis=%s" % [Dictionary(battle.get("_pending_result")).size(), panel.visible if panel != null else false]
		_fail("Flow smoke timed out: " + context)
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
			if not _battle_seen or not _analysis_seen:
				_fail("Flow smoke failed: reached reward without battle and result confirmation")
				return
			print("Flow smoke passed: Map -> Battle -> completed victory/defeat presentation -> result Continue -> Reward")
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
	var panel: Control = battle_screen.get("_analysis_panel") as Control
	if panel != null and panel.visible and not _analysis_seen:
		var stage: BattleStage3D = battle_screen.get("_battle_stage") as BattleStage3D
		if stage == null or not stage.has_battle_end_presentation_finished():
			_fail("Flow smoke failed: result UI appeared before battle-end presentation finished")
			return
		var next: Button = panel.find_child("BattleContinueButton", true, false) as Button
		if next == null or next.disabled or not next.is_visible_in_tree():
			_fail("Flow smoke failed: result Continue button is unavailable")
			return
		_analysis_seen = true
		print("Flow smoke: result visible after presentation; pressing Continue")
		next.pressed.emit()
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
