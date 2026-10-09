extends Node
class_name HoverActionReveal

var enabled: bool = true
var _target: Control
var _actions: Control


static func attach(target: Control, actions: Control, reserve_space: bool = true) -> HoverActionReveal:
	var reveal: HoverActionReveal = HoverActionReveal.new()
	reveal.name = "HoverActionReveal"
	reveal._target = target
	reveal._actions = actions
	if reserve_space:
		var parent: Node = actions.get_parent()
		var index: int = actions.get_index()
		var slot: Control = Control.new()
		slot.name = "HoverActionsSlot"
		slot.custom_minimum_size = actions.get_combined_minimum_size()
		slot.custom_minimum_size.y = maxf(44.0, slot.custom_minimum_size.y)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.remove_child(actions)
		parent.add_child(slot)
		parent.move_child(slot, index)
		slot.add_child(actions)
		actions.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actions.hide()
	target.add_child(reveal)
	return reveal


func _process(_delta: float) -> void:
	if not is_instance_valid(_target) or get_window() == null or not get_window().has_focus() or not _target.get_global_rect().has_point(_target.get_global_mouse_position()):
		update_for_control(null)
		return
	# Descendant buttons, clipping, scrolling, and modal overlays share one hit test.
	update_for_control(get_viewport().gui_get_hovered_control())


func update_for_control(hovered: Control) -> void:
	if not is_instance_valid(_target) or not is_instance_valid(_actions):
		return
	_actions.visible = enabled and _target.is_visible_in_tree() and is_instance_valid(hovered) and (
		hovered == _target or _target.is_ancestor_of(hovered)
	)
