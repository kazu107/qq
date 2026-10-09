extends Node

var _window: JavaScriptObject
var _bridge: JavaScriptObject
var _sequence: int = 0
var _pending_frames: int = 0


func _ready() -> void:
	_window = JavaScriptBridge.get_interface("window")
	_bridge = JavaScriptBridge.create_callback(_command)
	_window.qqLayoutCommand = _bridge
	call_deferred("_start_boot")


func _start_boot() -> void:
	var previous: Node = get_tree().current_scene
	get_tree().current_scene = null
	reparent(SceneRouter)
	var boot: Control = load("res://scenes/boot/Boot.tscn").instantiate() as Control
	get_tree().root.add_child(boot)
	get_tree().current_scene = boot
	if previous != null and previous != self:
		previous.queue_free()


func _command(arguments: Array) -> void:
	var payload: Dictionary = JSON.parse_string(String(arguments[0]))
	_sequence = int(payload.get("sequence", 0))
	if String(payload.get("action", "")) == "screen":
		_open_screen(String(payload.get("screen", "hub")))
	elif String(payload.get("action", "")) == "battle_simulate":
		_simulate_battle_result()
	_pending_frames = 8


func _simulate_battle_result() -> void:
	var screen: Control = get_tree().current_scene as Control
	if screen == null or screen.scene_file_path != "res://scenes/battle/Battle.tscn":
		return
	var engine: RealtimeBattleEngine = screen.get("_engine")
	engine.set_audio_enabled(false)
	var bot: EnemyAI = EnemyAI.new()
	bot.side = "player"
	engine.start_battle()
	for index: int in range(5000):
		bot.update(engine, 0.05)
		engine.update(0.05)
		if engine.battle_state.winner != "":
			break


func _open_screen(screen: String) -> void:
	Game.clear_battle_tutorial()
	Game.settings["developer_mode"] = false
	Game.meta_progress["infinite_mode_unlocked"] = screen == "hub_infinite"
	match screen:
		"hub": SceneRouter.go_to_hub()
		"hub_continue":
			Game.start_new_run("balanced", 4242)
			Game.stash_active_run_for_hub()
			Game.start_arena_run("balanced")
			Game.stash_active_run_for_hub()
			SceneRouter.go_to_hub()
		"hub_developer":
			Game.settings["developer_mode"] = true
			SceneRouter.go_to_hub()
		"hub_infinite": SceneRouter.go_to_hub()
		"settings": SceneRouter.go_to_settings()
		"setup": SceneRouter.go_to_run_setup()
		"arena_setup": SceneRouter.go_to_run_setup(Game.RUN_SETUP_MODE_ARENA)
		"meta": SceneRouter.go_to_meta_progress()
		"library": SceneRouter.go_to_card_library()
		"tutorials": SceneRouter.go_to_battle_tutorial()
		"online": SceneRouter.go_to_online_lobby()
		"map":
			Game.start_new_run("balanced", 4242)
			SceneRouter.go_to_map()
		"arena":
			Game.start_arena_run("balanced")
			SceneRouter.go_to_arena()
		"battle":
			Game.start_new_run("balanced", 4242)
			Game.developer_open_battle("scout")
			SceneRouter.go_to_battle()
		"reward":
			Game.start_new_run("balanced", 4242)
			Game.developer_open_reward()
			SceneRouter.go_to_reward()
		"event":
			Game.start_new_run("balanced", 4242)
			Game.developer_open_event("salvage_cache")
			SceneRouter.go_to_facility()
		"result":
			Game.start_new_run("balanced", 4242)
			Game.developer_open_result()
			SceneRouter.go_to_result()


func _process(_delta: float) -> void:
	if _pending_frames <= 0:
		return
	_pending_frames -= 1
	if _pending_frames == 0:
		_window.qqLayoutState = JSON.stringify(_inspect())


func _inspect() -> Dictionary:
	var screen: Control = get_tree().current_scene as Control
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var controls: Array[Dictionary] = []
	if screen != null:
		_collect_controls(screen, controls, false)
	var result: Dictionary = {
		"sequence": _sequence,
		"screen": screen.scene_file_path.get_file().get_basename() if screen != null else "",
		"viewport": [viewport_rect.size.x, viewport_rect.size.y],
		"window": [get_window().size.x, get_window().size.y],
		"aspect": get_window().content_scale_aspect,
		"controls": controls,
	}
	if screen != null:
		var deck: CardHandPanel = screen.find_child("EquippedDeck", true, false) as CardHandPanel
		if deck == null:
			deck = screen.find_child("ArenaEquippedDeck", true, false) as CardHandPanel
		if deck != null:
			var cards: Array[Dictionary] = []
			for card: CardButton in deck._buttons:
				if not card.visible:
					continue
				var remove: Button = card.get_node_or_null("DeckUnequipButton") as Button
				cards.append({"id": card.runtime_id, "rect": _rect_values(card.get_global_rect()), "close": remove.visible if remove != null else false,
					"close_rect": _rect_values(remove.get_global_rect()) if remove != null else [], "disabled": remove.disabled if remove != null else true})
			var rows: Array[Dictionary] = []
			var inventory: VBoxContainer = screen.get("_inventory_box") as VBoxContainer
			for frame: Control in inventory.get_children():
				var actions: HBoxContainer = frame.find_child("*LoadoutActions*", true, false) as HBoxContainer
				if actions != null:
					rows.append({"name": String(frame.name), "rect": _rect_values(frame.get_global_rect()), "actions": actions.visible,
						"buttons": actions.get_child_count(), "equip_rect": _rect_values((actions.get_child(0) as Control).get_global_rect())})
			result["loadout"] = {"cards": cards, "rows": rows}
		if screen.scene_file_path.get_file().get_basename() == "CardLibrary":
			var search: LineEdit = screen.find_child("LibrarySearch", true, false) as LineEdit
			var empty: Label = screen.find_child("LibraryEmptyNotice", true, false) as Label
			result["library"] = {"cards": Dictionary(screen.get("_card_widgets")).keys(), "search": search.text, "empty": empty.visible}
		elif screen.scene_file_path.get_file().get_basename() == "OnlineLobby":
			result["lobby"] = {"connected": NetworkManager.is_session_connected(), "capacity": NetworkManager.get_player_capacity()}
		var stage: BattleStage3D = screen.find_child("BattleStage3D", true, false) as BattleStage3D
		if stage != null:
			var player_status: BattleUnitStatus3D = stage.get_player_status_model()
			var enemy_status: BattleUnitStatus3D = stage.get_enemy_status_model()
			result["battle"] = {
				"field": _rect_values(stage.get_global_rect()),
				"player_status": _point_values(stage.project_world_position(player_status.global_position)),
				"enemy_status": _point_values(stage.project_world_position(enemy_status.global_position)),
				"status_corners": _project_status_corners(stage, player_status) + _project_status_corners(stage, enemy_status),
			}
			var outcome: BattleResultAnalysisPanel = screen.find_child("BattleResultAnalysisPanel", true, false) as BattleResultAnalysisPanel
			if outcome != null:
				result["outcome"] = {"visible": outcome.visible, "details": outcome._details_modal.visible, "title": outcome._title.text,
					"finished": stage.has_battle_end_presentation_finished(), "samples": outcome._hp_chart._samples.size()}
	return result


func _project_status_corners(stage: BattleStage3D, status: BattleUnitStatus3D) -> Array[Array]:
	var corners: Array[Array] = []
	for x_sign: float in [-1.0, 1.0]:
		for y_sign: float in [-1.0, 1.0]:
			var world: Vector3 = status.to_global(Vector3(BattleUnitStatus3D.PANEL_SIZE.x * x_sign * 0.5, BattleUnitStatus3D.PANEL_SIZE.y * y_sign * 0.5, 0.0))
			corners.append(_point_values(stage.global_position + stage.project_world_position(world)))
	return corners


func _collect_controls(node: Node, controls: Array[Dictionary], in_scroll: bool) -> void:
	var control: Control = node as Control
	if control != null and (not control.is_visible_in_tree() or control.get_viewport() != get_viewport()):
		return
	var scrolling: bool = in_scroll or node is ScrollContainer
	if control != null and (control is Container or control is BaseButton or control is LineEdit or control is SpinBox):
		controls.append({
			"name": String(control.name), "class": control.get_class(),
			"rect": _rect_values(control.get_global_rect()), "scroll": scrolling,
		})
	for child: Node in node.get_children():
		_collect_controls(child, controls, scrolling)


func _rect_values(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _point_values(point: Vector2) -> Array[float]:
	return [point.x, point.y]
