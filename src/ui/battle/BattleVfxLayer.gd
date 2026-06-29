extends Control
class_name BattleVfxLayer

const DAMAGE_COLOR := Color(1.0, 0.25, 0.18, 1.0)
const HEAL_COLOR := Color(0.34, 1.0, 0.48, 1.0)
const SHIELD_COLOR := Color(0.42, 0.86, 1.0, 1.0)
const RESOLVE_COLOR := Color(1.0, 0.78, 0.28, 1.0)
const TWO_PI: float = PI * 2.0


class VfxShape:
	extends Control

	var shape_type: String = "disc"
	var color: Color = Color.WHITE
	var radius: float = 16.0
	var thickness: float = 3.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		match shape_type:
			"ring":
				draw_arc(Vector2.ZERO, radius, 0.0, PI * 2.0, 72, color, thickness, true)
			"disc":
				draw_circle(Vector2.ZERO, radius, color)
			"spark":
				draw_line(Vector2(-radius, 0.0), Vector2(radius, 0.0), color, thickness, true)
				draw_line(Vector2(0.0, -radius), Vector2(0.0, radius), color.lightened(0.25), maxf(1.0, thickness * 0.62), true)
			"slash":
				draw_line(Vector2(-radius, radius * 0.55), Vector2(radius, -radius * 0.55), color, thickness, true)
				draw_line(Vector2(-radius * 0.72, radius * 0.18), Vector2(radius * 0.72, -radius * 0.92), color.lightened(0.28), maxf(1.0, thickness * 0.42), true)
			_:
				draw_circle(Vector2.ZERO, radius, color)


class VfxParticle:
	extends RefCounted

	var control: Control
	var velocity: Vector2 = Vector2.ZERO
	var angular_velocity: float = 0.0
	var lifetime: float = 0.75
	var elapsed: float = 0.0
	var fade_start: float = 0.45
	var start_scale: Vector2 = Vector2.ONE
	var end_scale: Vector2 = Vector2.ONE


var _particles: Array[VfxParticle] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func play_resolution(
	event_data: Dictionary,
	actor_panel: UnitPanel,
	target_panel: UnitPanel,
	player_panel: UnitPanel,
	enemy_panel: UnitPanel
) -> void:
	var actor_point: Vector2 = _get_panel_center(actor_panel)
	var fallback_target: UnitPanel = target_panel
	if fallback_target == null:
		fallback_target = actor_panel
	var target_point: Vector2 = _get_panel_center(fallback_target)
	var card_id: String = String(event_data.get("card_id", ""))
	_spawn_resolve_flash(actor_point, card_id)

	var result: Dictionary = Dictionary(event_data.get("result", {}))
	_play_unit_delta("player", result, player_panel, actor_point)
	_play_unit_delta("enemy", result, enemy_panel, actor_point)


func _process(delta: float) -> void:
	for index in range(_particles.size() - 1, -1, -1):
		var particle: VfxParticle = _particles[index]
		if particle == null or particle.control == null or not is_instance_valid(particle.control):
			_particles.remove_at(index)
			continue

		particle.elapsed += delta
		var progress: float = clampf(particle.elapsed / maxf(0.001, particle.lifetime), 0.0, 1.0)
		particle.control.position += particle.velocity * delta
		particle.control.rotation += particle.angular_velocity * delta
		particle.control.scale = particle.start_scale.lerp(particle.end_scale, _ease_out_cubic(progress))
		var fade_progress: float = clampf((progress - particle.fade_start) / maxf(0.001, 1.0 - particle.fade_start), 0.0, 1.0)
		particle.control.modulate.a = 1.0 - fade_progress
		if particle.elapsed >= particle.lifetime:
			particle.control.queue_free()
			_particles.remove_at(index)


func _play_unit_delta(unit_key: String, result: Dictionary, unit_panel: UnitPanel, actor_point: Vector2) -> void:
	if unit_panel == null:
		return
	var before_data: Dictionary = Dictionary(result.get("%s_before" % unit_key, {}))
	var after_data: Dictionary = Dictionary(result.get("%s_after" % unit_key, {}))
	if before_data.is_empty() or after_data.is_empty():
		return

	var unit_point: Vector2 = _get_panel_center(unit_panel)
	var hp_delta: int = int(after_data.get("hp", 0)) - int(before_data.get("hp", 0))
	var shield_delta: int = int(after_data.get("shield", 0)) - int(before_data.get("shield", 0))
	if hp_delta < 0:
		_spawn_damage(unit_point)
	elif hp_delta > 0:
		_spawn_heal(unit_point)
	if shield_delta > 0:
		_spawn_shield_gain(unit_point)
	elif shield_delta < 0:
		_spawn_shield_hit(unit_point)


func _spawn_resolve_flash(actor_point: Vector2, card_id: String) -> void:
	var tint: Color = _resolve_card_color(card_id)
	_spawn_ring("ResolveFlash", actor_point, tint, 14.0, 3.0, 0.34, Vector2(0.45, 0.45), Vector2(1.35, 1.35))


func _spawn_damage(target_point: Vector2) -> void:
	_spawn_shape("DamageSlash", "slash", target_point, DAMAGE_COLOR, 28.0, 7.0, 0.34, Vector2(0.70, 0.70), Vector2(1.12, 1.12), Vector2.ZERO, -0.25)
	_spawn_burst("DamageImpact", target_point, DAMAGE_COLOR, 8, 0.52, 140.0)


func _spawn_heal(unit_point: Vector2) -> void:
	_spawn_ring("HealRing", unit_point, HEAL_COLOR, 18.0, 4.0, 0.55, Vector2(0.38, 0.38), Vector2(1.72, 1.72))
	for index in range(7):
		var offset_x: float = -30.0 + float(index) * 10.0
		var velocity: Vector2 = Vector2(offset_x * 0.10, -70.0 - float(index % 3) * 16.0)
		_spawn_disc("HealMote", unit_point + Vector2(offset_x, 24.0), HEAL_COLOR.lightened(0.10), 5.0, 0.72, velocity)


func _spawn_shield_gain(unit_point: Vector2) -> void:
	_spawn_ring("ShieldRing", unit_point, SHIELD_COLOR, 24.0, 5.0, 0.62, Vector2(0.42, 0.42), Vector2(1.85, 1.85))
	_spawn_ring("ShieldCore", unit_point, SHIELD_COLOR.lightened(0.18), 14.0, 3.0, 0.46, Vector2(0.75, 0.75), Vector2(1.20, 1.20))


func _spawn_shield_hit(unit_point: Vector2) -> void:
	_spawn_ring("ShieldHit", unit_point, SHIELD_COLOR.lightened(0.22), 22.0, 4.0, 0.38, Vector2(1.24, 0.82), Vector2(1.88, 1.18))
	_spawn_burst("ShieldShard", unit_point, SHIELD_COLOR, 6, 0.48, 108.0)


func _spawn_burst(prefix: String, center: Vector2, color: Color, count: int, lifetime: float, speed: float) -> void:
	for index in range(count):
		var ratio: float = float(index) / float(maxi(1, count))
		var angle: float = ratio * TWO_PI
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var radius: float = 5.0 + float(index % 3) * 2.0
		_spawn_shape(prefix, "spark", center + direction * 8.0, color, radius, 3.0, lifetime, Vector2(0.8, 0.8), Vector2(0.2, 0.2), direction * speed, angle)


func _spawn_ring(
	node_name: String,
	position: Vector2,
	color: Color,
	radius: float,
	thickness: float,
	lifetime: float,
	start_scale: Vector2,
	end_scale: Vector2
) -> void:
	_spawn_shape(node_name, "ring", position, color, radius, thickness, lifetime, start_scale, end_scale, Vector2.ZERO, 0.0)


func _spawn_disc(node_name: String, position: Vector2, color: Color, radius: float, lifetime: float, velocity: Vector2) -> void:
	_spawn_shape(node_name, "disc", position, color, radius, 2.0, lifetime, Vector2.ONE, Vector2(0.35, 0.35), velocity, 0.0)


func _spawn_shape(
	node_name: String,
	shape_type: String,
	position: Vector2,
	color: Color,
	radius: float,
	thickness: float,
	lifetime: float,
	start_scale: Vector2,
	end_scale: Vector2,
	velocity: Vector2,
	rotation: float
) -> void:
	var shape: VfxShape = VfxShape.new()
	shape.name = node_name
	shape.shape_type = shape_type
	shape.color = color
	shape.radius = radius
	shape.thickness = thickness
	shape.position = position
	shape.rotation = rotation
	shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shape)
	shape.queue_redraw()
	_track_particle(shape, lifetime, velocity, 0.0, start_scale, end_scale, 0.45)


func _track_particle(
	control: Control,
	lifetime: float,
	velocity: Vector2,
	angular_velocity: float,
	start_scale: Vector2,
	end_scale: Vector2,
	fade_start: float
) -> void:
	var particle: VfxParticle = VfxParticle.new()
	particle.control = control
	particle.lifetime = lifetime
	particle.velocity = velocity
	particle.angular_velocity = angular_velocity
	particle.start_scale = start_scale
	particle.end_scale = end_scale
	particle.fade_start = fade_start
	_particles.append(particle)


func _get_panel_center(panel: UnitPanel) -> Vector2:
	if panel == null:
		return size * 0.5
	var portrait: Control = panel.find_child("Portrait", true, false) as Control
	var source: Control = portrait
	if source == null:
		source = panel
	var rect: Rect2 = source.get_global_rect()
	return get_global_transform_with_canvas().affine_inverse() * rect.get_center()


func _resolve_card_color(card_id: String) -> Color:
	if card_id == "":
		return RESOLVE_COLOR
	var hue: float = float(abs(card_id.hash()) % 1000) / 1000.0
	return Color.from_hsv(hue, 0.55, 1.0, 1.0).lerp(RESOLVE_COLOR, 0.34)


func _ease_out_cubic(value: float) -> float:
	var inverse: float = 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - inverse * inverse * inverse
