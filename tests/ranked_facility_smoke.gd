extends Node


func _ready() -> void:
	Database.load_all()
	Game.ensure_meta_initialized()
	Game.settings["replay_auto_export"] = false
	call_deferred("_run")


func _run() -> void:
	var checked: Array[String] = []
	for kind: String in ["shop", "forge", "heal", "event"]:
		var success: bool = false
		for seed_value: int in range(1, 16):
			RankedSession.verifying = false
			var ticket: Dictionary = {"id": "test", "user_id": "test", "seed": seed_value, "starter_id": "balanced", "ruleset": RankedSession.RULESET}
			RankedSession.initialize(ticket)
			Game.unequip_card("guard")
			Game.equip_card("guard")
			assert(RankedSession._random_step == 0, "Free loadout changes must not reroll future rewards")
			var steps: Array = Game.current_run.map_state["steps"]
			var parent: String = ""
			var child: String = ""
			var allowed: Array[String] = MapRouteGraph.allowed_ids(Game.current_run.map_state, 0)
			for node: Dictionary in steps[0]["nodes"]:
				if not allowed.has(String(node["id"])): continue
				for next: Dictionary in steps[1]["nodes"]:
					if String(next["type"]) == kind and Array(node.get("next_ids", [])).has(String(next["id"])):
						parent = String(node["id"])
						child = String(next["id"])
						break
				if parent != "": break
			if parent == "": continue
			Game.select_map_node(parent)
			var battle: RealtimeBattleEngine = RealtimeBattleEngine.new()
			battle.record_visuals = false
			battle.set_audio_enabled(false)
			battle.setup(Game.current_run, Game.prepare_next_battle())
			battle.start_battle()
			for tick: int in 18000:
				if battle.battle_state.winner != "": break
				if tick % 12 == 0:
					for card: CardRuntimeState in battle.battle_state.player.card_runtime_states:
						if card.can_use(): battle.request_use_card("player", card.runtime_id)
				battle.update(RankedSession.STEP)
			if battle.battle_state.winner == "":
				battle.dispose()
				continue
			Game.complete_battle(battle.build_summary())
			battle.dispose()
			if Game.current_run.defeated: continue
			Game.skip_reward()
			Game.select_map_node(child)
			if kind == "shop":
				var offers: Array[Dictionary] = Game.get_shop_offers()
				for index: int in offers.size():
					if Game.current_run.gold >= int(offers[index].get("price", 0)):
						Game.buy_shop_offer(index)
						break
			elif kind == "forge":
				var cards: Array[String] = Game.get_forge_options()
				if not cards.is_empty(): Game.upgrade_forge_card(cards[0])
			elif kind == "heal": Game.use_heal_node_choice("standard_repair")
			else:
				for choice: Dictionary in Game.get_active_event_data().get("choices", []):
					if bool(choice.get("enabled", true)):
						Game.resolve_event_choice(String(choice["id"]))
						break
			if Game.current_screen_hint == "facility": Game.leave_facility()
			var run: RunState = Game.current_run
			var expected: Dictionary = {"gold": run.gold, "max_hp": run.max_hp, "hp": run.player_hp, "attack": run.attack, "speed": run.speed, "card_upgrades": run.card_upgrades.duplicate(), "relics": run.relics.duplicate(), "cards": run.equipped_cards.duplicate()}
			var replay: Dictionary = RankedSession.replay(ticket, Array(run.ranking["commands"]).duplicate(true))
			if replay.has("error"):
				push_error("Ranked facility replay failed: " + kind + " " + JSON.stringify(replay))
				get_tree().quit(1)
				return
			for key: String in expected:
				if expected[key] != replay["result"].get(key):
					push_error("Ranked facility state mismatch: " + kind + " " + key)
					get_tree().quit(1)
					return
			success = true
			checked.append(kind)
			break
		if not success:
			push_error("No valid ranked route for " + kind)
			get_tree().quit(1)
			return
	print("RANKED_FACILITY_SMOKE_OK ", JSON.stringify(checked))
	get_tree().quit()
