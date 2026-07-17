extends RefCounted
class_name NetworkBattleClock

const SNAPSHOT_INTERVAL_SECONDS: float = 1.0 / 12.0
const MIN_RENDER_LEAD_SECONDS: float = 0.10
const MAX_RENDER_LEAD_SECONDS: float = 0.35
const MIN_PREDICTION_LIMIT_SECONDS: float = 0.30
const MAX_PREDICTION_LIMIT_SECONDS: float = 0.80
const HARD_RESYNC_GAP_SECONDS: float = 1.25
const CORRECTION_GAIN: float = 2.5
const MIN_PLAYBACK_RATE: float = 0.85
const MAX_PLAYBACK_RATE: float = 1.20

var _authoritative_time: float = 0.0
var _display_time: float = 0.0
var _initialized: bool = false
var _running: bool = false


func reset() -> void:
	_authoritative_time = 0.0
	_display_time = 0.0
	_initialized = false
	_running = false


func apply_snapshot(authoritative_time: float, battle_started: bool, battle_finished: bool = false) -> float:
	var resolved_time: float = maxf(0.0, authoritative_time)
	var started_now: bool = battle_started and not _running
	if not _initialized:
		_authoritative_time = resolved_time
		_display_time = resolved_time
		_initialized = true
	elif _running:
		_authoritative_time = maxf(_authoritative_time, resolved_time)
	else:
		_authoritative_time = resolved_time

	if started_now or not battle_started or battle_finished:
		_display_time = resolved_time
	elif _authoritative_time - _display_time > HARD_RESYNC_GAP_SECONDS:
		_display_time = _authoritative_time

	_running = battle_started and not battle_finished
	return _display_time


func advance(delta: float, ping_ms: int) -> float:
	if not _initialized or not _running or delta <= 0.0:
		return _display_time

	var clamped_ping_ms: int = clampi(ping_ms, 0, 1000)
	var render_lead: float = clampf(
		SNAPSHOT_INTERVAL_SECONDS * 1.5 + float(clamped_ping_ms) / 2000.0,
		MIN_RENDER_LEAD_SECONDS,
		MAX_RENDER_LEAD_SECONDS
	)
	var prediction_limit: float = clampf(
		MIN_PREDICTION_LIMIT_SECONDS + float(clamped_ping_ms) / 1000.0,
		MIN_PREDICTION_LIMIT_SECONDS,
		MAX_PREDICTION_LIMIT_SECONDS
	)
	var target_time: float = _authoritative_time + render_lead
	var correction_error: float = target_time - _display_time
	var playback_rate: float = clampf(
		1.0 + correction_error * CORRECTION_GAIN,
		MIN_PLAYBACK_RATE,
		MAX_PLAYBACK_RATE
	)
	var predicted_time: float = minf(
		_display_time + delta * playback_rate,
		_authoritative_time + prediction_limit
	)
	_display_time = maxf(_display_time, predicted_time)
	return _display_time


func get_display_time() -> float:
	return _display_time


func get_authoritative_time() -> float:
	return _authoritative_time
