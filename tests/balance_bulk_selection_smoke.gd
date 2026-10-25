extends Node

var _checks: int = 0
var _lab: Control


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.settings["developer_mode"] = true
	Game.set_language("ja")
	Game.start_new_run("balanced", 4242)
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Bulk selection: " + message)
		get_tree().quit(1)
		assert(value, message)


func _node(id: String) -> Node:
	return _lab.find_child(id, true, false)


func _field(path: String) -> void:
	var option: OptionButton = _node("BalanceBulkField") as OptionButton
	for index: int in option.item_count:
		if option.get_item_metadata(index) == path:
			option.select(index); option.item_selected.emit(index)
			return
	_check(false, "missing field: " + path)


func _run() -> void:
	_lab = load("res://scenes/debug/BalanceLab.tscn").instantiate() as Control
	add_child(_lab)
	for frame: int in 180:
		if _lab.call("is_content_ready"): break
		await get_tree().process_frame
	var draft: BalanceDraft = _lab.get("draft") as BalanceDraft
	draft.reset()
	draft.set_value("card", "guard", "effects.0.amount", 9)
	var search: LineEdit = _node("BalanceSearch") as LineEdit
	search.text = "guard"; _lab.call("_filter_catalog")
	_lab.call("_select", "card", "guard")
	var original: String = JSON.stringify(draft.document())
	_lab.call("_open_bulk")
	_field("recast_time")
	(_node("BalanceBulkAmount") as SpinBox).value = 0.5
	var guard: CheckBox = _node("BalanceBulkTarget_guard") as CheckBox
	var quick: CheckBox = _node("BalanceBulkTarget_quick_guard") as CheckBox
	_check(guard != null and quick != null and guard.icon != null, "target icon checkboxes missing")
	guard.button_pressed = false
	_check(quick.button_pressed, "excluding one card excluded another")
	_check(JSON.stringify(draft.document()) == original, "preview changed the draft")
	var count: Label = _node("BalanceBulkTargetCount") as Label
	var selected: int = int(count.get_meta("selected_count"))
	var target_search: LineEdit = _node("BalanceBulkSearch") as LineEdit
	target_search.text = "quick_guard"; target_search.text_changed.emit(target_search.text)
	_check(not guard.visible and quick.visible and int(count.get_meta("selected_count")) == selected, "list search changed target selection")
	target_search.text = ""; target_search.text_changed.emit("")
	_check(guard.visible and quick.visible and int(count.get_meta("selected_count")) == selected, "clearing search did not restore the target list")
	(_node("BalanceBulkExcludeAll") as Button).pressed.emit()
	_check((_node("BalanceBulkApply") as Button).disabled and int(count.get_meta("selected_count")) == 0, "empty selection must be a no-op")
	quick.button_pressed = true
	_check(not (_node("BalanceBulkApply") as Button).disabled, "selected target did not enable apply")
	(_node("BalanceBulkApply") as Button).pressed.emit()
	await get_tree().process_frame
	_check(draft.card("guard").recast_time == 12 and draft.card("guard").effects[0]["amount"] == 9, "excluded card or its existing edits changed")
	_check(draft.card("quick_guard").recast_time == 8, "included card did not change")
	_lab.call("_open_bulk")
	guard = _node("BalanceBulkTarget_guard") as CheckBox
	_check(not guard.button_pressed and (_node("BalanceBulkTarget_quick_guard") as CheckBox).button_pressed, "exclusions lost on reopen")
	var before_cancel: String = JSON.stringify(draft.document())
	(_node("BalanceBulkIncludeAll") as Button).pressed.emit()
	(_node("BalanceBulkCancel") as Button).pressed.emit()
	await get_tree().process_frame
	_check(JSON.stringify(draft.document()) == before_cancel, "cancel applied preview")
	(_node("BalanceGradeTabs") as TabBar).current_tab = 3
	_lab.call("_open_bulk")
	_field("grade_overrides.3.recast_time")
	(_node("BalanceBulkAmount") as SpinBox).value = 0.5
	(_node("BalanceBulkTarget_quick_guard") as CheckBox).button_pressed = false
	(_node("BalanceBulkApply") as Button).pressed.emit()
	await get_tree().process_frame
	_check(draft.card("guard", 3).recast_time == 4.5 and draft.card("guard", 2).recast_time == 10, "grade-specific bulk edit leaked across grades")
	_check(draft.card("quick_guard", 3).recast_time == 13, "grade-specific exclusion was ignored")
	search.text = ""; _lab.call("_switch_kind", "relic")
	_lab.call("_select", "relic", "reactive_barrier")
	_lab.call("_open_bulk")
	_field("parameters.starting_shield")
	_check((_node("BalanceBulkTarget_tempered_edge") as CheckBox).disabled, "incompatible target must be disabled")
	_check((_node("BalanceBulkTarget_reactive_barrier") as CheckBox).button_pressed, "card exclusions leaked into relic selection")
	(_node("BalanceBulkCancel") as Button).pressed.emit()
	await get_tree().process_frame
	_lab.call("_open_bulk")
	draft.set_value("card", "quick_slash", "effects.0.amount", 6)
	var changed_elsewhere: String = JSON.stringify(draft.document())
	(_node("BalanceBulkApply") as Button).pressed.emit()
	_check(JSON.stringify(draft.document()) == changed_elsewhere and (_node("BalanceBulkPreview") as TextEdit).text.contains("中止"), "stale preview overwrote a newer draft")
	(_node("BalanceBulkCancel") as Button).pressed.emit()
	await get_tree().process_frame
	var restored: BalanceDraft = BalanceDraft.new()
	_check(restored.import_document(draft.document()) and not JSON.stringify(draft.document()).contains("excluded"), "selection preferences leaked into numeric exports")
	_check(Database.get_card("guard").effects[0]["amount"] == 8 and Database.get_card("quick_guard").recast_time == 16, "bulk draft changed published definitions")
	_lab.queue_free(); await get_tree().process_frame
	print("BALANCE_BULK_SELECTION_SMOKE_OK checks=%d exclusion/search/empty/apply/cancel/reopen/grade/relic/export" % _checks)
	get_tree().quit()
