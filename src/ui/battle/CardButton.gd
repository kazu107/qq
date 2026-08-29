extends Button
class_name CardButton

signal card_requested(runtime_id: String)
signal card_hovered(runtime_id: String)
signal card_unhovered(runtime_id: String)

const ART_PATH_TEMPLATE := "res://assets/icons/cards/%s.png"
const FRAME_FILL := Color(0.09, 0.10, 0.13, 0.96)
const NAME_BAR_COLOR := Color(0.03, 0.04, 0.06, 0.84)
const BADGE_DARK := Color(0.07, 0.08, 0.10, 0.88)
const BADGE_ACTIVE := Color(0.16, 0.44, 0.70, 0.92)
const COST_BADGE_COLOR := Color(0.12, 0.72, 0.32, 0.96)
const TEXT_LIGHT := Color(0.97, 0.96, 0.93, 1.0)
const COOLDOWN_SHADE := Color(0.01, 0.02, 0.03, 0.70)
const PROGRESS_EDGE := Color(1.0, 0.95, 0.72, 0.38)
const BLEACH_COLOR := Color(1.0, 1.0, 1.0, 0.34)
const TIMELINE_NEXT_BADGE := Color(1.0, 0.70, 0.16, 0.96)
const EFFECT_CHIP_FILL := Color(0.025, 0.035, 0.050, 0.91)
const EFFECT_CHIP_BORDER := Color(0.66, 0.78, 0.84, 0.58)
const EFFECT_REMAINDER_FILL := Color(0.08, 0.12, 0.16, 0.94)
const COMMON_BORDER := Color(0.88, 0.80, 0.67, 1.0)
const RARE_BORDER := Color(0.47, 0.86, 0.90, 1.0)
const EPIC_BORDER := Color(0.97, 0.69, 0.34, 1.0)
const LEGENDARY_BORDER := Color(1.0, 0.93, 0.48, 1.0)
const ACTIVE_PLAYER_BORDER := Color(0.24, 0.56, 1.0, 1.0)
const ACTIVE_ENEMY_BORDER := Color(0.95, 0.28, 0.25, 1.0)
const TOOLTIP_BUFF_COLOR := "#72d36f"
const TOOLTIP_NERF_COLOR := "#ff6868"
const TOOLTIP_STATUS_COLOR := "#ffd45a"
const NAME_FONT_MAX_SIZE: int = 15
const NAME_FONT_MIN_SIZE: int = 10

static var _texture_cache: Dictionary = {}
static var _use_legacy_tooltips: bool = false


static func warm_texture_cache(card_ids: Array[String]) -> int:
	var warmed_count: int = 0
	for card_id in card_ids:
		if _load_card_texture(card_id) != null:
			warmed_count += 1
	return warmed_count


static func get_cached_texture_count() -> int:
	return _texture_cache.size()


var runtime_id: String = ""
var _can_use: bool = false
var _click_enabled: bool = true
var _recovery_ratio: float = 1.0
var _tooltip_bbcode: String = ""
var _simple_tooltip_text: String = ""
var _simple_tooltip_bbcode: String = ""
var _legacy_tooltip_text: String = ""
var _legacy_tooltip_bbcode: String = ""
var _comparison_card_override: CardDef

var _art_rect: TextureRect
var _bleach_overlay: ColorRect
var _frame_overlay: Panel
var _cooldown_shade: ColorRect
var _progress_edge: ColorRect
var _name_bar: ColorRect
var _name_label: Label
var _state_badge: ColorRect
var _state_label: Label
var _cost_badge: ColorRect
var _cost_label: Label
var _meta_badge: ColorRect
var _meta_label: Label
var _timeline_next_badge: ColorRect
var _timeline_next_label: Label
var _timing_badge: ColorRect
var _timing_icon: TextureRect
var _timing_label: Label
var _effect_strip: Control
var _effect_chip_panels: Array[Panel] = []
var _effect_chip_icons: Array[TextureRect] = []
var _effect_chip_labels: Array[RichTextLabel] = []
var _effect_remainder_badge: Panel
var _effect_remainder_label: Label
var _name_type_icon: TextureRect
var _face_summaries: Array[Dictionary] = []
var _face_cast_time: float = 0.0


func _ready() -> void:
	_ensure_visuals()


func set_tile_size(size: Vector2) -> void:
	custom_minimum_size = size
	if _art_rect != null:
		call_deferred("_refresh_card_face")


func set_bleach_enabled(enabled: bool, amount: float = BLEACH_COLOR.a) -> void:
	_ensure_visuals()
	_bleach_overlay.visible = enabled
	_bleach_overlay.color = Color(BLEACH_COLOR.r, BLEACH_COLOR.g, BLEACH_COLOR.b, clampf(amount, 0.0, 1.0))
	if enabled:
		_bleach_overlay.z_index = 100
		move_child(_bleach_overlay, get_child_count() - 1)


func bind(
	card_def: CardDef,
	runtime_state: CardRuntimeState,
	can_use: bool,
	click_enabled: bool = true,
	blocked_reason: String = "",
	comparison_card_def: CardDef = null
) -> void:
	_ensure_visuals()
	_comparison_card_override = comparison_card_def
	runtime_id = runtime_state.runtime_id
	_click_enabled = click_enabled
	_can_use = can_use and click_enabled
	text = ""
	_art_rect.texture = _get_card_texture(card_def.id)
	_set_card_name(card_def.name)
	_set_cost_value(card_def.active_slot_cost)
	_set_card_face_data(card_def)

	var meta_text: String = "%dS" % card_def.active_slot_cost
	var tooltip_state: String = Localization.get_text("card.state.ready", "Ready")
	var tooltip_blocked: String = ""
	var modulate_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	var recovery_ratio: float = 1.0

	match runtime_state.state:
		CardRuntimeState.CardState.READY:
			if can_use:
				meta_text = Localization.get_text("card.meta.ready", "ready")
			elif click_enabled:
				tooltip_state = Localization.get_text("card.state.ready", "Ready")
				tooltip_blocked = blocked_reason
				if tooltip_blocked == "":
					tooltip_blocked = Localization.get_text("card.blocked_slots", "Blocked: active slots full")
				modulate_color = Color(0.84, 0.84, 0.84, 1.0)
		CardRuntimeState.CardState.PREPARING:
			meta_text = Localization.get_text("card.meta.casting", "casting")
			tooltip_state = Localization.get_text("card.state.preparing", "Preparing")
		CardRuntimeState.CardState.RESOLVING:
			tooltip_state = Localization.get_text("card.state.resolving", "Resolving")
		CardRuntimeState.CardState.COOLDOWN:
			meta_text = "%.1fs" % runtime_state.get_display_cooldown_remaining()
			tooltip_state = Localization.get_textf("card.state.cooldown", "Cooldown {seconds}s remaining", {
				"seconds": "%.1f" % runtime_state.get_display_cooldown_remaining(),
			})
			recovery_ratio = _compute_cooldown_ratio(card_def, runtime_state)
		CardRuntimeState.CardState.DISABLED:
			tooltip_state = Localization.get_text("card.state.disabled", "Disabled")
			modulate_color = Color(0.72, 0.72, 0.72, 1.0)
		CardRuntimeState.CardState.INTERRUPTED:
			tooltip_state = Localization.get_text("card.state.interrupted", "Interrupted")
			modulate_color = Color(0.78, 0.78, 0.78, 1.0)

	_state_label.text = ""
	_state_badge.visible = false
	_set_timeline_indicators(false, false)
	_meta_label.text = meta_text
	_meta_badge.visible = true
	_meta_badge.color = BADGE_DARK
	modulate = modulate_color
	set_bleach_enabled(false)
	_set_mouse_cursor(_can_use)
	_apply_frame(_get_rarity_border(card_def.rarity))
	_set_recovery_ratio(recovery_ratio)
	_set_tooltip_variants(
		_build_hand_tooltip(card_def, tooltip_state, tooltip_blocked, runtime_state, false),
		_build_hand_tooltip(card_def, tooltip_state, tooltip_blocked, runtime_state, true),
		_build_legacy_tooltip(card_def, tooltip_blocked, false),
		_build_legacy_tooltip(card_def, tooltip_blocked, true)
	)


func bind_preview(
	card_def: CardDef,
	preview_id: String,
	click_enabled: bool = false,
	badge_text: String = "CARD",
	comparison_card_def: CardDef = null
) -> void:
	_ensure_visuals()
	_comparison_card_override = comparison_card_def
	runtime_id = preview_id
	_click_enabled = click_enabled
	_can_use = click_enabled
	text = ""
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_art_rect.texture = _get_card_texture(card_def.id)
	_set_card_name(card_def.name)
	_set_cost_value(card_def.active_slot_cost)
	_set_card_face_data(card_def)
	_state_label.text = ""
	_state_badge.visible = false
	_set_timeline_indicators(false, false)
	_meta_label.text = ""
	_meta_badge.visible = false
	_meta_badge.color = BADGE_DARK
	set_bleach_enabled(false)
	_apply_frame(_get_rarity_border(card_def.rarity))
	_set_mouse_cursor(_can_use)
	_set_recovery_ratio(1.0)
	_set_tooltip_variants(
		_build_preview_simple_tooltip(card_def, false),
		_build_preview_simple_tooltip(card_def, true),
		_build_legacy_tooltip(card_def, "", false),
		_build_legacy_tooltip(card_def, "", true)
	)


func bind_active(card_def: CardDef, instance: ActiveCardInstance, battle_time: float, comparison_card_def: CardDef = null) -> void:
	_ensure_visuals()
	_comparison_card_override = comparison_card_def
	runtime_id = instance.runtime_id
	_click_enabled = false
	_can_use = false
	text = ""
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_art_rect.texture = _get_card_texture(card_def.id)
	_set_card_name(card_def.name)
	_set_cost_value(card_def.active_slot_cost)
	_set_card_face_data(card_def)
	_state_label.text = ""
	_state_badge.visible = false
	_set_timeline_indicators(false, false)

	var remaining: float = instance.get_remaining(battle_time)
	_meta_label.text = Localization.get_text("card.meta.casting", "casting")
	_meta_badge.visible = true
	_meta_badge.color = BADGE_DARK
	set_bleach_enabled(false)
	_apply_frame(_get_active_border(instance.owner_side))
	_set_mouse_cursor(false)
	_set_recovery_ratio(_compute_active_ratio(instance, battle_time))
	_set_tooltip_variants(
		_build_active_tooltip(card_def, instance, remaining, false),
		_build_active_tooltip(card_def, instance, remaining, true),
		_build_legacy_tooltip(card_def, "", false),
		_build_legacy_tooltip(card_def, "", true)
	)


func bind_timeline(
	card_def: CardDef,
	entry: TimelineEntry,
	battle_time: float,
	is_next: bool = false,
	friendly_side: String = "player",
	comparison_card_def: CardDef = null
) -> void:
	_ensure_visuals()
	_comparison_card_override = comparison_card_def
	runtime_id = entry.runtime_id
	_click_enabled = false
	_can_use = false
	text = ""
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_art_rect.texture = _get_card_texture(card_def.id)
	_set_card_name(card_def.name)
	_set_cost_value(card_def.active_slot_cost)
	_set_card_face_data(card_def)
	_state_label.text = ""
	_state_badge.visible = false

	var remaining: float = maxf(0.0, entry.scheduled_time - battle_time)
	_meta_label.text = "%.1fs" % remaining
	_meta_badge.visible = true
	_meta_badge.color = BADGE_ACTIVE if is_next else BADGE_DARK
	set_bleach_enabled(false)
	var display_side: String = "player" if entry.owner_side == friendly_side else "enemy"
	_apply_frame(_get_active_border(display_side), 4 if is_next else 2, 8 if is_next else 4)
	_set_mouse_cursor(false)
	_set_recovery_ratio(1.0)
	_set_timeline_indicators(true, is_next)
	_set_tooltip_variants(
		_build_timeline_tooltip(card_def, entry, remaining, false),
		_build_timeline_tooltip(card_def, entry, remaining, true),
		_build_legacy_tooltip(card_def, "", false),
		_build_legacy_tooltip(card_def, "", true)
	)


func append_tooltip_line(line_text: String, line_bbcode: String = "") -> void:
	if line_text == "":
		return
	if line_bbcode == "":
		line_bbcode = _escape_bbcode(line_text)
	_simple_tooltip_text = _append_tooltip_text(_simple_tooltip_text, line_text)
	_simple_tooltip_bbcode = _append_tooltip_text(_simple_tooltip_bbcode, line_bbcode)
	_legacy_tooltip_text = _append_tooltip_text(_legacy_tooltip_text, line_text)
	_legacy_tooltip_bbcode = _append_tooltip_text(_legacy_tooltip_bbcode, line_bbcode)
	_apply_stored_tooltip_mode()


func _on_pressed() -> void:
	if not _click_enabled or not _can_use or runtime_id == "":
		return
	card_requested.emit(runtime_id)


func _on_mouse_entered() -> void:
	if runtime_id == "":
		return
	card_hovered.emit(runtime_id)


func _on_mouse_exited() -> void:
	if runtime_id == "":
		return
	card_unhovered.emit(runtime_id)


func _on_gui_input(event: InputEvent) -> void:
	var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button_event == null:
		return
	if mouse_button_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_button_event.pressed:
		return
	_use_legacy_tooltips = not _use_legacy_tooltips
	get_tree().call_group("CardButtons", "_apply_stored_tooltip_mode")
	accept_event()


func _make_custom_tooltip(for_text: String) -> Object:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "CardTooltipPopup"
	panel.custom_minimum_size = Vector2(460.0, 0.0)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var label: RichTextLabel = RichTextLabel.new()
	label.name = "CardTooltipText"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(440.0, 0.0)
	if _tooltip_bbcode != "":
		label.text = _tooltip_bbcode
	else:
		label.text = _escape_bbcode(for_text)
	margin.add_child(label)
	return panel


func _ensure_visuals() -> void:
	if _art_rect != null:
		return

	focus_mode = Control.FOCUS_NONE
	flat = true
	clip_contents = true
	size_flags_horizontal = 0
	size_flags_vertical = 0
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(108.0, 108.0)

	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	if not resized.is_connected(_update_cooldown_mask):
		resized.connect(_update_cooldown_mask)
	if not resized.is_connected(_fit_name_label_to_text):
		resized.connect(_fit_name_label_to_text)
	if not resized.is_connected(_refresh_card_face):
		resized.connect(_refresh_card_face)
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	if not is_in_group("CardButtons"):
		add_to_group("CardButtons")

	_art_rect = TextureRect.new()
	_art_rect.name = "Art"
	_art_rect.anchor_right = 1.0
	_art_rect.anchor_bottom = 1.0
	_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_configure_overlay(_art_rect)
	add_child(_art_rect)

	_bleach_overlay = ColorRect.new()
	_bleach_overlay.name = "BleachOverlay"
	_bleach_overlay.anchor_right = 1.0
	_bleach_overlay.anchor_bottom = 1.0
	_bleach_overlay.color = BLEACH_COLOR
	_bleach_overlay.visible = false
	_bleach_overlay.z_index = 100
	_configure_overlay(_bleach_overlay)
	add_child(_bleach_overlay)

	_frame_overlay = Panel.new()
	_frame_overlay.name = "FrameOverlay"
	_frame_overlay.anchor_right = 1.0
	_frame_overlay.anchor_bottom = 1.0
	_configure_overlay(_frame_overlay)
	add_child(_frame_overlay)

	_cooldown_shade = ColorRect.new()
	_cooldown_shade.name = "CooldownShade"
	_cooldown_shade.anchor_bottom = 1.0
	_cooldown_shade.color = COOLDOWN_SHADE
	_configure_overlay(_cooldown_shade)
	add_child(_cooldown_shade)

	_progress_edge = ColorRect.new()
	_progress_edge.name = "ProgressEdge"
	_progress_edge.anchor_bottom = 1.0
	_progress_edge.color = PROGRESS_EDGE
	_configure_overlay(_progress_edge)
	add_child(_progress_edge)

	_name_bar = ColorRect.new()
	_name_bar.name = "NameBar"
	_name_bar.anchor_top = 1.0
	_name_bar.anchor_right = 1.0
	_name_bar.anchor_bottom = 1.0
	_name_bar.offset_top = -34.0
	_name_bar.color = NAME_BAR_COLOR
	_configure_overlay(_name_bar)
	add_child(_name_bar)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.anchor_right = 1.0
	_name_label.anchor_bottom = 1.0
	_name_label.offset_left = 8.0
	_name_label.offset_top = 4.0
	_name_label.offset_right = -8.0
	_name_label.offset_bottom = -4.0
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.clip_text = true
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_color", TEXT_LIGHT)
	_configure_overlay(_name_label)
	_name_bar.add_child(_name_label)

	_name_type_icon = TextureRect.new()
	_name_type_icon.name = "CardTypeIcon"
	_name_type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_name_type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_configure_overlay(_name_type_icon)
	_name_bar.add_child(_name_type_icon)

	_effect_strip = Control.new()
	_effect_strip.name = "EffectStrip"
	_effect_strip.anchor_right = 1.0
	_effect_strip.anchor_bottom = 1.0
	_configure_overlay(_effect_strip)
	add_child(_effect_strip)
	for chip_index in range(2):
		_create_effect_chip(chip_index)

	_effect_remainder_badge = Panel.new()
	_effect_remainder_badge.name = "EffectRemainder"
	_effect_remainder_badge.add_theme_stylebox_override("panel", _make_effect_chip_style(EFFECT_REMAINDER_FILL, EFFECT_CHIP_BORDER))
	_effect_remainder_badge.visible = false
	_configure_overlay(_effect_remainder_badge)
	_effect_strip.add_child(_effect_remainder_badge)

	_effect_remainder_label = Label.new()
	_effect_remainder_label.name = "Count"
	_effect_remainder_label.anchor_right = 1.0
	_effect_remainder_label.anchor_bottom = 1.0
	_effect_remainder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_effect_remainder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_effect_remainder_label.add_theme_color_override("font_color", TEXT_LIGHT)
	_effect_remainder_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.86))
	_effect_remainder_label.add_theme_constant_override("outline_size", 2)
	_effect_remainder_label.add_theme_font_size_override("font_size", 11)
	_configure_overlay(_effect_remainder_label)
	_effect_remainder_badge.add_child(_effect_remainder_label)

	_state_badge = ColorRect.new()
	_state_badge.name = "StateBadge"
	_state_badge.visible = false
	_configure_overlay(_state_badge)
	add_child(_state_badge)

	_state_label = Label.new()
	_state_label.name = "State"
	_state_label.visible = false
	_configure_overlay(_state_label)
	_state_badge.add_child(_state_label)

	_cost_badge = ColorRect.new()
	_cost_badge.name = "CostBadge"
	_cost_badge.offset_left = -5.0
	_cost_badge.offset_top = -5.0
	_cost_badge.offset_right = 25.0
	_cost_badge.offset_bottom = 25.0
	_cost_badge.color = COST_BADGE_COLOR
	_configure_overlay(_cost_badge)
	add_child(_cost_badge)

	_cost_label = Label.new()
	_cost_label.name = "Cost"
	_cost_label.anchor_right = 1.0
	_cost_label.anchor_bottom = 1.0
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.88, 1.0))
	_cost_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
	_cost_label.add_theme_constant_override("outline_size", 3)
	_cost_label.add_theme_font_size_override("font_size", 16)
	_configure_overlay(_cost_label)
	_cost_badge.add_child(_cost_label)

	_meta_badge = ColorRect.new()
	_meta_badge.name = "MetaBadge"
	_meta_badge.anchor_left = 1.0
	_meta_badge.anchor_right = 1.0
	_meta_badge.offset_left = -66.0
	_meta_badge.offset_top = 8.0
	_meta_badge.offset_right = -8.0
	_meta_badge.offset_bottom = 30.0
	_configure_overlay(_meta_badge)
	add_child(_meta_badge)

	_meta_label = Label.new()
	_meta_label.name = "Meta"
	_meta_label.anchor_right = 1.0
	_meta_label.anchor_bottom = 1.0
	_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_meta_label.add_theme_color_override("font_color", TEXT_LIGHT)
	_configure_overlay(_meta_label)
	_meta_badge.add_child(_meta_label)

	_timing_badge = ColorRect.new()
	_timing_badge.name = "TimingBadge"
	_timing_badge.color = BADGE_DARK
	_timing_badge.visible = false
	_configure_overlay(_timing_badge)
	add_child(_timing_badge)

	_timing_icon = TextureRect.new()
	_timing_icon.name = "Icon"
	_timing_icon.texture = CardEffectIconFactory.get_icon("time")
	_timing_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_timing_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_configure_overlay(_timing_icon)
	_timing_badge.add_child(_timing_icon)

	_timing_label = Label.new()
	_timing_label.name = "Value"
	_timing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timing_label.add_theme_color_override("font_color", TEXT_LIGHT)
	_timing_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.84))
	_timing_label.add_theme_constant_override("outline_size", 2)
	_timing_label.add_theme_font_size_override("font_size", 11)
	_configure_overlay(_timing_label)
	_timing_badge.add_child(_timing_label)

	_timeline_next_badge = ColorRect.new()
	_timeline_next_badge.name = "TimelineNextBadge"
	_timeline_next_badge.visible = false
	_timeline_next_badge.offset_left = 38.0
	_timeline_next_badge.offset_top = 8.0
	_timeline_next_badge.offset_right = 94.0
	_timeline_next_badge.offset_bottom = 30.0
	_timeline_next_badge.color = TIMELINE_NEXT_BADGE
	_configure_overlay(_timeline_next_badge)
	add_child(_timeline_next_badge)

	_timeline_next_label = Label.new()
	_timeline_next_label.name = "Next"
	_timeline_next_label.anchor_right = 1.0
	_timeline_next_label.anchor_bottom = 1.0
	_timeline_next_label.text = Localization.get_text("timeline.next", "NEXT")
	_timeline_next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timeline_next_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timeline_next_label.add_theme_color_override("font_color", Color(0.06, 0.04, 0.02, 1.0))
	_configure_overlay(_timeline_next_label)
	_timeline_next_badge.add_child(_timeline_next_label)

	_apply_frame(COMMON_BORDER)
	_update_cooldown_mask()
	_refresh_card_face()


func _configure_overlay(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _create_effect_chip(chip_index: int) -> void:
	var panel: Panel = Panel.new()
	panel.name = "EffectChip%d" % (chip_index + 1)
	panel.add_theme_stylebox_override("panel", _make_effect_chip_style(EFFECT_CHIP_FILL, EFFECT_CHIP_BORDER))
	panel.visible = false
	_configure_overlay(panel)
	_effect_strip.add_child(panel)
	_effect_chip_panels.append(panel)

	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_configure_overlay(icon)
	panel.add_child(icon)
	_effect_chip_icons.append(icon)

	var value_label: RichTextLabel = RichTextLabel.new()
	value_label.name = "Value"
	value_label.bbcode_enabled = true
	value_label.fit_content = false
	value_label.scroll_active = false
	value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("default_color", TEXT_LIGHT)
	value_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
	value_label.add_theme_constant_override("outline_size", 2)
	value_label.add_theme_font_size_override("normal_font_size", 11)
	_configure_overlay(value_label)
	panel.add_child(value_label)
	_effect_chip_labels.append(value_label)


func _make_effect_chip_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _set_card_face_data(card_def: CardDef) -> void:
	_face_summaries = CardFaceSummaryResolver.build_summaries(card_def, _get_comparison_card(card_def))
	_face_cast_time = maxf(0.0, card_def.cast_time)
	_refresh_card_face()
	call_deferred("_refresh_card_face")


func _refresh_card_face() -> void:
	if _effect_strip == null or _name_bar == null:
		return

	var resolved_width: float = size.x if size.x > 1.0 else custom_minimum_size.x
	var resolved_height: float = size.y if size.y > 1.0 else custom_minimum_size.y
	resolved_width = maxf(48.0, resolved_width)
	resolved_height = maxf(48.0, resolved_height)

	var name_height: float = 34.0 if resolved_height >= 140.0 else (28.0 if resolved_height >= 88.0 else 23.0)
	var strip_height: float = 26.0 if resolved_height >= 140.0 else (21.0 if resolved_height >= 88.0 else 18.0)
	var strip_gap: float = 4.0 if resolved_height >= 104.0 else 2.0
	var strip_y: float = maxf(28.0, resolved_height - name_height - strip_height - strip_gap)
	_name_bar.offset_top = -name_height

	var has_summary: bool = not _face_summaries.is_empty()
	var show_type_icon: bool = has_summary and resolved_width >= 84.0 and resolved_height >= 84.0
	_name_type_icon.visible = show_type_icon
	if show_type_icon:
		var type_icon_size: float = 18.0 if name_height >= 28.0 else 15.0
		_name_type_icon.texture = CardEffectIconFactory.get_icon(String(_face_summaries[0].get("icon_id", "effect")))
		_name_type_icon.position = Vector2(5.0, (name_height - type_icon_size) * 0.5)
		_name_type_icon.size = Vector2(type_icon_size, type_icon_size)
	_name_label.offset_left = 26.0 if show_type_icon else 5.0
	_name_label.offset_top = 2.0
	_name_label.offset_right = -5.0
	_name_label.offset_bottom = -2.0

	var meta_width: float = clampf(resolved_width * 0.52, 48.0, 66.0)
	_meta_badge.offset_left = -meta_width - 7.0
	_meta_badge.offset_top = 7.0
	_meta_badge.offset_right = -7.0
	_meta_badge.offset_bottom = 29.0

	var show_timing: bool = has_summary and resolved_width >= 112.0 and resolved_height >= 112.0
	_timing_badge.visible = show_timing
	if show_timing:
		var timing_width: float = 61.0
		var timing_y: float = 33.0 if _meta_badge.visible else 7.0
		_timing_badge.position = Vector2(resolved_width - timing_width - 7.0, timing_y)
		_timing_badge.size = Vector2(timing_width, 20.0)
		_timing_icon.position = Vector2(3.0, 2.0)
		_timing_icon.size = Vector2(16.0, 16.0)
		_timing_label.position = Vector2(18.0, 0.0)
		_timing_label.size = Vector2(timing_width - 20.0, 20.0)
		_timing_label.text = "%ss" % _format_face_number(_face_cast_time, 1, false)

	if _timeline_next_badge != null:
		_timeline_next_badge.offset_left = 38.0
		_timeline_next_badge.offset_top = 7.0
		_timeline_next_badge.offset_right = minf(94.0, resolved_width - meta_width - 11.0)
		_timeline_next_badge.offset_bottom = 29.0

	_effect_strip.visible = has_summary
	if not has_summary:
		for hidden_panel in _effect_chip_panels:
			hidden_panel.visible = false
		_effect_remainder_badge.visible = false
		_fit_name_label_to_text()
		return

	var visible_limit: int = 2 if resolved_width >= 104.0 else 1
	var visible_count: int = mini(visible_limit, _face_summaries.size())
	var remaining_count: int = maxi(0, _face_summaries.size() - visible_count)
	var outer_margin: float = 4.0
	var chip_gap: float = 3.0
	var remainder_width: float = 25.0 if remaining_count > 0 else 0.0
	var occupied_gaps: int = maxi(0, visible_count - 1) + (1 if remaining_count > 0 else 0)
	var available_chip_width: float = resolved_width - outer_margin * 2.0 - remainder_width - chip_gap * float(occupied_gaps)
	var chip_width: float = maxf(26.0, available_chip_width / float(maxi(1, visible_count)))
	var cursor_x: float = outer_margin
	var icon_size: float = 18.0 if strip_height >= 24.0 else (15.0 if strip_height >= 20.0 else 13.0)
	var show_delta: bool = chip_width >= 50.0

	for chip_index in range(_effect_chip_panels.size()):
		var panel: Panel = _effect_chip_panels[chip_index]
		if chip_index >= visible_count:
			panel.visible = false
			continue
		var summary: Dictionary = _face_summaries[chip_index]
		panel.visible = true
		panel.position = Vector2(cursor_x, strip_y)
		panel.size = Vector2(chip_width, strip_height)
		var icon: TextureRect = _effect_chip_icons[chip_index]
		icon.texture = CardEffectIconFactory.get_icon(String(summary.get("icon_id", "effect")))
		icon.position = Vector2(3.0, (strip_height - icon_size) * 0.5)
		icon.size = Vector2(icon_size, icon_size)
		var value_label: RichTextLabel = _effect_chip_labels[chip_index]
		value_label.position = Vector2(icon_size + 4.0, 0.0)
		value_label.size = Vector2(maxf(1.0, chip_width - icon_size - 6.0), strip_height)
		value_label.add_theme_font_size_override("normal_font_size", 12 if strip_height >= 24.0 else 10)
		value_label.text = _build_face_value_bbcode(summary, show_delta)
		cursor_x += chip_width + chip_gap

	_effect_remainder_badge.visible = remaining_count > 0
	if remaining_count > 0:
		_effect_remainder_badge.position = Vector2(cursor_x, strip_y)
		_effect_remainder_badge.size = Vector2(remainder_width, strip_height)
		_effect_remainder_label.text = "+%d" % remaining_count
		_effect_remainder_label.add_theme_font_size_override("font_size", 12 if strip_height >= 24.0 else 10)

	_fit_name_label_to_text()


func _build_face_value_bbcode(summary: Dictionary, show_delta: bool) -> String:
	var value_text: String = String(summary.get("value_text", ""))
	var delta_text: String = String(summary.get("delta_text", ""))
	var delta_state: String = String(summary.get("delta_state", "neutral"))
	if value_text == "":
		return ""
	if delta_text == "" or delta_state == "neutral":
		return "[center]%s[/center]" % value_text

	var color: String = TOOLTIP_BUFF_COLOR if delta_state == "buff" else TOOLTIP_NERF_COLOR
	if show_delta:
		return "[center]%s[font_size=9][color=%s](%s)[/color][/font_size][/center]" % [value_text, color, delta_text]
	return "[center][color=%s]%s[/color][/center]" % [color, value_text]


func _format_face_number(value: float, decimals: int, force_sign: bool) -> String:
	var value_text: String
	if decimals <= 0 or is_equal_approx(value, roundf(value)):
		value_text = "%d" % int(roundf(value))
	else:
		var pattern: String = "%." + str(decimals) + "f"
		value_text = pattern % value
	if force_sign and value > 0.0:
		return "+%s" % value_text
	return value_text


func _set_card_name(card_name: String) -> void:
	if _name_label == null:
		return
	_name_label.text = card_name
	_fit_name_label_to_text()
	call_deferred("_fit_name_label_to_text")


func _fit_name_label_to_text() -> void:
	if _name_label == null:
		return
	var resolved_width: float = size.x if size.x > 1.0 else custom_minimum_size.x
	var available_width: float = maxf(24.0, resolved_width - (31.0 if _name_type_icon != null and _name_type_icon.visible else 10.0))
	var font: Font = _name_label.get_theme_font("font")
	var maximum_size: int = NAME_FONT_MAX_SIZE if resolved_width >= 104.0 else (13 if resolved_width >= 84.0 else 11)
	var minimum_size: int = mini(NAME_FONT_MIN_SIZE, maximum_size)
	var chosen_size: int = maximum_size
	if font != null and _name_label.text != "":
		chosen_size = minimum_size
		for candidate_size: int in range(maximum_size, minimum_size - 1, -1):
			var measured_size: Vector2 = font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, candidate_size)
			if measured_size.x <= available_width:
				chosen_size = candidate_size
				break
	_name_label.add_theme_font_size_override("font_size", chosen_size)


func _set_cost_value(cost: int) -> void:
	if _cost_badge == null or _cost_label == null:
		return
	_cost_badge.visible = true
	_cost_label.text = "%d" % maxi(0, cost)


func _apply_frame(border_color: Color, border_width: int = 2, overlay_width: int = 4) -> void:
	var hover_color: Color = border_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.35)
	var pressed_color: Color = border_color.lerp(Color(1.0, 0.92, 0.72, 1.0), 0.45)
	add_theme_stylebox_override("normal", _make_stylebox(border_color, border_width))
	add_theme_stylebox_override("hover", _make_stylebox(hover_color, border_width + 1))
	add_theme_stylebox_override("pressed", _make_stylebox(pressed_color, border_width + 1))
	add_theme_stylebox_override("focus", _make_stylebox(pressed_color, border_width + 1))
	if _frame_overlay != null:
		_frame_overlay.add_theme_stylebox_override("panel", _make_overlay_stylebox(border_color, overlay_width))


func _make_stylebox(border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FRAME_FILL
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.24)
	style.shadow_size = 6
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _make_overlay_stylebox(border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _set_recovery_ratio(value: float) -> void:
	_recovery_ratio = clampf(value, 0.0, 1.0)
	_update_cooldown_mask()


func _set_timeline_indicators(show_timeline: bool, is_next: bool) -> void:
	if _timeline_next_badge != null:
		_timeline_next_badge.visible = show_timeline and is_next


func _set_mouse_cursor(enabled: bool) -> void:
	if enabled:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW


func _update_cooldown_mask() -> void:
	if _cooldown_shade == null or _progress_edge == null:
		return

	var hidden_width: float = size.x * (1.0 - _recovery_ratio)
	_cooldown_shade.offset_left = 0.0
	_cooldown_shade.offset_top = 0.0
	_cooldown_shade.offset_right = hidden_width
	_cooldown_shade.offset_bottom = 0.0
	_cooldown_shade.visible = hidden_width > 1.0

	if hidden_width <= 1.0 or _recovery_ratio <= 0.0 or _recovery_ratio >= 1.0:
		_progress_edge.visible = false
		return

	_progress_edge.visible = true
	_progress_edge.offset_left = maxf(0.0, hidden_width - 3.0)
	_progress_edge.offset_top = 0.0
	_progress_edge.offset_right = minf(size.x, hidden_width + 1.0)
	_progress_edge.offset_bottom = 0.0


func _compute_cooldown_ratio(card_def: CardDef, runtime_state: CardRuntimeState) -> float:
	if card_def.recast_time <= 0.0:
		return 1.0
	return clampf(1.0 - (runtime_state.cooldown_remaining / card_def.recast_time), 0.0, 1.0)


func _compute_active_ratio(instance: ActiveCardInstance, battle_time: float) -> float:
	var total_duration: float = max(0.001, instance.scheduled_time - instance.created_at)
	var elapsed: float = clampf(battle_time - instance.created_at, 0.0, total_duration)
	return clampf(elapsed / total_duration, 0.0, 1.0)


func _compute_timeline_ratio(entry: TimelineEntry, battle_time: float) -> float:
	var total_duration: float = max(0.001, entry.scheduled_time - entry.created_at)
	var elapsed: float = clampf(battle_time - entry.created_at, 0.0, total_duration)
	return clampf(elapsed / total_duration, 0.0, 1.0)


func _build_hand_tooltip(card_def: CardDef, _tooltip_state: String, tooltip_blocked: String, _runtime_state: CardRuntimeState, rich: bool = false) -> String:
	var lines: Array[String] = _build_battle_tooltip_lines(card_def, rich)
	if tooltip_blocked != "":
		lines.append("")
		lines.append(tooltip_blocked)
	return "\n".join(lines)


func _build_preview_simple_tooltip(card_def: CardDef, rich: bool = false) -> String:
	return "\n".join(_build_battle_tooltip_lines(card_def, rich))


func _build_preview_tooltip(card_def: CardDef, rich: bool = false) -> String:
	var comparison_card: CardDef = _get_comparison_card(card_def)
	var base_cast_time: float = card_def.cast_time
	var base_recast_time: float = card_def.recast_time
	if comparison_card != null:
		base_cast_time = comparison_card.cast_time
		base_recast_time = comparison_card.recast_time
	var lines: Array[String] = [
		card_def.name,
		card_def.description,
		"",
		Localization.get_textf("card.tooltip.rarity", "Rarity: {value}", {"value": Localization.get_rarity_name(card_def.rarity)}),
		Localization.get_textf("card.tooltip.tags", "Tags: {value}", {"value": _build_tags_text(card_def.tags)}),
		Localization.get_textf("card.tooltip.cast", "Cast: {value}s", {"value": _format_compared_float(card_def.cast_time, base_cast_time, 1, false, rich)}),
		Localization.get_textf("card.tooltip.recast", "Recast: {value}s", {"value": _format_compared_float(card_def.recast_time, base_recast_time, 1, false, rich)}),
		Localization.get_textf("card.tooltip.loadout_cost", "Loadout Cost: {cost}", {"cost": card_def.loadout_cost}),
		Localization.get_textf("card.tooltip.slots", "Slots: {value}", {"value": card_def.active_slot_cost}),
		Localization.get_textf("card.tooltip.target", "Target: {value}", {"value": Localization.get_target_name(card_def.target_type)}),
	]
	_append_effect_lines(lines, card_def, rich)
	_append_grade_lines(lines, card_def.id)
	return "\n".join(lines)


func _build_legacy_tooltip(card_def: CardDef, extra_note: String = "", rich: bool = false) -> String:
	var lines: Array[String] = []
	for raw_line in _build_preview_tooltip(card_def, rich).split("\n"):
		lines.append(String(raw_line))
	if extra_note != "":
		lines.append("")
		lines.append(extra_note)
	return "\n".join(lines)


func _build_active_tooltip(card_def: CardDef, _instance: ActiveCardInstance, _remaining: float, rich: bool = false) -> String:
	return "\n".join(_build_battle_tooltip_lines(card_def, rich))


func _build_timeline_tooltip(card_def: CardDef, _entry: TimelineEntry, _remaining: float, rich: bool = false) -> String:
	return "\n".join(_build_battle_tooltip_lines(card_def, rich))


func _build_battle_tooltip_lines(card_def: CardDef, rich: bool = false) -> Array[String]:
	var comparison_card: CardDef = _get_comparison_card(card_def)
	var base_cast_time: float = card_def.cast_time
	var base_recast_time: float = card_def.recast_time
	if comparison_card != null:
		base_cast_time = comparison_card.cast_time
		base_recast_time = comparison_card.recast_time

	var lines: Array[String] = [card_def.name]
	_append_battle_effect_lines(lines, card_def, rich)
	lines.append(Localization.get_textf("card.tooltip.cast", "Cast: {value}s", {
		"value": _format_compared_float(card_def.cast_time, base_cast_time, 1, false, rich),
	}))
	lines.append(Localization.get_textf("card.tooltip.recast", "Recast: {value}s", {
		"value": _format_compared_float(card_def.recast_time, base_recast_time, 1, false, rich),
	}))
	lines.append(Localization.get_textf("card.tooltip.loadout_cost", "Loadout Cost: {cost}", {
		"cost": card_def.loadout_cost,
	}))
	_append_status_detail_lines(lines, card_def, rich)
	return lines


func _build_tags_text(tags: Array[String]) -> String:
	return Localization.get_tags_text(tags)


func _set_tooltip_variants(simple_text: String, simple_bbcode: String, legacy_text: String, legacy_bbcode: String) -> void:
	_simple_tooltip_text = simple_text
	_simple_tooltip_bbcode = simple_bbcode
	_legacy_tooltip_text = legacy_text
	_legacy_tooltip_bbcode = legacy_bbcode
	_apply_stored_tooltip_mode()


func _append_tooltip_text(base_text: String, line_text: String) -> String:
	if base_text == "":
		return line_text
	return "%s\n%s" % [base_text, line_text]


func _apply_stored_tooltip_mode() -> void:
	if _use_legacy_tooltips:
		tooltip_text = _legacy_tooltip_text
		_tooltip_bbcode = _legacy_tooltip_bbcode
	else:
		tooltip_text = _simple_tooltip_text
		_tooltip_bbcode = _simple_tooltip_bbcode


func _get_comparison_card(card_def: CardDef) -> CardDef:
	if card_def == null:
		return null
	if _comparison_card_override != null and _comparison_card_override.id == card_def.id:
		return _comparison_card_override
	return Database.get_card(card_def.id)


func _format_compared_float(current_value: float, base_value: float, decimals: int, higher_is_beneficial: bool, rich: bool) -> String:
	var current_text: String = _format_float_value(current_value, decimals, false)
	var delta: float = current_value - base_value
	if absf(delta) < 0.001:
		return current_text

	var delta_text: String = _format_float_value(delta, decimals, true)
	var compared_text: String = "%s(%s)" % [current_text, delta_text]
	if not rich:
		return compared_text

	var is_beneficial: bool = delta > 0.0 if higher_is_beneficial else delta < 0.0
	var color: String = TOOLTIP_BUFF_COLOR if is_beneficial else TOOLTIP_NERF_COLOR
	return "%s[color=%s](%s)[/color]" % [current_text, color, delta_text]


func _format_float_value(value: float, decimals: int, force_sign: bool) -> String:
	if decimals <= 0:
		var int_value: int = int(roundf(value))
		if force_sign:
			if int_value >= 0:
				return "+%d" % int_value
			return "%d" % int_value
		return "%d" % int_value
	var pattern: String = "%." + str(decimals) + "f"
	var value_text: String = pattern % value
	if force_sign and value >= 0.0:
		return "+%s" % value_text
	return value_text


func _escape_bbcode(value: String) -> String:
	return value.replace("[", "[lb]").replace("]", "[rb]")


func _append_effect_lines(lines: Array[String], card_def: CardDef, rich: bool = false) -> void:
	var effect_lines: Array[String] = CardInfoFormatter.build_effect_lines(card_def, _get_comparison_card(card_def), rich)
	if effect_lines.is_empty():
		return
	lines.append(Localization.get_text("card.tooltip.effects", "Effects:"))
	for effect_line in effect_lines:
		lines.append("- %s" % effect_line)


func _append_battle_effect_lines(lines: Array[String], card_def: CardDef, rich: bool = false) -> void:
	var effect_lines: Array[String] = CardInfoFormatter.build_effect_lines(card_def, _get_comparison_card(card_def), rich)
	if effect_lines.is_empty():
		if card_def.description != "":
			lines.append("%s %s" % [
				Localization.get_text("card.tooltip.effects", "Effects:"),
				_highlight_status_names(card_def.description, card_def, rich),
			])
		return

	for effect_index in range(effect_lines.size()):
		var highlighted_line: String = _highlight_status_names(effect_lines[effect_index], card_def, rich)
		if effect_index == 0:
			lines.append("%s %s" % [Localization.get_text("card.tooltip.effects", "Effects:"), highlighted_line])
		else:
			lines.append("- %s" % highlighted_line)


func _highlight_status_names(text: String, card_def: CardDef, rich: bool) -> String:
	if not rich:
		return text
	var highlighted_text: String = text
	for status_id in _get_applied_status_ids(card_def):
		var status_name: String = Localization.get_status_name(status_id)
		highlighted_text = highlighted_text.replace(status_name, "[color=%s]%s[/color]" % [TOOLTIP_STATUS_COLOR, status_name])
	return highlighted_text


func _append_status_detail_lines(lines: Array[String], card_def: CardDef, rich: bool = false) -> void:
	var status_ids: Array[String] = _get_applied_status_ids(card_def)
	if status_ids.is_empty():
		return
	lines.append("")
	lines.append(Localization.get_text("card.tooltip.status_details", "Status Details:"))
	for status_id in status_ids:
		var status_name: String = Localization.get_status_name(status_id)
		if rich:
			status_name = "[color=%s]%s[/color]" % [TOOLTIP_STATUS_COLOR, status_name]
		lines.append("%s: %s" % [status_name, _get_status_detail_text(status_id)])


func _get_applied_status_ids(card_def: CardDef) -> Array[String]:
	var status_ids: Array[String] = []
	for effect in card_def.effects:
		if String(effect.get("type", "")) != "apply_status":
			continue
		var status_id: String = String(effect.get("status", ""))
		if status_id != "" and not status_ids.has(status_id):
			status_ids.append(status_id)
	return status_ids


func _get_status_detail_text(status_id: String) -> String:
	match status_id:
		"bleed":
			return Localization.get_textf("status.detail.bleed", "Takes {amount} damage every {interval}s.", {
				"amount": 1,
				"interval": "%.1f" % UnitState.BLEED_TICK_INTERVAL,
			})
		"weak":
			return Localization.get_textf("status.detail.weak", "Attack -{amount} while active.", {"amount": 2})
		"slow":
			return Localization.get_textf("status.detail.slow", "Cast time +{percent}% while active.", {"percent": 10})
		"vulnerable":
			return Localization.get_textf("status.detail.vulnerable", "Incoming damage +{amount} while active.", {"amount": 3})
		_:
			return Localization.get_text("status.detail.unknown", "Temporary status effect.")


func _append_grade_lines(lines: Array[String], card_id: String) -> void:
	var grade_lines: Array[String] = CardInfoFormatter.build_grade_lines(card_id)
	if grade_lines.is_empty():
		return
	lines.append(Localization.get_text("card.tooltip.grades", "Grades:"))
	for grade_line in grade_lines:
		lines.append("- %s" % grade_line)


func _get_rarity_border(rarity: String) -> Color:
	match rarity:
		"rare":
			return RARE_BORDER
		"epic":
			return EPIC_BORDER
		"legendary":
			return LEGENDARY_BORDER
		_:
			return COMMON_BORDER


func _get_active_border(owner_side: String) -> Color:
	if owner_side == "enemy":
		return ACTIVE_ENEMY_BORDER
	return ACTIVE_PLAYER_BORDER


func _get_card_texture(card_id: String) -> Texture2D:
	return CardButton._load_card_texture(card_id)


static func _load_card_texture(card_id: String) -> Texture2D:
	if _texture_cache.has(card_id):
		return _texture_cache[card_id] as Texture2D

	var path: String = ART_PATH_TEMPLATE % card_id
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var resource: Resource = load(path)
		texture = resource as Texture2D
	if texture == null:
		texture = _build_placeholder_texture(card_id)
	_texture_cache[card_id] = texture
	return texture


static func _build_placeholder_texture(card_id: String) -> Texture2D:
	var image: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var hue: float = float(abs(card_id.hash()) % 1000) / 1000.0
	var base_color: Color = Color.from_hsv(hue, 0.58, 0.78, 1.0)
	var accent_color: Color = base_color.lightened(0.18)
	var panel_color: Color = base_color.darkened(0.22)
	var name_bar_color: Color = base_color.darkened(0.42)

	image.fill(base_color)
	image.fill_rect(Rect2i(18, 18, 220, 220), accent_color)
	image.fill_rect(Rect2i(36, 36, 184, 184), panel_color)
	image.fill_rect(Rect2i(0, 198, 256, 58), name_bar_color)

	for band_index in range(0, 256, 28):
		image.fill_rect(Rect2i(0, band_index, 256, 8), base_color.darkened(0.10))
	for stripe_index in range(0, 256, 32):
		image.fill_rect(Rect2i(stripe_index, 0, 10, 256), accent_color.darkened(0.08))

	return ImageTexture.create_from_image(image)
