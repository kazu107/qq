extends Node

const PROVENANCE_PATH: String = "res://data/art_provenance.json"
const EXPECTED_ASSETS: Dictionary = {
	"balanced": {"path": "res://assets/models/battle/balanced.glb", "size": 0},
	"scout": {"path": "res://assets/models/battle/scout.glb", "size": 0},
	"quick_slash": {"path": "res://assets/icons/cards/quick_slash.png", "size": 512},
	"guard": {"path": "res://assets/icons/cards/guard.png", "size": 512},
	"delay_step": {"path": "res://assets/icons/cards/delay_step.png", "size": 512},
	"repair_burst": {"path": "res://assets/icons/cards/repair_burst.png", "size": 512},
	"auto_turret": {"path": "res://assets/icons/cards/auto_turret.png", "size": 512},
	"event_horizon": {"path": "res://assets/icons/cards/event_horizon.png", "size": 512},
	"iron_plating": {"path": "res://assets/icons/relics/iron_plating.png", "size": 512},
	"auxiliary_core": {"path": "res://assets/icons/relics/auxiliary_core.png", "size": 512},
	"chrono_shard": {"path": "res://assets/icons/relics/chrono_shard.png", "size": 512},
	"salvage_magnet": {"path": "res://assets/icons/relics/salvage_magnet.png", "size": 512},
	"bleed": {"path": "res://assets/icons/status/bleed.png", "size": 96},
	"attack": {"path": "res://assets/icons/ui/attack.png", "size": 64},
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var provenance_file: FileAccess = FileAccess.open(PROVENANCE_PATH, FileAccess.READ)
	if provenance_file == null:
		_fail("Art provenance smoke failed: provenance file is missing")
		return
	var parsed: Variant = JSON.parse_string(provenance_file.get_as_text())
	if not parsed is Dictionary:
		_fail("Art provenance smoke failed: provenance root is not an object")
		return
	var provenance: Dictionary = parsed as Dictionary
	var assets_value: Variant = provenance.get("assets", [])
	if not assets_value is Array:
		_fail("Art provenance smoke failed: assets is not an array")
		return
	var assets: Array = assets_value as Array
	if assets.size() != EXPECTED_ASSETS.size():
		_fail("Art provenance smoke failed: expected %d entries, found %d" % [EXPECTED_ASSETS.size(), assets.size()])
		return

	var seen_ids: Dictionary = {}
	var seen_hashes: Dictionary = {}
	for asset_value: Variant in assets:
		if not asset_value is Dictionary:
			_fail("Art provenance smoke failed: asset entry is not an object")
			return
		var asset: Dictionary = asset_value as Dictionary
		var asset_id: String = String(asset.get("asset_id", ""))
		if not EXPECTED_ASSETS.has(asset_id) or seen_ids.has(asset_id):
			_fail("Art provenance smoke failed: unknown or duplicate asset id %s" % asset_id)
			return
		seen_ids[asset_id] = true

		var expected: Dictionary = EXPECTED_ASSETS[asset_id] as Dictionary
		var runtime_path: String = "res://%s" % String(asset.get("runtime_path", ""))
		if runtime_path != String(expected.get("path", "")) or not FileAccess.file_exists(runtime_path):
			_fail("Art provenance smoke failed: invalid runtime path for %s" % asset_id)
			return
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(runtime_path)
		var expected_hash: String = String(asset.get("export_sha256", ""))
		if bytes.is_empty() or _sha256(bytes) != expected_hash:
			_fail("Art provenance smoke failed: output hash mismatch for %s" % asset_id)
			return
		if seen_hashes.has(expected_hash):
			_fail("Art provenance smoke failed: %s duplicates %s" % [asset_id, String(seen_hashes[expected_hash])])
			return
		seen_hashes[expected_hash] = asset_id

		var expected_size: int = int(expected.get("size", 0))
		if expected_size > 0:
			var image: Image = Image.new()
			var load_error: Error = image.load_png_from_buffer(bytes)
			if load_error != OK or image.get_width() != expected_size or image.get_height() != expected_size:
				_fail("Art provenance smoke failed: invalid image size for %s" % asset_id)
				return

		var source_path: String = "res://%s" % String(asset.get("source_path", ""))
		if not FileAccess.file_exists(source_path):
			_fail("Art provenance smoke failed: Blender source is missing for %s" % asset_id)
			return

	if seen_ids.size() != EXPECTED_ASSETS.size():
		_fail("Art provenance smoke failed: one or more expected IDs were not recorded")
		return
	print("ART_PROVENANCE_SMOKE_OK %d Blender-authored assets verified" % seen_ids.size())
	get_tree().quit()


func _sha256(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
