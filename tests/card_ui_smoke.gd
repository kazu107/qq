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

	var scene_root: Control = get_tree().current_scene as Control
	var atmosphere_background: Control = null
	if scene_root != null:
		atmosphere_background = scene_root.find_child("GameAtmosphereBackground", false, false) as Control
	if scene_root == null or scene_root.theme == null or atmosphere_background == null or atmosphere_background.z_index > -1000:
		push_error("Card UI smoke failed: global rich UI theme/background was not applied")
		get_tree().quit(1)
		return

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
	var ready_cost_badge: ColorRect = ready_button.get_node("CostBadge") as ColorRect
	var ready_cost: Label = ready_button.get_node("CostBadge/Cost") as Label
	if ready_cost_badge == null \
	or ready_cost == null \
	or ready_cost.text != str(strike_def.active_slot_cost) \
	or ready_cost_badge.color.g < 0.6 \
	or ready_cost_badge.offset_left >= 0.0 \
	or ready_cost_badge.offset_top >= 0.0:
		push_error("Card UI smoke failed: card cost should render in a green top-left badge")
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
	if first_button.tooltip_text.find("Grades:") != -1:
		push_error("Card UI smoke failed: battle hand tooltip should omit grade info")
		get_tree().quit(1)
		return
	var weak_def: CardDef = Database.get_card("weak_shot")
	var weak_state: CardRuntimeState = CardRuntimeState.new()
	weak_state.runtime_id = "weak_probe"
	weak_state.card_id = "weak_shot"
	var weak_button: CardButton = CardButton.new()
	weak_button.set_tile_size(Vector2(120.0, 120.0))
	weak_button.size = Vector2(120.0, 120.0)
	add_child(weak_button)
	weak_button.bind(weak_def, weak_state, false, false)
	await get_tree().process_frame
	var weak_status_name: String = Localization.get_status_name("weak")
	if weak_button.tooltip_text.find("Status Details:") == -1 or weak_button.tooltip_text.find(weak_status_name) == -1:
		push_error("Card UI smoke failed: battle tooltip should append applied status details")
		get_tree().quit(1)
		return
	var weak_rich_tooltip: Control = weak_button._make_custom_tooltip(weak_button.tooltip_text) as Control
	var weak_rich_label: RichTextLabel = weak_rich_tooltip.find_child("CardTooltipText", true, false) as RichTextLabel
	if weak_rich_label == null or weak_rich_label.text.find("[color=#ffd45a]%s[/color]" % weak_status_name) == -1:
		push_error("Card UI smoke failed: battle tooltip should highlight applied status names")
		get_tree().quit(1)
		return
	weak_rich_tooltip.free()
	var tooltip_run: RunState = RunState.from_starter(Database.get_starter("balanced"), 123)
	tooltip_run.temporary_card_modifiers = {
		"quick_slash": {
			"damage": 2,
			"cast_time": 1.2,
			"recast_time": -2.0,
		},
	}
	var boosted_quick: CardDef = CardUpgradeResolver.build_effective_card("quick_slash", tooltip_run)
	var boosted_button: CardButton = CardButton.new()
	boosted_button.set_tile_size(Vector2(120.0, 120.0))
	boosted_button.size = Vector2(120.0, 120.0)
	add_child(boosted_button)
	boosted_button.bind_preview(boosted_quick, "boosted_quick")
	await get_tree().process_frame
	if boosted_button.tooltip_text.find("Deal 6 (+2) damage") == -1:
		push_error("Card UI smoke failed: boosted tooltip should show plain effect deltas")
		get_tree().quit(1)
		return
	if boosted_button.tooltip_text.find("Grades:") == -1 or boosted_button.tooltip_text.find("Base | Cast") == -1 or boosted_button.tooltip_text.find("+3 |") == -1:
		push_error("Card UI smoke failed: preview tooltip should keep all grade info")
		get_tree().quit(1)
		return
	if boosted_button.tooltip_text.find("Cast: 3.0 (+1.2)s") == -1 or boosted_button.tooltip_text.find("Recast: 6.0 (-2.0)s") == -1:
		push_error("Card UI smoke failed: boosted tooltip should show plain timing deltas")
		get_tree().quit(1)
		return
	var rich_tooltip: Control = boosted_button._make_custom_tooltip(boosted_button.tooltip_text) as Control
	var rich_label: RichTextLabel = rich_tooltip.find_child("CardTooltipText", true, false) as RichTextLabel
	if rich_label == null \
	or rich_label.text.find("[color=#72d36f]6 (+2)[/color]") == -1 \
	or rich_label.text.find("[color=#ff6868]3.0 (+1.2)[/color]") == -1 \
	or rich_label.text.find("[color=#72d36f]6.0 (-2.0)[/color]") == -1:
		push_error("Card UI smoke failed: boosted custom tooltip should color beneficial and harmful deltas")
		get_tree().quit(1)
		return
	rich_tooltip.free()
	if absf(first_button.size.x - first_button.size.y) > 0.1:
		push_error("Card UI smoke failed: battle hand tile is not square")
		get_tree().quit(1)
		return
	var hovered_runtime_ids: Array[String] = []
	var unhovered_runtime_ids: Array[String] = []
	hand_panel.card_hovered.connect(func(runtime_id: String) -> void:
		hovered_runtime_ids.append(runtime_id)
	)
	hand_panel.card_unhovered.connect(func(runtime_id: String) -> void:
		unhovered_runtime_ids.append(runtime_id)
	)
	first_button.emit_signal("mouse_entered")
	first_button.emit_signal("mouse_exited")
	await get_tree().process_frame
	if not hovered_runtime_ids.has("hand_quick") or not unhovered_runtime_ids.has("hand_quick"):
		push_error("Card UI smoke failed: hand panel should relay player card hover state")
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
	timeline_panel.set_fixed_horizon(6.0)
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
	var guard_button_before_delay: CardButton = _find_timeline_card(cards_track, "timeline_3")
	if guard_button_before_delay == null:
		push_error("Card UI smoke failed: target card for delay slide was not rendered")
		get_tree().quit(1)
		return
	var guard_position_before_delay: float = guard_button_before_delay.position.x
	timeline_panel.refresh_timeline([
		_make_timeline_entry("reload", "player", 4.2, 1.0, 2),
		_make_timeline_entry("heavy_swing", "enemy", 2.8, 0.5, 1),
		_make_timeline_entry("guard", "player", 4.4, 0.8, 3),
	], 1.5)
	var guard_button_delay_start: CardButton = _find_timeline_card(cards_track, "timeline_3")
	if guard_button_delay_start == null or absf(guard_button_delay_start.position.x - guard_position_before_delay) > 1.0:
		push_error("Card UI smoke failed: delayed timeline card should start sliding from its previous position")
		get_tree().quit(1)
		return
	timeline_panel.refresh_timeline([
		_make_timeline_entry("reload", "player", 4.2, 1.0, 2),
		_make_timeline_entry("heavy_swing", "enemy", 2.8, 0.5, 1),
		_make_timeline_entry("guard", "player", 4.4, 0.8, 3),
	], 1.75)
	var guard_button_delay_mid: CardButton = _find_timeline_card(cards_track, "timeline_3")
	var expected_mid_x: float = _expected_timeline_x(timeline_panel, 2.15, 6.0)
	if guard_button_delay_mid == null or absf(guard_button_delay_mid.position.x - expected_mid_x) > 1.0:
		push_error("Card UI smoke failed: delayed timeline card should slide toward the delayed time over 0.5s")
		get_tree().quit(1)
		return
	timeline_panel.refresh_timeline([
		_make_timeline_entry("reload", "player", 4.2, 1.0, 2),
		_make_timeline_entry("heavy_swing", "enemy", 2.8, 0.5, 1),
		_make_timeline_entry("guard", "player", 4.4, 0.8, 3),
	], 2.0)
	var guard_button_delay_end: CardButton = _find_timeline_card(cards_track, "timeline_3")
	var expected_end_x: float = _expected_timeline_x(timeline_panel, 2.4, 6.0)
	if guard_button_delay_end == null or absf(guard_button_delay_end.position.x - expected_end_x) > 1.0:
		push_error("Card UI smoke failed: delayed timeline card should include elapsed time when the slide ends")
		get_tree().quit(1)
		return
	var reverse_entry_start: TimelineEntry = _make_timeline_entry("guard", "enemy", 4.0, 1.0, 7)
	timeline_panel.refresh_timeline([reverse_entry_start], 2.0)
	var reverse_button_start: CardButton = _find_timeline_card(cards_track, "timeline_7")
	var expected_reverse_start_x: float = _expected_timeline_x(timeline_panel, 2.0, 6.0)
	if reverse_button_start == null or absf(reverse_button_start.position.x - expected_reverse_start_x) > 1.0:
		push_error("Card UI smoke failed: reverse-flow target card should start at its current remaining time")
		get_tree().quit(1)
		return
	var reverse_entry_step: TimelineEntry = _make_timeline_entry("guard", "enemy", 4.5, 1.0, 7)
	reverse_entry_step.continuous_shift_battle_time = 2.25
	reverse_entry_step.continuous_shift_amount = 0.5
	timeline_panel.refresh_timeline([reverse_entry_step], 2.25)
	var reverse_button_step: CardButton = _find_timeline_card(cards_track, "timeline_7")
	var expected_reverse_step_x: float = _expected_timeline_x(timeline_panel, 2.25, 6.0)
	if reverse_button_step == null or absf(reverse_button_step.position.x - expected_reverse_step_x) > 1.0:
		push_error("Card UI smoke failed: reverse-flow timeline card should move right at the direct continuous-flow position")
		get_tree().quit(1)
		return
	var reverse_entry_step_2: TimelineEntry = _make_timeline_entry("guard", "enemy", 5.0, 1.0, 7)
	reverse_entry_step_2.continuous_shift_battle_time = 2.5
	reverse_entry_step_2.continuous_shift_amount = 0.5
	timeline_panel.refresh_timeline([reverse_entry_step_2], 2.5)
	var reverse_button_step_2: CardButton = _find_timeline_card(cards_track, "timeline_7")
	var expected_reverse_step_2_x: float = _expected_timeline_x(timeline_panel, 2.5, 6.0)
	if reverse_button_step_2 == null or absf(reverse_button_step_2.position.x - expected_reverse_step_2_x) > 1.0:
		push_error("Card UI smoke failed: reverse-flow timeline card should keep moving right at a steady calculated rate")
		get_tree().quit(1)
		return
	timeline_panel.refresh_timeline([
		_make_timeline_entry("reload", "player", 4.2, 1.0, 2),
		_make_timeline_entry("heavy_swing", "enemy", 2.8, 0.5, 1),
		_make_timeline_entry("guard", "player", 3.4, 0.8, 3),
	], 1.5)
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
	var zero_marker: Label = timeline_scale.get_child(0) as Label
	if zero_marker == null or zero_marker.text != "0s":
		push_error("Card UI smoke failed: timeline scale should start at 0s")
		get_tree().quit(1)
		return
	var quarter_marker: Label = timeline_scale.get_child(1) as Label
	if quarter_marker == null or quarter_marker.text != "1.5s":
		push_error("Card UI smoke failed: timeline scale should render quarter steps from the ceiling max")
		get_tree().quit(1)
		return
	var max_marker: Label = timeline_scale.get_child(timeline_scale.get_child_count() - 1) as Label
	if max_marker == null or max_marker.text != "6s":
		push_error("Card UI smoke failed: timeline scale should use fixed max cast time")
		get_tree().quit(1)
		return
	if earliest_button.tooltip_text.find("Cast:") == -1 or earliest_button.tooltip_text.find("Recast:") == -1:
		push_error("Card UI smoke failed: timeline tooltip text was not assigned")
		get_tree().quit(1)
		return
	if earliest_button.tooltip_text.find("Owner:") != -1:
		push_error("Card UI smoke failed: battle timeline tooltip should omit owner metadata")
		get_tree().quit(1)
		return
	if earliest_button.tooltip_text.find("Grades:") != -1:
		push_error("Card UI smoke failed: battle timeline tooltip should omit grade info")
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
	var timeline_preview_entry: TimelineEntry = _make_timeline_entry("quick_slash", "player", 5.1, 1.5, 900)
	timeline_preview_entry.runtime_id = "preview_hand_quick"
	timeline_panel.refresh_timeline([
		_make_timeline_entry("reload", "player", 4.2, 1.0, 2),
		_make_timeline_entry("heavy_swing", "enemy", 2.8, 0.5, 1),
		_make_timeline_entry("guard", "player", 3.4, 0.8, 3),
	], 1.5, null, timeline_preview_entry, Database.get_card("quick_slash"))
	await get_tree().process_frame
	var timeline_preview: CardButton = cards_track.get_node("TimelinePreviewCard") as CardButton
	if timeline_preview == null or not timeline_preview.visible:
		push_error("Card UI smoke failed: timeline preview card should be visible while hovering")
		get_tree().quit(1)
		return
	var timeline_preview_bleach: ColorRect = timeline_preview.get_node("BleachOverlay") as ColorRect
	if timeline_preview_bleach == null or timeline_preview_bleach.visible:
		push_error("Card UI smoke failed: timeline preview should not use a white bleach overlay")
		get_tree().quit(1)
		return
	timeline_panel.refresh_timeline([
		_make_timeline_entry("reload", "player", 4.2, 1.0, 2),
		_make_timeline_entry("heavy_swing", "enemy", 2.8, 0.5, 1),
		_make_timeline_entry("guard", "player", 3.4, 0.8, 3),
	], 1.5)
	timeline_panel.refresh_timeline([
		_make_timeline_entry("reload", "player", 4.2, 1.0, 2),
		_make_timeline_entry("heavy_swing", "enemy", 2.8, 0.5, 1),
		_make_timeline_entry("guard", "player", 3.4, 0.8, 3),
	], 1.5, null, timeline_preview_entry, Database.get_card("quick_slash"))
	var timeline_preview_start_alpha: float = timeline_preview.modulate.a
	if absf(timeline_preview_start_alpha - 0.58) > 0.01:
		push_error("Card UI smoke failed: timeline preview alpha should start at 0.58")
		get_tree().quit(1)
		return
	timeline_panel._process(0.5)
	var timeline_preview_mid_alpha: float = timeline_preview.modulate.a
	if absf(timeline_preview_mid_alpha - 0.32) > 0.02:
		push_error("Card UI smoke failed: timeline preview alpha should reach 0.32 halfway through the cycle")
		get_tree().quit(1)
		return
	timeline_panel._process(0.5)
	var timeline_preview_end_alpha: float = timeline_preview.modulate.a
	if absf(timeline_preview_end_alpha - 0.58) > 0.02:
		push_error("Card UI smoke failed: timeline preview alpha should return to 0.58 after one cycle")
		get_tree().quit(1)
		return
	if timeline_preview.position.x <= earliest_button.position.x:
		push_error("Card UI smoke failed: timeline preview card should be positioned by preview cast time")
		get_tree().quit(1)
		return
	timeline_panel.refresh_timeline([
		_make_timeline_entry("reload", "player", 4.2, 1.0, 2),
		_make_timeline_entry("heavy_swing", "enemy", 2.8, 0.5, 1),
		_make_timeline_entry("guard", "player", 3.4, 0.8, 3),
	], 1.5)
	await get_tree().process_frame
	if timeline_preview.visible:
		push_error("Card UI smoke failed: timeline preview card should hide after hover ends")
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
	player_unit.speed = 5
	player_unit.active_slot_max = 4
	player_unit.active_slots_used = 2
	unit_panel.refresh_unit(player_unit)
	await get_tree().process_frame
	var obsolete_stats_label: Label = unit_panel.find_child("StatsLabel", true, false) as Label
	var stats_icon_row: HBoxContainer = unit_panel.get_node("BodyRow/InfoColumn/StatsIconRow") as HBoxContainer
	var attack_icon: TextureRect = null
	var speed_icon: TextureRect = null
	var attack_value: Label = null
	var speed_value: Label = null
	if stats_icon_row != null:
		attack_icon = stats_icon_row.find_child("AttackIcon", true, false) as TextureRect
		speed_icon = stats_icon_row.find_child("SpeedIcon", true, false) as TextureRect
		attack_value = stats_icon_row.find_child("AttackValue", true, false) as Label
		speed_value = stats_icon_row.find_child("SpeedValue", true, false) as Label
	if obsolete_stats_label != null \
	or stats_icon_row == null \
	or attack_icon == null \
	or speed_icon == null \
	or attack_icon.texture == null \
	or speed_icon.texture == null \
	or attack_value == null \
	or speed_value == null \
	or attack_value.text != "3" \
	or speed_value.text != "5":
		push_error("Card UI smoke failed: unit attack/speed stats should render as icons and values without the old text line")
		get_tree().quit(1)
		return
	player_unit.add_status("bleed", 10.0)
	player_unit.tick_statuses(6.0)
	player_unit.add_status("slow", 5.0)
	unit_panel.refresh_unit(player_unit)
	await get_tree().process_frame

	var status_icon_row: HBoxContainer = unit_panel.get_node("BodyRow/InfoColumn/StatusIconRow") as HBoxContainer
	var bleed_icon: TextureRect = null
	var slow_icon: TextureRect = null
	var bleed_time_label: Label = null
	if status_icon_row != null:
		bleed_icon = status_icon_row.find_child("StatusIcon_bleed", true, false) as TextureRect
		slow_icon = status_icon_row.find_child("StatusIcon_slow", true, false) as TextureRect
		bleed_time_label = status_icon_row.find_child("StatusTime_bleed", true, false) as Label
	if status_icon_row == null \
	or bleed_icon == null \
	or slow_icon == null \
	or bleed_time_label == null:
		push_error("Card UI smoke failed: unit statuses should render as icon/time groups")
		get_tree().quit(1)
		return
	if bleed_time_label.text != "4.0s":
		push_error("Card UI smoke failed: status icon should show remaining seconds to the right")
		get_tree().quit(1)
		return
	if bleed_time_label.self_modulate.g < 0.9:
		push_error("Card UI smoke failed: status seconds should use the bright green timer style")
		get_tree().quit(1)
		return
	if bleed_icon.tooltip_text != "":
		push_error("Card UI smoke failed: status icons should not use Godot's built-in tooltip")
		get_tree().quit(1)
		return
	if bleed_icon.self_modulate != Color.WHITE or slow_icon.self_modulate != Color.WHITE:
		push_error("Card UI smoke failed: status icons should not darken by remaining duration")
		get_tree().quit(1)
		return
	var bleed_icon_before_refresh: TextureRect = bleed_icon
	bleed_icon.emit_signal("mouse_entered")
	await get_tree().process_frame
	var status_tooltip_popup: PanelContainer = find_child("StatusTooltipPopup", true, false) as PanelContainer
	var status_tooltip_text: Label = null
	if status_tooltip_popup != null:
		status_tooltip_text = status_tooltip_popup.find_child("StatusTooltipText", true, false) as Label
	if status_tooltip_popup == null \
	or status_tooltip_text == null \
	or not status_tooltip_popup.visible \
	or status_tooltip_text.text.find("Remaining: 4.0s") == -1 \
	or status_tooltip_text.text.find("Takes 1 damage") == -1:
		push_error("Card UI smoke failed: status icon mouseover should show a visible detail popup")
		get_tree().quit(1)
		return
	if status_tooltip_popup.size.y > 120.0:
		push_error("Card UI smoke failed: status tooltip should size to its text instead of stretching down")
		get_tree().quit(1)
		return
	player_unit.tick_statuses(2.0)
	unit_panel.refresh_unit(player_unit)
	await get_tree().process_frame
	bleed_icon = status_icon_row.find_child("StatusIcon_bleed", true, false) as TextureRect
	bleed_time_label = status_icon_row.find_child("StatusTime_bleed", true, false) as Label
	if bleed_icon != bleed_icon_before_refresh:
		push_error("Card UI smoke failed: status icons should be reused across refreshes so hover can remain active")
		get_tree().quit(1)
		return
	if bleed_time_label == null or bleed_time_label.text != "2.0s":
		push_error("Card UI smoke failed: status seconds should update as remaining time decreases")
		get_tree().quit(1)
		return
	if status_tooltip_text.text.find("Remaining: 2.0s") == -1:
		push_error("Card UI smoke failed: status tooltip should update while the icon remains hovered")
		get_tree().quit(1)
		return
	if status_icon_row.find_child("StatusDarken_bleed", true, false) != null:
		push_error("Card UI smoke failed: status icon darken overlay should be removed")
		get_tree().quit(1)
		return
	bleed_icon.emit_signal("mouse_exited")
	await get_tree().process_frame
	var status_label: Label = unit_panel.get_node("BodyRow/InfoColumn/StatusLabel") as Label
	if status_label == null or status_label.text.find("Bleed") != -1 or status_label.text.find("Slow") != -1:
		push_error("Card UI smoke failed: unit status details should move out of the label text")
		get_tree().quit(1)
		return

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
	var shield_anchor: Control = unit_panel.get_node("BodyRow/InfoColumn/HpStack/ShieldBadgeAnchor") as Control
	var shield_icon: TextureRect = unit_panel.get_node("BodyRow/InfoColumn/HpStack/ShieldBadgeAnchor/ShieldIcon") as TextureRect
	var shield_label: Label = unit_panel.get_node("BodyRow/InfoColumn/HpStack/ShieldBadgeAnchor/ShieldLabel") as Label
	if shield_icon == null or shield_icon.texture == null or shield_label == null or shield_label.text != "3":
		push_error("Card UI smoke failed: shield icon badge and shield value should match the unit state")
		get_tree().quit(1)
		return
	if shield_anchor == null \
	or shield_anchor.get_parent() != hp_bar.get_parent() \
	or shield_anchor.offset_left >= 0.0 \
	or shield_anchor.offset_top >= 0.0:
		push_error("Card UI smoke failed: shield icon should overlap the left side of the HP bar")
		get_tree().quit(1)
		return
	if shield_label.get_theme_font_size("font_size") < 21 or shield_label.get_theme_constant("outline_size") < 6:
		push_error("Card UI smoke failed: shield value should be larger with a stronger outline")
		get_tree().quit(1)
		return
	if unit_panel.find_child("ShieldBar", true, false) != null:
		push_error("Card UI smoke failed: shield should no longer render as a bar")
		get_tree().quit(1)
		return
	if unit_panel.find_child("ShieldBadge", true, false) != null or unit_panel.find_child("ShieldStack", true, false) != null:
		push_error("Card UI smoke failed: shield should render without a square background frame")
		get_tree().quit(1)
		return
	var unit_slot_label: Label = unit_panel.get_node("BodyRow/InfoColumn/SlotBattery/SlotLabel") as Label
	if unit_slot_label == null or unit_slot_label.visible or unit_slot_label.text != "":
		push_error("Card UI smoke failed: unit panel should hide active slot text")
		get_tree().quit(1)
		return
	var slot_bars: HBoxContainer = unit_panel.get_node("BodyRow/InfoColumn/SlotBattery/SlotBatteryBars") as HBoxContainer
	if slot_bars == null or slot_bars.get_child_count() != 4:
		push_error("Card UI smoke failed: unit panel should render slot battery cells")
		get_tree().quit(1)
		return
	var first_slot_cell: Panel = slot_bars.get_child(0) as Panel
	var last_slot_cell: Panel = slot_bars.get_child(3) as Panel
	if first_slot_cell == null or last_slot_cell == null:
		push_error("Card UI smoke failed: unit panel slot battery cells should be panels")
		get_tree().quit(1)
		return
	var first_slot_style: StyleBoxFlat = first_slot_cell.get_theme_stylebox("panel") as StyleBoxFlat
	var last_slot_style: StyleBoxFlat = last_slot_cell.get_theme_stylebox("panel") as StyleBoxFlat
	if first_slot_style == null or last_slot_style == null or first_slot_style.bg_color.a < 0.9 or last_slot_style.bg_color.a > 0.8:
		push_error("Card UI smoke failed: used and empty slot battery cells should be visually distinct")
		get_tree().quit(1)
		return
	unit_panel.refresh_unit(player_unit, 1)
	await get_tree().process_frame
	var preview_slot_cell: Panel = slot_bars.get_child(2) as Panel
	var preview_slot_style: StyleBoxFlat = preview_slot_cell.get_theme_stylebox("panel") as StyleBoxFlat
	if preview_slot_style == null or preview_slot_style.border_color.b < 0.9 or preview_slot_style.bg_color.a < 0.25 or preview_slot_style.bg_color.a > 0.7:
		push_error("Card UI smoke failed: slot battery should preview hovered card slot usage")
		get_tree().quit(1)
		return
	var preview_slot_start_alpha: float = preview_slot_style.bg_color.a
	unit_panel._process(0.5)
	var preview_slot_mid_style: StyleBoxFlat = preview_slot_cell.get_theme_stylebox("panel") as StyleBoxFlat
	if preview_slot_mid_style == null or absf(preview_slot_mid_style.bg_color.a - preview_slot_start_alpha) < 0.05 or preview_slot_mid_style.bg_color.a < 0.25 or preview_slot_mid_style.bg_color.a > 0.7:
		push_error("Card UI smoke failed: slot battery preview should pulse like the timeline preview")
		get_tree().quit(1)
		return
	unit_panel.refresh_unit(player_unit, 3)
	await get_tree().process_frame
	if slot_bars.get_child_count() < 5:
		push_error("Card UI smoke failed: slot battery should add overflow preview cells to the right")
		get_tree().quit(1)
		return
	var overflow_slot_cell: Panel = slot_bars.get_child(4) as Panel
	if overflow_slot_cell == null:
		push_error("Card UI smoke failed: slot battery overflow preview cell should be a panel")
		get_tree().quit(1)
		return
	var overflow_slot_style: StyleBoxFlat = overflow_slot_cell.get_theme_stylebox("panel") as StyleBoxFlat
	if not overflow_slot_cell.visible or overflow_slot_style == null or overflow_slot_style.border_color.r < 0.9 or overflow_slot_style.border_color.b > 0.4:
		push_error("Card UI smoke failed: slot battery overflow preview should be red and visible")
		get_tree().quit(1)
		return
	unit_panel.refresh_unit(player_unit)
	await get_tree().process_frame
	if overflow_slot_cell.visible:
		push_error("Card UI smoke failed: slot battery overflow preview should hide after hover ends")
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

	var floating_labels: Array[Label] = _collect_floating_text_labels(effect_layer)
	var floating_texts: Array[String] = []
	for effect_label in floating_labels:
		floating_texts.append(effect_label.text)
		if effect_label.get_theme_font_size("font_size") < 30 \
		or effect_label.get_theme_constant("outline_size") < 4 \
		or effect_label.get_parent() != effect_layer:
			push_error("Card UI smoke failed: floating battle numbers should be large direct labels without badge backgrounds")
			get_tree().quit(1)
			return
		if effect_label.text.find("Shield") != -1:
			push_error("Card UI smoke failed: floating shield changes should render as numbers only")
			get_tree().quit(1)
			return
	if effect_layer.find_child("FloatingStatBadge", true, false) != null:
		push_error("Card UI smoke failed: floating battle numbers should not use a background badge")
		get_tree().quit(1)
		return
	if not floating_texts.has("-9") or not floating_texts.has("+2"):
		push_error("Card UI smoke failed: floating battle numbers should show damage and shield gain as numbers only")
		get_tree().quit(1)
		return
	unit_panel._process(1.0)
	await get_tree().process_frame
	if _collect_floating_text_labels(effect_layer).size() < 2:
		push_error("Card UI smoke failed: floating battle text should stay visible slightly longer")
		get_tree().quit(1)
		return
	var floating_count_before_decay: int = _collect_floating_text_labels(effect_layer).size()
	player_unit.shield = 4
	unit_panel.refresh_unit(player_unit, 0, 1)
	await get_tree().process_frame
	if _collect_floating_text_labels(effect_layer).size() != floating_count_before_decay:
		push_error("Card UI smoke failed: natural shield decay should not emit floating battle text")
		get_tree().quit(1)
		return

	Game.developer_open_battle("scout", "balanced")
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
	var battle_player_hand_panel: CardHandPanel = battle_scene.find_child("PlayerHandPanel", true, false) as CardHandPanel
	if battle_player_hand_panel == null or battle_player_hand_panel.get_child_count() < 1:
		push_error("Card UI smoke failed: battle player hand panel was not rendered")
		get_tree().quit(1)
		return
	var battle_enemy_loadout_panel: CardHandPanel = battle_scene.find_child("EnemyLoadoutPanel", true, false) as CardHandPanel
	if battle_enemy_loadout_panel == null or battle_enemy_loadout_panel.get_child_count() < 1:
		push_error("Card UI smoke failed: battle enemy loadout panel was not rendered")
		get_tree().quit(1)
		return
	var battle_enemy_card: CardButton = battle_enemy_loadout_panel.get_child(0) as CardButton
	if battle_enemy_card == null or battle_enemy_card.custom_minimum_size != Vector2(100.0, 100.0):
		push_error("Card UI smoke failed: enemy loadout cards should match player card size")
		get_tree().quit(1)
		return
	if battle_enemy_loadout_panel.custom_minimum_size.x < 320.0 or battle_player_hand_panel.custom_minimum_size.x < 320.0:
		push_error("Card UI smoke failed: battle side loadouts should reserve three card columns")
		get_tree().quit(1)
		return
	var battle_player_card: CardButton = battle_player_hand_panel.get_child(0) as CardButton
	if battle_player_card == null:
		push_error("Card UI smoke failed: battle player hand card was not rendered")
		get_tree().quit(1)
		return
	battle_player_card.emit_signal("mouse_entered")
	await get_tree().process_frame
	var battle_cards_track: Control = battle_timeline_panel.get_node("TimelineScroll/TimelineCards") as Control
	var battle_preview: CardButton = battle_cards_track.get_node("TimelinePreviewCard") as CardButton
	if battle_preview == null or not battle_preview.visible:
		push_error("Card UI smoke failed: battle hand hover should show a timeline preview")
		get_tree().quit(1)
		return
	if not battle_preview.runtime_id.begins_with("preview_"):
		push_error("Card UI smoke failed: battle timeline preview should use a preview runtime id")
		get_tree().quit(1)
		return
	var battle_preview_style: StyleBoxFlat = battle_preview.get_theme_stylebox("normal") as StyleBoxFlat
	if battle_preview_style == null or battle_preview_style.border_color.b < 0.8:
		push_error("Card UI smoke failed: battle timeline preview should use the player border color")
		get_tree().quit(1)
		return
	var battle_preview_bleach: ColorRect = battle_preview.get_node("BleachOverlay") as ColorRect
	if battle_preview_bleach == null or battle_preview_bleach.visible:
		push_error("Card UI smoke failed: battle timeline preview should not use a white bleach overlay")
		get_tree().quit(1)
		return
	if battle_preview.modulate.a > 0.59 or battle_preview.modulate.a < 0.31:
		push_error("Card UI smoke failed: battle timeline preview alpha should stay within the transparent pulse range")
		get_tree().quit(1)
		return
	var battle_player_panel: UnitPanel = battle_scene.find_child("PlayerUnitPanel", true, false) as UnitPanel
	if battle_player_panel == null:
		push_error("Card UI smoke failed: battle player panel should exist for slot preview")
		get_tree().quit(1)
		return
	var battle_slot_bars: HBoxContainer = battle_player_panel.get_node("BodyRow/InfoColumn/SlotBattery/SlotBatteryBars") as HBoxContainer
	if battle_slot_bars == null or not _has_slot_preview(battle_slot_bars):
		push_error("Card UI smoke failed: battle hand hover should preview slot usage")
		get_tree().quit(1)
		return
	battle_player_card.emit_signal("mouse_exited")
	await get_tree().process_frame
	if battle_preview.visible:
		push_error("Card UI smoke failed: battle hand hover preview should hide on mouse exit")
		get_tree().quit(1)
		return
	var battle_timeline_scale: HBoxContainer = battle_timeline_panel.get_node("TimelineScale") as HBoxContainer
	if battle_timeline_scale == null or battle_timeline_scale.get_child_count() < 1:
		push_error("Card UI smoke failed: battle timeline scale markers were not rendered")
		get_tree().quit(1)
		return
	var battle_info: RichTextLabel = battle_scene.find_child("BattleInfoLabel", true, false) as RichTextLabel
	if battle_info == null:
		push_error("Card UI smoke failed: battle info label should be named for layout checks")
		get_tree().quit(1)
		return
	var battle_start_button: Button = battle_scene.find_child("BattleStartButton", true, false) as Button
	var battle_engine: RealtimeBattleEngine = battle_scene.get("_engine") as RealtimeBattleEngine
	if battle_start_button == null or battle_engine == null:
		push_error("Card UI smoke failed: battle start button should exist above the battle info")
		get_tree().quit(1)
		return
	if battle_engine.has_battle_started() or not battle_start_button.visible or battle_start_button.disabled:
		push_error("Card UI smoke failed: battle should wait with a visible start button before any card is committed")
		get_tree().quit(1)
		return
	battle_start_button.emit_signal("pressed")
	await get_tree().process_frame
	if not battle_engine.has_battle_started() or battle_start_button.visible:
		push_error("Card UI smoke failed: battle start button should start the fight and hide itself")
		get_tree().quit(1)
		return
	if not battle_info.bbcode_enabled or not battle_info.text.begins_with("[center]") or not battle_info.text.ends_with("[/center]"):
		push_error("Card UI smoke failed: battle info text should be centered inside the section")
		get_tree().quit(1)
		return
	var forbidden_battle_info_parts: Array[String] = [
		"Player Slots",
		"Enemy Slots",
		Localization.get_textf("battle.info.timeline_entries", "Timeline Entries: {value}", {"value": 0}).replace("0", ""),
		Localization.get_text("battle.info.controls", "Controls:").replace(":", ""),
		Localization.get_text("battle.info.click_card", "- Click a player card to commit it").replace("-", "").strip_edges(),
		Localization.get_text("battle.info.hover_card", "- Hover any card for details").replace("-", "").strip_edges(),
		Localization.get_text("battle.info.slow_mode", "- Hold Space to slow time to 30%").replace("-", "").strip_edges(),
	]
	for forbidden_text in forbidden_battle_info_parts:
		if forbidden_text != "" and battle_info.text.find(forbidden_text) != -1:
			push_error("Card UI smoke failed: battle info should omit controls and timeline count")
			get_tree().quit(1)
			return
	var main_split: HBoxContainer = battle_scene.find_child("MainSplit", true, false) as HBoxContainer
	var battle_info_section: VBoxContainer = battle_scene.find_child("BattleInfoSection", true, false) as VBoxContainer
	var enemy_section: VBoxContainer = battle_scene.find_child("EnemySection", true, false) as VBoxContainer
	var player_section: VBoxContainer = battle_scene.find_child("PlayerSection", true, false) as VBoxContainer
	if main_split == null or main_split.alignment != BoxContainer.ALIGNMENT_CENTER:
		push_error("Card UI smoke failed: battle sections should be centered together")
		get_tree().quit(1)
		return
	var battle_info_frame: Control = null
	if battle_info_section != null:
		battle_info_frame = battle_info_section.get_parent() as Control
	if battle_info_frame == null or battle_info_frame.size_flags_horizontal != Control.SIZE_SHRINK_CENTER or battle_info_frame.size_flags_vertical != Control.SIZE_SHRINK_CENTER:
		push_error("Card UI smoke failed: battle info frame should fit its text")
		get_tree().quit(1)
		return
	if battle_info.custom_minimum_size.x < 240.0 or battle_info.autowrap_mode != TextServer.AUTOWRAP_OFF:
		push_error("Card UI smoke failed: battle info should keep enough width to avoid vertical text wrapping")
		get_tree().quit(1)
		return
	var enemy_frame: Control = null
	if enemy_section != null:
		enemy_frame = enemy_section.get_parent() as Control
	var player_frame: Control = null
	if player_section != null:
		player_frame = player_section.get_parent() as Control
	if enemy_frame == null or player_frame == null or enemy_frame.size_flags_horizontal != Control.SIZE_SHRINK_CENTER or player_frame.size_flags_horizontal != Control.SIZE_SHRINK_CENTER:
		push_error("Card UI smoke failed: player and enemy frames should move toward center")
		get_tree().quit(1)
		return
	if enemy_frame.custom_minimum_size.x < 340.0 or player_frame.custom_minimum_size.x < 340.0:
		push_error("Card UI smoke failed: player and enemy frames should fit three card columns")
		get_tree().quit(1)
		return
	var battle_player_slots: Label = battle_scene.find_child("SlotLabel", true, false) as Label
	if battle_player_slots == null or battle_player_slots.visible or battle_player_slots.text != "":
		push_error("Card UI smoke failed: player unit panel should hide active slot text")
		get_tree().quit(1)
		return
	var battle_banner: RunInfoBanner = battle_scene.find_child("RunInfoBanner", true, false) as RunInfoBanner
	var battle_banner_hp: Label = null
	var battle_banner_gold: Label = null
	if battle_banner != null:
		battle_banner_hp = battle_banner.find_child("RunHpValue", true, false) as Label
		battle_banner_gold = battle_banner.find_child("RunGoldValue", true, false) as Label
	if battle_banner == null \
	or battle_banner_hp == null \
	or battle_banner_gold == null \
	or battle_banner_hp.text.find("/") == -1:
		push_error("Card UI smoke failed: battle scene should render the shared run info banner")
		get_tree().quit(1)
		return
	var battle_max_marker: Label = battle_timeline_scale.get_child(battle_timeline_scale.get_child_count() - 1) as Label
	if battle_max_marker == null or battle_max_marker.text != "4s":
		push_error("Card UI smoke failed: battle timeline scale should use both loadouts' max cast time")
		get_tree().quit(1)
		return
	var timeline_header: HBoxContainer = battle_timeline_panel.get_node("TimelineHeader") as HBoxContainer
	var timeline_title: Label = battle_timeline_panel.get_node("TimelineHeader/TimelineTitle") as Label
	var timeline_queued: Label = battle_timeline_panel.get_node("TimelineHeader/TimelineQueuedLabel") as Label
	if timeline_header == null or timeline_title == null or timeline_queued == null:
		push_error("Card UI smoke failed: timeline title and queued count should share a header row")
		get_tree().quit(1)
		return
	var expected_timeline_title: String = Localization.get_text("battle.timeline", "Timeline")
	var expected_queued_prefix: String = Localization.get_textf("timeline.queued", "Queued {count}", {"count": 0}).replace("0", "")
	if timeline_title.text != expected_timeline_title or timeline_queued.text.find(expected_queued_prefix) == -1:
		push_error("Card UI smoke failed: timeline header should show title and queued count")
		get_tree().quit(1)
		return
	if timeline_section == null or _count_labels_with_text(timeline_section, expected_timeline_title) != 1:
		push_error("Card UI smoke failed: timeline section should not render a duplicate title")
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
		"auto_turret",
		"crisis_drone_swarm",
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

	var status_icon_ids: Array[String] = ["bleed", "weak", "slow", "vulnerable"]
	for status_icon_id in status_icon_ids:
		if not FileAccess.file_exists("res://assets/icons/status/%s.png" % status_icon_id):
			push_error("Card UI smoke failed: missing generated status icon for %s" % status_icon_id)
			get_tree().quit(1)
			return

	for relic_id in Database.get_all_relic_ids():
		if not ResourceLoader.exists("res://assets/icons/relics/%s.png" % relic_id):
			push_error("Card UI smoke failed: missing generated relic art for %s" % relic_id)
			get_tree().quit(1)
			return

	var relic_icon: RelicIcon = RelicIcon.new()
	relic_icon.set_icon_size(Vector2(52.0, 52.0))
	relic_icon.bind_relic_id("iron_plating")
	add_child(relic_icon)
	await get_tree().process_frame
	var relic_art: TextureRect = relic_icon.get_node("RelicArt") as TextureRect
	if relic_art == null or relic_art.texture == null:
		push_error("Card UI smoke failed: relic icon should render generated art")
		get_tree().quit(1)
		return
	if relic_icon.tooltip_text.find("Iron Plating") == -1 or relic_icon.tooltip_text.find("max HP") == -1:
		push_error("Card UI smoke failed: relic icon tooltip should include name and effect description")
		get_tree().quit(1)
		return
	var relic_tooltip: Control = relic_icon._make_custom_tooltip(relic_icon.tooltip_text) as Control
	var relic_tooltip_text: RichTextLabel = relic_tooltip.find_child("RelicTooltipText", true, false) as RichTextLabel
	if relic_tooltip_text == null or relic_tooltip_text.text.find("Iron Plating") == -1:
		push_error("Card UI smoke failed: relic custom tooltip should render text")
		get_tree().quit(1)
		return
	relic_tooltip.free()

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


func _find_timeline_card(cards_track: Control, runtime_id: String) -> CardButton:
	for child in cards_track.get_children():
		var button: CardButton = child as CardButton
		if button != null and button.runtime_id == runtime_id:
			return button
	return null


func _collect_floating_text_labels(effect_layer: Control) -> Array[Label]:
	var labels: Array[Label] = []
	if effect_layer == null:
		return labels
	for child in effect_layer.get_children():
		var direct_label: Label = child as Label
		if direct_label != null:
			labels.append(direct_label)
			continue
		var child_control: Control = child as Control
		if child_control == null:
			continue
		var nested_label: Label = child_control.find_child("FloatingStatLabel", true, false) as Label
		if nested_label != null:
			labels.append(nested_label)
	return labels


func _count_labels_with_text(root: Node, text: String) -> int:
	var count: int = 0
	for child in root.get_children():
		var child_node: Node = child as Node
		var label: Label = child_node as Label
		if label != null and label.text == text:
			count += 1
		count += _count_labels_with_text(child_node, text)
	return count


func _expected_timeline_x(timeline_panel: TimelinePanel, remaining: float, horizon: float) -> float:
	var timeline_scroll: Control = timeline_panel.get_node("TimelineScroll") as Control
	var track_width: float = timeline_scroll.size.x
	if track_width <= 168.0:
		track_width = 960.0
	var usable_width: float = maxf(1.0, track_width - 168.0)
	return usable_width * clampf(remaining, 0.0, horizon) / horizon


func _has_slot_preview(slot_bars: HBoxContainer) -> bool:
	for child in slot_bars.get_children():
		var slot_cell: Panel = child as Panel
		if slot_cell == null or not slot_cell.visible:
			continue
		var slot_style: StyleBoxFlat = slot_cell.get_theme_stylebox("panel") as StyleBoxFlat
		if slot_style != null and slot_style.border_color.b > 0.9 and slot_style.bg_color.a < 0.8:
			return true
	return false
