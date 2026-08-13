extends Node

var _failed: bool = false


func _ready() -> void:
	Database.load_all()
	call_deferred("_run")


func _run() -> void:
	if not Database.load_errors.is_empty():
		_fail("Battle visual profiles smoke failed: database could not be loaded")
		return

	var expected_ids: Array[String] = []
	for starter: Dictionary in Database.starters:
		expected_ids.append(String(starter.get("id", "")))
	for raw_enemy_id: Variant in Database.enemies.keys():
		expected_ids.append(String(raw_enemy_id))
	if expected_ids.size() != 25:
		_fail("Battle visual profiles smoke failed: expected 25 combatant ids, found %d" % expected_ids.size())
		return

	var actor := BattleActor3D.new()
	actor.name = "VisualProfileProbe"
	actor.configure("player")
	add_child(actor)
	await get_tree().process_frame

	var unique_weapons: Dictionary = {}
	var unique_offhands: Dictionary = {}
	var unique_heads: Dictionary = {}
	var unique_backs: Dictionary = {}
	var unique_scales: Dictionary = {}
	var boss_count: int = 0
	for profile_id: String in expected_ids:
		if not Database.battle_visuals.has(profile_id):
			_fail("Battle visual profiles smoke failed: no explicit profile for %s" % profile_id)
			return
		var fallback_id: String = "default_enemy" if Database.enemies.has(profile_id) else "default_player"
		var profile: Dictionary = Database.get_battle_visual_profile(profile_id, fallback_id)
		if profile.is_empty():
			_fail("Battle visual profiles smoke failed: missing profile for %s" % profile_id)
			return
		if not _profile_types_are_valid(profile_id, profile):
			return

		actor.configure_visual(profile_id, profile)
		if actor.get_visual_profile_id() != profile_id:
			_fail("Battle visual profiles smoke failed: actor did not apply %s" % profile_id)
			return
		if actor.find_child("DefaultWeapon", true, false) == null:
			_fail("Battle visual profiles smoke failed: %s did not create a weapon" % profile_id)
			return
		if actor.get_humanoid_model().get_geometry_piece_count() > 64:
			_fail("Battle visual profiles smoke failed: %s exceeded the 64-piece Web budget" % profile_id)
			return
		if actor.get_body_scale().is_equal_approx(Vector3.ZERO):
			_fail("Battle visual profiles smoke failed: %s has an invalid body scale" % profile_id)
			return

		unique_weapons[actor.get_weapon_type()] = true
		unique_offhands[actor.get_offhand_type()] = true
		unique_heads[actor.get_head_type()] = true
		unique_backs[actor.get_back_type()] = true
		unique_scales[_scale_key(actor.get_body_scale())] = true
		var expected_boss: bool = profile_id.begins_with("boss_")
		if actor.is_boss_profile() != expected_boss:
			_fail("Battle visual profiles smoke failed: boss flag mismatch for %s" % profile_id)
			return
		if expected_boss:
			boss_count += 1
			if actor.find_child("BossAura", true, false) == null or actor.get_body_scale().y < 1.25:
				_fail("Battle visual profiles smoke failed: %s lacks boss silhouette treatment" % profile_id)
				return

	if unique_weapons.size() < 10 \
	or unique_offhands.size() < 6 \
	or unique_heads.size() < 8 \
	or unique_backs.size() < 7 \
	or unique_scales.size() < 18 \
	or boss_count != 4:
		_fail("Battle visual profiles smoke failed: visual diversity targets were not met")
		return

	var stage := BattleStage3D.new()
	stage.name = "VisualMappingStage"
	add_child(stage)
	await get_tree().process_frame
	stage.configure_combatants("local", "opponent", "enemy", "chrono", "boss_axiom_breaker")
	var local_actor: BattleActor3D = stage.find_child("PlayerBattleActor3D", true, false) as BattleActor3D
	var opponent_actor: BattleActor3D = stage.find_child("EnemyBattleActor3D", true, false) as BattleActor3D
	if local_actor == null \
	or opponent_actor == null \
	or local_actor.get_visual_profile_id() != "chrono" \
	or opponent_actor.get_visual_profile_id() != "boss_axiom_breaker" \
	or local_actor.get_weapon_type() != "staff" \
	or opponent_actor.get_weapon_type() != "greatsword":
		_fail("Battle visual profiles smoke failed: stage did not map local and opponent profiles")
		return
	var local_platform: MeshInstance3D = local_actor.find_child("Platform", true, false) as MeshInstance3D
	var opponent_platform: MeshInstance3D = opponent_actor.find_child("Platform", true, false) as MeshInstance3D
	var local_platform_material: StandardMaterial3D = null
	var opponent_platform_material: StandardMaterial3D = null
	if local_platform != null:
		local_platform_material = local_platform.material_override as StandardMaterial3D
	if opponent_platform != null:
		opponent_platform_material = opponent_platform.material_override as StandardMaterial3D
	if local_platform_material == null \
	or opponent_platform_material == null \
	or local_platform_material.albedo_color.b <= local_platform_material.albedo_color.r \
	or opponent_platform_material.albedo_color.r <= opponent_platform_material.albedo_color.b:
		_fail("Battle visual profiles smoke failed: team platforms should remain blue and red")
		return

	print("BATTLE_VISUAL_PROFILES_SMOKE_OK 25 profiles, 10 weapons, equipment silhouettes, and boss scales validated")
	get_tree().quit()


func _profile_types_are_valid(profile_id: String, profile: Dictionary) -> bool:
	var weapon: String = String(profile.get("weapon", ""))
	var offhand: String = String(profile.get("offhand", ""))
	var head: String = String(profile.get("head", ""))
	var back: String = String(profile.get("back", ""))
	if not CommonBattleHumanoid3D.WEAPON_TYPES.has(weapon) \
	or not CommonBattleHumanoid3D.OFFHAND_TYPES.has(offhand) \
	or not CommonBattleHumanoid3D.HEAD_TYPES.has(head) \
	or not CommonBattleHumanoid3D.BACK_TYPES.has(back):
		_fail("Battle visual profiles smoke failed: unsupported equipment in %s" % profile_id)
		return false
	var scale_data: Variant = profile.get("body_scale", [])
	if not scale_data is Array or scale_data.size() != 3:
		_fail("Battle visual profiles smoke failed: invalid body scale in %s" % profile_id)
		return false
	return true


func _scale_key(value: Vector3) -> String:
	return "%.2f:%.2f:%.2f" % [value.x, value.y, value.z]


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	get_tree().quit(1)
