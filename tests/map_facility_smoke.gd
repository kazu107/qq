extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	if Database.get_all_event_ids().size() < 8:
		_fail("Map/facility smoke failed: event database should expose expanded event content")
		return
	Game.ensure_meta_initialized()
	call_deferred("_run")


func _run() -> void:
	await _exercise_run_a()
	if _failed:
		return

	await _exercise_run_b()
	if _failed:
		return

	print("Map/facility smoke passed: relics=%d loadout=%d/%d" % [
		Game.current_run.relics.size(),
		Game.get_current_loadout_cost(),
		Game.get_loadout_limit(),
	])
	get_tree().quit()


func _exercise_run_a() -> void:
	Game.start_new_run("balanced")
	await _assert_map_scene()
	if _failed:
		return

	_exercise_loadout_editing()
	if _failed:
		return

	_complete_battle_step("normal_battle", true, false)
	if _failed:
		return

	await _exercise_heal_node()
	if _failed:
		return

	_complete_battle_step("elite_battle", true, true)
	if _failed:
		return

	await _exercise_forge_node()


func _exercise_run_b() -> void:
	Game.start_new_run("balanced")

	_complete_battle_step("normal_battle", true, false)
	if _failed:
		return

	await _exercise_shop_node()
	if _failed:
		return

	await _exercise_hazard_node()
	if _failed:
		return

	await _exercise_event_node()


func _assert_map_scene() -> void:
	if Game.current_screen_hint != "map":
		_fail("Map/facility smoke failed: new run should start on the map")
		return

	var map_scene: Control = load("res://scenes/map/Map.tscn").instantiate() as Control
	add_child(map_scene)
	await get_tree().process_frame

	var steps_box: VBoxContainer = map_scene.find_child("MapSteps", true, false) as VBoxContainer
	var equipped_deck: CardHandPanel = map_scene.find_child("EquippedDeck", true, false) as CardHandPanel
	var inventory_box: VBoxContainer = map_scene.find_child("LoadoutInventory", true, false) as VBoxContainer
	var relic_icon_row: RelicIconRow = map_scene.find_child("MapRelicIconRow", true, false) as RelicIconRow
	if steps_box == null or steps_box.get_child_count() == 0:
		_fail("Map/facility smoke failed: map scene did not render step nodes")
	elif equipped_deck == null or equipped_deck.get_child_count() == 0:
		_fail("Map/facility smoke failed: map scene did not render equipped loadout")
	elif inventory_box == null or inventory_box.get_child_count() == 0:
		_fail("Map/facility smoke failed: map scene did not render inventory rows")
	elif relic_icon_row == null:
		_fail("Map/facility smoke failed: map scene did not render relic icon row")
	if _failed:
		return
	_assert_map_loadout_inventory(map_scene)
	if _failed:
		return
	var current_step_panel: PanelContainer = steps_box.find_child("MapStep_0", true, false) as PanelContainer
	var first_step_header: Label = steps_box.find_child("MapStepHeader_0", true, false) as Label
	var area_one_text: String = Localization.get_textf("map.summary.area", "Area {value}", {"value": 1})
	if first_step_header == null or first_step_header.text.count(area_one_text) != 1:
		_fail("Map/facility smoke failed: step header should show the area label only once")
		return
	var current_step_style: StyleBoxFlat = null
	if current_step_panel != null:
		current_step_style = current_step_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if current_step_style == null or current_step_style.border_color.r < 0.95 or current_step_style.border_color.g < 0.65 or current_step_style.border_width_top < 3:
		_fail("Map/facility smoke failed: current map step should have a yellow outline")
		return
	var first_node_button: MapNodeButton = _find_first_map_node_button(steps_box)
	if first_node_button == null:
		_fail("Map/facility smoke failed: map scene did not render node buttons")
		return
	var node_icon: TextureRect = first_node_button.find_child("MapNodeTypeIcon", true, false) as TextureRect
	var node_name: Label = first_node_button.find_child("MapNodeName", true, false) as Label
	if first_node_button.text != "" or node_icon == null or node_icon.texture == null or node_name == null or node_name.text == "":
		_fail("Map/facility smoke failed: node map should render only area icon and area name")
		return
	if first_node_button.tooltip_text.find("Status:") != -1 or first_node_button.tooltip_text.find("Locked") != -1:
		_fail("Map/facility smoke failed: node map should not expose lock status wording")
		return
	var locked_node_button: MapNodeButton = _find_first_locked_map_node_button(steps_box)
	if locked_node_button == null:
		_fail("Map/facility smoke failed: locked node should render a lock icon")
		return
	var lock_icon: TextureRect = locked_node_button.find_child("MapNodeLockIcon", true, false) as TextureRect
	if lock_icon == null or lock_icon.texture == null:
		_fail("Map/facility smoke failed: locked node lock icon was missing")
		return
	var locked_step_panel: PanelContainer = _get_step_panel_for_node(locked_node_button)
	var locked_step_style: StyleBoxFlat = null
	if locked_step_panel != null:
		locked_step_style = locked_step_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if locked_step_style == null or locked_step_style.bg_color.a < 0.5:
		_fail("Map/facility smoke failed: locked step frame should be dimmed")
		return

	Game.current_run.map_state["current_step"] = 4
	map_scene.call("_refresh_ui")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var steps_scroll: ScrollContainer = map_scene.find_child("MapStepsScroll", true, false) as ScrollContainer
	var advanced_step_panel: PanelContainer = map_scene.find_child("MapStep_4", true, false) as PanelContainer
	if steps_scroll == null or advanced_step_panel == null or absf(float(steps_scroll.scroll_vertical) - advanced_step_panel.position.y) > 3.0:
		_fail("Map/facility smoke failed: map should scroll the current step to the top")
		return
	Game.current_run.map_state["current_step"] = 0

	map_scene.queue_free()
	await get_tree().process_frame


func _assert_map_loadout_inventory(map_scene: Control) -> void:
	var entries: Array[Dictionary] = Game.get_loadout_entries()
	if entries.is_empty():
		_fail("Map/facility smoke failed: loadout entries were empty")
		return
	var entry: Dictionary = entries[0]
	var card_id: String = String(entry.get("card_id", ""))
	var frame: PanelContainer = map_scene.find_child("LoadoutCardFrame_%s" % card_id, true, false) as PanelContainer
	var info_box: VBoxContainer = map_scene.find_child("LoadoutCardInfo_%s" % card_id, true, false) as VBoxContainer
	var count_row: HBoxContainer = map_scene.find_child("LoadoutCountRow_%s" % card_id, true, false) as HBoxContainer
	var owned_icon: TextureRect = map_scene.find_child("OwnedCount_%sIcon" % card_id, true, false) as TextureRect
	var equipped_icon: TextureRect = map_scene.find_child("EquippedCount_%sIcon" % card_id, true, false) as TextureRect
	var owned_value: Label = map_scene.find_child("OwnedCount_%sValue" % card_id, true, false) as Label
	var equipped_value: Label = map_scene.find_child("EquippedCount_%sValue" % card_id, true, false) as Label
	var actions: HBoxContainer = map_scene.find_child("LoadoutActions_%s" % card_id, true, false) as HBoxContainer
	if frame == null or info_box == null or count_row == null:
		_fail("Map/facility smoke failed: map loadout card frame should render count-only info")
		return
	if owned_icon == null or owned_icon.texture == null or equipped_icon == null or equipped_icon.texture == null:
		_fail("Map/facility smoke failed: map loadout counts should render icons")
		return
	if owned_value == null or owned_value.text != str(int(entry.get("owned_count", 0))):
		_fail("Map/facility smoke failed: map loadout owned count should render as a number")
		return
	if equipped_value == null or equipped_value.text != str(int(entry.get("equipped_count", 0))):
		_fail("Map/facility smoke failed: map loadout equipped count should render as a number")
		return
	if actions == null or actions.get_child_count() != 2:
		_fail("Map/facility smoke failed: map loadout actions should render equip and unequip buttons")
		return
	if actions.get_parent() != info_box or actions.get_index() <= count_row.get_index():
		_fail("Map/facility smoke failed: map loadout actions should sit below the count row")
		return
	if actions.visible:
		_fail("Map/facility smoke failed: map loadout actions should be hidden before hover")
		return
	map_scene.call("_set_loadout_actions_visible", actions, true)
	if not actions.visible:
		_fail("Map/facility smoke failed: map loadout actions should appear on frame hover")
		return
	map_scene.call("_set_loadout_actions_visible", actions, false)


func _find_first_map_node_button(root: Node) -> MapNodeButton:
	for child in root.get_children():
		var child_node: Node = child as Node
		if child_node is MapNodeButton:
			return child_node as MapNodeButton
		var nested_button: MapNodeButton = _find_first_map_node_button(child_node)
		if nested_button != null:
			return nested_button
	return null


func _find_first_locked_map_node_button(root: Node) -> MapNodeButton:
	for child in root.get_children():
		var child_node: Node = child as Node
		if child_node is MapNodeButton:
			var node_button: MapNodeButton = child_node as MapNodeButton
			var lock_overlay: Control = node_button.find_child("MapNodeLockOverlay", true, false) as Control
			if lock_overlay != null and lock_overlay.visible:
				return node_button
		var nested_button: MapNodeButton = _find_first_locked_map_node_button(child_node)
		if nested_button != null:
			return nested_button
	return null


func _get_step_panel_for_node(node_button: MapNodeButton) -> PanelContainer:
	var row: Node = node_button.get_parent()
	if row == null:
		return null
	var box: Node = row.get_parent()
	if box == null:
		return null
	return box.get_parent() as PanelContainer


func _exercise_loadout_editing() -> void:
	var entries: Array[Dictionary] = Game.get_loadout_entries()
	if entries.is_empty():
		_fail("Map/facility smoke failed: loadout entries were empty")
		return
	if Game.current_run.equipped_cards.size() <= 1:
		_fail("Map/facility smoke failed: starter loadout should contain multiple cards")
		return

	var card_id: String = Game.current_run.equipped_cards[Game.current_run.equipped_cards.size() - 1]
	var cost_before: int = Game.get_current_loadout_cost()
	if not Game.unequip_card(card_id):
		_fail("Map/facility smoke failed: could not unequip a starter card")
		return
	if Game.get_current_loadout_cost() >= cost_before:
		_fail("Map/facility smoke failed: unequipping did not reduce loadout cost")
		return
	if not Game.equip_card(card_id):
		_fail("Map/facility smoke failed: could not re-equip a starter card")
		return
	if Game.get_current_loadout_cost() != cost_before:
		_fail("Map/facility smoke failed: re-equipping did not restore loadout cost")


func _complete_battle_step(node_type: String, pick_reward: bool, expect_relic_gain: bool) -> void:
	var battle_node: Dictionary = _find_available_node(node_type)
	if battle_node.is_empty():
		_fail("Map/facility smoke failed: no available %s node found" % node_type)
		return

	var destination: String = Game.select_map_node(String(battle_node.get("id", "")))
	if destination != "battle":
		_fail("Map/facility smoke failed: selecting %s did not route to battle" % node_type)
		return

	var enemy_id: String = Game.prepare_next_battle()
	if enemy_id == "":
		_fail("Map/facility smoke failed: %s did not resolve an enemy" % node_type)
		return

	var relics_before: int = Game.current_run.relics.size()
	Game.complete_battle(_build_victory_summary(enemy_id))
	if Game.current_screen_hint != "reward" or Game.reward_options.is_empty():
		_fail("Map/facility smoke failed: %s victory did not open reward selection" % node_type)
		return
	if expect_relic_gain and Game.current_run.relics.size() <= relics_before:
		_fail("Map/facility smoke failed: %s victory did not grant a relic" % node_type)
		return

	if pick_reward:
		var deck_before: int = Game.current_run.player_cards.size()
		Game.choose_reward(Game.reward_options[0])
		if Game.current_run.player_cards.size() != deck_before + 1:
			_fail("Map/facility smoke failed: taking a reward after %s did not add a card" % node_type)
			return
	else:
		Game.skip_reward()

	if Game.current_screen_hint != "map":
		_fail("Map/facility smoke failed: resolving %s reward did not return to map" % node_type)


func _exercise_heal_node() -> void:
	Game.current_run.player_hp = max(1, Game.current_run.player_hp - 8)

	var heal_node: Dictionary = _find_available_node("heal")
	if heal_node.is_empty():
		_fail("Map/facility smoke failed: no available heal node found")
		return
	if Game.select_map_node(String(heal_node.get("id", ""))) != "facility":
		_fail("Map/facility smoke failed: selecting heal node did not route to facility")
		return

	await _assert_facility_scene("heal")
	if _failed:
		return

	var hp_before: int = Game.current_run.player_hp
	var recovered: int = Game.use_heal_node()
	if recovered <= 0 or Game.current_run.player_hp <= hp_before:
		_fail("Map/facility smoke failed: heal node did not recover HP")
		return
	if Game.current_screen_hint != "map":
		_fail("Map/facility smoke failed: heal node did not return to map")


func _exercise_forge_node() -> void:
	var forge_node: Dictionary = _find_available_node("forge")
	if forge_node.is_empty():
		_fail("Map/facility smoke failed: no available forge node found")
		return
	if Game.select_map_node(String(forge_node.get("id", ""))) != "facility":
		_fail("Map/facility smoke failed: selecting forge node did not route to facility")
		return

	var facility_scene: Control = await _assert_facility_scene("forge")
	if _failed or facility_scene == null:
		return

	var forge_options: Array[String] = Game.get_forge_options()
	if forge_options.is_empty():
		_fail("Map/facility smoke failed: forge has no upgrade candidates")
		facility_scene.queue_free()
		await get_tree().process_frame
		return

	var forge_choice_list: VBoxContainer = facility_scene.find_child("ForgeChoiceList", true, false) as VBoxContainer
	if forge_choice_list == null or forge_choice_list.get_child_count() < forge_options.size() + 3:
		_fail("Map/facility smoke failed: forge should render upgrade, service, and leave choices")
		facility_scene.queue_free()
		await get_tree().process_frame
		return

	if Game.get_forge_service_choices().size() < 2:
		_fail("Map/facility smoke failed: forge should expose additional service choices")
		facility_scene.queue_free()
		await get_tree().process_frame
		return

	var card_id: String = forge_options[0]
	var current_tier: int = CardUpgradeResolver.get_tier(Game.current_run, card_id)
	var tier_after: int = Game.upgrade_forge_card(card_id)
	if tier_after != current_tier + 1:
		_fail("Map/facility smoke failed: forge upgrade did not advance card tier")
		facility_scene.queue_free()
		await get_tree().process_frame
		return

	Game.leave_facility()
	if Game.current_screen_hint != "map":
		_fail("Map/facility smoke failed: leaving forge did not return to map")

	facility_scene.queue_free()
	await get_tree().process_frame


func _exercise_shop_node() -> void:
	var shop_node: Dictionary = _find_available_node("shop")
	if shop_node.is_empty():
		_fail("Map/facility smoke failed: no available shop node found")
		return
	if Game.select_map_node(String(shop_node.get("id", ""))) != "facility":
		_fail("Map/facility smoke failed: selecting shop node did not route to facility")
		return

	var facility_scene: Control = await _assert_facility_scene("shop")
	if _failed or facility_scene == null:
		return

	var offers: Array[Dictionary] = Game.get_shop_offers()
	if offers.is_empty():
		_fail("Map/facility smoke failed: shop has no offers")
		facility_scene.queue_free()
		await get_tree().process_frame
		return
	var shop_choice_list: VBoxContainer = facility_scene.find_child("ShopChoiceList", true, false) as VBoxContainer
	if shop_choice_list == null or shop_choice_list.get_child_count() < offers.size() + 4:
		_fail("Map/facility smoke failed: shop should render card offers, service choices, and leave choice")
		facility_scene.queue_free()
		await get_tree().process_frame
		return
	if not _has_named_child_prefix(facility_scene, "ChoiceCardPreview_"):
		_fail("Map/facility smoke failed: shop choices should render card previews")
		facility_scene.queue_free()
		await get_tree().process_frame
		return
	if Game.get_shop_service_choices().size() < 3:
		_fail("Map/facility smoke failed: shop should expose additional service choices")
		facility_scene.queue_free()
		await get_tree().process_frame
		return

	var deck_before: int = Game.current_run.player_cards.size()
	var bought: bool = false
	Game.current_run.gold = max(Game.current_run.gold, 200)
	var gold_before_service: int = Game.current_run.gold
	if not Game.use_shop_service_choice("courier_job") or Game.current_run.gold <= gold_before_service:
		_fail("Map/facility smoke failed: shop courier service choice did not grant gold")
		facility_scene.queue_free()
		await get_tree().process_frame
		return
	for offer_index in range(offers.size()):
		var offer_data: Dictionary = offers[offer_index]
		if bool(offer_data.get("bought", false)):
			continue
		if Game.current_run.gold < int(offer_data.get("price", 0)):
			continue
		if Game.buy_shop_offer(offer_index):
			bought = true
			break
	if not bought:
		_fail("Map/facility smoke failed: shop could not buy any offer")
		facility_scene.queue_free()
		await get_tree().process_frame
		return
	if Game.current_run.player_cards.size() != deck_before + 1:
		_fail("Map/facility smoke failed: shop purchase did not add a card")
		facility_scene.queue_free()
		await get_tree().process_frame
		return

	Game.leave_facility()
	if Game.current_screen_hint != "map":
		_fail("Map/facility smoke failed: leaving shop did not return to map")

	facility_scene.queue_free()
	await get_tree().process_frame


func _exercise_hazard_node() -> void:
	var hazard_node: Dictionary = _find_available_node("hazard")
	if hazard_node.is_empty():
		_fail("Map/facility smoke failed: no available hazard node found")
		return
	if Game.select_map_node(String(hazard_node.get("id", ""))) != "facility":
		_fail("Map/facility smoke failed: selecting hazard node did not route to facility")
		return

	var facility_scene: Control = await _assert_facility_scene("hazard")
	if _failed or facility_scene == null:
		return
	facility_scene.queue_free()
	await get_tree().process_frame

	if not Game.continue_hazard():
		_fail("Map/facility smoke failed: could not start hazard battle")
		return

	var first_enemy_id: String = Game.pending_enemy_id
	Game.complete_battle(_build_victory_summary(first_enemy_id))
	if Game.current_screen_hint != "reward" or Game.reward_options.is_empty():
		_fail("Map/facility smoke failed: clearing the first hazard wave should open rewards")
		return

	var hazard_status: Dictionary = Game.get_hazard_status()
	if int(hazard_status.get("waves_cleared", 0)) != 1:
		_fail("Map/facility smoke failed: hazard did not record the cleared wave")
		return
	Game.skip_reward()
	if Game.current_screen_hint != "facility":
		_fail("Map/facility smoke failed: skipping an interim hazard reward should return to facility")
		return

	var relics_before: int = Game.current_run.relics.size()
	if not Game.continue_hazard():
		_fail("Map/facility smoke failed: could not continue the second hazard wave")
		return

	var second_enemy_id: String = Game.pending_enemy_id
	Game.complete_battle(_build_victory_summary(second_enemy_id))
	if Game.current_screen_hint != "reward" or Game.reward_options.is_empty():
		_fail("Map/facility smoke failed: final hazard wave did not open rewards")
		return
	if Game.current_run.relics.size() <= relics_before:
		_fail("Map/facility smoke failed: final hazard reward did not grant a relic")
		return

	Game.skip_reward()
	if Game.current_screen_hint != "map":
		_fail("Map/facility smoke failed: hazard reward did not return to map")


func _exercise_event_node() -> void:
	var event_node: Dictionary = _find_available_node("event")
	if event_node.is_empty():
		_fail("Map/facility smoke failed: no available event node found")
		return
	if Game.select_map_node(String(event_node.get("id", ""))) != "facility":
		_fail("Map/facility smoke failed: selecting event node did not route to facility")
		return

	var facility_scene: Control = await _assert_facility_scene("event")
	if _failed or facility_scene == null:
		return

	var event_data: Dictionary = Game.get_active_event_data()
	var choices: Array = Array(event_data.get("choices", []))
	if choices.size() != 3:
		_fail("Map/facility smoke failed: event node should produce exactly three choices")
		facility_scene.queue_free()
		await get_tree().process_frame
		return

	var chosen_id: String = ""
	for raw_choice in choices:
		var choice_data: Dictionary = Dictionary(raw_choice)
		if bool(choice_data.get("enabled", true)):
			chosen_id = String(choice_data.get("id", ""))
			break
	if chosen_id == "":
		_fail("Map/facility smoke failed: event node produced no usable choices")
		facility_scene.queue_free()
		await get_tree().process_frame
		return

	var result_text: String = Game.resolve_event_choice(chosen_id)
	if result_text == "":
		_fail("Map/facility smoke failed: event choice did not resolve")
		facility_scene.queue_free()
		await get_tree().process_frame
		return
	if Game.current_screen_hint != "map":
		_fail("Map/facility smoke failed: event resolution did not return to map")

	facility_scene.queue_free()
	await get_tree().process_frame


func _assert_facility_scene(expected_type: String) -> Control:
	if Game.get_active_facility_type() != expected_type:
		_fail("Map/facility smoke failed: active facility type should be %s" % expected_type)
		return null

	var facility_scene: Control = load("res://scenes/facility/Facility.tscn").instantiate() as Control
	add_child(facility_scene)
	await get_tree().process_frame

	var options_box: VBoxContainer = facility_scene.find_child("FacilityOptions", true, false) as VBoxContainer
	var facility_deck: CardHandPanel = facility_scene.find_child("FacilityDeck", true, false) as CardHandPanel
	var relic_icon_row: RelicIconRow = facility_scene.find_child("FacilityRelicIconRow", true, false) as RelicIconRow
	if options_box == null or options_box.get_child_count() == 0:
		_fail("Map/facility smoke failed: %s scene did not render options" % expected_type)
		return facility_scene
	if ["shop", "forge", "heal", "event", "hazard"].has(expected_type):
		var choice_list_name: String = "%sChoiceList" % expected_type.capitalize()
		if expected_type == "event":
			choice_list_name = "EventChoiceList"
		var choice_list: VBoxContainer = facility_scene.find_child(choice_list_name, true, false) as VBoxContainer
		var deck_frame: Control = null
		if facility_deck != null and facility_deck.get_parent() != null:
			deck_frame = facility_deck.get_parent().get_parent() as Control
		var expected_min_choices: int = 3
		if expected_type == "shop":
			expected_min_choices = 7
		elif expected_type == "forge":
			expected_min_choices = 4
		elif expected_type == "hazard":
			expected_min_choices = 1
		if choice_list == null or choice_list.get_child_count() < expected_min_choices:
			_fail("Map/facility smoke failed: %s scene should render large choice buttons" % expected_type)
		elif deck_frame == null or deck_frame.visible:
			_fail("Map/facility smoke failed: %s scene should hide the battle loadout frame" % expected_type)
		elif relic_icon_row == null or relic_icon_row.visible:
			_fail("Map/facility smoke failed: %s scene should hide node summary relics" % expected_type)
		if _failed:
			return facility_scene
		if expected_type == "hazard":
			_assert_hazard_choice_description(facility_scene)
		elif expected_type == "shop":
			_assert_choice_title_width(facility_scene, "ChoiceTitle_leave_shop", expected_type)
		elif expected_type == "forge":
			_assert_choice_title_width(facility_scene, "ChoiceTitle_leave_forge", expected_type)
		return facility_scene
	if facility_deck == null or facility_deck.get_child_count() == 0:
		_fail("Map/facility smoke failed: %s scene did not render loadout cards" % expected_type)
	elif relic_icon_row == null:
		_fail("Map/facility smoke failed: %s scene did not render relic icon row" % expected_type)
	return facility_scene


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


func _find_first_hbox(parent: Control) -> HBoxContainer:
	for child in parent.get_children():
		if child is HBoxContainer:
			return child as HBoxContainer
	return null


func _assert_hazard_choice_description(facility_scene: Control) -> void:
	var description_label: Label = facility_scene.find_child("ChoiceDescription_continue_hazard", true, false) as Label
	if description_label == null:
		_fail("Map/facility smoke failed: hazard choice should render current wave description")
		return
	if description_label.text.find("/") == -1 or description_label.text.find("\n") == -1:
		_fail("Map/facility smoke failed: hazard choice description should include wave progress and description")


func _assert_choice_title_width(facility_scene: Control, title_name: String, expected_type: String) -> void:
	var title_label: Label = facility_scene.find_child(title_name, true, false) as Label
	if title_label == null:
		_fail("Map/facility smoke failed: %s leave choice title was missing" % expected_type)
		return
	if title_label.custom_minimum_size.x < 300.0:
		_fail("Map/facility smoke failed: %s leave choice title width is too narrow" % expected_type)


func _has_named_child_prefix(root: Node, prefix: String) -> bool:
	if String(root.name).begins_with(prefix):
		return true
	for child in root.get_children():
		if _has_named_child_prefix(child, prefix):
			return true
	return false


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
