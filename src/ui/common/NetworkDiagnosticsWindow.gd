extends Window
class_name NetworkDiagnosticsWindow

var _label: Label
var _elapsed: float = 0.0


static func open(parent: Node) -> void:
	if not Game.is_developer_mode_enabled():
		return
	var existing: Node = parent.get_node_or_null("NetworkDiagnostics")
	if existing != null:
		(existing as Window).popup_centered()
		return
	var window: NetworkDiagnosticsWindow = NetworkDiagnosticsWindow.new()
	window.name = "NetworkDiagnostics"
	parent.add_child(window)
	window.popup_centered(Vector2i(610, 440))


func _ready() -> void:
	title = Localization.get_text("network.diagnostics", "Network diagnostics")
	close_requested.connect(queue_free)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(_label)
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.5:
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	var data: Dictionary = NetworkManager.diagnostics.snapshot()
	_label.text = "%s\nFPS %d | Ping %d ms\nTX %.1f KiB/s (%.1f/s)\nRX %.1f KiB/s (%.1f/s)\n%s %s\n%s %d / %d / %d\n\n%s" % [
		String(NetworkManager.ConnectionState.keys()[NetworkManager.get_connection_state()]), Engine.get_frames_per_second(), NetworkManager.get_connection_ping_ms(),
		float(data["tx_bytes_s"]) / 1024.0, float(data["tx_hz"]), float(data["rx_bytes_s"]) / 1024.0, float(data["rx_hz"]),
		Localization.get_text("network.snapshot_age", "Snapshot age:"), "%d ms" % int(data["age_ms"]) if int(data["age_ms"]) >= 0 else "--",
		Localization.get_text("network.snapshot_counts", "Accepted / rejected / sequence gaps:"), int(data["accepted"]), int(data["stale"]), int(data["gaps"]),
		Localization.get_text("network.diagnostics_note", "5-second application snapshot payload averages, not wire bandwidth. Gaps can include reordering; they are not a packet-loss percentage. Host local snapshots are not RX traffic. This window does not pause a match.")]
