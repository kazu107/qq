extends PanelContainer
class_name RunInfoBanner

const ICON_SIZE: Vector2 = Vector2(30.0, 30.0)
const RELIC_ICON_SIZE: Vector2 = Vector2(30.0, 30.0)
const TEXT_COLOR: Color = Color(0.94, 0.98, 0.96, 1.0)

var _hp_label: Label
var _gold_label: Label
var _step_label: Label
var _relic_row: RelicIconRow


func _ready() -> void:
	name = "RunInfoBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", _make_banner_stylebox())
	_build_ui()
	refresh()


func refresh(live_hp: int = -1, live_max_hp: int = -1) -> void:
	if Game.current_run == null:
		visible = false
		return

	visible = true
	var hp_value: int = live_hp if live_hp >= 0 else Game.current_run.player_hp
	var max_hp_value: int = live_max_hp if live_max_hp > 0 else Game.current_run.max_hp
	_hp_label.text = "%d/%d" % [maxi(0, hp_value), maxi(1, max_hp_value)]
	_gold_label.text = "%d" % maxi(0, Game.current_run.gold)
	_step_label.text = "%d/%d" % [
		min(Game.get_map_step_count(), Game.get_current_step_index() + 1),
		maxi(1, Game.get_map_step_count()),
	]
	_relic_row.refresh_relic_ids(Game.current_run.relics)


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 7)
	add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "RunInfoBannerRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	_hp_label = _add_icon_value(row, "Hp", "hp")
	_gold_label = _add_icon_value(row, "Gold", "gold")
	_step_label = _add_icon_value(row, "Step", "step")

	var relic_group: HBoxContainer = HBoxContainer.new()
	relic_group.name = "RunRelicGroup"
	relic_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	relic_group.add_theme_constant_override("separation", 8)
	row.add_child(relic_group)

	var relic_icon: TextureRect = _build_icon_rect("relic")
	relic_group.add_child(relic_icon)

	_relic_row = RelicIconRow.new()
	_relic_row.name = "RunRelicIconRow"
	_relic_row.set_icon_size(RELIC_ICON_SIZE)
	relic_group.add_child(_relic_row)

	var spacer: Control = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)


func _add_icon_value(parent: Control, node_prefix: String, icon_id: String) -> Label:
	var group: HBoxContainer = HBoxContainer.new()
	group.name = "Run%sGroup" % node_prefix
	group.add_theme_constant_override("separation", 6)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(group)

	group.add_child(_build_icon_rect(icon_id))

	var value_label: Label = Label.new()
	value_label.name = "Run%sValue" % node_prefix
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", TEXT_COLOR)
	value_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
	value_label.add_theme_constant_override("outline_size", 3)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(value_label)
	return value_label


func _build_icon_rect(icon_id: String) -> TextureRect:
	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.name = "RunIcon_%s" % icon_id
	icon_rect.custom_minimum_size = ICON_SIZE
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = StatIconFactory.get_icon(icon_id)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon_rect


func _make_banner_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.043, 0.90)
	style.border_color = Color(0.26, 0.52, 0.60, 0.72)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 3.0)
	return style
