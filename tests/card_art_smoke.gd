extends Node

const CARD_ART_DIR: String = "res://assets/icons/cards"
const EXPECTED_SIZE: int = 512


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	var card_ids: Array[String] = Database.get_all_card_ids()
	if card_ids.is_empty():
		_fail("Card art smoke failed: no card definitions were loaded")
		return
	if _count_png_files() != card_ids.size():
		_fail("Card art smoke failed: PNG count does not match card definition count")
		return

	var hashes: Dictionary = {}
	for card_id: String in card_ids:
		var path: String = "%s/%s.png" % [CARD_ART_DIR, card_id]
		if not FileAccess.file_exists(path):
			_fail("Card art smoke failed: missing image for %s" % card_id)
			return

		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var image: Image = Image.new()
		var image_error: Error = image.load_png_from_buffer(bytes)
		if image_error != OK or image.is_empty():
			_fail("Card art smoke failed: image could not be decoded for %s" % card_id)
			return
		if image.get_width() != EXPECTED_SIZE or image.get_height() != EXPECTED_SIZE:
			_fail("Card art smoke failed: %s is %dx%d instead of %dx%d" % [
				card_id,
				image.get_width(),
				image.get_height(),
				EXPECTED_SIZE,
				EXPECTED_SIZE,
			])
			return

		var hash_context: HashingContext = HashingContext.new()
		var hash_error: Error = hash_context.start(HashingContext.HASH_SHA256)
		if hash_error != OK:
			_fail("Card art smoke failed: could not initialize SHA-256")
			return
		hash_context.update(bytes)
		var digest: String = hash_context.finish().hex_encode()
		if digest.is_empty():
			_fail("Card art smoke failed: could not hash %s" % card_id)
			return
		if hashes.has(digest):
			_fail("Card art smoke failed: %s duplicates %s exactly" % [
				card_id,
				String(hashes[digest]),
			])
			return
		hashes[digest] = card_id

		var texture: Texture2D = ResourceLoader.load(path) as Texture2D
		if texture == null or texture.get_width() != EXPECTED_SIZE or texture.get_height() != EXPECTED_SIZE:
			_fail("Card art smoke failed: Godot texture import failed for %s" % card_id)
			return

	print("Card art smoke passed: %d unique generated images." % card_ids.size())
	get_tree().quit()


func _count_png_files() -> int:
	var directory: DirAccess = DirAccess.open(CARD_ART_DIR)
	if directory == null:
		return 0
	var count: int = 0
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".png"):
			count += 1
		file_name = directory.get_next()
	directory.list_dir_end()
	return count


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
