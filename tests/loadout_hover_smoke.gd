extends Node

var _failures: Array[String] = []


func _ready() -> void:
	Database.load_all()
	Game.settings["developer_mode"] = false
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	for arena: bool in [false, true]:
		if arena:
			Game.start_arena_run("balanced")
		else:
			Game.start_new_run("balanced", 4242)
		Game.current_run.player_cards = ["quick_slash", "quick_slash", "strike"]
		Game.current_run.equipped_cards = Game.current_run.player_cards.duplicate()
		var screen: Control = load("res://scenes/arena/Arena.tscn" if arena else "res://scenes/map/Map.tscn").instantiate() as Control
		add_child(screen)
		await get_tree().process_frame
		await get_tree().process_frame
		var panel: CardHandPanel = screen.find_child("ArenaEquippedDeck" if arena else "EquippedDeck", true, false) as CardHandPanel
		var card: CardButton = panel._buttons[1]
		var remove: Button = card.get_node("DeckUnequipButton") as Button
		var reveal: HoverActionReveal = card.get_node("HoverActionReveal") as HoverActionReveal
		_check(not remove.visible, "Deck close button must start hidden")
		reveal.update_for_control(card)
		_check(remove.visible and not remove.disabled, "Deck hover must reveal a usable close button")
		reveal.update_for_control(remove)
		_check(remove.visible, "Close button must not flicker when it becomes the hovered control")
		_check(card.get_art_rect().encloses(remove.get_rect()), "Close button must be inside the art's top-right corner")
		reveal.update_for_control(screen)
		_check(not remove.visible, "Close button must hide when hovering another control")
		remove.pressed.emit()
		_check(Game.current_run.equipped_cards == ["quick_slash", "strike"], "Unequip must remove one copy, not all duplicates")
		_check(Game.current_run.player_cards.size() == 3, "Unequipping must not sell or delete an owned card")
		remove.pressed.emit()
		_check(Game.current_run.equipped_cards == ["quick_slash"], "Reused close buttons must act on their current card, not their old card ID")
		var last_remove: Button = panel._buttons[0].get_node("DeckUnequipButton") as Button
		_check(last_remove.disabled, "Last card restriction must be preserved")
		last_remove.pressed.emit()
		_check(Game.current_run.equipped_cards.size() == 1, "Disabled close button bypassed last-card protection")
		panel.set_unequip_enabled(false)
		var last_reveal: HoverActionReveal = panel._buttons[0].get_node("HoverActionReveal") as HoverActionReveal
		last_reveal.update_for_control(panel._buttons[0])
		_check(not last_remove.visible, "Preparation lock must hide deck close actions")
		var prefix: String = "Arena" if arena else ""
		var frame: PanelContainer = screen.find_child(prefix + "LoadoutCardFrame_quick_slash", true, false) as PanelContainer
		var actions: HBoxContainer = screen.find_child(prefix + "LoadoutActions_quick_slash", true, false) as HBoxContainer
		var frame_reveal: HoverActionReveal = frame.get_node("HoverActionReveal") as HoverActionReveal
		_check(actions.get_child_count() == 2, "Inventory must contain only equip and sell actions")
		frame_reveal.update_for_control(frame)
		await get_tree().process_frame
		var extent: Vector2 = frame.size
		frame_reveal.update_for_control(null)
		await get_tree().process_frame
		_check(frame.size.is_equal_approx(extent), "Hiding actions changed the card frame dimensions")
		for index: int in range(30):
			frame_reveal.update_for_control(actions.get_child(0) as Control)
			_check(actions.visible, "Moving between buttons hid inventory actions")
			frame_reveal.update_for_control(screen)
			_check(not actions.visible, "Missed exit left inventory actions visible")
		screen.queue_free()
		await get_tree().process_frame
	if _failures.is_empty():
		print("LOADOUT_HOVER_OK map/arena, duplicate/reused cards, last card, preparation lock, stable dimensions, child hover and missed exit")
		get_tree().quit()
	else:
		for failure: String in _failures:
			push_error(failure)
		get_tree().quit(1)
