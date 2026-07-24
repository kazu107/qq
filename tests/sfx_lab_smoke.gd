extends Node

const SFX_LAB_SCENE: PackedScene = preload("res://scenes/debug/SfxLab.tscn")

var _previous_developer_mode: bool = false


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	_previous_developer_mode = Game.is_developer_mode_enabled()
	Game.settings["developer_mode"] = true
	call_deferred("_run")


func _run() -> void:
	var lab: Control = SFX_LAB_SCENE.instantiate() as Control
	if lab == null:
		_fail("SFX lab smoke failed: scene could not be instantiated")
		return
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame

	var catalog: Array[Dictionary] = AudioManager.get_sfx_catalog()
	var grid: GridContainer = lab.find_child("SfxLabGrid", true, false) as GridContainer
	if grid == null:
		_fail("SFX lab smoke failed: grid was not created")
		return
	if grid.get_child_count() != catalog.size():
		_fail("SFX lab smoke failed: rendered %d tiles for %d catalog entries" % [grid.get_child_count(), catalog.size()])
		return

	var category_option: OptionButton = lab.find_child("SfxLabCategory", true, false) as OptionButton
	if category_option == null or category_option.item_count != 11:
		_fail("SFX lab smoke failed: category filter was incomplete")
		return

	for entry: Dictionary in catalog:
		var sfx_id: String = String(entry.get("sfx_id", ""))
		var play_button: Button = lab.find_child("Play_%s" % sfx_id, true, false) as Button
		if play_button == null:
			_fail("SFX lab smoke failed: play button was missing for %s" % sfx_id)
			return
		if play_button.disabled:
			_fail("SFX lab smoke failed: generated asset was unavailable for %s" % sfx_id)
			return

	var search_edit: LineEdit = lab.find_child("SfxLabSearch", true, false) as LineEdit
	if search_edit == null:
		_fail("SFX lab smoke failed: search field was missing")
		return
	search_edit.text = "card_quick_slash"
	search_edit.text_changed.emit(search_edit.text)
	await get_tree().process_frame
	var visible_tiles: int = 0
	for child: Node in grid.get_children():
		var tile: Control = child as Control
		if tile != null and tile.visible:
			visible_tiles += 1
	if visible_tiles != 1:
		_fail("SFX lab smoke failed: exact ID search showed %d tiles" % visible_tiles)
		return

	AudioManager.clear_play_history()
	var target_button: Button = lab.find_child("Play_card_quick_slash", true, false) as Button
	target_button.pressed.emit()
	if AudioManager.get_last_sfx_id() != "card_quick_slash":
		_fail("SFX lab smoke failed: play button did not route to AudioManager")
		return

	var panel: DeveloperPanel = DeveloperPanel.new()
	add_child(panel)
	panel.configure("Developer", [], "")
	if panel.find_child("DevSfxLab", true, false) == null:
		_fail("SFX lab smoke failed: developer panel did not expose the lab")
		return

	Game.settings["developer_mode"] = _previous_developer_mode
	print("SFX lab smoke passed: %d sounds" % catalog.size())
	get_tree().quit()


func _fail(message: String) -> void:
	Game.settings["developer_mode"] = _previous_developer_mode
	push_error(message)
	get_tree().quit(1)
