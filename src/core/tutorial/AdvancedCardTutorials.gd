extends RefCounted
class_name AdvancedCardTutorials

const IDS: Array[String] = ["prepared_combos", "hostile_reservations", "regeneration", "damage_conversion"]
const CATALOG: Array[Dictionary] = [
	{"id":"prepared_combos", "title_key":"tutorial.prepared.title", "title_fallback":"Prepared Card Combos",
	 "description_key":"tutorial.prepared.description", "description_fallback":"Save an attack boost, then combine it with Echo for two effect resolutions.",
	 "duration_key":"tutorial.prepared.duration", "duration_fallback":"About 3 minutes",
	 "difficulty_key":"tutorial.difficulty.advanced", "difficulty_fallback":"Advanced",
	 "cards":["reserve_focus", "guard", "echo_cast", "quick_slash"], "enemy_id":"scout", "enemy_ai":false,
	 "training":{"enemy_hp":240}},
	{"id":"hostile_reservations", "title_key":"tutorial.hostile.title", "title_fallback":"Disrupt the Next Card",
	 "description_key":"tutorial.hostile.description", "description_fallback":"Weaken the next enemy attack and extend its recast, then compare an unmodified attack.",
	 "duration_key":"tutorial.hostile.duration", "duration_fallback":"About 3 minutes",
	 "difficulty_key":"tutorial.difficulty.advanced", "difficulty_fallback":"Advanced",
	 "cards":["reserve_weaken", "reserve_recast_jam"], "enemy_id":"scout", "enemy_ai":false,
	 "training":{"enemy_hp":240, "enemy_attack":12}},
	{"id":"regeneration", "title_key":"tutorial.regeneration.title", "title_fallback":"Regeneration Layers",
	 "description_key":"tutorial.regeneration.description", "description_fallback":"Watch periodic healing, combine three regeneration layers, and observe them expire.",
	 "duration_key":"tutorial.regeneration.duration", "duration_fallback":"About 3 minutes",
	 "difficulty_key":"tutorial.difficulty.advanced", "difficulty_fallback":"Advanced",
	 "cards":["regen_patch", "regen_salve", "regen_burst"], "enemy_id":"scout", "enemy_ai":false,
	 "training":{"player_hp":20, "enemy_hp":240}},
	{"id":"damage_conversion", "title_key":"tutorial.conversion.title", "title_fallback":"Damage Conversion",
	 "description_key":"tutorial.conversion.description", "description_fallback":"Convert real attacks into HP or shield, respect the lockout, and test the fatigue exception.",
	 "duration_key":"tutorial.conversion.duration", "duration_fallback":"About 4 minutes",
	 "difficulty_key":"tutorial.difficulty.advanced", "difficulty_fallback":"Advanced",
	 "cards":["life_conversion", "barrier_conversion", "life_conversion"], "enemy_id":"scout", "enemy_ai":false,
	 "training":{"player_hp":28, "enemy_hp":240, "enemy_attack":12}},
]


static func _s(key: String, mode: String, progress: int, total: int, title: String, body: String, target: String, extra: Dictionary = {}) -> Dictionary:
	var step: Dictionary = {"key":key, "mode":mode, "progress":progress, "total":total, "title":title, "body":body, "target":target, "timeout":45.0}
	step.merge(extra, true)
	return step


static func build_steps(id: String) -> Array[Dictionary]:
	match id:
		"prepared_combos": return _prepared()
		"hostile_reservations": return _hostile()
		"regeneration": return _regeneration()
		"damage_conversion": return _conversion()
	return []


static func _prepared() -> Array[Dictionary]:
	return [
		_s("prepared_intro", "continue", 1, 7, "Prepare before attacking", "Practice uses a durable target with its AI disabled. First store a boost with Focused Command.", "card:reserve_focus"),
		_s("prepared_focus", "queue_card", 2, 7, "Store an attack boost", "Queue Focused Command. The boost starts when it resolves, not when registered.", "card:reserve_focus", {"card_id":"reserve_focus"}),
		_s("prepared_wait_focus", "wait_event", 2, 7, "Activate the boost", "Watch Focused Command reach 0 seconds.", "timeline", {"event_type":"resolve_card", "event_card_id":"reserve_focus", "event_side":"player"}),
		_s("prepared_stored", "continue", 3, 7, "A boost is waiting", "The boost icon appears on your status plate. It waits for the next attack, not the next arbitrary card. Hover to inspect it.", "player_status_row"),
		_s("prepared_guard", "queue_card", 3, 7, "A shield card does not spend it", "Queue Guard to test the attack-only condition.", "card:guard", {"card_id":"guard"}),
		_s("prepared_wait_guard", "wait_event", 3, 7, "Resolve Guard", "Guard grants shield. The stored attack boost must remain.", "timeline", {"event_type":"resolve_card", "event_card_id":"guard", "event_side":"player"}),
		_s("prepared_kept", "continue", 4, 7, "The attack boost remains", "The boost survived Guard. Next, prepare Echo; setup cards also do not consume this boost.", "player_status_row"),
		_s("prepared_echo", "queue_card", 4, 7, "Prepare Echo", "Queue Echo. It arms two effect resolutions for the next eligible manually played card.", "card:echo_cast", {"card_id":"echo_cast"}),
		_s("prepared_wait_echo", "wait_event", 4, 7, "Arm Echo", "Wait until Echo resolves before playing the attack.", "timeline", {"event_type":"resolve_card", "event_card_id":"echo_cast", "event_side":"player"}),
		_s("prepared_both", "continue", 5, 7, "Both preparations are active", "Your status row now shows the boost and Echo. Quick Slash's tooltip reflects the boost. Echo repeats effects without registering a second timeline card.", "player_status_row"),
		_s("prepared_attack", "queue_card", 6, 7, "Release the combo", "Queue Quick Slash. Its attack boost applies to both effect resolutions.", "card:quick_slash", {"card_id":"quick_slash"}),
		_s("prepared_wait_attack", "wait_event", 6, 7, "Watch two resolutions", "Quick Slash activates once and applies its effects twice. Both preparations are consumed; slots and recast are paid only once.", "timeline", {"event_type":"resolve_card", "event_card_id":"quick_slash", "event_side":"player", "result_minimums":{"effect_repeats":2}}),
		_s("prepared_result", "continue", 7, 7, "Check the result", "The target lost HP twice. Both preparation icons disappeared. You can inspect the attack and the combat log before finishing.", "enemy_status"),
		_s("prepared_complete", "complete", 7, 7, "Prepared combo complete", "Match a preparation to the right card type and wait for it to activate. Echo repeats effects, not the whole registration.", ""),
	]


static func _hostile() -> Array[Dictionary]:
	return [
		_s("hostile_intro", "continue", 1, 6, "Prepare a trap for the next card", "This opponent attacks only when the guide queues a card. Compare two identical attacks, first with reservations and then without them.", "enemy_status"),
		_s("hostile_weaken", "queue_card", 2, 6, "Weaken the next attack", "Queue Weakening Tag. It applies to the next eligible attack that resolves, not simply the first card registered.", "card:reserve_weaken", {"card_id":"reserve_weaken"}),
		_s("hostile_wait_weaken", "wait_event", 2, 6, "Apply the tag", "Wait for Weakening Tag to resolve.", "timeline", {"event_type":"resolve_card", "event_card_id":"reserve_weaken"}),
		_s("hostile_recast", "queue_card", 3, 6, "Add a recast penalty", "Queue Recast Jammer. Different reservation types can affect the same next card.", "card:reserve_recast_jam", {"card_id":"reserve_recast_jam"}),
		_s("hostile_wait_recast", "wait_event", 3, 6, "Apply the second reservation", "Wait until both reservations are on the opponent.", "timeline", {"event_type":"resolve_card", "event_card_id":"reserve_recast_jam"}),
		_s("hostile_armed", "continue", 4, 6, "Two reservations are ready", "The enemy status row shows both reservations. Hover to inspect them, then continue to queue an enemy Quick Slash.", "enemy_status_row"),
		_s("hostile_attack", "continue", 4, 6, "Watch the affected attack", "Enemy Quick Slash is queued. Its damage is reduced and its recast will be longer. Continue to run time.", "timeline", {"action":"queue_enemy:quick_slash"}),
		_s("hostile_wait_attack", "wait_event", 4, 6, "Resolve the affected attack", "The attack consumes both matching reservations when it resolves.", "timeline", {"event_type":"resolve_card", "event_card_id":"quick_slash", "event_side":"enemy"}),
		_s("hostile_result", "continue", 5, 6, "Check the longer cooldown", "Inspect the used enemy card's countdown. Both reservation icons are gone. Next, compare the opponent's other copy of Quick Slash.", "enemy_card:quick_slash"),
		_s("hostile_normal", "continue", 5, 6, "An unmodified copy", "A second Quick Slash is queued with no reservations. Continue and compare the HP loss and cooldown.", "timeline", {"action":"queue_enemy:quick_slash"}),
		_s("hostile_wait_normal", "wait_event", 5, 6, "Resolve the normal attack", "This copy uses its normal damage and recast.", "timeline", {"event_type":"resolve_card", "event_card_id":"quick_slash", "event_side":"enemy"}),
		_s("hostile_complete", "complete", 6, 6, "Next-card disruption complete", "The first attack dealt less damage and received a longer recast. The second was unaffected: reservations are consumed, not permanent debuffs.", ""),
	]


static func _regeneration() -> Array[Dictionary]:
	return [
		_s("regeneration_intro", "continue", 1, 7, "Heal over time", "Your training character starts wounded. The opponent will not attack. Regeneration heals every 3 seconds while its layers remain active.", "player_status"),
		_s("regeneration_patch", "queue_card", 2, 7, "Apply the first layer", "Queue Nano Regeneration. Unlike direct healing, its HP recovery waits for a regeneration tick.", "card:regen_patch", {"card_id":"regen_patch"}),
		_s("regeneration_wait_patch", "wait_event", 2, 7, "Activate regeneration", "Wait for the card to resolve and create its status icon.", "timeline", {"event_type":"resolve_card", "event_card_id":"regen_patch"}),
		_s("regeneration_status", "continue", 3, 7, "Read power and remaining time", "Hover the regeneration icon. Its duration is running only when time is resumed. Continue to observe the first real healing tick.", "player_status_row"),
		_s("regeneration_first_tick", "wait_event", 3, 7, "Wait for periodic healing", "Watch the HP bar increase without playing another card.", "player_status", {"event_type":"status_heal", "event_side":"player", "result_minimums":{"amount":1}}),
		_s("regeneration_salve", "queue_card", 4, 7, "Mix immediate and periodic healing", "Queue First Aid Gel. It heals immediately and adds a separate regeneration layer.", "card:regen_salve", {"card_id":"regen_salve"}),
		_s("regeneration_wait_salve", "wait_event", 4, 7, "Add the second layer", "The immediate heal and the ongoing layer are distinct effects.", "timeline", {"event_type":"resolve_card", "event_card_id":"regen_salve"}),
		_s("regeneration_burst", "queue_card", 5, 7, "Add a short, powerful layer", "Queue Focused Renewal to reach three independently timed layers.", "card:regen_burst", {"card_id":"regen_burst"}),
		_s("regeneration_wait_burst", "wait_event", 5, 7, "Reach three layers", "The existing layers keep their own remaining durations.", "timeline", {"event_type":"resolve_card", "event_card_id":"regen_burst"}),
		_s("regeneration_layers", "continue", 6, 7, "Three layers contribute together", "Hover regeneration to inspect all three layers. Tick healing combines their active powers. At most three layers are kept; a new fourth layer replaces the shortest remaining layer.", "player_status_row"),
		_s("regeneration_combined_tick", "wait_event", 6, 7, "Observe a combined tick", "Resume time to see multiple layers heal on the same tick.", "player_status", {"event_type":"status_heal", "event_side":"player", "result_minimums":{"amount":3}}),
		_s("regeneration_expiration", "continue", 7, 7, "Duration is not permanent power", "Continue and watch the layers expire. Their healing contribution ends when their own time runs out.", "player_status_row"),
		_s("regeneration_wait_expiration", "wait_condition", 7, 7, "Observe expiration", "Watch the remaining seconds and HP. The guide waits until all regeneration layers have ended.", "player_status_row", {"condition":"statuses_clear", "statuses":["regen"]}),
		_s("regeneration_complete", "complete", 7, 7, "Regeneration lesson complete", "You observed delayed healing, immediate healing, three combined layers and their expiration. Recovery never exceeds maximum HP.", ""),
	]


static func _conversion() -> Array[Dictionary]:
	return [
		_s("conversion_intro", "continue", 1, 9, "Turn an attack into a resource", "The character starts wounded. Two copies of Life Conversion are supplied for the two tests. Only the guide queues enemy attacks.", "card:life_conversion"),
		_s("conversion_life", "queue_card", 2, 9, "Prepare Life Conversion", "Queue Life Conversion. Protection starts on activation, so it must finish before the incoming attack.", "card:life_conversion", {"card_id":"life_conversion"}),
		_s("conversion_wait_life", "wait_event", 2, 9, "Activate the field", "Wait until the conversion status appears.", "timeline", {"event_type":"resolve_card", "event_card_id":"life_conversion"}),
		_s("conversion_life_armed", "continue", 3, 9, "The field is active", "Hover the conversion icon for the current percentage and duration. Continue to queue one enemy attack while protection is active.", "player_status_row"),
		_s("conversion_life_attack", "wait_event", 3, 9, "Convert damage to HP", "The guide queued Quick Slash. Its combat damage will be prevented and part becomes HP, without consuming shield.", "timeline", {"action":"queue_enemy:quick_slash", "event_type":"resolve_card", "event_card_id":"quick_slash", "event_side":"enemy", "result_minimums":{"damage_prevented":1}, "hp_direction":"increase"}),
		_s("conversion_life_result", "continue", 4, 9, "HP increased instead of decreasing", "Check your HP. A higher Grade improves the conversion percentage, not immunity to fatigue. Continue to let this field end and wait out its lockout.", "player_status"),
		_s("conversion_wait_lockout", "wait_condition", 4, 9, "Wait for redeployment", "The field expires, then its redeployment lockout runs. Shield conversion is tested only after both statuses have cleared.", "player_status_row", {"condition":"statuses_clear", "statuses":["damage_conversion", "conversion_lockout"]}),
		_s("conversion_barrier", "queue_card", 5, 9, "Prepare Barrier Conversion", "Queue Barrier Conversion after the lockout. This field converts prevented damage into shield instead of HP.", "card:barrier_conversion", {"card_id":"barrier_conversion"}),
		_s("conversion_wait_barrier", "wait_event", 5, 9, "Activate shield conversion", "Wait for Barrier Conversion to activate.", "timeline", {"event_type":"resolve_card", "event_card_id":"barrier_conversion"}),
		_s("conversion_barrier_armed", "continue", 6, 9, "Test another enemy attack", "Continue to queue the opponent's other Quick Slash while this field is active.", "player_status_row"),
		_s("conversion_barrier_attack", "wait_event", 6, 9, "Convert damage to shield", "The attack is prevented. Watch the shield value increase instead of losing HP.", "timeline", {"action":"queue_enemy:quick_slash", "event_type":"resolve_card", "event_card_id":"quick_slash", "event_side":"enemy", "result_minimums":{"damage_prevented":1}, "shield_direction":"increase"}),
		_s("conversion_barrier_result", "continue", 7, 9, "Shield was gained", "Conversion produced shield. Shield still decays normally. Continue to finish this field and its lockout before testing the fatigue exception.", "player_shield"),
		_s("conversion_wait_second_lockout", "wait_condition", 7, 9, "Prepare the exception test", "Waiting for both the field and the redeployment lockout to clear.", "player_status_row", {"condition":"statuses_clear", "statuses":["damage_conversion", "conversion_lockout"]}),
		_s("conversion_fatigue_intro", "continue", 8, 9, "Fatigue is not converted", "The guide will queue one real fatigue card, then pause before it activates. Use the second Life Conversion to test the exception while protection is definitely active.", "timeline"),
		_s("conversion_wait_fatigue_queue", "wait_condition", 8, 9, "Queue fatigue", "The neutral card uses its normal 5-second cast; neither its schedule nor its damage is shortened for this test.", "timeline", {"action":"debug_fatigue", "condition":"fatigue_queued"}),
		_s("conversion_fatigue_approach", "wait_condition", 8, 9, "Wait for the right timing", "The guide pauses with about 3 seconds remaining so Life Conversion can resolve safely before fatigue.", "timeline", {"condition":"active_card_remaining", "side":"environment", "card_id":"environment_fatigue", "maximum":3.0}),
		_s("conversion_second_life", "queue_card", 8, 9, "Use the second Life Conversion", "Queue the ready copy. Its protection will be active when fatigue reaches 0 seconds.", "card:life_conversion", {"card_id":"life_conversion"}),
		_s("conversion_wait_second_life", "wait_event", 8, 9, "Activate protection again", "Watch Life Conversion activate before the neutral card.", "timeline", {"event_type":"resolve_card", "event_card_id":"life_conversion"}),
		_s("conversion_exception_ready", "continue", 9, 9, "Protection is active; fatigue is next", "Confirm the conversion icon, then continue. Fatigue bypasses conversion; ordinary shield can still absorb fatigue.", "player_status_row"),
		_s("conversion_wait_fatigue", "wait_event", 9, 9, "Observe the exception", "Watch the real fatigue card activate while conversion is still active.", "timeline", {"event_type":"fatigue_card", "event_card_id":"environment_fatigue"}),
		_s("conversion_complete", "complete", 9, 9, "Damage conversion complete", "Attacks were prevented and converted to HP or shield. Fatigue still caused damage during the active field. HP costs are also excluded, and fields cannot be extended by recasting during their duration.", ""),
	]
