extends RefCounted
class_name HpBarAnimation

const DURATION_SECONDS: float = 0.2

var displayed_ratio: float = 1.0
var target_ratio: float = 1.0
var _initialized: bool = false
var _unit_id: String = ""
var _max_hp: int = 0
var _from_ratio: float = 1.0
var _elapsed: float = DURATION_SECONDS


func reset() -> void:
	_initialized = false


func set_value(unit_id: String, hp: int, max_hp: int) -> void:
	var resolved_max: int = maxi(1, max_hp)
	var ratio: float = clampf(float(hp) / float(resolved_max), 0.0, 1.0)
	if not _initialized or unit_id != _unit_id or resolved_max != _max_hp:
		_initialized = true
		_unit_id = unit_id
		_max_hp = resolved_max
		displayed_ratio = ratio
		target_ratio = ratio
		_from_ratio = ratio
		_elapsed = DURATION_SECONDS
	elif ratio != target_ratio:
		# Repeated snapshots must not restart the transition; new hits retarget from the visible fill.
		_from_ratio = displayed_ratio
		target_ratio = ratio
		_elapsed = 0.0


func advance(delta: float) -> void:
	if _elapsed >= DURATION_SECONDS:
		return
	_elapsed = minf(DURATION_SECONDS, _elapsed + maxf(0.0, delta))
	displayed_ratio = lerpf(_from_ratio, target_ratio, _elapsed / DURATION_SECONDS)
