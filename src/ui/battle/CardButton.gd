extends Button
class_name CardButton

signal card_requested(runtime_id: String)

const ART_PATH_TEMPLATE := "res://assets/icons/cards/%s.png"
const FRAME_FILL := Color(0.09, 0.10, 0.13, 0.96)
const NAME_BAR_COLOR := Color(0.03, 0.04, 0.06, 0.84)
const BADGE_DARK := Color(0.07, 0.08, 0.10, 0.88)
const BADGE_ACTIVE := Color(0.16, 0.44, 0.70, 0.92)
const TEXT_LIGHT := Color(0.97, 0.96, 0.93, 1.0)
const COOLDOWN_SHADE := Color(0.01, 0.02, 0.03, 0.70)
const PROGRESS_EDGE := Color(1.0, 0.95, 0.72, 0.38)
const COMMON_BORDER := Color(0.88, 0.80, 0.67, 1.0)
const RARE_BORDER := Color(0.47, 0.86, 0.90, 1.0)
const EPIC_BORDER := Color(0.97, 0.69, 0.34, 1.0)
const ACTIVE_PLAYER_BORDER := Color(0.24, 0.56, 1.0, 1.0)
const ACTIVE_ENEMY_BORDER := Color(0.95, 0.28, 0.25, 1.0)

static var _texture_cache: Dictionary = {}

var runtime_id: String = ""
var _can_use: bool = false
var _click_enabled: bool = true
var _recovery_ratio: float = 1.0

var _art_rect: TextureRect
var _frame_overlay: Panel
var _cooldown_shade: ColorRect
var _progress_edge: ColorRect
var _name_bar: ColorRect
var _name_label: Label
var _state_badge: ColorRect
var _state_label: Label
var _meta_badge: ColorRect
var _meta_label: Label


func _ready() -> void:
	_ensure_visuals()


func set_tile_size(size: Vector2) -> void:
	custom_minimum_size = size


func bind(card_def: CardDef, runtime_state: CardRuntimeState, can_use: bool, click_enabled: bool = true) -> void:
	_ensure_visuals()
	runtime_id = runtime_state.runtime_id
	_click_enabled = click_enabled
	_can_use = can_use and click_enabled
	text = ""
	_art_rect.texture = _get_card_texture(card_def.id)
	_name_label.text = card_def.name

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
	_meta_label.text = meta_text
	_meta_badge.color = BADGE_DARK
	modulate = modulate_color
	_set_mouse_cursor(_can_use)
	_apply_frame(_get_rarity_border(card_def.rarity))
	_set_recovery_ratio(recovery_ratio)
	tooltip_text = _build_hand_tooltip(card_def, tooltip_state, tooltip_blocked, runtime_state)


func bind_preview(card_def: CardDef, preview_id: String, click_enabled: bool = false, badge_text: String = "CARD") -> void:
	_ensure_visuals()
	runtime_id = preview_id
	_click_enabled = click_enabled
	_can_use = click_enabled
	text = ""
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_art_rect.texture = _get_card_texture(card_def.id)
	_name_label.text = card_def.name
	_state_label.text = ""
	_state_badge.visible = false
	_meta_label.text = "%dS" % card_def.active_slot_cost
	_meta_badge.color = BADGE_DARK
	_apply_frame(_get_rarity_border(card_def.rarity))
	_set_mouse_cursor(_can_use)
	_set_recovery_ratio(1.0)
	tooltip_text = _build_preview_tooltip(card_def)


func bind_active(card_def: CardDef, instance: ActiveCardInstance, battle_time: float) -> void:
	_ensure_visuals()
	runtime_id = instance.runtime_id
	_click_enabled = false
	_can_use = false
	text = ""
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_art_rect.texture = _get_card_texture(card_def.id)
	_name_label.text = card_def.name
	_state_label.text = ""
	_state_badge.visible = false

	var remaining: float = instance.get_remaining(battle_time)
	_meta_label.text = Localization.get_text("card.meta.casting", "casting")
	_meta_badge.color = BADGE_DARK
	_apply_frame(_get_active_border(instance.owner_side))
	_set_mouse_cursor(false)
	_set_recovery_ratio(_compute_active_ratio(instance, battle_time))
	tooltip_text = _build_active_tooltip(card_def, instance, remaining)


func bind_timeline(card_def: CardDef, entry: TimelineEntry, battle_time: float) -> void:
	_ensure_visuals()
	runtime_id = entry.runtime_id
	_click_enabled = false
	_can_use = false
	text = ""
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_art_rect.texture = _get_card_texture(card_def.id)
	_name_label.text = card_def.name
	_state_label.text = ""
	_state_badge.visible = false

	var remaining: float = max(0.0, entry.scheduled_time - battle_time)
	_meta_label.text = Localization.get_text("card.meta.casting", "casting")
	_meta_badge.color = BADGE_DARK
	_apply_frame(_get_active_border(entry.owner_side))
	_set_mouse_cursor(false)
	_set_recovery_ratio(_compute_timeline_ratio(entry, battle_time))
	tooltip_text = _build_timeline_tooltip(card_def, entry, remaining)


func _on_pressed() -> void:
	if not _click_enabled or not _can_use or runtime_id == "":
		return
	card_requested.emit(runtime_id)


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

	_art_rect = TextureRect.new()
	_art_rect.name = "Art"
	_art_rect.anchor_right = 1.0
	_art_rect.anchor_bottom = 1.0
	_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_configure_overlay(_art_rect)
	add_child(_art_rect)

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

	_apply_frame(COMMON_BORDER)
	_update_cooldown_mask()


func _configure_overlay(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_frame(border_color: Color) -> void:
	var hover_color: Color = border_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.35)
	var pressed_color: Color = border_color.lerp(Color(1.0, 0.92, 0.72, 1.0), 0.45)
	add_theme_stylebox_override("normal", _make_stylebox(border_color, 2))
	add_theme_stylebox_override("hover", _make_stylebox(hover_color, 3))
	add_theme_stylebox_override("pressed", _make_stylebox(pressed_color, 3))
	add_theme_stylebox_override("focus", _make_stylebox(pressed_color, 3))
	if _frame_overlay != null:
		_frame_overlay.add_theme_stylebox_override("panel", _make_overlay_stylebox(border_color, 4))


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
	_progress_edge.offset_left = max(0.0, hidden_width - 3.0)
	_progress_edge.offset_top = 0.0
	_progress_edge.offset_right = min(size.x, hidden_width + 1.0)
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


func _build_hand_tooltip(card_def: CardDef, tooltip_state: String, tooltip_blocked: String, runtime_state: CardRuntimeState) -> String:
	var lines: Array[String] = [
		card_def.name,
		card_def.description,
		"",
		Localization.get_textf("card.tooltip.rarity", "Rarity: {value}", {"value": Localization.get_rarity_name(card_def.rarity)}),
		Localization.get_textf("card.tooltip.tags", "Tags: {value}", {"value": _build_tags_text(card_def.tags)}),
		Localization.get_textf("card.tooltip.cast", "Cast: {value}s", {"value": "%.1f" % card_def.cast_time}),
		Localization.get_textf("card.tooltip.recast", "Recast: {value}s", {"value": "%.1f" % card_def.recast_time}),
		Localization.get_textf("card.tooltip.slots", "Slots: {value}", {"value": card_def.active_slot_cost}),
		Localization.get_textf("card.tooltip.target", "Target: {value}", {"value": Localization.get_target_name(card_def.target_type)}),
		Localization.get_textf("card.tooltip.state", "State: {value}", {"value": tooltip_state}),
	]
	_append_effect_lines(lines, card_def)
	if runtime_state.state == CardRuntimeState.CardState.COOLDOWN:
		lines.append(Localization.get_textf("card.tooltip.recovery", "Recovery: {value}%", {
			"value": int(round(_compute_cooldown_ratio(card_def, runtime_state) * 100.0)),
		}))
	if tooltip_blocked != "":
		lines.append(tooltip_blocked)
	_append_grade_lines(lines, card_def.id)
	return "\n".join(lines)


func _build_preview_tooltip(card_def: CardDef) -> String:
	var lines: Array[String] = [
		card_def.name,
		card_def.description,
		"",
		Localization.get_textf("card.tooltip.rarity", "Rarity: {value}", {"value": Localization.get_rarity_name(card_def.rarity)}),
		Localization.get_textf("card.tooltip.tags", "Tags: {value}", {"value": _build_tags_text(card_def.tags)}),
		Localization.get_textf("card.tooltip.cast", "Cast: {value}s", {"value": "%.1f" % card_def.cast_time}),
		Localization.get_textf("card.tooltip.recast", "Recast: {value}s", {"value": "%.1f" % card_def.recast_time}),
		Localization.get_textf("card.tooltip.slots", "Slots: {value}", {"value": card_def.active_slot_cost}),
		Localization.get_textf("card.tooltip.target", "Target: {value}", {"value": Localization.get_target_name(card_def.target_type)}),
	]
	_append_effect_lines(lines, card_def)
	_append_grade_lines(lines, card_def.id)
	return "\n".join(lines)


func _build_active_tooltip(card_def: CardDef, instance: ActiveCardInstance, remaining: float) -> String:
	var lines: Array[String] = [
		card_def.name,
		card_def.description,
		"",
		Localization.get_textf("card.tooltip.owner", "Owner: {value}", {"value": Localization.get_owner_name(instance.owner_side)}),
		Localization.get_textf("card.tooltip.rarity", "Rarity: {value}", {"value": Localization.get_rarity_name(card_def.rarity)}),
		Localization.get_textf("card.tooltip.tags", "Tags: {value}", {"value": _build_tags_text(card_def.tags)}),
		Localization.get_textf("card.tooltip.resolves_in", "Resolves in: {value}s", {"value": "%.1f" % remaining}),
		Localization.get_textf("card.tooltip.slots_used", "Slots Used: {value}", {"value": instance.slot_cost}),
	]
	_append_effect_lines(lines, card_def)
	if instance.interruptible:
		lines.append(Localization.get_text("card.tooltip.interruptible", "Interruptible"))
	_append_grade_lines(lines, card_def.id)
	return "\n".join(lines)


func _build_timeline_tooltip(card_def: CardDef, entry: TimelineEntry, remaining: float) -> String:
	var lines: Array[String] = [
		card_def.name,
		card_def.description,
		"",
		Localization.get_textf("card.tooltip.owner", "Owner: {value}", {"value": Localization.get_owner_name(entry.owner_side)}),
		Localization.get_textf("card.tooltip.rarity", "Rarity: {value}", {"value": Localization.get_rarity_name(card_def.rarity)}),
		Localization.get_textf("card.tooltip.tags", "Tags: {value}", {"value": _build_tags_text(card_def.tags)}),
		Localization.get_textf("card.tooltip.resolves_in", "Resolves in: {value}s", {"value": "%.1f" % remaining}),
		Localization.get_textf("card.tooltip.cast_window", "Cast Window: {value}s", {"value": "%.1f" % max(0.0, entry.scheduled_time - entry.created_at)}),
		Localization.get_textf("card.tooltip.slots_used", "Slots Used: {value}", {"value": entry.slot_cost}),
	]
	_append_effect_lines(lines, card_def)
	if entry.interruptible:
		lines.append(Localization.get_text("card.tooltip.interruptible", "Interruptible"))
	_append_grade_lines(lines, card_def.id)
	return "\n".join(lines)


func _build_tags_text(tags: Array[String]) -> String:
	return Localization.get_tags_text(tags)


func _append_effect_lines(lines: Array[String], card_def: CardDef) -> void:
	var effect_lines: Array[String] = CardInfoFormatter.build_effect_lines(card_def)
	if effect_lines.is_empty():
		return
	lines.append(Localization.get_text("card.tooltip.effects", "Effects:"))
	for effect_line in effect_lines:
		lines.append("- %s" % effect_line)


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
		_:
			return COMMON_BORDER


func _get_active_border(owner_side: String) -> Color:
	if owner_side == "enemy":
		return ACTIVE_ENEMY_BORDER
	return ACTIVE_PLAYER_BORDER


func _get_card_texture(card_id: String) -> Texture2D:
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


func _build_placeholder_texture(card_id: String) -> Texture2D:
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
