extends RefCounted
class_name RegenerationRules

const TICK_INTERVAL: float = 3.0
const MAX_LAYERS: int = 3
const EPSILON: float = 0.0000001
const CARD_IDS: Array[String] = ["regen_patch", "regen_salve", "regen_barrier", "regen_emergency", "regen_bloodwrap", "regen_burst", "regen_spring", "regen_tank"]


static func normalize(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	var layers: Array[Dictionary] = []
	for raw: Variant in Array(value.get("layers", [])):
		if raw is not Dictionary or float(raw.get("duration", 0)) <= EPSILON: continue
		layers.append({"duration": float(raw["duration"]), "power": maxi(1, int(raw.get("power", 1))), "source_side": String(raw.get("source_side", "")), "card_id": String(raw.get("card_id", ""))})
	while layers.size() > MAX_LAYERS: layers.pop_front()
	result["tick_accumulator"] = clampf(float(value.get("tick_accumulator", 0)), 0, TICK_INTERVAL)
	result["suspended"] = maxf(0, float(value.get("suspended", 0)))
	return _summarize(result, layers)


static func add(value: Dictionary, duration: float, power: int, source_side: String, card_id: String) -> Dictionary:
	var result: Dictionary = normalize(value)
	if duration <= EPSILON: return result
	var layers: Array = result["layers"]
	if layers.is_empty(): result["tick_accumulator"] = 0; result["suspended"] = 0
	if layers.size() >= MAX_LAYERS:
		var shortest: int = 0
		for i: int in layers.size():
			if float(layers[i]["duration"]) < float(layers[shortest]["duration"]): shortest = i
		layers.remove_at(shortest)
	layers.append({"duration": duration, "power": maxi(1, power), "source_side": source_side, "card_id": card_id})
	return _summarize(result, layers)


static func adjust_duration(value: Dictionary, amount: float) -> Dictionary:
	var result: Dictionary = normalize(value)
	var layers: Array[Dictionary] = []
	for layer: Dictionary in result["layers"]:
		layer["duration"] = maxf(0, float(layer["duration"]) + amount)
		if float(layer["duration"]) > EPSILON: layers.append(layer)
	return _summarize(result, layers)


static func tick(value: Dictionary, delta: float) -> Dictionary:
	var result: Dictionary = normalize(value)
	var events: Array[Dictionary] = []
	var pending: float = maxf(0, delta)
	var paused: float = minf(pending, float(result["suspended"]))
	result["suspended"] = float(result["suspended"]) - paused; pending -= paused
	var layers: Array = result["layers"]
	var phase: float = float(result["tick_accumulator"])
	while pending > EPSILON and not layers.is_empty():
		var step: float = minf(pending, maxf(0, TICK_INTERVAL - phase))
		for layer: Dictionary in layers: step = minf(step, float(layer["duration"]))
		var sources: Array[Dictionary] = []
		var total: int = 0
		for layer: Dictionary in layers:
			total += int(layer["power"])
			sources.append({"side": layer["source_side"], "card_id": layer["card_id"], "amount": int(layer["power"])})
			layer["duration"] = maxf(0, float(layer["duration"]) - step)
		pending -= step; phase += step
		if phase + EPSILON >= TICK_INTERVAL:
			phase = 0
			events.append({"type": "status_heal", "status": "regen", "amount": total, "sources": sources, "time_offset": delta - pending})
		var active: Array[Dictionary] = []
		for layer: Dictionary in layers:
			if float(layer["duration"]) > EPSILON: active.append(layer)
		layers = active
		if layers.is_empty(): events.append({"type": "status_expired", "status": "regen", "time_offset": delta - pending})
	result["tick_accumulator"] = phase
	return {"data": _summarize(result, layers), "events": events}


static func next_tick_in(value: Dictionary) -> float:
	var data: Dictionary = normalize(value)
	var next: float = maxf(0, TICK_INTERVAL - float(data["tick_accumulator"]))
	return -1 if float(data["duration"]) + EPSILON < next else float(data["suspended"]) + next


static func _summarize(data: Dictionary, layers: Array) -> Dictionary:
	var duration: float = 0
	var power: int = 0
	for layer: Dictionary in layers: duration = maxf(duration, float(layer["duration"])); power += int(layer["power"])
	data["layers"] = layers; data["duration"] = duration; data["power"] = power; data["stacks"] = layers.size()
	data["max_duration"] = maxf(duration, float(data.get("max_duration", duration)))
	return data
