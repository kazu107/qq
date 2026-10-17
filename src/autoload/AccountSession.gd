extends Node

signal changed

var snapshot: Dictionary = {"available": false, "authenticated": false, "needsUsername": false, "user": null, "providers": []}
var _bridge: JavaScriptObject
var _listener: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web"): return
	_bridge = JavaScriptBridge.get_interface("qqAccount")
	if _bridge == null: return
	_listener = JavaScriptBridge.create_callback(_on_snapshot)
	_bridge.subscribe(_listener)


func is_supported() -> bool:
	return OS.has_feature("web") and _bridge != null


func refresh() -> void:
	if is_supported(): _bridge.refresh()


func open_account(language: String) -> bool:
	return is_supported() and bool(_bridge.open(language))


func _on_snapshot(arguments: Array) -> void:
	if arguments.is_empty(): return
	var text: String = String(arguments[0])
	if text.length() > 8192: return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary: return
	# Display-only identity; never persist browser sessions or OAuth tokens in the game save.
	snapshot = Dictionary(parsed)
	changed.emit()
