extends RefCounted
class_name UiIconHelper

const DATA_PATH: String = "res://data/ui_action_icons.json"
static var _labels: Dictionary = {}


static func get_ids() -> Array[String]:
	if _labels.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_labels = parsed
	var ids: Array[String] = []
	for id: String in _labels:
		ids.append(id)
	return ids


static func get_hint(id: String) -> String:
	get_ids()
	var labels: Array = _labels.get(id, [id, id])
	return String(labels[0 if Localization.get_language() == "ja" else 1])


static func icon_node(id: String, extent: float = 24.0, hint: String = "") -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = StatIconFactory.get_icon(id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2.ONE * extent
	icon.tooltip_text = hint if hint != "" else get_hint(id)
	return icon


static func decorate(button: Button, id: String, hint: String = "", compact: bool = false, value: String = "") -> void:
	button.icon = StatIconFactory.get_icon(id)
	button.add_theme_constant_override("icon_max_width", 22)
	button.add_theme_constant_override("h_separation", 7)
	if compact:
		button.text = value
		button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, 36.0)
		button.tooltip_text = hint if hint != "" else get_hint(id)
	elif hint != "" and button.tooltip_text == "":
		button.tooltip_text = hint
	button.set_meta("semantic_icon", id)


static func decorate_default(button: Button) -> void:
	if button is OptionButton or button is CheckButton or button is CheckBox or button is CardButton or button.icon != null or button.text == "":
		return
	# Data IDs in UnlockCard_foo / ClaimAchievement_foo are not action names.
	var name: String = String(button.name).to_lower()
	if name.begins_with("unlock") or name.begins_with("claimachievement"):
		name = name.get_slice("_", 0)
	var id: String = ""
	# Stable node names avoid locale-specific text guessing and per-frame traversal.
	for rule: Array in [
		["returnhub", "home"], ["return_hub", "home"], ["back", "back"], ["previous", "back"],
		["deckunequip", "unequip"], ["equipbutton", "equip"], ["sellbutton", "sell"],
		["reroll", "reroll"], ["retry", "restart"], ["reset", "restart"],
		["export", "export"], ["save", "save"], ["loadbutton", "load"], ["loadpreset", "load"], ["delete", "delete"],
		["unlock", "unlock"], ["claim", "claim"], ["upgrade", "upgrade"],
		["close", "close"], ["logbutton", "log"], ["details", "info"], ["inspect", "info"],
		["spectat", "spectator"], ["addbot", "bot"], ["removebot", "close"],
		["webmultiplayer", "online"], ["ready", "ready"], ["start", "play"], ["continue", "next"], ["next", "next"],
		["play", "play"], ["pause", "pause"], ["stop", "pause"], ["stepforward", "next"], ["replay", "play"], ["leave", "exit"], ["exit", "exit"],
		["host", "online"], ["join", "online"],
		["tutorial", "tutorial"], ["metaprogress", "meta_points"], ["cardlibrary", "card_owned"],
	]:
		if name.contains(String(rule[0])):
			id = String(rule[1])
			break
	if id == "":
		return
	if name.contains("deckunequip"):
		var hint: String = button.tooltip_text if button.tooltip_text != "" else get_hint(id)
		decorate(button, id, hint, true)
		button.custom_minimum_size.x = 24.0
		button.add_theme_constant_override("icon_max_width", 16)
	elif name.contains("removebot") or name.ends_with("close"):
		decorate(button, id, button.tooltip_text, true)
	else:
		decorate(button, id)
