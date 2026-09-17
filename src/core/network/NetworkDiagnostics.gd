extends RefCounted
class_name NetworkDiagnostics

const WINDOW_MS: int = 5000
const MAX_SAMPLES: int = 2048
var samples: Array[Dictionary] = []
var last_received_ms: int = -1
var accepted: int = 0
var stale: int = 0
var gaps: int = 0
var _sequences: Dictionary = {}


func sent(payload: Dictionary, recipients: int = 1) -> void:
	if recipients <= 0:
		return
	_add("tx", var_to_bytes(payload).size() * recipients, recipients)


func received(payload: Dictionary, was_accepted: bool) -> void:
	_add("rx", var_to_bytes(payload).size(), 1)
	if not was_accepted:
		stale += 1
		return
	accepted += 1
	last_received_ms = Time.get_ticks_msec()
	var match_id: String = String(payload.get("match_id", ""))
	var sequence: int = int(payload.get("sequence", 0))
	if _sequences.has(match_id):
		gaps += maxi(0, sequence - int(_sequences[match_id]) - 1)
	_sequences[match_id] = sequence
	if _sequences.size() > 32:
		_sequences.erase(_sequences.keys()[0])


func _add(direction: String, bytes_count: int, count: int) -> void:
	samples.append({"at": Time.get_ticks_msec(), "direction": direction, "bytes": bytes_count, "count": count})
	_prune()


func _prune() -> void:
	var cutoff: int = Time.get_ticks_msec() - WINDOW_MS
	while not samples.is_empty() and (int(samples[0]["at"]) < cutoff or samples.size() > MAX_SAMPLES):
		samples.pop_front()


func snapshot() -> Dictionary:
	_prune()
	var result: Dictionary = {"tx_bytes_s": 0.0, "rx_bytes_s": 0.0, "tx_hz": 0.0, "rx_hz": 0.0,
		"accepted": accepted, "stale": stale, "gaps": gaps, "age_ms": -1 if last_received_ms < 0 else Time.get_ticks_msec() - last_received_ms}
	for sample in samples:
		var direction: String = String(sample["direction"])
		result[direction + "_bytes_s"] += float(sample["bytes"]) / 5.0
		result[direction + "_hz"] += float(sample["count"]) / 5.0
	return result
