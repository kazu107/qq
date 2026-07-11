extends SceneTree

const CARD_DATA_PATH: String = "res://data/cards.json"
const DEFAULT_OUTPUT_DIR: String = "res://assets/icons/cards"
const TARGET_SIZE: int = 512
const CONTACT_COLUMNS: int = 10
const CONTACT_CELL_SIZE: int = 128
const CONTACT_INSET: int = 8


func _initialize() -> void:
	var manifest_path: String = ""
	var output_dir: String = ProjectSettings.globalize_path(DEFAULT_OUTPUT_DIR)
	var contact_sheet_path: String = ""
	var allow_partial: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):
			manifest_path = argument.substr("--manifest=".length())
		elif argument.begins_with("--output-dir="):
			output_dir = argument.substr("--output-dir=".length())
		elif argument.begins_with("--contact-sheet="):
			contact_sheet_path = argument.substr("--contact-sheet=".length())
		elif argument == "--allow-partial":
			allow_partial = true

	if manifest_path.is_empty():
		_fail("Missing required --manifest=<path> argument")
		return

	var manifest: Dictionary = _load_manifest(manifest_path)
	var card_ids: Array[String] = _load_card_ids()
	if manifest.is_empty() or card_ids.is_empty():
		quit(1)
		return

	var import_ids: Array[String] = []
	if allow_partial:
		for manifest_id_value: Variant in manifest.keys():
			var manifest_id: String = String(manifest_id_value)
			if not card_ids.has(manifest_id):
				_fail("Generated art manifest contains an unknown card: %s" % manifest_id)
				return
		for card_id: String in card_ids:
			if manifest.has(card_id):
				import_ids.append(card_id)
	elif manifest.size() != card_ids.size():
		_fail("Generated art manifest has %d entries, but cards.json has %d cards" % [
			manifest.size(),
			card_ids.size(),
		])
		return
	else:
		for card_id: String in card_ids:
			import_ids.append(card_id)

	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_error != OK:
		_fail("Could not create card art output directory: %s" % output_dir)
		return

	var processed_images: Array[Image] = []
	for card_id: String in import_ids:
		var source_path: String = String(manifest.get(card_id, ""))
		if source_path.is_empty() or not FileAccess.file_exists(source_path):
			_fail("Missing generated source image for card: %s" % card_id)
			return

		var image: Image = Image.new()
		var load_error: Error = image.load(source_path)
		if load_error != OK or image.is_empty():
			_fail("Could not load generated source for %s: %s" % [card_id, source_path])
			return
		if image.get_width() != image.get_height():
			_fail("Generated source is not square for %s: %dx%d" % [
				card_id,
				image.get_width(),
				image.get_height(),
			])
			return

		image.convert(Image.FORMAT_RGBA8)
		if image.get_width() != TARGET_SIZE:
			image.resize(TARGET_SIZE, TARGET_SIZE, Image.INTERPOLATE_LANCZOS)

		var target_path: String = output_dir.path_join("%s.png" % card_id)
		var save_error: Error = image.save_png(target_path)
		if save_error != OK:
			_fail("Could not save generated card art: %s" % target_path)
			return
		processed_images.append(image)

	if not contact_sheet_path.is_empty():
		var contact_error: Error = _save_contact_sheet(processed_images, contact_sheet_path)
		if contact_error != OK:
			_fail("Could not save card art contact sheet: %s" % contact_sheet_path)
			return

	print("Imported %d generated card images at %dx%d." % [
		processed_images.size(),
		TARGET_SIZE,
		TARGET_SIZE,
	])
	quit()


func _load_manifest(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open generated art manifest: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Generated art manifest must be a JSON object")
		return {}
	return parsed as Dictionary


func _load_card_ids() -> Array[String]:
	var file: FileAccess = FileAccess.open(CARD_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open card data: %s" % CARD_DATA_PATH)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_error("Card data must be a JSON array")
		return []

	var card_ids: Array[String] = []
	for entry_value: Variant in parsed as Array:
		if not entry_value is Dictionary:
			push_error("Card data contains a non-object entry")
			return []
		var entry: Dictionary = entry_value as Dictionary
		var card_id: String = String(entry.get("id", ""))
		if card_id.is_empty() or card_ids.has(card_id):
			push_error("Card data contains an empty or duplicate id: %s" % card_id)
			return []
		card_ids.append(card_id)
	return card_ids


func _save_contact_sheet(images: Array[Image], path: String) -> Error:
	var row_count: int = ceili(float(images.size()) / float(CONTACT_COLUMNS))
	var sheet: Image = Image.create_empty(
		CONTACT_COLUMNS * CONTACT_CELL_SIZE,
		row_count * CONTACT_CELL_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	sheet.fill(Color("101820"))
	var thumbnail_size: int = CONTACT_CELL_SIZE - CONTACT_INSET * 2
	for index: int in images.size():
		var thumbnail: Image = Image.new()
		thumbnail.copy_from(images[index])
		thumbnail.resize(thumbnail_size, thumbnail_size, Image.INTERPOLATE_LANCZOS)
		var column: int = index % CONTACT_COLUMNS
		var row: int = index / CONTACT_COLUMNS
		var destination: Vector2i = Vector2i(
			column * CONTACT_CELL_SIZE + CONTACT_INSET,
			row * CONTACT_CELL_SIZE + CONTACT_INSET
		)
		sheet.blit_rect(thumbnail, Rect2i(Vector2i.ZERO, thumbnail.get_size()), destination)
	return sheet.save_png(path)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
