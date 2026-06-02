extends RefCounted
class_name CardRuntimeState

const READY_DISPLAY_THRESHOLD := 0.05

enum CardState {
	READY,
	PREPARING,
	RESOLVING,
	COOLDOWN,
	DISABLED,
	INTERRUPTED,
}

var runtime_id: String = ""
var card_id: String = ""
var loadout_index: int = 0
var state: CardState = CardState.READY
var cooldown_remaining: float = 0.0


func can_use() -> bool:
	return state == CardState.READY


func begin_prepare() -> void:
	state = CardState.PREPARING


func begin_resolve() -> void:
	state = CardState.RESOLVING


func begin_cooldown(duration: float) -> void:
	state = CardState.COOLDOWN
	set_cooldown_remaining(duration)


func tick(delta: float) -> void:
	if state != CardState.COOLDOWN:
		return
	set_cooldown_remaining(cooldown_remaining - delta)


func set_cooldown_remaining(value: float) -> void:
	cooldown_remaining = max(0.0, value)
	if cooldown_remaining <= READY_DISPLAY_THRESHOLD:
		cooldown_remaining = 0.0
		state = CardState.READY
	elif state == CardState.COOLDOWN:
		state = CardState.COOLDOWN


func get_display_cooldown_remaining() -> float:
	if cooldown_remaining <= 0.0:
		return 0.0
	return ceilf(cooldown_remaining * 10.0) / 10.0


func get_state_name() -> String:
	match state:
		CardState.READY:
			return "READY"
		CardState.PREPARING:
			return "PREPARING"
		CardState.RESOLVING:
			return "RESOLVING"
		CardState.COOLDOWN:
			return "COOLDOWN"
		CardState.DISABLED:
			return "DISABLED"
		CardState.INTERRUPTED:
			return "INTERRUPTED"
	return "UNKNOWN"
