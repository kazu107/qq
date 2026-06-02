extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.developer_reset_meta_progress()
	Game.start_new_run("balanced")
	call_deferred("_run")


func _run() -> void:
	var default_bundle: Dictionary = Game.preview_reward_package("normal", 1)
	if int(default_bundle.get("gold", 0)) <= 0 or int(default_bundle.get("heal", 0)) <= 0:
		_fail("Reward progression smoke failed: default reward bundle did not grant gold and healing")
		return
	if Array(default_bundle.get("options", [])).size() != 3:
		_fail("Reward progression smoke failed: normal reward bundle should render three options")
		return
	if not _contains_unowned_card(Array(default_bundle.get("options", [])), Game.current_run.player_cards):
		_fail("Reward progression smoke failed: normal rewards should prefer at least one unowned card")
		return
	for raw_card_id in Array(default_bundle.get("options", [])):
		var card_def: CardDef = Database.get_card(String(raw_card_id))
		if card_def == null or card_def.rarity != "common":
			_fail("Reward progression smoke failed: locked rarity leaked into the default reward pool")
			return

	Game.developer_unlock_all_meta()
	var area_one_bundle: Dictionary = Game.preview_reward_package("normal", 1)
	var area_three_bundle: Dictionary = Game.preview_reward_package("normal", 3)
	if int(area_three_bundle.get("gold", 0)) <= int(area_one_bundle.get("gold", 0)):
		_fail("Reward progression smoke failed: area scaling did not increase gold rewards")
		return
	if int(area_three_bundle.get("heal", 0)) <= int(area_one_bundle.get("heal", 0)):
		_fail("Reward progression smoke failed: area scaling did not increase healing rewards")
		return

	var boss_bundle: Dictionary = Game.preview_reward_package("boss", 3)
	if int(boss_bundle.get("option_count", -1)) != 0 or not Array(boss_bundle.get("options", [])).is_empty():
		_fail("Reward progression smoke failed: boss reward bundle should not offer post-clear card picks")
		return

	Game.set_developer_mode_enabled(true)
	var elite_bundle: Dictionary = Game.developer_open_reward_preview("elite", 3)
	if Array(elite_bundle.get("options", [])).size() != 3:
		_fail("Reward progression smoke failed: elite preview should expose three reward options")
		return

	var reward_scene: Control = load("res://scenes/reward/Reward.tscn").instantiate() as Control
	add_child(reward_scene)
	await get_tree().process_frame
	var reward_cards: CardHandPanel = reward_scene.find_child("RewardCards", true, false) as CardHandPanel
	if reward_cards == null or reward_cards.get_child_count() != 3:
		_fail("Reward progression smoke failed: reward scene did not render refined reward cards")
		return
	var developer_panel: DeveloperPanel = reward_scene.find_child("DeveloperPanel", true, false) as DeveloperPanel
	if developer_panel == null or reward_scene.find_child("DevPreviewEliteReward", true, false) == null:
		_fail("Reward progression smoke failed: reward scene developer tools for preview were missing")
		return

	print("Reward progression smoke passed")
	get_tree().quit()


func _contains_unowned_card(candidate_cards: Array, owned_cards: Array[String]) -> bool:
	for raw_card_id in candidate_cards:
		if not owned_cards.has(String(raw_card_id)):
			return true
	return false


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
