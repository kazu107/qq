extends SubViewportContainer
class_name BattleStage3D

const DEFAULT_VIEWPORT_SIZE := Vector2i(960, 540)
const TILE_COLUMNS: int = 7
const TILE_ROWS: int = 5
const MAX_QUEUED_EVENTS: int = 32

const DAMAGE_COLOR := Color(1.0, 0.22, 0.12, 1.0)
const SHIELD_COLOR := Color(0.18, 0.74, 1.0, 1.0)
const HEAL_COLOR := Color(0.24, 1.0, 0.48, 1.0)
const STATUS_COLOR := Color(1.0, 0.72, 0.16, 1.0)
const INTERRUPT_COLOR := Color(0.92, 0.32, 1.0, 1.0)
const START_COLOR := Color(0.32, 0.86, 1.0, 1.0)
const FLOATING_TEXT_LIFETIME: float = 1.75
const FLOATING_TEXT_FADE_START: float = 0.58
const FLOATING_TEXT_SIZE := Vector2(132.0, 58.0)


class StageEffect:
	extends RefCounted

	var node: MeshInstance3D
	var material: StandardMaterial3D
	var start_position: Vector3 = Vector3.ZERO
	var end_position: Vector3 = Vector3.ZERO
	var start_scale: Vector3 = Vector3.ONE
	var end_scale: Vector3 = Vector3.ONE
	var color: Color = Color.WHITE
	var arc_height: float = 0.0
	var duration: float = 0.5
	var elapsed: float = 0.0


class FloatingCombatText:
	extends RefCounted

	var label: Label
	var actor: BattleActor3D
	var screen_offset: Vector2 = Vector2.ZERO
	var drift: Vector2 = Vector2(0.0, -34.0)
	var lifetime: float = FLOATING_TEXT_LIFETIME
	var elapsed: float = 0.0

var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D
var _floating_text_layer: Control
var _player_actor: BattleActor3D
var _enemy_actor: BattleActor3D
var _projectile_mesh: SphereMesh
var _impact_mesh: SphereMesh
var _camera_home_position: Vector3 = Vector3.ZERO
var _camera_shake: float = 0.0
var _camera_shake_elapsed: float = 0.0
var _queued_events: Array[Dictionary] = []
var _active_event: Dictionary = {}
var _active_event_elapsed: float = 0.0
var _active_event_duration: float = 0.0
var _effects: Array[StageEffect] = []
var _floating_texts: Array[FloatingCombatText] = []
var _floating_text_serial: int = 0
var _cast_counts: Dictionary = {}
var _local_unit_id: String = "player"
var _opponent_unit_id: String = "enemy"
var _local_engine_side: String = "player"
var _local_visual_id: String = "default_player"
var _opponent_visual_id: String = "default_enemy"


func _ready() -> void:
	name = "BattleStage3D"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_build_stage()
	set_process(true)


func _process(delta: float) -> void:
	_update_event_queue(delta)
	_update_effects(delta)
	_update_floating_combat_texts(delta)
	_update_camera(delta)


func configure_combatants(
	local_unit_id: String,
	opponent_unit_id: String,
	local_engine_side: String = "player",
	local_visual_id: String = "default_player",
	opponent_visual_id: String = "default_enemy"
) -> void:
	_local_unit_id = local_unit_id
	_opponent_unit_id = opponent_unit_id
	_local_engine_side = local_engine_side if local_engine_side == "enemy" else "player"
	_local_visual_id = local_visual_id if local_visual_id != "" else "default_player"
	_opponent_visual_id = opponent_visual_id if opponent_visual_id != "" else "default_enemy"
	_cast_counts.clear()
	_queued_events.clear()
	_active_event.clear()
	_active_event_elapsed = 0.0
	_active_event_duration = 0.0
	_clear_effects()
	_clear_floating_combat_texts()
	if _player_actor != null:
		_player_actor.configure_visual(
			_local_visual_id,
			Database.get_battle_visual_profile(_local_visual_id, "default_player")
		)
		_player_actor.reset_performance()
	if _enemy_actor != null:
		_enemy_actor.configure_visual(
			_opponent_visual_id,
			Database.get_battle_visual_profile(_opponent_visual_id, "default_enemy")
		)
		_enemy_actor.reset_performance()


func play_battle_event(event_data: Dictionary) -> void:
	if event_data.is_empty():
		return
	_emit_event_combat_text(event_data)
	_queued_events.append(event_data.duplicate(true))
	while _queued_events.size() > MAX_QUEUED_EVENTS:
		_queued_events.pop_front()
	if _active_event.is_empty():
		_start_next_event()


func get_pending_event_count() -> int:
	return _queued_events.size() + (0 if _active_event.is_empty() else 1)


func get_active_effect_count() -> int:
	return _effects.size()


func get_floating_combat_text_count() -> int:
	return _floating_texts.size()


func get_floating_combat_text_values() -> Array[String]:
	var values: Array[String] = []
	for floating_text in _floating_texts:
		if floating_text != null and floating_text.label != null and is_instance_valid(floating_text.label):
			values.append(floating_text.label.text)
	return values


func get_actor_screen_position(unit_id: String) -> Vector2:
	return _project_actor_position(_actor_for_unit_id(unit_id))


func _build_stage() -> void:
	_build_effect_resources()
	_viewport = SubViewport.new()
	_viewport.name = "BattleStageViewport"
	_viewport.size = DEFAULT_VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "BattleStageWorld"
	_viewport.add_child(_world_root)

	_build_environment()
	_build_arena()
	_build_actors()
	_build_camera()
	_build_floating_text_layer()


func _build_floating_text_layer() -> void:
	_floating_text_layer = Control.new()
	_floating_text_layer.name = "BattleStageFloatingTextLayer"
	_floating_text_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floating_text_layer.z_index = 40
	add_child(_floating_text_layer)
	_floating_text_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_effect_resources() -> void:
	_projectile_mesh = SphereMesh.new()
	_projectile_mesh.radius = 0.16
	_projectile_mesh.height = 0.32
	_impact_mesh = SphereMesh.new()
	_impact_mesh.radius = 0.24
	_impact_mesh.height = 0.48


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "BattleWorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.035, 0.055, 1.0)
	environment.background_energy_multiplier = 0.82
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.48, 0.64, 1.0)
	environment.ambient_light_energy = 0.72
	world_environment.environment = environment
	_world_root.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "BattleKeyLight"
	key_light.rotation_degrees = Vector3(-54.0, -32.0, 0.0)
	key_light.light_color = Color(0.84, 0.91, 1.0, 1.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	_world_root.add_child(key_light)

	var warm_fill := OmniLight3D.new()
	warm_fill.name = "BattleWarmFill"
	warm_fill.position = Vector3(-3.5, 3.2, -1.5)
	warm_fill.light_color = Color(1.0, 0.45, 0.22, 1.0)
	warm_fill.light_energy = 1.25
	warm_fill.omni_range = 7.0
	warm_fill.shadow_enabled = false
	_world_root.add_child(warm_fill)


func _build_arena() -> void:
	var base_material: StandardMaterial3D = _make_material(Color(0.025, 0.075, 0.09, 1.0), 0.0)
	var tile_a: StandardMaterial3D = _make_material(Color(0.075, 0.14, 0.16, 1.0), 0.0)
	var tile_b: StandardMaterial3D = _make_material(Color(0.055, 0.105, 0.13, 1.0), 0.0)
	var blue_line: StandardMaterial3D = _make_material(Color(0.08, 0.62, 0.92, 1.0), 0.78)
	var red_line: StandardMaterial3D = _make_material(Color(0.92, 0.20, 0.12, 1.0), 0.72)
	var prop_material: StandardMaterial3D = _make_material(Color(0.07, 0.09, 0.12, 1.0), 0.0)

	var arena_base := BoxMesh.new()
	arena_base.size = Vector3(13.4, 0.28, 8.4)
	_add_mesh("ArenaBase", arena_base, Vector3(0.0, -0.14, 0.0), base_material)

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(1.62, 0.10, 1.30)
	for row in range(TILE_ROWS):
		for column in range(TILE_COLUMNS):
			var tile_x: float = (float(column) - float(TILE_COLUMNS - 1) * 0.5) * 1.76
			var tile_z: float = (float(row) - float(TILE_ROWS - 1) * 0.5) * 1.44
			var tile_name: String = "ArenaTile_%d_%d" % [column, row]
			_add_mesh(tile_name, tile_mesh, Vector3(tile_x, 0.01, tile_z), tile_a if (column + row) % 2 == 0 else tile_b)

	var lane_mesh := BoxMesh.new()
	lane_mesh.size = Vector3(0.08, 0.025, 6.96)
	_add_mesh("PlayerLaneGlow", lane_mesh, Vector3(0.88, 0.08, 0.0), blue_line)
	_add_mesh("EnemyLaneGlow", lane_mesh, Vector3(-0.88, 0.08, 0.0), red_line)

	var divider_mesh := BoxMesh.new()
	divider_mesh.size = Vector3(10.62, 0.028, 0.055)
	_add_mesh("CenterDivider", divider_mesh, Vector3(0.0, 0.085, 0.0), _make_material(Color(0.46, 0.72, 0.78, 1.0), 0.46))

	var prop_mesh := BoxMesh.new()
	prop_mesh.size = Vector3(1.0, 1.0, 1.0)
	var prop_positions: Array[Vector3] = [
		Vector3(-5.6, 0.5, -3.7),
		Vector3(-4.3, 0.34, -3.85),
		Vector3(5.5, 0.46, -3.7),
		Vector3(4.2, 0.28, -3.9),
	]
	var prop_scales: Array[Vector3] = [
		Vector3(0.9, 1.0, 0.9),
		Vector3(0.62, 0.68, 0.62),
		Vector3(0.82, 0.92, 0.82),
		Vector3(0.54, 0.56, 0.54),
	]
	for index in range(prop_positions.size()):
		var prop: MeshInstance3D = _add_mesh("ArenaProp_%d" % index, prop_mesh, prop_positions[index], prop_material)
		prop.scale = prop_scales[index]


func _build_actors() -> void:
	_enemy_actor = BattleActor3D.new()
	_enemy_actor.name = "EnemyBattleActor3D"
	_enemy_actor.configure("enemy")
	_enemy_actor.position = Vector3(-2.55, 0.08, -0.75)
	_world_root.add_child(_enemy_actor)

	_player_actor = BattleActor3D.new()
	_player_actor.name = "PlayerBattleActor3D"
	_player_actor.configure("player")
	_player_actor.position = Vector3(2.55, 0.08, 0.85)
	_world_root.add_child(_player_actor)

	_enemy_actor.look_at(_player_actor.position, Vector3.UP)
	_player_actor.look_at(_enemy_actor.position, Vector3.UP)
	_enemy_actor.capture_home_transform()
	_player_actor.capture_home_transform()


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "BattleStageCamera"
	_camera.position = Vector3(0.0, 7.4, 10.6)
	_camera.fov = 42.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_world_root.add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.82, -0.15), Vector3.UP)
	_camera.current = true
	_camera_home_position = _camera.position


func _emit_event_combat_text(event_data: Dictionary) -> void:
	match String(event_data.get("event_type", "")):
		"prepare_card":
			var prepare_actor: BattleActor3D = _actor_for_unit_id(String(event_data.get("actor_id", "")))
			var prepare_result: Dictionary = Dictionary(event_data.get("result", {}))
			var shield_cost: int = maxi(0, int(prepare_result.get("shield_cost", 0)))
			if shield_cost > 0:
				_spawn_floating_combat_text(prepare_actor, "-%d" % shield_cost, SHIELD_COLOR, 0)
		"resolve_card":
			var result: Dictionary = Dictionary(event_data.get("result", {}))
			_emit_unit_delta_text(_player_actor, _unit_delta(result, _player_actor))
			_emit_unit_delta_text(_enemy_actor, _unit_delta(result, _enemy_actor))
		"status_damage":
			var status_target: BattleActor3D = _actor_for_unit_id(String(event_data.get("target_id", "")))
			var damage_amount: int = maxi(0, -int(event_data.get("hp_delta", 0)))
			if damage_amount <= 0:
				var status_result: Dictionary = Dictionary(event_data.get("result", {}))
				damage_amount = maxi(0, int(status_result.get("amount", 0)))
			if damage_amount > 0:
				_spawn_floating_combat_text(status_target, "-%d" % damage_amount, DAMAGE_COLOR, 0)


func _emit_unit_delta_text(actor: BattleActor3D, delta_data: Dictionary) -> void:
	if actor == null or delta_data.is_empty():
		return
	var hp_delta: int = int(delta_data.get("hp", 0))
	var shield_delta: int = int(delta_data.get("shield", 0))
	if hp_delta < 0:
		_spawn_floating_combat_text(actor, "-%d" % absi(hp_delta), DAMAGE_COLOR, -1 if shield_delta != 0 else 0)
	elif hp_delta > 0:
		_spawn_floating_combat_text(actor, "+%d" % hp_delta, HEAL_COLOR, -1 if shield_delta != 0 else 0)
	if shield_delta != 0:
		var shield_text: String = "+%d" % shield_delta if shield_delta > 0 else "-%d" % absi(shield_delta)
		_spawn_floating_combat_text(actor, shield_text, SHIELD_COLOR, 1 if hp_delta != 0 else 0)


func _spawn_floating_combat_text(actor: BattleActor3D, value_text: String, color: Color, lane: int) -> void:
	if actor == null or value_text == "" or _floating_text_layer == null:
		return
	var label := Label.new()
	label.name = "FloatingCombatText"
	label.text = value_text
	label.size = FLOATING_TEXT_SIZE
	label.custom_minimum_size = FLOATING_TEXT_SIZE
	label.pivot_offset = FLOATING_TEXT_SIZE * 0.5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", color.lightened(0.12))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.98))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.84))
	label.add_theme_constant_override("outline_size", 7)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floating_text_layer.add_child(label)

	var floating_text := FloatingCombatText.new()
	floating_text.label = label
	floating_text.actor = actor
	var serial_lane: float = float((_floating_text_serial % 3) - 1) * 11.0
	floating_text.screen_offset = Vector2(float(lane) * 50.0 + serial_lane, -24.0)
	_floating_text_serial += 1
	_floating_texts.append(floating_text)
	_update_floating_combat_text(floating_text)


func _update_event_queue(delta: float) -> void:
	if _active_event.is_empty():
		_start_next_event()
		return
	_active_event_elapsed += delta
	if _active_event_elapsed < _active_event_duration:
		return
	_active_event.clear()
	_active_event_elapsed = 0.0
	_active_event_duration = 0.0
	_start_next_event()


func _start_next_event() -> void:
	if _queued_events.is_empty():
		return
	_active_event = _queued_events.pop_front()
	_active_event_elapsed = 0.0
	_active_event_duration = _begin_event(_active_event)
	if _active_event_duration <= 0.0:
		_active_event_duration = 0.08


func _begin_event(event_data: Dictionary) -> float:
	var event_type: String = String(event_data.get("event_type", ""))
	match event_type:
		"battle_start":
			_reset_stage_performance()
			_spawn_impact(Vector3(0.0, 0.18, 0.0), START_COLOR, 0.72, 2.6)
			return 0.42
		"prepare_card":
			_begin_prepare(event_data)
			return 0.18
		"resolve_card":
			_begin_resolution(event_data)
			return 0.76
		"status_damage":
			var status_target: BattleActor3D = _actor_for_unit_id(String(event_data.get("target_id", "")))
			if status_target != null:
				status_target.play_action(BattleActor3D.ACTION_HIT)
				_spawn_impact(_actor_effect_position(status_target), DAMAGE_COLOR, 0.42, 1.4)
			_add_camera_shake(0.10)
			return 0.46
		"interrupt_card":
			_begin_interrupt(event_data)
			return 0.58
		"boss_passive":
			var boss_actor: BattleActor3D = _actor_for_unit_id(String(event_data.get("actor_id", "")))
			var passive_target: BattleActor3D = _actor_for_unit_id(String(event_data.get("target_id", "")))
			if boss_actor != null:
				boss_actor.play_action(BattleActor3D.ACTION_STATUS)
			if passive_target != null:
				passive_target.play_action(BattleActor3D.ACTION_STATUS)
				_spawn_impact(_actor_effect_position(passive_target), STATUS_COLOR, 0.62, 1.8)
			return 0.66
		"battle_end":
			_begin_battle_end(event_data)
			return 1.10
		_:
			return 0.08


func _begin_prepare(event_data: Dictionary) -> void:
	var actor_id: String = String(event_data.get("actor_id", ""))
	var actor: BattleActor3D = _actor_for_unit_id(actor_id)
	if actor == null:
		return
	_cast_counts[actor_id] = int(_cast_counts.get(actor_id, 0)) + 1
	actor.play_action(BattleActor3D.ACTION_CAST)
	_spawn_impact(_actor_effect_position(actor), _color_for_actor(actor), 0.38, 1.24)


func _begin_resolution(event_data: Dictionary) -> void:
	var actor_id: String = String(event_data.get("actor_id", ""))
	var target_id: String = String(event_data.get("target_id", ""))
	var actor: BattleActor3D = _actor_for_unit_id(actor_id)
	var target: BattleActor3D = _actor_for_unit_id(target_id)
	_decrement_cast(actor_id, actor)

	var card_def: CardDef = Database.get_card(String(event_data.get("card_id", "")))
	var profile: Dictionary = _build_card_profile(card_def)
	var result: Dictionary = Dictionary(event_data.get("result", {}))
	var actor_delta: Dictionary = _unit_delta(result, actor)
	var target_delta: Dictionary = _unit_delta(result, target)
	var offensive: bool = bool(profile.get("offensive", false)) \
		or int(target_delta.get("hp", 0)) < 0 \
		or int(target_delta.get("shield", 0)) < 0

	if actor != null:
		if offensive and target != null and target != actor:
			actor.play_action(BattleActor3D.ACTION_ATTACK)
			_spawn_projectile(actor, target, _resolve_card_color(card_def), 0.42)
		elif int(actor_delta.get("hp", 0)) > 0 or bool(profile.get("heal", false)):
			actor.play_action(BattleActor3D.ACTION_HEAL)
		elif int(actor_delta.get("shield", 0)) > 0 or bool(profile.get("shield", false)):
			actor.play_action(BattleActor3D.ACTION_SHIELD)
		elif bool(profile.get("status", false)):
			actor.play_action(BattleActor3D.ACTION_STATUS)
		else:
			actor.play_action(BattleActor3D.ACTION_ATTACK)

	_apply_unit_delta(actor, actor_delta, profile, actor == target)
	if target != actor:
		_apply_unit_delta(target, target_delta, profile, true)
	if bool(profile.get("status", false)) and target != null:
		_spawn_impact(_actor_effect_position(target), STATUS_COLOR, 0.62, 1.68)
	if offensive:
		_add_camera_shake(0.13 if int(target_delta.get("hp", 0)) < 0 else 0.08)


func _begin_interrupt(event_data: Dictionary) -> void:
	var actor: BattleActor3D = _actor_for_unit_id(String(event_data.get("actor_id", "")))
	var target_id: String = String(event_data.get("target_id", ""))
	var target: BattleActor3D = _actor_for_unit_id(target_id)
	_decrement_cast(target_id, target)
	if actor != null and actor != target:
		actor.play_action(BattleActor3D.ACTION_ATTACK)
	if target != null:
		target.play_action(BattleActor3D.ACTION_INTERRUPT)
		_spawn_impact(_actor_effect_position(target), INTERRUPT_COLOR, 0.52, 1.64)
	_add_camera_shake(0.10)


func _begin_battle_end(event_data: Dictionary) -> void:
	var result: Dictionary = Dictionary(event_data.get("result", {}))
	var winner: String = String(result.get("winner", event_data.get("actor_id", "draw")))
	var winner_actor: BattleActor3D = _actor_for_engine_side(winner)
	if winner_actor == null:
		if _player_actor != null:
			_player_actor.stop_casting()
		if _enemy_actor != null:
			_enemy_actor.stop_casting()
		return
	var loser_actor: BattleActor3D = _enemy_actor if winner_actor == _player_actor else _player_actor
	winner_actor.play_action(BattleActor3D.ACTION_VICTORY)
	if loser_actor != null:
		loser_actor.play_action(BattleActor3D.ACTION_DEFEAT)
	_spawn_impact(_actor_effect_position(winner_actor), _color_for_actor(winner_actor), 0.88, 2.2)


func _apply_unit_delta(actor: BattleActor3D, delta_data: Dictionary, profile: Dictionary, allow_reaction: bool) -> void:
	if actor == null:
		return
	var hp_delta: int = int(delta_data.get("hp", 0))
	var shield_delta: int = int(delta_data.get("shield", 0))
	var position_3d: Vector3 = _actor_effect_position(actor)
	if hp_delta < 0:
		if allow_reaction:
			actor.play_action(BattleActor3D.ACTION_HIT)
		_spawn_impact(position_3d, DAMAGE_COLOR, 0.48, 1.54)
	elif hp_delta > 0:
		if allow_reaction:
			actor.play_action(BattleActor3D.ACTION_HEAL)
		_spawn_impact(position_3d, HEAL_COLOR, 0.68, 1.86)
	if shield_delta < 0 and hp_delta >= 0:
		if allow_reaction:
			actor.play_action(BattleActor3D.ACTION_BLOCK)
		_spawn_impact(position_3d, SHIELD_COLOR, 0.44, 1.62)
	elif shield_delta > 0:
		if allow_reaction:
			actor.play_action(BattleActor3D.ACTION_SHIELD)
		_spawn_impact(position_3d, SHIELD_COLOR, 0.68, 1.92)
	elif bool(profile.get("status", false)) and allow_reaction and hp_delta == 0:
		actor.play_action(BattleActor3D.ACTION_STATUS)


func _build_card_profile(card_def: CardDef) -> Dictionary:
	var profile: Dictionary = {
		"offensive": false,
		"heal": false,
		"shield": false,
		"status": false,
	}
	if card_def == null:
		return profile
	for raw_effect in card_def.effects:
		var effect: Dictionary = Dictionary(raw_effect)
		match String(effect.get("type", "")):
			"deal_damage", "delay_enemy_active_card", "interrupt_card":
				profile["offensive"] = true
			"heal":
				profile["heal"] = true
			"gain_shield":
				profile["shield"] = true
			"apply_status", "remove_status", "modify_attack", "modify_speed", "timeline_flow":
				profile["status"] = true
	return profile


func _unit_delta(result: Dictionary, actor: BattleActor3D) -> Dictionary:
	if actor == null:
		return {}
	var engine_side: String = _engine_side_for_actor(actor)
	var before_data: Dictionary = Dictionary(result.get("%s_before" % engine_side, {}))
	var after_data: Dictionary = Dictionary(result.get("%s_after" % engine_side, {}))
	if before_data.is_empty() or after_data.is_empty():
		return {}
	return {
		"hp": int(after_data.get("hp", 0)) - int(before_data.get("hp", 0)),
		"shield": int(after_data.get("shield", 0)) - int(before_data.get("shield", 0)),
		"status_added": _has_added_status(before_data, after_data),
	}


func _has_added_status(before_data: Dictionary, after_data: Dictionary) -> bool:
	var before_statuses: Dictionary = Dictionary(before_data.get("statuses", {}))
	var after_statuses: Dictionary = Dictionary(after_data.get("statuses", {}))
	for status_id in after_statuses.keys():
		if not before_statuses.has(status_id):
			return true
	return false


func _decrement_cast(unit_id: String, actor: BattleActor3D) -> void:
	var remaining: int = maxi(0, int(_cast_counts.get(unit_id, 0)) - 1)
	_cast_counts[unit_id] = remaining
	if remaining == 0 and actor != null:
		actor.stop_casting()


func _actor_for_unit_id(unit_id: String) -> BattleActor3D:
	if unit_id == "":
		return null
	if unit_id == _local_unit_id:
		return _player_actor
	if unit_id == _opponent_unit_id:
		return _enemy_actor
	if unit_id == _local_engine_side:
		return _player_actor
	if unit_id == _opponent_engine_side():
		return _enemy_actor
	return null


func _actor_for_engine_side(engine_side: String) -> BattleActor3D:
	if engine_side == _local_engine_side:
		return _player_actor
	if engine_side == _opponent_engine_side():
		return _enemy_actor
	return null


func _engine_side_for_actor(actor: BattleActor3D) -> String:
	return _local_engine_side if actor == _player_actor else _opponent_engine_side()


func _opponent_engine_side() -> String:
	return "enemy" if _local_engine_side == "player" else "player"


func _reset_stage_performance() -> void:
	_cast_counts.clear()
	_clear_floating_combat_texts()
	if _player_actor != null:
		_player_actor.reset_performance()
	if _enemy_actor != null:
		_enemy_actor.reset_performance()


func _spawn_projectile(actor: BattleActor3D, target: BattleActor3D, color: Color, duration: float) -> void:
	if actor == null or target == null:
		return
	_spawn_effect(
		"BattleProjectile3D",
		_projectile_mesh,
		actor.get_weapon_world_position(),
		_actor_effect_position(target),
		color,
		duration,
		Vector3(0.55, 0.55, 0.55),
		Vector3(1.18, 1.18, 1.18),
		0.52
	)


func _spawn_impact(position_3d: Vector3, color: Color, duration: float, end_scale: float) -> void:
	_spawn_effect(
		"BattleImpact3D",
		_impact_mesh,
		position_3d,
		position_3d,
		color,
		duration,
		Vector3(0.18, 0.18, 0.18),
		Vector3.ONE * end_scale,
		0.0
	)


func _spawn_effect(
	node_name: String,
	mesh: Mesh,
	start_position: Vector3,
	end_position: Vector3,
	color: Color,
	duration: float,
	start_scale: Vector3,
	end_scale: Vector3,
	arc_height: float
) -> void:
	if _world_root == null:
		return
	var material: StandardMaterial3D = _make_effect_material(color)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.position = start_position
	node.scale = start_scale
	_world_root.add_child(node)
	var effect := StageEffect.new()
	effect.node = node
	effect.material = material
	effect.start_position = start_position
	effect.end_position = end_position
	effect.start_scale = start_scale
	effect.end_scale = end_scale
	effect.color = color
	effect.arc_height = arc_height
	effect.duration = maxf(0.08, duration)
	_effects.append(effect)


func _update_effects(delta: float) -> void:
	for index in range(_effects.size() - 1, -1, -1):
		var effect: StageEffect = _effects[index]
		if effect == null or effect.node == null or not is_instance_valid(effect.node):
			_effects.remove_at(index)
			continue
		effect.elapsed += delta
		var progress: float = clampf(effect.elapsed / effect.duration, 0.0, 1.0)
		var eased: float = _ease_out_cubic(progress)
		effect.node.position = effect.start_position.lerp(effect.end_position, eased)
		effect.node.position.y += sin(progress * PI) * effect.arc_height
		effect.node.scale = effect.start_scale.lerp(effect.end_scale, eased)
		var faded_color: Color = effect.color
		faded_color.a = 1.0 - progress
		effect.material.albedo_color = faded_color
		effect.material.emission = Color(effect.color.r, effect.color.g, effect.color.b, faded_color.a)
		if progress >= 1.0:
			effect.node.queue_free()
			_effects.remove_at(index)


func _clear_effects() -> void:
	for effect in _effects:
		if effect != null and effect.node != null and is_instance_valid(effect.node):
			effect.node.queue_free()
	_effects.clear()


func _update_floating_combat_texts(delta: float) -> void:
	for index in range(_floating_texts.size() - 1, -1, -1):
		var floating_text: FloatingCombatText = _floating_texts[index]
		if floating_text == null or floating_text.label == null or not is_instance_valid(floating_text.label):
			_floating_texts.remove_at(index)
			continue
		floating_text.elapsed += delta
		_update_floating_combat_text(floating_text)
		if floating_text.elapsed >= floating_text.lifetime:
			floating_text.label.queue_free()
			_floating_texts.remove_at(index)


func _update_floating_combat_text(floating_text: FloatingCombatText) -> void:
	if floating_text == null or floating_text.label == null or floating_text.actor == null:
		return
	var progress: float = clampf(floating_text.elapsed / maxf(0.01, floating_text.lifetime), 0.0, 1.0)
	var actor_position: Vector2 = _project_actor_position(floating_text.actor)
	floating_text.label.position = actor_position \
		+ floating_text.screen_offset \
		+ floating_text.drift * progress \
		- FLOATING_TEXT_SIZE * 0.5
	var fade_progress: float = clampf(
		(progress - FLOATING_TEXT_FADE_START) / (1.0 - FLOATING_TEXT_FADE_START),
		0.0,
		1.0
	)
	floating_text.label.modulate.a = 1.0 - fade_progress
	var pop_scale: float = lerpf(1.28, 1.0, clampf(progress / 0.16, 0.0, 1.0))
	floating_text.label.scale = Vector2.ONE * pop_scale


func _clear_floating_combat_texts() -> void:
	for floating_text in _floating_texts:
		if floating_text != null and floating_text.label != null and is_instance_valid(floating_text.label):
			floating_text.label.queue_free()
	_floating_texts.clear()
	_floating_text_serial = 0


func _project_actor_position(actor: BattleActor3D) -> Vector2:
	if actor == null or _camera == null or _viewport == null:
		return size * 0.5
	var viewport_position: Vector2 = _camera.unproject_position(_actor_effect_position(actor) + Vector3(0.0, 0.42, 0.0))
	var viewport_size := Vector2(_viewport.size)
	var display_size: Vector2 = size
	if display_size.x <= 1.0 or display_size.y <= 1.0:
		display_size = Vector2(DEFAULT_VIEWPORT_SIZE)
	return Vector2(
		viewport_position.x * display_size.x / maxf(1.0, viewport_size.x),
		viewport_position.y * display_size.y / maxf(1.0, viewport_size.y)
	)


func _add_camera_shake(amount: float) -> void:
	_camera_shake = maxf(_camera_shake, amount)
	_camera_shake_elapsed = 0.0


func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	if _camera_shake <= 0.001:
		_camera.position = _camera_home_position
		return
	_camera_shake_elapsed += delta
	_camera_shake = move_toward(_camera_shake, 0.0, delta * 0.34)
	_camera.position = _camera_home_position + Vector3(
		sin(_camera_shake_elapsed * 43.0) * _camera_shake,
		cos(_camera_shake_elapsed * 37.0) * _camera_shake * 0.62,
		0.0
	)


func _actor_effect_position(actor: BattleActor3D) -> Vector3:
	return actor.get_effect_world_position() if actor != null else Vector3.ZERO


func _color_for_actor(actor: BattleActor3D) -> Color:
	return Color(0.18, 0.76, 1.0, 1.0) if actor == _player_actor else Color(1.0, 0.30, 0.14, 1.0)


func _resolve_card_color(card_def: CardDef) -> Color:
	if card_def == null:
		return DAMAGE_COLOR
	if card_def.tags.has("shield"):
		return SHIELD_COLOR
	if card_def.tags.has("heal"):
		return HEAL_COLOR
	if card_def.tags.has("debuff") or card_def.tags.has("control"):
		return STATUS_COLOR
	return DAMAGE_COLOR


func _make_effect_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.45
	return material


func _ease_out_cubic(value: float) -> float:
	var inverse: float = 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - inverse * inverse * inverse


func _add_mesh(
	node_name: String,
	mesh: Mesh,
	world_position: Vector3,
	material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = world_position
	instance.material_override = material
	_world_root.add_child(instance)
	return instance


func _make_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.14
	material.roughness = 0.74
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material
