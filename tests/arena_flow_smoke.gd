extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.developer_reset_meta_progress()
	call_deferred("_run")


func _run() -> void:
	await _assert_arena_setup_has_only_arena_start()
	if _failed:
		return
	if not Game.start_arena_run("balanced", 24680):
		_fail("Arena flow smoke failed: arena run did not start")
		return
	if Game.current_run == null or not Game.current_run.arena_mode or Game.current_screen_hint != "arena":
		_fail("Arena flow smoke failed: arena state was not initialized")
		return
	if Game.get_arena_card_offers().size() < 3 or Game.get_arena_relic_offers().is_empty():
		_fail("Arena flow smoke failed: preparation shop did not roll card and relic offers")
		return
	if not _assert_arena_shop_can_surface_locked_content():
		return

	await _assert_arena_scene()
	if _failed:
		return

	Game.current_run.gold = 999
	var first_card_offer: Dictionary = Game.get_arena_card_offers()[0]
	var held_card_id: String = String(first_card_offer.get("card_id", ""))
	if not Game.toggle_arena_card_hold(0):
		_fail("Arena flow smoke failed: card offer could not be held")
		return
	if not Game.reroll_arena_shop_for_gold():
		_fail("Arena flow smoke failed: held shop reroll failed")
		return
	var rerolled_first_offer: Dictionary = Game.get_arena_card_offers()[0]
	if String(rerolled_first_offer.get("card_id", "")) != held_card_id or not bool(rerolled_first_offer.get("held", false)):
		_fail("Arena flow smoke failed: held card offer did not survive shop reroll")
		return
	var owned_before: int = Game.current_run.player_cards.size()
	if not Game.buy_arena_card_offer(0):
		_fail("Arena flow smoke failed: card offer could not be bought")
		return
	if Game.current_run.player_cards.size() <= owned_before or not Game.current_run.player_cards.has(held_card_id):
		_fail("Arena flow smoke failed: bought arena card was not added")
		return
	await _assert_arena_loadout_contains(held_card_id)
	if _failed:
		return
	Game.current_run.loadout_limit = 99
	if not Game.equip_card(held_card_id):
		_fail("Arena flow smoke failed: bought arena card could not be equipped from arena loadout")
		return
	if not Game.unequip_card(held_card_id):
		_fail("Arena flow smoke failed: bought arena card could not be unequipped from arena loadout")
		return
	var sell_value: int = Game.get_card_sell_value(held_card_id)
	var gold_before_sell: int = Game.current_run.gold
	var owned_before_sell: int = Game.current_run.player_cards.size()
	if not Game.sell_loadout_card(held_card_id):
		_fail("Arena flow smoke failed: bought arena card could not be sold from arena loadout")
		return
	if Game.current_run.player_cards.size() != owned_before_sell - 1:
		_fail("Arena flow smoke failed: selling an arena card should remove one owned copy")
		return
	if Game.current_run.gold != gold_before_sell + sell_value:
		_fail("Arena flow smoke failed: selling an arena card did not grant half value")
		return
	if not _has_gold_delta_popup("+%d" % sell_value):
		_fail("Arena flow smoke failed: selling an arena card did not show a gold popup")
		return

	var relic_offers: Array[Dictionary] = Game.get_arena_relic_offers()
	if relic_offers.is_empty():
		_fail("Arena flow smoke failed: relic offers disappeared")
		return
	var relic_id: String = String(relic_offers[0].get("relic_id", ""))
	if not Game.toggle_arena_relic_hold(0):
		_fail("Arena flow smoke failed: relic offer could not be held")
		return
	if not Game.buy_arena_relic_offer(0):
		_fail("Arena flow smoke failed: relic offer could not be bought")
		return
	if not Game.current_run.relics.has(relic_id):
		_fail("Arena flow smoke failed: bought arena relic was not granted")
		return

	if not Game.start_next_arena_battle():
		_fail("Arena flow smoke failed: next arena battle did not start")
		return
	var enemy_id: String = Game.pending_enemy_id
	if Game.current_screen_hint != "battle" or enemy_id == "":
		_fail("Arena flow smoke failed: arena battle did not set pending enemy")
		return

	Game.complete_battle({
		"winner": "player",
		"enemy_id": enemy_id,
		"enemy_name": Localization.get_enemy_name(enemy_id, enemy_id),
		"player_hp": Game.current_run.player_hp,
		"battle_time": 12.0,
		"battle_events": [],
	})
	if Game.current_screen_hint != "arena" or Game.current_run.arena_wins != 1:
		_fail("Arena flow smoke failed: victory did not return to arena preparation")
		return
	if Game.get_arena_pending_rewards().is_empty():
		_fail("Arena flow smoke failed: victory did not create arena reward choices")
		return
	if Game.start_next_arena_battle():
		_fail("Arena flow smoke failed: arena allowed next battle before choosing victory reward")
		return
	await _assert_arena_reward_modal()
	if _failed:
		return
	var reward_id: String = String(Game.get_arena_pending_rewards()[0].get("id", ""))
	if not Game.choose_arena_victory_reward(reward_id):
		_fail("Arena flow smoke failed: arena victory reward could not be chosen")
		return
	if not Game.get_arena_pending_rewards().is_empty():
		_fail("Arena flow smoke failed: chosen arena reward did not clear pending rewards")
		return
	if Game.get_arena_card_offers().is_empty() or Game.get_arena_relic_offers().is_empty():
		_fail("Arena flow smoke failed: post-victory preparation shop was not available")
		return

	print("Arena flow smoke passed: wins=%d gold=%d relics=%d" % [
		Game.current_run.arena_wins,
		Game.current_run.gold,
		Game.current_run.relics.size(),
	])
	get_tree().quit()


func _assert_arena_setup_has_only_arena_start() -> void:
	Game.prepare_run_setup(Game.RUN_SETUP_MODE_ARENA)
	var run_setup_scene: Control = load("res://scenes/run_setup/RunSetup.tscn").instantiate() as Control
	add_child(run_setup_scene)
	await get_tree().process_frame
	var normal_start_button: Button = run_setup_scene.find_child("RunStartSelectedButton", true, false) as Button
	var arena_start_button: Button = run_setup_scene.find_child("ArenaStartSelectedButton", true, false) as Button
	if normal_start_button != null:
		_fail("Arena flow smoke failed: arena setup should not render the normal run start button")
	elif arena_start_button == null:
		_fail("Arena flow smoke failed: arena setup did not render the arena start button")
	run_setup_scene.queue_free()
	Game.prepare_run_setup(Game.RUN_SETUP_MODE_NORMAL)
	await get_tree().process_frame


func _assert_arena_shop_can_surface_locked_content() -> bool:
	var unlocked_card_ids: Array[String] = Game.get_unlocked_card_ids()
	var unlocked_relic_ids: Array[String] = Game.get_unlocked_relic_ids()
	var saw_locked_card: bool = _card_offers_include_locked(Game.get_arena_card_offers(), unlocked_card_ids)
	var saw_locked_relic: bool = _relic_offers_include_locked(Game.get_arena_relic_offers(), unlocked_relic_ids)
	Game.current_run.gold = 9999
	for _attempt_index in range(24):
		if saw_locked_card and saw_locked_relic:
			return true
		if not Game.reroll_arena_shop_for_gold():
			_fail("Arena flow smoke failed: arena shop reroll failed while checking full content pool")
			return false
		saw_locked_card = saw_locked_card or _card_offers_include_locked(Game.get_arena_card_offers(), unlocked_card_ids)
		saw_locked_relic = saw_locked_relic or _relic_offers_include_locked(Game.get_arena_relic_offers(), unlocked_relic_ids)
	if not saw_locked_card:
		_fail("Arena flow smoke failed: arena card shop never surfaced a locked card")
		return false
	if not saw_locked_relic:
		_fail("Arena flow smoke failed: arena relic shop never surfaced a locked relic")
		return false
	return true


func _card_offers_include_locked(offers: Array[Dictionary], unlocked_card_ids: Array[String]) -> bool:
	for offer_data in offers:
		var card_id: String = String(offer_data.get("card_id", ""))
		if card_id != "" and not unlocked_card_ids.has(card_id):
			return true
	return false


func _relic_offers_include_locked(offers: Array[Dictionary], unlocked_relic_ids: Array[String]) -> bool:
	for offer_data in offers:
		var relic_id: String = String(offer_data.get("relic_id", ""))
		if relic_id != "" and not unlocked_relic_ids.has(relic_id):
			return true
	return false


func _assert_arena_scene() -> void:
	var arena_scene: Control = load("res://scenes/arena/Arena.tscn").instantiate() as Control
	add_child(arena_scene)
	await get_tree().process_frame

	var status_label: Label = arena_scene.find_child("ArenaStatusLabel", true, false) as Label
	var card_offers: VBoxContainer = arena_scene.find_child("ArenaCardOffers", true, false) as VBoxContainer
	var relic_offers: VBoxContainer = arena_scene.find_child("ArenaRelicOffers", true, false) as VBoxContainer
	var start_button: Button = arena_scene.find_child("ArenaStartBattleButton", true, false) as Button
	var reroll_button: Button = arena_scene.find_child("ArenaRerollShopButton", true, false) as Button
	if status_label == null or status_label.text == "":
		_fail("Arena flow smoke failed: arena scene did not render status")
	elif card_offers == null or card_offers.get_child_count() < 3:
		_fail("Arena flow smoke failed: arena scene did not render card offers")
	elif relic_offers == null or relic_offers.get_child_count() < 1:
		_fail("Arena flow smoke failed: arena scene did not render relic offers")
	elif start_button == null or start_button.disabled:
		_fail("Arena flow smoke failed: arena scene start button was unavailable")
	elif reroll_button == null:
		_fail("Arena flow smoke failed: arena scene reroll button was missing")
	arena_scene.queue_free()
	await get_tree().process_frame


func _assert_arena_loadout_contains(card_id: String) -> void:
	var arena_scene: Control = load("res://scenes/arena/Arena.tscn").instantiate() as Control
	add_child(arena_scene)
	await get_tree().process_frame
	var inventory_scroll: ScrollContainer = arena_scene.find_child("ArenaLoadoutInventoryScroll", true, false) as ScrollContainer
	var inventory_box: VBoxContainer = arena_scene.find_child("ArenaLoadoutInventory", true, false) as VBoxContainer
	var card_frame: PanelContainer = arena_scene.find_child("ArenaLoadoutCardFrame_%s" % card_id, true, false) as PanelContainer
	var equip_button: Button = arena_scene.find_child("ArenaEquipButton_%s" % card_id, true, false) as Button
	var unequip_button: Button = arena_scene.find_child("ArenaUnequipButton_%s" % card_id, true, false) as Button
	var sell_button: Button = arena_scene.find_child("ArenaSellButton_%s" % card_id, true, false) as Button
	if inventory_scroll == null or inventory_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_fail("Arena flow smoke failed: arena loadout inventory should not expose horizontal scrolling")
	elif inventory_box == null:
		_fail("Arena flow smoke failed: arena loadout inventory did not render")
	elif card_frame == null:
		_fail("Arena flow smoke failed: bought arena card did not render in loadout inventory")
	elif equip_button == null or unequip_button == null:
		_fail("Arena flow smoke failed: arena loadout did not render equip and unequip buttons")
	elif sell_button == null or sell_button.icon == null or sell_button.text == "":
		_fail("Arena flow smoke failed: arena loadout did not render a priced sell button")
	arena_scene.queue_free()
	await get_tree().process_frame


func _assert_arena_reward_modal() -> void:
	var arena_scene: Control = load("res://scenes/arena/Arena.tscn").instantiate() as Control
	add_child(arena_scene)
	await get_tree().process_frame
	var reward_modal: PanelContainer = arena_scene.find_child("ArenaRewardModal", true, false) as PanelContainer
	var reward_options: HBoxContainer = arena_scene.find_child("ArenaRewardOptions", true, false) as HBoxContainer
	var start_button: Button = arena_scene.find_child("ArenaStartBattleButton", true, false) as Button
	if reward_modal == null or not reward_modal.visible:
		_fail("Arena flow smoke failed: pending victory reward did not show a modal")
	elif reward_options == null or reward_options.get_child_count() < 3:
		_fail("Arena flow smoke failed: victory reward modal did not render reward choices")
	elif start_button == null or not start_button.disabled:
		_fail("Arena flow smoke failed: next battle should be blocked while reward is pending")
	arena_scene.queue_free()
	await get_tree().process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)


func _has_gold_delta_popup(expected_text: String) -> bool:
	for popup in get_tree().root.find_children("*GoldDeltaPopup*", "", true, false):
		var popup_control: Control = popup as Control
		if popup_control == null:
			continue
		var value_label: Label = popup_control.find_child("GoldDeltaValue", true, false) as Label
		if value_label != null and value_label.text == expected_text:
			return true
	return false
