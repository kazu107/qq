extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.developer_reset_meta_progress()
	call_deferred("_run")


func _run() -> void:
	_assert_default_meta()
	if _failed:
		return

	Game.start_new_run("balanced")
	var rewards: Array[String] = Game.developer_reroll_rewards()
	if rewards.is_empty():
		_fail("Meta progress smoke failed: default reward reroll returned no cards")
		return
	for card_id in rewards:
		var card_def: CardDef = Database.get_card(card_id)
		if card_def == null or card_def.rarity != "common":
			_fail("Meta progress smoke failed: locked rare or epic card leaked into the default reward pool")
			return

	var meta_scene: Control = load("res://scenes/meta/MetaProgress.tscn").instantiate() as Control
	add_child(meta_scene)
	await get_tree().process_frame

	var starter_box: VBoxContainer = meta_scene.find_child("MetaStarterBox", true, false) as VBoxContainer
	var card_box: VBoxContainer = meta_scene.find_child("MetaCardBox", true, false) as VBoxContainer
	var relic_box: VBoxContainer = meta_scene.find_child("MetaRelicBox", true, false) as VBoxContainer
	var achievement_box: VBoxContainer = meta_scene.find_child("MetaAchievementBox", true, false) as VBoxContainer
	if achievement_box == null or achievement_box.get_child_count() == 0:
		_fail("Meta progress smoke failed: achievement section did not render")
		return
	if starter_box == null or starter_box.get_child_count() == 0:
		_fail("Meta progress smoke failed: starter unlock section did not render")
		return
	if card_box == null or card_box.get_child_count() == 0:
		_fail("Meta progress smoke failed: card unlock section did not render")
		return
	if relic_box == null or relic_box.get_child_count() == 0:
		_fail("Meta progress smoke failed: relic unlock section did not render")
		return
	for frame_name: String in [
		"MetaAchievementFrame_first_victory",
		"MetaStarterFrame_balanced",
		"MetaCardFrame_quick_slash",
		"MetaRelicFrame_iron_plating",
	]:
		var entry_frame: PanelContainer = meta_scene.find_child(frame_name, true, false) as PanelContainer
		var entry_style: StyleBoxFlat = null
		if entry_frame != null:
			entry_style = entry_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if entry_style == null or entry_style.border_width_top < 1:
			_fail("Meta progress smoke failed: entry frame %s did not render a visible divider" % frame_name)
			return
	var iron_relic_icon: RelicIcon = meta_scene.find_child("MetaRelic_iron_plating", true, false) as RelicIcon
	if iron_relic_icon == null or iron_relic_icon.tooltip_text.find("Iron Plating") == -1:
		_fail("Meta progress smoke failed: relic unlock section should render relic icons with tooltips")
		return

	Game.developer_add_achievement_stat("victories", 1)
	meta_scene.call("_refresh_ui")
	await get_tree().process_frame
	var first_victory_button: Button = meta_scene.find_child("ClaimAchievement_first_victory", true, false) as Button
	if first_victory_button == null or first_victory_button.disabled:
		_fail("Meta progress smoke failed: first victory achievement should become claimable")
		return
	first_victory_button.emit_signal("pressed")
	await get_tree().process_frame
	if int(Game.get_permanent_bonuses().get("max_hp", 0)) != 5:
		_fail("Meta progress smoke failed: achievement claim should grant a permanent HP bonus")
		return
	var base_hp: int = int(Database.get_starter("balanced").get("max_hp", 0))
	Game.start_new_run("balanced")
	if Game.current_run == null or Game.current_run.max_hp != base_hp + 5:
		_fail("Meta progress smoke failed: claimed permanent HP bonus should apply to new runs")
		return

	Game.developer_add_points(10)
	meta_scene.call("_refresh_ui")
	await get_tree().process_frame

	if meta_scene.find_child("UnlockStarter_tempo", true, false) == null \
	or meta_scene.find_child("UnlockCard_assault", true, false) == null \
	or meta_scene.find_child("UnlockRelic_chrono_shard", true, false) == null:
		_fail("Meta progress smoke failed: expected unlock buttons were not rendered")
		return

	var tempo_button: Button = meta_scene.find_child("UnlockStarter_tempo", true, false) as Button
	tempo_button.emit_signal("pressed")
	await get_tree().process_frame
	var assault_button: Button = meta_scene.find_child("UnlockCard_assault", true, false) as Button
	assault_button.emit_signal("pressed")
	await get_tree().process_frame
	var chrono_button: Button = meta_scene.find_child("UnlockRelic_chrono_shard", true, false) as Button
	chrono_button.emit_signal("pressed")
	await get_tree().process_frame

	if not _has_starter_id(Game.get_unlocked_starters(), "tempo"):
		_fail("Meta progress smoke failed: starter unlock did not apply")
		return
	if not Game.get_unlocked_card_ids().has("assault"):
		_fail("Meta progress smoke failed: card unlock did not apply")
		return
	if not Game.get_unlocked_relic_ids().has("chrono_shard"):
		_fail("Meta progress smoke failed: relic unlock did not apply")
		return
	if Game.get_meta_points() != 16:
		_fail("Meta progress smoke failed: meta point total did not decrease by unlock costs")
		return

	meta_scene.queue_free()
	await get_tree().process_frame

	var run_setup_scene: Control = load("res://scenes/run_setup/RunSetup.tscn").instantiate() as Control
	add_child(run_setup_scene)
	await get_tree().process_frame
	if run_setup_scene.find_child("StarterButton_tempo", true, false) == null:
		_fail("Meta progress smoke failed: RunSetup did not reflect the unlocked starter")
		return
	if run_setup_scene.find_child("StarterButton_fortress", true, false) != null:
		_fail("Meta progress smoke failed: RunSetup should keep locked starters hidden")
		return
	run_setup_scene.queue_free()
	await get_tree().process_frame

	var library_scene: Control = load("res://scenes/library/CardLibrary.tscn").instantiate() as Control
	add_child(library_scene)
	await get_tree().process_frame
	var assault_status: Label = library_scene.find_child("LibraryStatus_assault", true, false) as Label
	var execution_status: Label = library_scene.find_child("LibraryStatus_execution", true, false) as Label
	if assault_status == null or assault_status.text != "Unlocked":
		_fail("Meta progress smoke failed: card library did not reflect the unlocked rare card")
		return
	if execution_status == null or execution_status.text.find("Locked") == -1:
		_fail("Meta progress smoke failed: card library should still show locked epic cards")
		return

	Game.developer_reset_meta_progress()
	if Game.get_meta_points() != Game.DEVELOPER_META_RESET_POINTS:
		_fail("Meta progress smoke failed: developer reset should restore the debug point budget")
		return
	if Game.get_unlocked_card_ids().has("assault"):
		_fail("Meta progress smoke failed: developer reset should relock previously unlocked rare cards")
		return
	if int(Game.get_permanent_bonuses().get("max_hp", 0)) != 0:
		_fail("Meta progress smoke failed: developer reset should clear claimed permanent bonuses")
		return

	meta_scene = load("res://scenes/meta/MetaProgress.tscn").instantiate() as Control
	add_child(meta_scene)
	await get_tree().process_frame
	var reset_assault_button: Button = meta_scene.find_child("UnlockCard_assault", true, false) as Button
	if reset_assault_button == null or reset_assault_button.disabled:
		_fail("Meta progress smoke failed: developer reset should allow cards to be unlocked again immediately")
		return
	reset_assault_button.emit_signal("pressed")
	await get_tree().process_frame
	if not Game.get_unlocked_card_ids().has("assault"):
		_fail("Meta progress smoke failed: card could not be re-unlocked after developer reset")
		return

	print("Meta progress smoke passed")
	get_tree().quit()


func _assert_default_meta() -> void:
	if Game.get_unlocked_starters().size() != 1:
		_fail("Meta progress smoke failed: default starter set should only unlock one starter")
		return
	var starter_id: String = String(Game.get_unlocked_starters()[0].get("id", ""))
	if starter_id != "balanced":
		_fail("Meta progress smoke failed: balanced starter should be unlocked by default")
		return
	if Game.get_unlocked_card_ids().has("assault"):
		_fail("Meta progress smoke failed: rare cards should be locked by default")
		return
	if Game.get_unlocked_relic_ids().has("chrono_shard"):
		_fail("Meta progress smoke failed: chrono shard should be locked by default")
	if Game.get_meta_points() != Game.DEVELOPER_META_RESET_POINTS:
		_fail("Meta progress smoke failed: developer reset should seed debug points")


func _has_starter_id(starters: Array[Dictionary], starter_id: String) -> bool:
	for starter in starters:
		if String(starter.get("id", "")) == starter_id:
			return true
	return false


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(1)
