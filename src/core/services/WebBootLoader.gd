extends RefCounted
class_name WebBootLoader


static func report_progress(text: String, progress: float) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"if(window.qqBootLoader){window.qqBootLoader.update(%s,%s);}" % [
			JSON.stringify(text), JSON.stringify(clampf(progress, 0.0, 1.0)),
		],
		true
	)


static func finish() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.qqBootLoader){window.qqBootLoader.finish();}", true)
