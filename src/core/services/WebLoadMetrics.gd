extends RefCounted
class_name WebLoadMetrics


static func record(event_name: String, elapsed_ms: float, details: Dictionary = {}) -> void:
	if not OS.has_feature("web"):
		return
	var entry: Dictionary = {
		"event": event_name,
		"elapsed_ms": snappedf(elapsed_ms, 0.01),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"details": details,
	}
	JavaScriptBridge.eval(
		"window.qqLoadMetrics=window.qqLoadMetrics||[];window.qqLoadMetrics.push(%s);" % JSON.stringify(entry)
		+ "if(window.qqLoadMetrics.length>128)window.qqLoadMetrics.shift();",
		true
	)
