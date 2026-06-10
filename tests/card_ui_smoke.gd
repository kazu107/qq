extends Control


func _ready() -> void:
	size = Vector2(1280.0, 720.0)
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	var probe_button: CardButton = CardButton.new()
	probe_button.set_tile_size(Vector2(120.0, 120.0))
	probe_button.size = Vector2(120.0, 120.0)
	add_child(probe_button)

	var cooldown_state: CardRuntimeState = CardRuntimeState.new()
	cooldown_state.runtime_id = "probe"
	cooldown_state.card_id = "strike"
	cooldown_state.begin_cooldown(1.5)
	var strike_def: CardDef = Database.get_card("strike")
	if strike_def == null:
		push_error("Card UI smoke failed: missing strike card definition")
		get_tree().quit(1)
		return

	probe_button.bind(strike_def, cooldown_state, false, false)
	await get_tree().process_frame

	var cooldown_shade: ColorRect = probe_button.get_node("CooldownShade") as ColorRect
	if cooldown_shade == null or cooldown_shade.size.x <= 0.0 or cooldown_shade.size.x >= probe_button.size.x:
		push_error("Card UI smoke failed: cooldown overlay was not positioned correctly")
		get_tree().quit(1)
		return
	var probe_state_badge: ColorRect = probe_button.get_node("StateBadge") as ColorRect
	if probe_state_badge == null or probe_state_badge.visible:
		push_error("Card UI smoke failed: state label badge should be hidden")
		get_tree().quit(1)
		return

	var rounding_state: CardRuntimeState = CardRuntimeState.new()
	rounding_state.begin_cooldown(0.04)
	if rounding_state.state != CardRuntimeState.CardState.READY or not is_zero_approx(rounding_state.cooldown_remaining):
		push_error("Card UI smoke failed: cooldown should become ready once display time reaches 0.0s")
		get_tree().quit(1)
		return

	var ready_state: CardRuntimeState = CardRuntimeState.new()
	var ready_button: CardButton = CardButton.new()
	ready_button.set_tile_size(Vector2(120.0, 120.0))
	ready_button.size = Vector2(120.0, 120.0)
	add_child(ready_button)
	ready_button.bind(strike_def, ready_state, true, true)
	await get_tree().process_frame
	var ready_meta: Label = ready_button.get_node("MetaBadge/Meta") as Label
	if ready_meta == null or ready_meta.text != "ready":
		push_error("Card UI smoke failed: usable card should show ready text")
		get_tree().quit(1)
		return

	var preparing_state: CardRuntimeState = CardRuntimeState.new()
	preparing_state.runtime_id = "prep_probe"
	preparing_state.card_id = "strike"
	preparing_state.begin_prepare()
	var preparing_button: CardButton = CardButton.new()
	preparing_button.set_tile_size(Vector2(120.0, 120.0))
	preparing_button.size = Vector2(120.0, 120.0)
	add_child(preparing_button)
	preparing_button.bind(strike_def, preparing_state, false, false)
	await get_tree().process_frame
	var preparing_meta: Label = preparing_button.get_node("MetaBadge/Meta") as Label
	if preparing_meta == null or preparing_meta.text != "casting":
		push_error("Card UI smoke failed: preparing card should show casting text")
		get_tree().quit(1)
		return

	var hand_panel: CardHandPanel = CardHandPanel.new()
	add_child(hand_panel)

	var unit: UnitState = UnitState.new()
	unit.active_slot_max = 3
	unit.active_slots_used = 1
	unit.set_runtime_states([
		_make_runtime_state("quick_slash", "hand_quick", 0, CardRuntimeState.CardState.READY, 0.0),
		_make_runtime_state("guard", "hand_guard", 1, CardRuntimeState.CardState.COOLDOWN, 1.0),
		_make_runtime_state("reload", "hand_reload", 2, CardRuntimeState.CardState.READY, 0.0),
	])

	hand_panel.refresh_cards(unit)
	await get_tree().process_frame

	if hand_panel.get_child_count() != 3:
		push_error("Card UI smoke failed: hand panel did not create the expected card pool")
		get_tree().quit(1)
		return

	var first_button: CardButton = hand_panel.get_child(0) as CardButton
	if first_button == null or first_button.tooltip_text == "":
		push_error("Card UI smoke failed: hover tooltip text was not assigned")
		get_tree().quit(1)
		return
	if first_button.tooltip_text.find("Effects:") == -1 or first_button.tooltip_text.find("Deal 4 damage") == -1:
		push_error("Card UI smoke failed: tooltip should include concrete effect values")
		get_tree().quit(1)
		return
	if first_button.tooltip_text.find("Grades:") == -1 or first_button.tooltip_text.find("Base | Cast") == -1 or first_button.tooltip_text.find("+3 |") == -1:
		push_error("Card UI smoke failed: tooltip should include all grade info")
		get_tree().quit(1)
		return
	if absf(first_button.size.x - first_button.size.y) > 0.1:
		push_error("Card UI smoke failed: battle hand tile is not square")
		get_tree().quit(1)
		return

	hand_panel.refresh_cards(unit)
	await get_tree().process_frame

	if hand_panel.get_child_count() != 3:
		push_error("Card UI smoke failed: hand panel recreated card nodes during refresh")
		get_tree().quit(1)
		return

	var timeline_panel: TimelinePanel = TimelinePanel.new()
	timeline_panel.size = Vector2(900.0, 300.0)
	add_child(timeline_panel)
	timeline_panel.refresh_timeline([
		_make_timeline_entry("reload", "player", 4.2, 1.0, 2),
		_make_timeline_entry("heavy_swing", "enemy", 2.8, 0.5, 1),
		_make_timeline_entry("guard", "player", 3.4, 0.8, 3),
	], 1.5)
	await get_tree().process_frame

	if timeline_panel.custom_minimum_size.y < 260.0:
		push_error("Card UI smoke failed: timeline panel height should stay fixed")
		get_tree().quit(1)
		return

	var cards_track: Control = timeline_panel.get_node("TimelineScroll/TimelineCards") as Control
	if cards_track == null or cards_track.get_child_count() < 3:
		push_error("Card UI smoke failed: timeline panel did not create card tiles")
		get_tree().quit(1)
		return

	var earliest_button: CardButton = cards_track.get_child(0) as CardButton
	if earliest_button == null or earliest_button.runtime_id != "timeline_1":
		push_error("Card UI smoke failed: timeline entries were not sorted by earliest cast")
		get_tree().quit(1)
		return
	if earliest_button.custom_minimum_size != Vector2(168.0, 168.0):
		push_error("Card UI smoke failed: timeline card tile should be four-card area size")
		get_tree().quit(1)
		return
	var timeline_meta: Label = earliest_button.get_node("MetaBadge/Meta") as Label
	if timeline_meta == null or timeline_meta.text != "1.3s":
		push_error("Card UI smoke failed: timeline card should show remaining seconds")
		get_tree().quit(1)
		return
	var later_button: CardButton = cards_track.get_child(2) as CardButton
	if later_button == null or earliest_button.position.x >= later_button.position.x:
		push_error("Card UI smoke failed: timeline cards should slide right-to-left by remaining time")
		get_tree().quit(1)
		return
	var next_badge: ColorRect = earliest_button.get_node("TimelineNextBadge") as ColorRect
	var next_label: Label = earliest_button.get_node("TimelineNextBadge/Next") as Label
	if next_badge == null or next_label == null or not next_badge.visible or next_label.text != "NEXT":
		push_error("Card UI smoke failed: earliest timeline card should show NEXT badge")
		get_tree().quit(1)
		return
	var timeline_progress: Node = earliest_button.find_child("TimelineProgressBar", true, false)
	if timeline_progress != null:
		push_error("Card UI smoke failed: timeline card should not use progress bars")
		get_tree().quit(1)
		return
	var timeline_shade: ColorRect = earliest_button.get_node("CooldownShade") as ColorRect
	if timeline_shade == null or timeline_shade.visible:
		push_error("Card UI smoke failed: timeline card should not use brightness shading")
		get_tree().quit(1)
		return
	var timeline_scale: HBoxContainer = timeline_panel.get_node("TimelineScale") as HBoxContainer
	if timeline_scale == null or timeline_scale.get_child_count() < 5:
		push_error("Card UI smoke failed: timeline scale markers were not rendered")
		get_tree().quit(1)
		return
	var now_marker: Label = timeline_scale.get_child(0) as Label
	if now_marker == null or now_marker.text != "NOW":
		push_error("Card UI smoke failed: timeline scale should start with NOW")
		get_tree().quit(1)
		return
	var max_marker: Label = timeline_scale.get_child(timeline_scale.get_child_count() - 1) as Label
	if max_marker == null or max_marker.text != "+3.2s":
		push_error("Card UI smoke failed: timeline scale should end at max cast time")
		get_tree().quit(1)
		return
	if earliest_button.tooltip_text.find("Owner: Enemy") == -1:
		push_error("Card UI smoke failed: timeline tooltip text was not assigned")
		get_tree().quit(1)
		return
	var timeline_style: StyleBoxFlat = earliest_button.get_theme_stylebox("normal") as StyleBoxFlat
	if timeline_style == null or timeline_style.border_color.r < 0.8:
		push_error("Card UI smoke failed: enemy timeline border should be red")
		get_tree().quit(1)
		return
	var timeline_overlay: Panel = earliest_button.get_node("FrameOverlay") as Panel
	if timeline_overlay == null:
		push_error("Card UI smoke failed: frame overlay node was not created")
		get_tree().quit(1)
		return
	var overlay_style: StyleBoxFlat = timeline_overlay.get_theme_stylebox("panel") as StyleBoxFlat
	if overlay_style == null or overlay_style.border_color.r < 0.8:
		push_error("Card UI smoke failed: enemy timeline overlay border should be red")
		get_tree().quit(1)
		return

	var preview_panel: CardHandPanel = CardHandPanel.new()
	add_child(preview_panel)
	preview_panel.set_tile_size(Vector2(96.0, 96.0))
	preview_panel.refresh_card_ids(["quick_slash", "guard", "reload"], false, "KIT")
	await get_tree().process_frame
	if preview_panel.get_child_count() != 3:
		push_error("Card UI smoke failed: preview panel did not create the expected card pool")
		get_tree().quit(1)
		return

	var run_setup_scene: Control = load("res://scenes/run_setup/RunSetup.tscn").instantiate() as Control
	add_child(run_setup_scene)
	await get_tree().process_frame
	var starter_cards: CardHandPanel = run_setup_scene.find_child("StarterCards", true, false) as CardHandPanel
	if starter_cards == null or starter_cards.get_child_count() < 1:
		push_error("Card UI smoke failed: RunSetup did not render starter cards")
		get_tree().quit(1)
		return
	run_setup_scene.queue_free()
	await get_tree().process_frame

	Game.start_new_run("balanced")
	Game.reward_options = ["assault", "guard", "reload"]
	Game.last_battle_summary = {"enemy_name": "Scout"}
	var reward_scene: Control = load("res://scenes/reward/Reward.tscn").instantiate() as Control
	add_child(reward_scene)
	await get_tree().process_frame
	var reward_cards: CardHandPanel = reward_scene.find_child("RewardCards", true, false) as CardHandPanel
	if reward_cards == null or reward_cards.get_child_count() != 3:
		push_error("Card UI smoke failed: Reward did not render reward cards")
		get_tree().quit(1)
		return

	reward_scene.queue_free()
	await get_tree().process_frame

	var unit_panel: UnitPanel = UnitPanel.new()
	unit_panel.configure_visual("player", "balanced")
	add_child(unit_panel)
	await get_tree().process_frame

	var player_unit: UnitState = UnitState.new()
	player_unit.unit_id = "player"
	player_unit.display_name = "Balanced Frame"
	player_unit.max_hp = 60
	player_unit.hp = 48
	player_unit.shield = 3
	player_unit.attack = 3
	player_unit.defense = 1
	player_unit.speed = 5
	unit_panel.refresh_unit(player_unit)
	await get_tree().process_frame

	var portrait: TextureRect = unit_panel.get_node("BodyRow/PortraitFrame/PortraitMargin/PortraitAnchor/Portrait") as TextureRect
	if portrait == null or portrait.texture == null:
		push_error("Card UI smoke failed: unit portrait was not rendered")
		get_tree().quit(1)
		return

	var hp_bar: ProgressBar = unit_panel.get_node("BodyRow/InfoColumn/HpStack/HpBar") as ProgressBar
	var hp_label: Label = unit_panel.get_node("BodyRow/InfoColumn/HpStack/HpLabel") as Label
	if hp_bar == null or hp_label == null or int(hp_bar.value) != 48 or hp_label.text != "48 / 60":
		push_error("Card UI smoke failed: HP bar and HP label should match the unit state")
		get_tree().quit(1)
		return

	player_unit.hp = 39
	player_unit.shield = 5
	unit_panel.refresh_unit(player_unit)
	await get_tree().process_frame

	var effect_layer: Control = unit_panel.get_node("BodyRow/PortraitFrame/PortraitMargin/PortraitAnchor/EffectLayer") as Control
	if effect_layer == null or effect_layer.get_child_count() < 2:
		push_error("Card UI smoke failed: unit portrait should emit floating battle text")
		get_tree().quit(1)
		return

	var floating_texts: Array[String] = []
	for effect_index in range(effect_layer.get_child_count()):
		var effect_label: Label = effect_layer.get_child(effect_index) as Label
		if effect_label != null:
			floating_texts.append(effect_label.text)
	if not floating_texts.has("-9") or not floating_texts.has("Shield +2"):
		push_error("Card UI smoke failed: floating battle text should show damage and shield gain")
		get_tree().quit(1)
		return

	Game.start_new_run("balanced")
	var battle_scene: Control = load("res://scenes/battle/Battle.tscn").instantiate() as Control
	add_child(battle_scene)
	await get_tree().process_frame

	var bottom_split: HBoxContainer = battle_scene.find_child("BottomSplit", true, false) as HBoxContainer
	var timeline_section: VBoxContainer = battle_scene.find_child("TimelineSection", true, false) as VBoxContainer
	var battle_timeline_panel: TimelinePanel = battle_scene.find_child("TimelinePanel", true, false) as TimelinePanel
	var obsolete_secondary_timeline_section: VBoxContainer = battle_scene.find_child("TimelineSectionSecondary", true, false) as VBoxContainer
	var obsolete_log_section: VBoxContainer = battle_scene.find_child("LogSection", true, false) as VBoxContainer
	var log_button: Button = battle_scene.find_child("BattleLogButton", true, false) as Button
	var log_popup: PanelContainer = battle_scene.find_child("BattleLogPopup", true, false) as PanelContainer
	var log_panel: LogPanel = battle_scene.find_child("BattleLogPanel", true, false) as LogPanel
	if bottom_split == null or timeline_section == null or battle_timeline_panel == null or log_button == null or log_popup == null or log_panel == null:
		push_error("Card UI smoke failed: battle scene layout sections were not created")
		get_tree().quit(1)
		return
	if obsolete_log_section != null:
		push_error("Card UI smoke failed: bottom log section should be replaced by a timeline section")
		get_tree().quit(1)
		return
	if obsolete_secondary_timeline_section != null or bottom_split.get_child_count() != 1:
		push_error("Card UI smoke failed: battle bottom area should be one connected timeline")
		get_tree().quit(1)
		return
	if bottom_split.custom_minimum_size.y < 320.0 or timeline_section.custom_minimum_size.y < 320.0:
		push_error("Card UI smoke failed: connected timeline should keep a fixed minimum height")
		get_tree().quit(1)
		return
	if battle_timeline_panel.custom_minimum_size.y < 260.0:
		push_error("Card UI smoke failed: connected timeline panel should keep the enlarged timeline height")
		get_tree().quit(1)
		return
	if log_panel.custom_minimum_size.y < 180.0:
		push_error("Card UI smoke failed: popup log panel should keep a fixed height")
		get_tree().quit(1)
		return
	if log_popup.visible:
		push_error("Card UI smoke failed: battle log popup should be hidden by default")
		get_tree().quit(1)
		return
	log_button.emit_signal("pressed")
	await get_tree().process_frame
	if not log_popup.visible:
		push_error("Card UI smoke failed: battle log button should open the log popup")
		get_tree().quit(1)
		return
	var battle_log_text: RichTextLabel = log_popup.find_child("BattleLogText", true, false) as RichTextLabel
	if battle_log_text == null:
		push_error("Card UI smoke failed: battle log popup did not render log text")
		get_tree().quit(1)
		return
	log_button.emit_signal("pressed")
	await get_tree().process_frame
	if log_popup.visible:
		push_error("Card UI smoke failed: battle log button should close the log popup")
		get_tree().quit(1)
		return
	battle_scene.queue_free()
	await get_tree().process_frame

	var new_card_ids: Array[String] = [
		"repair_burst",
		"tripwire",
		"stasis_field",
		"rupture_strike",
		"bastion_drive",
		"adrenaline_link",
		"purge_pulse",
		"meteor_crash",
	]
	for card_id in new_card_ids:
		if not ResourceLoader.exists("res://assets/icons/cards/%s.png" % card_id):
			push_error("Card UI smoke failed: missing generated art for %s" % card_id)
			get_tree().quit(1)
			return

	var portrait_ids: Array[String] = [
		"balanced",
		"tempo",
		"fortress",
		"scout",
		"brute",
		"disruptor",
		"guardian",
		"raider",
		"medic_drone",
		"chronoguard",
		"boss_timekeeper",
	]
	for portrait_id in portrait_ids:
		if not ResourceLoader.exists("res://assets/portraits/%s.png" % portrait_id):
			push_error("Card UI smoke failed: missing generated portrait for %s" % portrait_id)
			get_tree().quit(1)
			return

	var shield_unit: UnitState = UnitState.new()
	shield_unit.shield = 3
	var decayed_once: int = shield_unit.tick_shield_decay(1.1)
	var decayed_twice: int = shield_unit.tick_shield_decay(2.1)
	if decayed_once != 1 or decayed_twice != 2 or shield_unit.shield != 0:
		push_error("Card UI smoke failed: shield should decay by 1 per second")
		get_tree().quit(1)
		return

	print("Card UI smoke passed")
	get_tree().quit()


func _make_runtime_state(card_id: String, runtime_id: String, loadout_index: int, state: CardRuntimeState.CardState, cooldown_remaining: float) -> CardRuntimeState:
	var runtime_state: CardRuntimeState = CardRuntimeState.new()
	runtime_state.card_id = card_id
	runtime_state.runtime_id = runtime_id
	runtime_state.loadout_index = loadout_index
	runtime_state.state = state
	runtime_state.cooldown_remaining = cooldown_remaining
	return runtime_state


func _make_timeline_entry(card_id: String, owner_side: String, scheduled_time: float, created_at: float, instance_id: int) -> TimelineEntry:
	var entry: TimelineEntry = TimelineEntry.new()
	entry.card_id = card_id
	entry.owner_side = owner_side
	entry.card_name = card_id
	entry.runtime_id = "timeline_%d" % instance_id
	entry.scheduled_time = scheduled_time
	entry.created_at = created_at
	entry.instance_id = instance_id
	entry.slot_cost = 1
	return entry
