extends Node


func _ready() -> void:
	var canonical: Array[String] = [str(LanProtocol.PROTOCOL_VERSION), "relic-resolver:%d" % LanProtocol.RELIC_RESOLVER_VERSION]
	for path: String in LanProtocol.CONTENT_PATHS:
		if path.ends_with(".json"):
			var lf: String = FileAccess.get_file_as_string(path).replace("\r\n", "\n").replace("\r", "\n")
			var expected: String = lf.sha256_text()
			for variant: String in [lf, lf.replace("\n", "\r\n"), lf.replace("\n", "\r")]:
				if LanProtocol.hash_content_text(variant) != expected:
					_fail("Line endings changed content hash: " + path)
					return
			canonical.append(expected)
		else:
			var source_hash: String = FileAccess.get_sha256(path)
			if LanProtocol.get_authored_content_hash(path) != source_hash:
				_fail("Export manifest did not preserve the original model hash: " + path)
				return
			canonical.append(source_hash)
	LanProtocol.clear_content_hash_cache()
	var expected_hash: String = "\n".join(canonical).sha256_text()
	if LanProtocol.build_content_hash() != expected_hash or LanProtocol.build_content_hash() != expected_hash:
		_fail("Combined content hash or cache changed its canonical value")
		return
	if LanProtocol.hash_content_text("{\"damage\":1}") == LanProtocol.hash_content_text("{\"damage\":2}"):
		_fail("Gameplay changes were not detected")
		return
	print("CONTENT_HASH_SMOKE_OK LF/CRLF/CR, binary assets, cache, gameplay changes; ", expected_hash.left(12))
	get_tree().quit()


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
