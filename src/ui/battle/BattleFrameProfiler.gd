extends Node
class_name BattleFrameProfiler

signal capture_finished(report: Dictionary)

var last_report: Dictionary = {}
var _frames_ms: Array[float] = []
var _ui_ms: Array[float] = []
var _ends_at: int = 0
var _started_at: int = 0
var _ui_this_frame: float = -1.0
var _last_frame_at_us: int = 0


func _ready() -> void:
	process_priority = 1000
	set_process(false)


func start_capture(seconds: float = 5.0) -> void:
	_frames_ms.clear()
	_ui_ms.clear()
	_ui_this_frame = -1.0
	_started_at = Time.get_ticks_msec()
	_last_frame_at_us = Time.get_ticks_usec()
	_ends_at = _started_at + roundi(clampf(seconds, 0.1, 10.0) * 1000.0)
	set_process(true)


func record_ui_time(milliseconds: float) -> void:
	_ui_this_frame = milliseconds


func _process(_delta: float) -> void:
	var now_us: int = Time.get_ticks_usec()
	# Bounded, opt-in capture only. No frame history is collected during normal play.
	if _frames_ms.size() < 2400:
		_frames_ms.append((now_us - _last_frame_at_us) / 1000.0)
		if _ui_this_frame >= 0.0:
			_ui_ms.append(_ui_this_frame)
	_ui_this_frame = -1.0
	_last_frame_at_us = now_us
	if Time.get_ticks_msec() < _ends_at:
		return
	set_process(false)
	last_report = {"seconds": (Time.get_ticks_msec() - _started_at) / 1000.0,
		"frame": summarize(_frames_ms), "ui": summarize(_ui_ms)}
	capture_finished.emit(last_report.duplicate(true))


static func summarize(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"count": 0, "mean_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0, "over_33ms": 0}
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var total: float = 0.0
	var slow_frames: int = 0
	for sample: float in samples:
		total += sample
		if sample > 1000.0 / 30.0:
			slow_frames += 1
	return {"count": samples.size(), "mean_ms": total / samples.size(),
		"p95_ms": sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.95) - 1)],
		"max_ms": sorted[-1], "over_33ms": slow_frames}
