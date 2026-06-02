extends Node

var _elapsed: float = 0.0
var _input_interval: float = 0.0
var _last_scene_name: String = ""


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.start_new_run("balanced")

	_prepare_hazard_path()
	if Game.get_active_facility_type() != "hazard":
		_fail("Hazard flow smoke failed: hazard node was not prepared")
		return
	if not Game.continue_hazard():
		_fail("Hazard flow smoke failed: could not enter hazard battle")
		return

	SceneRouter.go_to_battle()


func _process(delta: float) -> void:
	_elapsed += delta
	_input_interval -= delta

	if _elapsed > 120.0:
		_fail("Hazard flow smoke timed out")
		return

	var scene: Node = get_tree().current_scene
	if scene == null:
		return

	var scene_name: String = String(scene.name)
	if scene_name != _last_scene_name:
		print("Hazard flow scene: %s" % scene_name)
		_last_scene_name = scene_name

	match scene_name:
		"Battle":
			_process_battle(scene)
		"Facility":
			var hazard_status: Dictionary = Game.get_hazard_status()
			if Game.get_active_facility_type() != "hazard" or int(hazard_status.get("waves_cleared", 0)) != 1:
				_fail("Hazard flow smoke failed: battle did not return to hazard facility after the first wave")
				return
			print("Hazard flow smoke passed: returned to facility after wave 1")
			get_tree().quit()
		"Reward":
			_fail("Hazard flow smoke failed: hazard wave 1 should not route to reward")
		"RunResult":
			_fail("Hazard flow smoke failed: player lost the hazard battle")


func _process_battle(scene: Node) -> void:
	if _input_interval > 0.0:
		return
	_input_interval = 0.1

	var battle_screen: Control = scene as Control
	var engine: RealtimeBattleEngine = battle_screen.get("_engine") as RealtimeBattleEngine
	if engine == null or engine.battle_state == null:
		return

	var player: UnitState = engine.battle_state.player
	for runtime_state in player.get_sorted_runtime_states():
		if not runtime_state.can_use():
			continue
		var card_def: CardDef = Database.get_card(runtime_state.card_id)
		if card_def == null:
			continue
		if player.active_slots_used + card_def.active_slot_cost > player.active_slot_max:
			continue
		battle_screen.call("_on_card_requested", runtime_state.runtime_id)
		return


func _prepare_hazard_path() -> void:
	var battle_node: Dictionary = _find_available_node("normal_battle")
	if battle_node.is_empty():
		return
	if Game.select_map_node(String(battle_node.get("id", ""))) != "battle":
		return

	var enemy_id: String = Game.prepare_next_battle()
	if enemy_id == "":
		return
	Game.complete_battle(_build_victory_summary(enemy_id))
	Game.skip_reward()

	var facility_node: Dictionary = _find_first_available_node(["heal", "shop"])
	if facility_node.is_empty():
		return
	if Game.select_map_node(String(facility_node.get("id", ""))) != "facility":
		return
	Game.leave_facility()

	# Stabilize the smoke so it verifies scene routing rather than battle balance.
	Game.current_run.player_hp = Game.current_run.max_hp
	Game.current_run.attack += 4
	Game.current_run.speed += 2

	var hazard_node: Dictionary = _find_available_node("hazard")
	if hazard_node.is_empty():
		return
	Game.select_map_node(String(hazard_node.get("id", "")))


func _build_victory_summary(enemy_id: String) -> Dictionary:
	var enemy_def: EnemyDef = Database.get_enemy(enemy_id)
	var enemy_name: String = enemy_id
	if enemy_def != null:
		enemy_name = enemy_def.name
	return {
		"winner": "player",
		"enemy_id": enemy_id,
		"enemy_name": enemy_name,
		"player_hp": max(1, Game.current_run.player_hp - 1),
	}


func _find_available_node(node_type: String) -> Dictionary:
	var current_step: Dictionary = Game.get_current_step_data()
	var nodes: Array = Array(current_step.get("nodes", []))
	for raw_node in nodes:
		var node_data: Dictionary = Dictionary(raw_node)
		if String(node_data.get("type", "")) == node_type and String(node_data.get("status", "")) == "available":
			return node_data
	return {}


func _find_first_available_node(node_types: Array[String]) -> Dictionary:
	for node_type in node_types:
		var node_data: Dictionary = _find_available_node(node_type)
		if not node_data.is_empty():
			return node_data
	return {}


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
