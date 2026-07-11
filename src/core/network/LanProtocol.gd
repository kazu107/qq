extends RefCounted
class_name LanProtocol

const PROTOCOL_VERSION: int = 3
const SNAPSHOT_VERSION: int = 2
const DEFAULT_PORT: int = 32475
const DISCOVERY_PORT: int = 32476
const MAX_PLAYERS: int = 2
const MAX_NAME_LENGTH: int = 20
const MAX_DECK_CARDS: int = 16
const MAX_RELICS: int = 4
const MAX_COMMANDS_PER_SECOND: int = 12
const RECONNECT_GRACE_SECONDS: float = 15.0
const CONTENT_PATHS: Array[String] = [
	"res://data/cards.json",
	"res://data/relics.json",
	"res://data/starters.json",
]

static var _cached_content_hash: String = ""


static func build_content_hash() -> String:
	if _cached_content_hash != "":
		return _cached_content_hash
	var parts: Array[String] = [str(PROTOCOL_VERSION)]
	for file_path in CONTENT_PATHS:
		var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			parts.append("missing:%s" % file_path)
			continue
		parts.append(file.get_as_text().sha256_text())
	_cached_content_hash = "\n".join(parts).sha256_text()
	return _cached_content_hash


static func clear_content_hash_cache() -> void:
	_cached_content_hash = ""


static func build_profile(
	player_name: String,
	starter_id: String,
	ready: bool = false,
	reconnect_token: String = ""
) -> Dictionary:
	var resolved_starter_id: String = _resolve_starter_id(starter_id)
	var starter_data: Dictionary = Database.get_starter(resolved_starter_id)
	var run_state: RunState = RunState.from_starter(starter_data, 1)
	var token: String = reconnect_token
	if token == "":
		token = _make_reconnect_token()
	return {
		"protocol_version": PROTOCOL_VERSION,
		"content_hash": build_content_hash(),
		"name": sanitize_player_name(player_name),
		"starter_id": resolved_starter_id,
		"ready": ready,
		"reconnect_token": token,
		"deck": run_state.equipped_cards.duplicate(),
		"card_upgrades": {},
		"relics": [],
	}


static func update_profile_starter(profile: Dictionary, starter_id: String) -> Dictionary:
	var updated: Dictionary = build_profile(
		String(profile.get("name", "Player")),
		starter_id,
		false,
		String(profile.get("reconnect_token", ""))
	)
	return updated


static func validate_profile(raw_profile: Dictionary) -> Dictionary:
	if int(raw_profile.get("protocol_version", -1)) != PROTOCOL_VERSION:
		return _invalid("protocol_mismatch")
	if String(raw_profile.get("content_hash", "")) != build_content_hash():
		return _invalid("content_mismatch")

	var starter_id: String = String(raw_profile.get("starter_id", ""))
	var starter_data: Dictionary = Database.get_starter(starter_id)
	if starter_data.is_empty():
		return _invalid("invalid_starter")

	var deck: Array[String] = _to_string_array(raw_profile.get("deck", []))
	if deck.is_empty() or deck.size() > MAX_DECK_CARDS:
		return _invalid("invalid_deck_size")
	for card_id in deck:
		if Database.get_card(card_id) == null:
			return _invalid("invalid_card")

	var starter_run: RunState = RunState.from_starter(starter_data, 1)
	if RunState.get_total_loadout_cost(deck) > starter_run.loadout_limit:
		return _invalid("loadout_over_limit")

	var upgrades: Dictionary = _sanitize_upgrades(raw_profile.get("card_upgrades", {}), deck)
	var relics: Array[String] = _sanitize_relics(raw_profile.get("relics", []))
	var token: String = String(raw_profile.get("reconnect_token", "")).strip_edges()
	if token.length() < 8 or token.length() > 64:
		return _invalid("invalid_reconnect_token")

	return {
		"valid": true,
		"error": "",
		"profile": {
			"protocol_version": PROTOCOL_VERSION,
			"content_hash": build_content_hash(),
			"name": sanitize_player_name(String(raw_profile.get("name", "Player"))),
			"starter_id": starter_id,
			"ready": bool(raw_profile.get("ready", false)),
			"reconnect_token": token,
			"deck": deck,
			"card_upgrades": upgrades,
			"relics": relics,
		},
	}


static func profile_to_run(profile: Dictionary, seed: int) -> RunState:
	var starter_data: Dictionary = Database.get_starter(String(profile.get("starter_id", "")))
	if starter_data.is_empty():
		return null
	var run_state: RunState = RunState.from_starter(starter_data, seed)
	var deck: Array[String] = _to_string_array(profile.get("deck", []))
	run_state.player_cards = deck.duplicate()
	run_state.equipped_cards = deck.duplicate()
	run_state.card_upgrades = Dictionary(profile.get("card_upgrades", {})).duplicate(true)
	run_state.relics = _to_string_array(profile.get("relics", []))
	run_state.gold = 0
	run_state.map_state = {}
	run_state.arena_mode = false
	run_state.infinite_mode = false
	return run_state


static func build_match_payload(
	host_profile: Dictionary,
	guest_profile: Dictionary,
	seed: int,
	host_peer_id: int,
	guest_peer_id: int
) -> Dictionary:
	var host_run: RunState = profile_to_run(host_profile, seed)
	var guest_run: RunState = profile_to_run(guest_profile, seed)
	if host_run == null or guest_run == null:
		return {}
	return {
		"protocol_version": PROTOCOL_VERSION,
		"content_hash": build_content_hash(),
		"match_id": "%d-%d" % [seed, Time.get_ticks_msec()],
		"seed": seed,
		"player_run": host_run.to_dict(),
		"enemy_run": guest_run.to_dict(),
		"player_name": String(host_profile.get("name", "Host")),
		"enemy_name": String(guest_profile.get("name", "Guest")),
		"peer_sides": {
			str(host_peer_id): "player",
			str(guest_peer_id): "enemy",
		},
	}


static func build_public_profile(profile: Dictionary, peer_id: int, side: String, ping_ms: int = 0) -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": String(profile.get("name", "Player")),
		"starter_id": String(profile.get("starter_id", "")),
		"ready": bool(profile.get("ready", false)),
		"deck_count": Array(profile.get("deck", [])).size(),
		"side": side,
		"ping_ms": maxi(0, ping_ms),
	}


static func validate_runtime_id(side: String, runtime_id: String) -> bool:
	if side != "player" and side != "enemy":
		return false
	if runtime_id.length() < 3 or runtime_id.length() > 48:
		return false
	return runtime_id.begins_with("%s_" % side)


static func sanitize_player_name(value: String) -> String:
	var sanitized: String = value.strip_edges().replace("\n", " ").replace("\r", " ")
	if sanitized == "":
		sanitized = "Player"
	return sanitized.left(MAX_NAME_LENGTH)


static func sanitize_port(value: int) -> int:
	return clampi(value, 1024, 65535)


static func get_lan_addresses() -> Array[String]:
	var addresses: Array[String] = []
	for raw_address in IP.get_local_addresses():
		var address: String = String(raw_address)
		if address.contains(":") or address.begins_with("127.") or address == "0.0.0.0":
			continue
		if not addresses.has(address):
			addresses.append(address)
	addresses.sort()
	return addresses


static func _resolve_starter_id(starter_id: String) -> String:
	if not Database.get_starter(starter_id).is_empty():
		return starter_id
	if not Database.starters.is_empty():
		return String(Database.starters[0].get("id", "balanced"))
	return "balanced"


static func _sanitize_upgrades(value: Variant, deck: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	var raw_upgrades: Dictionary = Dictionary(value)
	for raw_card_id in raw_upgrades.keys():
		var card_id: String = String(raw_card_id)
		if not deck.has(card_id):
			continue
		result[card_id] = clampi(int(raw_upgrades.get(raw_card_id, 0)), 0, CardUpgradeResolver.MAX_TIER)
	return result


static func _sanitize_relics(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for raw_relic_id in Array(value):
		var relic_id: String = String(raw_relic_id)
		if result.size() >= MAX_RELICS:
			break
		if relic_id == "" or result.has(relic_id) or Database.get_relic(relic_id) == null:
			continue
		result.append(relic_id)
	return result


static func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in Array(value):
		result.append(String(item))
	return result


static func _make_reconnect_token() -> String:
	var source: String = "%d:%d:%d" % [Time.get_ticks_usec(), Time.get_unix_time_from_system(), randi()]
	return source.sha256_text().left(24)


static func _invalid(error_code: String) -> Dictionary:
	return {
		"valid": false,
		"error": error_code,
		"profile": {},
	}
