extends Node

var _checks: int = 0
var _simulation: Array[Dictionary] = []


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.set_language("en")
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		push_error("Infinite variants: " + message)
		get_tree().quit(1)
		assert(value, message)


func _run_at(cycle: int) -> RunState:
	var run: RunState = RunState.from_starter(Database.get_starter("balanced"), 4242)
	run.infinite_mode = true
	run.max_hp = 10000
	run.player_hp = 10000
	run.map_state = MapGenerator.new().generate_infinite_run(4242)
	for index: int in range(1, cycle): MapGenerator.new().append_infinite_cycle(run.map_state, 4242)
	run.map_state["current_step"] = (cycle - 1) * 28
	return run


func _run() -> void:
	_check(InfiniteEnemyCatalog.entries().size() == 18 and Database.enemies.size() == 36, "all eighteen base enemies need variants")
	_check(Database.get_all_card_ids().size() == 122 and Database.get_boss_card_ids().size() == 3 and Database.get_enemy_card_ids().size() == 8, "collectible/boss/enemy-only catalogs must stay separate")
	var old_definitions: Dictionary = {}
	for raw: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(Database.ENEMIES_PATH)):
		old_definitions[String(raw["id"])] = raw
	for entry: Dictionary in InfiniteEnemyCatalog.entries():
		var base: EnemyDef = Database.get_enemy(entry["base_id"])
		var variant: EnemyDef = Database.get_enemy(entry["id"])
		_check(variant != null and variant.infinite_only and variant.base_enemy_id == base.id, "variant identity " + String(entry["id"]))
		_check(base.max_hp == int(old_definitions[base.id]["max_hp"]) and base.cards == CardDef._to_string_array(old_definitions[base.id]["cards"]), "base definition must not change")
		_check(variant.max_hp > base.max_hp and variant.attack > base.attack, "variant must be an upgrade")
		_check(InfiniteEnemyCatalog.resolve(base.id, 1) == base.id and InfiniteEnemyCatalog.resolve(base.id, 2) == variant.id, "cycle boundary")
		_check(InfiniteEnemyCatalog.resolve(variant.id, 100) == variant.id, "variant mapping must be idempotent")
		_check(variant.cards.size() >= 4 and variant.cards != base.cards, "variant loadout must be curated")
		for card_id: String in variant.cards: _check(Database.get_card(card_id) != null, "unknown loadout card " + card_id)
		var original_profile: Dictionary = Database.get_battle_visual_profile(base.id)
		var variant_profile: Dictionary = Database.get_battle_visual_profile(variant.id)
		_check(original_profile.model_scene == variant_profile.model_scene and variant_profile.has("material_palette"), "reuse GLB geometry and supply a palette")
		_check(ResourceLoader.exists("res://assets/portraits/%s.png" % variant.id), "variant portrait missing")
		for cycle: int in [1, 2, 5]:
			var run: RunState = _run_at(cycle)
			var preview: UnitState = RealtimeBattleEngine.build_enemy_preview(run, base.id, {"infinite_power":cycle})
			var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
			engine.set_audio_enabled(false)
			engine.setup(run, base.id)
			_check(engine.battle_state.enemy.unit_id == (base.id if cycle == 1 else variant.id), "runtime cycle selection")
			_check(preview.unit_id == engine.battle_state.enemy.unit_id and preview.max_hp == engine.battle_state.enemy.max_hp and preview.attack == engine.battle_state.enemy.attack, "preview and battle must match")
			engine.dispose()
		var simulation: RealtimeBattleEngine = RealtimeBattleEngine.new()
		simulation.set_audio_enabled(false)
		simulation.setup(_run_at(2), base.id)
		simulation.start_battle()
		if base.id == "boss_timekeeper":
			_check(simulation.battle_state.active_instances.any(func(instance: ActiveCardInstance) -> bool: return instance.card_id == "timekeeper_final_strike" and is_zero_approx(instance.created_at)), "ascended Timekeeper must queue the final strike immediately")
		for frame: int in 450: simulation.update(0.1)
		var resolved: Array[String] = []
		for event: Dictionary in simulation.battle_state.battle_events:
			if event.get("event_type", "") == "resolve_card": resolved.append(String(event.get("card_id", "")))
		_check(not resolved.is_empty(), "variant AI never resolved a card: " + variant.id)
		_simulation.append({"id":variant.id, "resolved":resolved, "damage":10000-simulation.battle_state.player.hp})
		simulation.dispose()
	await _test_materials()
	_test_maps()
	_test_cards()
	Game.set_language("ja")
	_check(Database.get_enemy("scout_ascended").name == "疾風のスカウト", "localized variant names")
	_check(Database.get_enemy("guardian_ascended").description.contains("シールド"), "localized tactics")
	print("INFINITE_ENEMY_VARIANTS_SIMULATION " + JSON.stringify(_simulation))
	print("INFINITE_ENEMY_VARIANTS_SMOKE_OK checks=%d enemies=18 cards=8 grades=0..5 cycles=1/2/5 materials/maps/migration/AI/preview" % _checks)
	get_tree().quit()


func _test_materials() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/blender/characters/qq_ascended_enemies.manifest.json"))
	var rendered_palettes: Dictionary = {}
	for asset: Dictionary in manifest["assets"]: rendered_palettes[asset["visual_id"]] = asset["palette"]
	for entry: Dictionary in InfiniteEnemyCatalog.entries():
		var actor: BattleActor3D = BattleActor3D.new()
		add_child(actor)
		var base_profile: Dictionary = Database.get_battle_visual_profile(entry["base_id"])
		var profile: Dictionary = Database.get_battle_visual_profile(entry["id"])
		for role: String in profile.material_palette:
			var color: Color = Color("#" + String(profile.material_palette[role]))
			var rendered: Array = rendered_palettes[entry["id"]][role]
			_check(absf(color.r - float(rendered[0])) < .004 and absf(color.g - float(rendered[1])) < .004 and absf(color.b - float(rendered[2])) < .004, "render and runtime palette mismatch")
		actor.configure("enemy", entry["base_id"], base_profile)
		var model: Node3D = actor.get_authored_model_root()
		actor.configure_visual(entry["id"], profile)
		_check(actor.get_authored_model_root() == model, "recolor must reuse the instantiated model")
		var changed: int = 0
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			for surface: int in mesh.mesh.get_surface_count():
				var original: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				var role: String = InfiniteEnemyCatalog.material_role(original.resource_name)
				if not profile.material_palette.has(role): continue
				var override: StandardMaterial3D = mesh.get_surface_override_material(surface) as StandardMaterial3D
				_check(override != null and override != original, "base materials must never be mutated")
				_check(override.albedo_color.is_equal_approx(Color("#" + String(profile.material_palette[role]))), "material recolor mismatch")
				changed += 1
		_check(changed > 5, "variant is not visibly recolored")
		var cached: int = BattleActor3D.get_cached_variant_material_count()
		actor.configure_visual(entry["id"], profile)
		_check(BattleActor3D.get_cached_variant_material_count() == cached, "rebind must reuse cached materials")
		var second: BattleActor3D = BattleActor3D.new()
		add_child(second)
		second.configure("enemy", entry["id"], profile)
		_check(BattleActor3D.get_cached_variant_material_count() == cached, "new actor must share cached palette materials")
		second.queue_free()
		actor.configure_visual(entry["base_id"], base_profile)
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			for surface: int in mesh.mesh.get_surface_count(): _check(mesh.get_surface_override_material(surface) == null, "base palette must restore cleanly")
		actor.queue_free()
		await get_tree().process_frame


func _test_maps() -> void:
	var run: RunState = _run_at(3)
	for index: int in Array(run.map_state["steps"]).size():
		for node: Dictionary in run.map_state["steps"][index]["nodes"]:
			for id: String in EncounterSeries.queue(node):
				_check(InfiniteEnemyCatalog.is_variant(id) == (index >= 28), "map/encounter cycle mapping")
	var hazard: Array[String] = EncounterSeries.build_hazard_queue(14, 30, true)
	_check(hazard == ["raider_ascended","guardian_ascended","raider_ascended","guardian_ascended"], "hazards must retain their local-area archetypes")
	var legacy: Dictionary = run.map_state.duplicate(true)
	legacy.erase("enemy_variant_version")
	var active: Dictionary = legacy["steps"][28]["nodes"][0]
	active["encounter_queue"] = ["scout", "guardian", "raider"]
	active["encounters_cleared"] = 1
	active["gold"] = 123
	InfiniteEnemyCatalog.upgrade_map(legacy)
	_check(active["encounter_queue"] == ["scout","guardian_ascended","raider_ascended"] and active["encounters_cleared"] == 1 and active["gold"] == 123, "migration must preserve cleared waves and rewards")
	var snapshot: String = JSON.stringify(legacy)
	InfiniteEnemyCatalog.upgrade_map(legacy)
	_check(snapshot == JSON.stringify(legacy), "map migration must be idempotent")
	var ordinary: RunState = _run_at(2)
	ordinary.infinite_mode = false
	_check(InfiniteEnemyCatalog.resolve_for_run("scout", ordinary) == "scout", "normal run isolation")
	ordinary.infinite_mode = true
	ordinary.arena_mode = true
	_check(InfiniteEnemyCatalog.resolve_for_run("scout", ordinary) == "scout", "arena isolation")
	_check(InfiniteScoreResolver.par_time("scout_ascended", 2) > InfiniteScoreResolver.par_time("scout", 2), "variant efficiency par must use base archetype and extra HP")


func _test_cards() -> void:
	for id: String in Database.get_enemy_card_ids():
		_check(not Database.is_collectible_card(id), "enemy cards must not enter player rewards")
		for tier: int in 6:
			var card: CardDef = CardUpgradeResolver.build_card_at_tier(id, tier)
			_check(card.enemy_only and not card.boss_only and card.cast_time > 0 and card.recast_time > 0, "enemy card grades")
			_check(not CardInfoFormatter.build_effect_lines(card).is_empty(), "enemy card effect information")
		_check(ResourceLoader.exists("res://assets/icons/cards/%s.png" % id), "enemy card illustration missing")
		_check(AudioManager.has_sfx(String(AudioManager.CARD_SOUND_ALIASES[id])), "enemy card audio alias missing")
		var run: RunState = _run_at(2)
		run.equipped_cards = [id]
		var engine: RealtimeBattleEngine = RealtimeBattleEngine.new()
		engine.set_audio_enabled(false)
		engine.setup(run, "scout")
		_check(not engine.request_use_card("player", "player_0"), "player must not commit enemy-only cards")
		engine.dispose()
