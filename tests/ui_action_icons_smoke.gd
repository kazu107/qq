extends Node


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("UI action icons: " + message)
		get_tree().quit(1)
		assert(condition, message)


func _run() -> void:
	_check(UiIconHelper.get_ids().size() == 36, "Missing action definitions")
	for id: String in UiIconHelper.get_ids():
		var texture: Texture2D = StatIconFactory.get_icon(id)
		_check(texture != null and texture.get_size() == Vector2(64, 64), "Invalid texture: " + id)
		_check(texture.resource_path == "res://assets/icons/ui/%s.png" % id, "Generated fallback used: " + id)
		_check(texture == StatIconFactory.get_icon(id), "Icon was decoded twice: " + id)
	var button: Button = Button.new()
	button.name = "TestRerollButton"
	button.text = "Reroll"
	add_child(button)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(String(button.get_meta("semantic_icon", "")) == "reroll", "Button did not receive global semantic styling")
	UiIconHelper.decorate(button, "sell", "Sell for 10 gold", true, "10")
	_check(button.text == "10" and button.tooltip_text.contains("10"), "Compact sale lost price/meaning")
	var custom: Button = Button.new()
	custom.name = "FacilityChoiceUpgrade"
	custom.text = ""
	add_child(custom)
	await get_tree().process_frame
	_check(custom.icon == null, "Custom-content option received an overlapping center icon")
	for entry: Array in [["ClaimAchievement_comeback_spirit", "claim"], ["ClaimAchievement_reward_reroller", "claim"], ["UnlockRelic_loadout_harness", "unlock"], ["UnlockCard_grit_reload", "unlock"], ["WebMultiplayerButton", "online"]]:
		var action: Button = Button.new()
		action.name = String(entry[0])
		action.text = "Action"
		UiIconHelper.decorate_default(action)
		_check(String(action.get_meta("semantic_icon", "")) == String(entry[1]), "Data ID overrode action meaning: " + String(entry[0]))
		action.free()
	var stage: BattleStage3D = BattleStage3D.new()
	stage.custom_minimum_size = Vector2(1280, 720)
	add_child(stage)
	await get_tree().process_frame
	var transparent: HBoxContainer = HBoxContainer.new()
	add_child(transparent)
	_check(stage._allows_status_hover(transparent), "Transparent layout blocked status hover")
	var modal: PanelContainer = PanelContainer.new()
	add_child(modal)
	var modal_content: VBoxContainer = VBoxContainer.new()
	modal.add_child(modal_content)
	_check(not stage._allows_status_hover(modal_content) and not stage._allows_status_hover(button), "Status hover leaked through a modal/action")
	var unit: UnitState = UnitState.new()
	unit.display_name = "Player"
	unit.hp = 60
	unit.max_hp = 60
	for id: String in ["bleed", "weak", "slow", "vulnerable"]:
		unit.add_status(id, 12.5)
	stage.refresh_unit_status(unit, unit)
	var plate: BattleUnitStatus3D = stage.get_player_status_model()
	_check(plate.get_status_regions().size() == 4, "3D plate truncated statuses")
	_check(not (plate.find_child("StatusValue3D", true, false) as Label3D).visible, "Status names remained on the plate")
	for id: String in ["bleed", "weak", "slow", "vulnerable"]:
		var icon: Sprite3D = plate.find_child("StatusIcon3D_" + id, true, false) as Sprite3D
		var value: Label3D = plate.find_child("StatusTime3D_" + id, true, false) as Label3D
		_check(icon != null and icon.visible and icon.texture != null, "Missing status image: " + id)
		_check(icon.billboard == BaseMaterial3D.BILLBOARD_DISABLED and value.billboard == BaseMaterial3D.BILLBOARD_DISABLED, "Status UI lost plate yaw")
		_check(value.text == "12.5s" and icon.modulate == Color.WHITE, "Status time or brightness incorrect")
	var region: Dictionary = plate.get_status_regions()[0]
	var center: Vector3 = Vector3.ZERO
	for point: Vector3 in region["corners"]:
		center += point * 0.25
	var hover: Dictionary = stage.get_status_hover_info(stage.project_world_position(center))
	_check(not hover.is_empty() and String(hover["text"]).contains("12.5"), "Projected status hover failed")
	unit.tick_statuses(0.5)
	stage.refresh_unit_status(unit, unit)
	hover = stage.get_status_hover_info(stage.project_world_position(center))
	_check(String(hover.get("text", "")).contains("12.0"), "World tooltip did not update live")
	unit.statuses.clear()
	stage.refresh_unit_status(unit, unit)
	_check(plate.get_status_regions().is_empty() and stage.get_status_hover_info(stage.project_world_position(center)).is_empty(), "Expired status retained its hover region")
	stage.queue_free()
	print("UI_ACTION_ICONS_SMOKE_OK 36 authored/cached icons, compact actions, 4 yaw-aligned statuses, live hover and expiry")
	get_tree().quit()
