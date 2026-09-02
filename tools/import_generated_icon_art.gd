extends SceneTree

const ALLOWED_TARGET_PREFIX: String = "res://assets/icons/"
const MIN_TARGET_SIZE: int = 24
const MAX_TARGET_SIZE: int = 2048
const CONTACT_COLUMNS: int = 4
const CONTACT_CELL_SIZE: int = 144
const CONTACT_INSET: int = 12


func _initialize() -> void:
	var manifest_path: String = ""
	var contact_sheet_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):
			manifest_path = argument.substr("--manifest=".length())
		elif argument.begins_with("--contact-sheet="):
			contact_sheet_path = argument.substr("--contact-sheet=".length())

	if manifest_path.is_empty():
		_fail("Missing required --manifest=<path> argument")
		return

	var manifest: Dictionary = _load_manifest(manifest_path)
	if manifest.is_empty():
		quit(1)
		return

	var asset_ids: Array[String] = []
	for asset_id_value: Variant in manifest.keys():
		asset_ids.append(String(asset_id_value))
	asset_ids.sort()

	var processed_images: Array[Image] = []
	for asset_id: String in asset_ids:
		var entry_value: Variant = manifest.get(asset_id, {})
		if not entry_value is Dictionary:
			_fail("Generated icon manifest entry must be an object: %s" % asset_id)
			return
		var entry: Dictionary = entry_value as Dictionary
		var source_path: String = String(entry.get("source", ""))
		var target_path: String = String(entry.get("target", ""))
		var target_size: int = int(entry.get("size", 0))
		if source_path.is_empty() or not FileAccess.file_exists(source_path):
			_fail("Missing generated source image for icon: %s" % asset_id)
			return
		if not target_path.begins_with(ALLOWED_TARGET_PREFIX) or not target_path.ends_with(".png"):
			_fail("Generated icon target is outside the icon directory: %s" % target_path)
			return
		if target_size < MIN_TARGET_SIZE or target_size > MAX_TARGET_SIZE:
			_fail("Generated icon target size is invalid for %s: %d" % [asset_id, target_size])
			return

		var image: Image = Image.new()
		var load_error: Error = image.load(source_path)
		if load_error != OK or image.is_empty():
			_fail("Could not load generated icon source for %s: %s" % [asset_id, source_path])
			return
		if image.get_width() != image.get_height():
			_fail("Generated icon source is not square for %s: %dx%d" % [
				asset_id,
				image.get_width(),
				image.get_height(),
			])
			return

		image.convert(Image.FORMAT_RGBA8)
		if image.get_width() != target_size:
			image.resize(target_size, target_size, Image.INTERPOLATE_LANCZOS)

		var absolute_target_path: String = ProjectSettings.globalize_path(target_path)
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_target_path.get_base_dir())
		if mkdir_error != OK:
			_fail("Could not create generated icon target directory: %s" % absolute_target_path.get_base_dir())
			return
		var save_error: Error = image.save_png(absolute_target_path)
		if save_error != OK:
			_fail("Could not save generated icon: %s" % target_path)
			return
		processed_images.append(image)

	if not contact_sheet_path.is_empty():
		var contact_error: Error = _save_contact_sheet(processed_images, contact_sheet_path)
		if contact_error != OK:
			_fail("Could not save generated icon contact sheet: %s" % contact_sheet_path)
			return

	print("Imported %d Blender-authored icons." % processed_images.size())
	quit()


func _load_manifest(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open generated icon manifest: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Generated icon manifest must be a JSON object")
		return {}
	return parsed as Dictionary


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
		sheet.blend_rect(thumbnail, Rect2i(Vector2i.ZERO, thumbnail.get_size()), destination)
	return sheet.save_png(path)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
