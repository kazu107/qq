extends RefCounted
class_name SlowModeController

const NORMAL_SCALE: float = 1.0
const SLOW_SCALE: float = 0.3


static func get_time_scale(is_slow_active: bool) -> float:
	if is_slow_active:
		return SLOW_SCALE
	return NORMAL_SCALE
