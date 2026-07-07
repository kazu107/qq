extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.developer_unlock_all_meta()
	call_deferred("_run")


func _run() -> void:
	if not Game.start_arena_run("balanced", 24680):
		_fail("Arena flow smoke failed: arena run did not start")
		return
	if Game.current_run == null or not Game.current_run.arena_mode or Game.current_screen_hint != "arena":
		_fail("Arena flow smoke failed: arena state was not initialized")
		return
	if Game.get_arena_card_offers().size() < 3 or Game.get_arena_relic_offers().is_empty():
		_fail("Arena flow smoke failed: preparation shop did not roll card and relic offers")
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
	if Game.get_arena_card_offers().is_empty() or Game.get_arena_relic_offers().is_empty():
		_fail("Arena flow smoke failed: post-victory preparation shop was not available")
		return

	print("Arena flow smoke passed: wins=%d gold=%d relics=%d" % [
		Game.current_run.arena_wins,
		Game.current_run.gold,
		Game.current_run.relics.size(),
	])
	get_tree().quit()


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


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
