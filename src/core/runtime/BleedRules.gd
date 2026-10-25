extends RefCounted
class_name BleedRules

const TICK_INTERVAL: float = 6.0
const MAX_LAYERS: int = 3
const ATTACK_RATIO: float = 0.25
const EPSILON: float = 0.0000001


static func resolve_power(effect: Dictionary, attack: int) -> int:
	var bonus: float = float(attack) + float(effect.get("_bleed_damage_bonus", 0))
	return maxi(1, int(effect.get("bleed_power", 1)) + floori(bonus * ATTACK_RATIO))


static func normalize(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	var layers: Array[Dictionary] = []
	if value.get("layers") is Array:
		for raw: Variant in value["layers"]:
			if raw is not Dictionary or float(raw.get("duration", 0)) <= EPSILON: continue
			layers.append({"duration": float(raw["duration"]), "power": maxi(1, int(raw.get("power", 1))), "source_side": String(raw.get("source_side", ""))})
	elif float(value.get("duration", 0)) > EPSILON:
		layers.append({"duration": float(value["duration"]), "power": maxi(1, int(value.get("damage", 1))), "source_side": String(value.get("source_side", ""))})
	while layers.size() > MAX_LAYERS: layers.pop_front()
	result["tick_accumulator"] = clampf(float(value.get("tick_accumulator", 0)), 0, TICK_INTERVAL)
	result["suspended"] = maxf(0, float(value.get("suspended", 0)))
	return _summarize(result, layers)


static func add(value: Dictionary, duration: float, power: int, source_side: String) -> Dictionary:
	var result: Dictionary = normalize(value)
	if duration <= EPSILON: return result
	var layers: Array = result["layers"]
	if layers.is_empty(): result["tick_accumulator"] = 0; result["suspended"] = 0
	if layers.size() >= MAX_LAYERS:
		var oldest: int = 0
		for index: int in layers.size():
			if float(layers[index]["duration"]) < float(layers[oldest]["duration"]): oldest = index
		layers.remove_at(oldest)
	layers.append({"duration": duration, "power": maxi(1, power), "source_side": source_side})
	result["source_side"] = source_side
	return _summarize(result, layers)


static func adjust_duration(value: Dictionary, amount: float) -> Dictionary:
	var result: Dictionary = normalize(value)
	var active: Array[Dictionary] = []
	for layer: Dictionary in result["layers"]:
		layer["duration"] = maxf(0, float(layer["duration"]) + amount)
		if float(layer["duration"]) > EPSILON: active.append(layer)
	return _summarize(result, active)


static func tick(value: Dictionary, delta: float) -> Dictionary:
	var result: Dictionary = normalize(value)
	var events: Array[Dictionary] = []
	var pending: float = maxf(0, delta)
	var paused: float = minf(pending, float(result["suspended"]))
	result["suspended"] = float(result["suspended"]) - paused
	pending -= paused
	var layers: Array = result["layers"]
	var phase: float = float(result["tick_accumulator"])
	while pending > EPSILON and not layers.is_empty():
		var step: float = minf(pending, maxf(0, TICK_INTERVAL - phase))
		for layer: Dictionary in layers: step = minf(step, float(layer["duration"]))
		var total: int = 0
		var sources: Dictionary = {}
		for layer: Dictionary in layers:
			total += int(layer["power"])
			var source: String = layer["source_side"]
			sources[source] = int(sources.get(source, 0)) + int(layer["power"])
			layer["duration"] = maxf(0, float(layer["duration"]) - step)
		pending -= step
		phase += step
		# Resolve the boundary tick before expiring layers, including the final tick.
		if phase + EPSILON >= TICK_INTERVAL:
			phase = 0
			events.append({"type": "status_damage", "status": "bleed", "amount": total, "source_amounts": sources,
				"source_side": String(sources.keys()[0]) if sources.size() == 1 else ""})
		var active: Array[Dictionary] = []
		for layer: Dictionary in layers:
			if float(layer["duration"]) > EPSILON: active.append(layer)
		layers = active
		if layers.is_empty(): events.append({"type": "status_expired", "status": "bleed", "last_tick_power": total})
	result["tick_accumulator"] = phase
	return {"data": _summarize(result, layers), "events": events}


static func next_tick_in(value: Dictionary) -> float:
	var data: Dictionary = normalize(value)
	var next: float = maxf(0, TICK_INTERVAL - float(data["tick_accumulator"]))
	if float(data["duration"]) + EPSILON < next: return -1
	return float(data["suspended"]) + next


static func _summarize(data: Dictionary, layers: Array) -> Dictionary:
	var duration: float = 0
	var power: int = 0
	for layer: Dictionary in layers:
		duration = maxf(duration, float(layer["duration"]))
		power += int(layer["power"])
	data["layers"] = layers
	data["duration"] = duration
	data["max_duration"] = maxf(duration, float(data.get("max_duration", duration)))
	data["stacks"] = layers.size()
	data["damage"] = power
	return data
