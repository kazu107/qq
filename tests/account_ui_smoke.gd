extends Node


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.settings["developer_mode"] = false
	Localization.set_language("ja", false)
	call_deferred("_run")


func _run() -> void:
	assert(not AccountSession.is_supported(), "Native play must not require browser authentication")
	assert(not AccountSession.open_account("ja"))
	AccountSession.refresh()
	var hub: Control = load("res://scenes/hub/Hub.tscn").instantiate() as Control
	add_child(hub)
	await get_tree().process_frame
	var button: Button = hub.find_child("HubAccountButton", true, false) as Button
	assert(button != null and button.disabled and button.icon != null)
	assert(button.text == Localization.get_text("account.open", "Sign in / Register"))
	assert(button.tooltip_text != "")
	AccountSession.snapshot = {"authenticated": true, "needsUsername": false, "user": {"username": "Untrusted_User"}}
	AccountSession.changed.emit()
	assert(button.text == Localization.get_text("account.signed_in", "Account: signed in"))
	assert(not button.text.contains("Untrusted_User"), "Unsubsetted user glyphs should remain in the browser account page")
	AccountSession.snapshot = {"authenticated": true, "needsUsername": true}
	AccountSession.changed.emit()
	assert(button.text == Localization.get_text("account.register_name", "Set username"))
	AccountSession.snapshot = {"available": false, "authenticated": false, "needsUsername": false}
	AccountSession.changed.emit()
	hub.queue_free()
	print("ACCOUNT_UI_SMOKE_OK")
	get_tree().quit()
