extends RefCounted
class_name BalanceDraft

signal changed

const DRAFT_PATH := "user://balance_lab_draft.json"
const FORMAT := "queuequest-balance-diff-v2"
const LEGACY: Dictionary = {
	"iron_plating": {"pickup_hp": 10}, "tempered_edge": {"pickup_attack": 1},
	"kinetic_boots": {"pickup_speed": 1}, "auxiliary_core": {"pickup_loadout": 2},
	"reactive_barrier": {"starting_shield": 6}, "chrono_shard": {"cast_multiplier": 0.9},
	"salvage_magnet": {"victory_gold": 10}, "repair_nanites": {"victory_heal": 5},
	"war_banner": {"starting_attack": 2}, "aegis_matrix": {"starting_shield": 8},
	"surge_gimbal": {"starting_speed": 1}, "phase_capacitor": {"starting_shield": 12},
	"echo_coil": {"victory_gold": 15}, "paradox_prism": {"cast_multiplier": 0.92, "starting_speed": 1},
	"rift_compass": {"starting_speed": 2}, "entropy_battery": {"victory_heal": 8},
	"omega_crown": {"starting_attack": 3}, "eternity_engine": {"cast_multiplier": 0.85, "starting_shield": 10},
	"titanium_rib": {"pickup_hp": 6}, "loadout_harness": {"pickup_loadout": 3}, "war_cache": {"pickup_gold": 35},
	"signal_lens": {"starting_attack": 1, "cast_multiplier": 0.97}, "pulse_injector": {"starting_speed": 2},
	"barrier_seed": {"starting_shield": 5, "starting_speed": 1}, "stasis_clock": {"cast_multiplier": 0.94},
	"blood_pump": {"starting_attack": 1, "victory_heal": 4}, "scavenger_contract": {"victory_gold": 20},
	"emergency_foam": {"starting_shield": 16}, "overclock_key": {"starting_attack": 2, "starting_speed": 1},
	"chrono_metronome": {"cast_multiplier": 0.88}, "armor_garden": {"pickup_hp": 4, "starting_shield": 4, "victory_heal": 3},
	"bounty_drone": {"starting_speed": 1, "victory_gold": 12}, "prism_furnace": {"starting_attack": 1, "starting_shield": 8, "cast_multiplier": 0.96},
	"archive_compass": {"pickup_loadout": 1, "victory_gold": 8, "victory_heal": 2}
}
const LABELS: Dictionary = {
	"ratio": "ダメージ変換率", "lockout_duration": "再展開待ち時間",
	"regen_power": "リジェネ回復量（3秒ごと）", "regen_max_hp_ratio": "最大HPからの回復割合", "bonus_power": "低HP時の追加回復量", "bonus_if_hp_below_ratio": "低HPの判定割合",
	"secondary": "追加効果量",
	"charges": "反響の獲得枚数",
	"bleed_power": "出血威力（1層・6秒ごと）",
	"loadout_cost": "ロードアウトコスト", "active_slot_cost": "使用スロット", "cast_time": "詠唱時間", "recast_time": "再使用時間", "priority_modifier": "優先度",
	"amount": "効果量", "damage": "ダメージ補正", "shield": "シールド", "heal": "回復", "duration": "持続時間", "delay": "遅延秒数", "haste": "加速秒数", "cooldown": "再使用短縮",
	"recast_reduction": "再使用短縮", "timing": "時間操作補正", "attack_mod": "攻撃補正", "speed_mod": "速度補正", "empower": "強化量",
	"count": "投入枚数", "multiplier": "倍率", "bonus_amount": "追加効果量", "max_count": "最大枚数", "hp_ratio_step": "HP割合の刻み", "count_per_step": "段階ごとの枚数",
	"every": "発動に必要な回数", "required_count": "必要数", "max_per_battle": "戦闘中の上限回数", "internal_cooldown": "発動間隔", "effective_ratio": "変換率", "max_amount": "効果量上限",
	"window_min": "最小時間差", "window_max": "最大時間差", "priority_bonus": "優先度加算", "required_empty_timeline_seconds": "空の待機秒数",
	"cast_multiplier": "詠唱時間倍率", "recast_multiplier": "再使用時間倍率", "max_per_instance": "カードごとの上限", "thresholds": "発動時刻",
	"fallback_delay": "中断できない時の遅延", "duration_multiplier": "持続時間倍率", "max_extension": "最大延長時間", "source_recast_penalty": "再使用の追加秒数",
	"next_attack_damage": "次の攻撃への加算", "amount_per_second": "1秒あたりの効果量", "interrupted_amount": "中断時の効果量",
	"seconds_per_charge": "充填に必要な秒数", "haste_per_charge": "充填1個の短縮秒数", "max_charges": "充填数上限", "minimum_slot_cost": "対象スロット数の下限", "minimum_cast": "最低詠唱時間",
	"reserved_slots": "予約スロット数", "interrupt_cast_multiplier": "中断カードの詠唱倍率", "max_per_source": "投入元ごとの回数上限", "required_heat": "必要な熱量", "max_per_card": "カードごとの上限",
	"refund_ratio": "返却率", "minimum_shield": "必要シールド", "decay_interval": "シールド減衰間隔", "shield_cost_bonus": "追加シールド消費",
	"low_hp_ratio": "低HP判定割合", "reset_hp_ratio": "高HP判定割合", "low_hp_cast_multiplier": "低HP時の詠唱倍率", "high_hp_effect_multiplier": "高HP時の効果倍率",
	"haste_amount": "加速秒数", "fallback_recast_reduction": "代わりの再使用短縮", "added_cast_per_bonus": "強化に必要な遅延秒数", "amount_per_step": "段階ごとの強化量",
	"stop_duration": "停止時間", "status_duration_reduction": "状態を消費する秒数", "defer_duration": "状態を保留する秒数", "remaining_duration_ratio": "残り時間の移植率", "max_statuses_per_battle": "移植数の上限",
	"bleed_final_ticks": "出血終了時の追加回数", "other_status_delay": "他の状態の遅延秒数", "max_total_discount": "合計割引の上限", "discount_after_first": "2枚目以降の割引", "minimum_equipped": "必要装備枚数",
	"max_overflow": "超過コスト上限", "status_duration_per_overflow": "超過1あたりの状態時間", "unused_capacity_per_slot": "追加スロットに必要な空き", "max_slots": "追加スロット上限",
	"source_cost": "発動カードのコスト", "target_cost_min": "対象コスト下限", "target_cost_max": "対象コスト上限", "window": "判定する時間幅", "amount_per_grade": "グレード差ごとの効果",
	"cast_reduction": "詠唱の短縮秒数", "effect_multiplier": "効果倍率", "minimum_post_resolve_cooldown": "発動後の最低再使用時間", "shield_to_damage_ratio": "シールドからダメージへの変換率", "damage_to_shield_ratio": "ダメージからシールドへの変換率", "cast_penalty": "詠唱の追加秒数", "slot_cost": "使用スロット", "main_effect_cap": "主効果の上限",
	"pickup_hp": "入手時の最大HP・回復", "pickup_attack": "入手時の攻撃", "pickup_speed": "入手時の速度", "pickup_loadout": "入手時のコスト上限", "pickup_gold": "入手時のゴールド",
	"starting_shield": "開始時のシールド", "starting_attack": "開始時の攻撃", "starting_speed": "開始時の速度", "victory_gold": "勝利時のゴールド", "victory_heal": "勝利時の回復"
}
static var _catalog: Dictionary = {}
static var _fields: Dictionary = {}
static var _source_hash: String = ""
static var _consumers: Dictionary = {}
static var _grade_origins: Dictionary = {}
var edits: Dictionary = {}
var error_text: String = ""
var _backup_failed: bool = false


static func warm_catalog() -> void:
	if not _catalog.is_empty(): return
	_catalog = {"card": {}, "relic": {}}
	var signature: String = ""
	var consumers_text: String = FileAccess.get_file_as_string("res://data/balance_lab_consumers.json").replace("\r\n", "\n")
	_consumers = JSON.parse_string(consumers_text)
	signature += consumers_text
	for pair: Array in [["card", Database.CARDS_PATH], ["card", Database.BOSS_CARDS_PATH], ["relic", Database.RELICS_PATH]]:
		var source: String = FileAccess.get_file_as_string(pair[1]).replace("\r\n", "\n")
		signature += source
		for row: Dictionary in JSON.parse_string(source):
			var data: Dictionary = row.duplicate(true)
			if pair[0] == "relic" and LEGACY.has(data["id"]): data["parameters"] = LEGACY[data["id"]].duplicate(true)
			_catalog[pair[0]][data["id"]] = data
	_source_hash = (signature + JSON.stringify(LEGACY)).sha256_text()


static func ids(kind: String) -> Array:
	warm_catalog()
	return Dictionary(_catalog.get(kind, {})).keys()


static func original(kind: String, id: String) -> Dictionary:
	warm_catalog()
	var result: Dictionary = Dictionary(Dictionary(_catalog.get(kind, {})).get(id, {})).duplicate(true)
	if kind == "card" and not result.is_empty():
		if not _grade_origins.has(id):
			var grades: Dictionary = {}
			var source: CardDef = CardDef.from_dict(result)
			for tier: int in range(1, CardUpgradeResolver.MAX_TIER + 1):
				var resolved: Dictionary = CardUpgradeResolver.build_card_at_tier(id, tier, source).to_dict()
				var numbers: Dictionary = {}
				for key: String in ["loadout_cost", "active_slot_cost", "cast_time", "recast_time", "priority_modifier", "effects"]: numbers[key] = _numeric_tree(resolved[key])
				grades[str(tier)] = numbers
			_grade_origins[id] = grades
		result["grade_overrides"] = _grade_origins[id].duplicate(true)
	return result


static func _numeric_tree(value: Variant) -> Variant:
	if value is float or value is int: return value
	var result: Dictionary = {}
	if value is Array:
		for index: int in value.size():
			var entry: Variant = _numeric_tree(value[index])
			if entry != null and (entry is not Dictionary or not entry.is_empty()): result[str(index)] = entry
	elif value is Dictionary:
		for key: String in value:
			var entry: Variant = _numeric_tree(value[key])
			if entry != null and (entry is not Dictionary or not entry.is_empty()): result[key] = entry
	else: return null
	return result


func data(kind: String, id: String) -> Dictionary:
	warm_catalog()
	var result: Dictionary = Dictionary(Dictionary(_catalog.get(kind, {})).get(id, {})).duplicate(true)
	for path: String in Dictionary(edits.get(kind + ":" + id, {})):
		_write(result, path, edits[kind + ":" + id][path])
	return result


func value(kind: String, id: String, path: String) -> float:
	if kind == "card" and path.begins_with("grade_overrides."):
		var parts: PackedStringArray = path.split(".")
		return float(read(card(id, int(parts[1])).to_dict(), ".".join(parts.slice(2))))
	return float(read(data(kind, id), path))


static func fields(kind: String, id: String) -> Array[Dictionary]:
	var key: String = kind + ":" + id + ":" + Localization.get_language()
	if _fields.has(key): return _fields[key].duplicate(true)
	var result: Array[Dictionary] = []
	var source: Dictionary = original(kind, id)
	for root: String in (["loadout_cost", "active_slot_cost", "cast_time", "recast_time", "priority_modifier", "effects", "upgrade_profile", "grade_overrides"] if kind == "card" else ["parameters", "effects"]):
		if source.has(root): _walk(source[root], root, result, source, kind)
	_fields[key] = result
	return result.duplicate(true)


static func fields_for_grade(kind: String, id: String, tier: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for field: Dictionary in fields(kind, id):
		if kind == "relic" or int(field["grade"]) == tier: result.append(field)
	return result


static func _walk(value: Variant, path: String, result: Array[Dictionary], source: Dictionary, kind: String) -> void:
	if value is Dictionary:
		for key: String in value: _walk(value[key], path + "." + key, result, source, kind)
	elif value is Array:
		for index: int in value.size(): _walk(value[index], path + "." + str(index), result, source, kind)
	elif value is float or value is int:
		var parts: PackedStringArray = path.split(".")
		var relative: String = path
		var grade: int = 0
		if path.begins_with("grade_overrides."):
			grade = int(parts[1]); relative = ".".join(parts.slice(2)); parts = relative.split(".")
		elif path.begins_with("upgrade_profile."): grade = -1
		var key: String = parts[-2] if parts[-1].is_valid_int() else parts[-1]
		var floating: bool = key.contains("time") or key.contains("duration") or key.contains("ratio") or key.contains("multiplier") or key.contains("delay") or key.contains("haste") or key.contains("interval") or key.contains("window") or key.contains("seconds") or key.contains("recast") or key.contains("cast") or key.contains("priority") or key in ["timing", "effective_ratio", "amount_per_grade", "added_cast_per_bonus"]
		if key == "amount" and relative.begins_with("effects."):
			var effect: Dictionary = source["effects"][int(parts[1])]
			floating = String(effect.get("type", "")) in ["delay_enemy_active_card", "haste_own_active_card", "reduce_recast", "empower_card", "reduce_source_recast", "haste_ally_when_enemy_delayed", "bank_delay_as_recast", "haste_at_thresholds"] or not is_equal_approx(float(value), roundf(float(value)))
			if effect.get("type") == "reserve_next_card": floating = effect.get("reservation") not in ["focus", "growth", "recoil", "heavy_commit", "chain"]
			if effect.get("type", "") == "empower_card" and effect.get("stat", "") in ["grade", "tier"]: floating = false
		floating = floating or key.contains("second") or key in ["thresholds", "max_extension", "max_per_instance", "minimum_cast", "window_min", "window_max"] or not is_equal_approx(float(value), roundf(float(value)))
		var minimum: float = 0.0
		if path.begins_with("upgrade_profile.") or key in ["priority_modifier", "amount"]: minimum = -10000.0 if path.begins_with("upgrade_profile.") or key == "priority_modifier" or source.get("id", "") != "" and relative.begins_with("effects.") and String(source["effects"][int(parts[1])].get("type", "")) in ["modify_attack", "modify_speed", "empower_card"] else 0.0
		if key in ["every", "required_count", "seconds_per_charge", "added_cast_per_bonus", "unused_capacity_per_slot", "decay_per_token", "shield_per_gold"]: minimum = 0.01 if floating else 1.0
		var maximum: float = 1.0 if key.ends_with("ratio") else 10000.0
		if relative.begins_with("effects.") and source["effects"][int(parts[1])].get("type") == "damage_conversion":
			if key == "ratio": minimum = 0; maximum = 1
			if key == "duration": maximum = DamageConversionRules.MAX_DURATION
			if key == "lockout_duration": minimum = DamageConversionRules.MIN_LOCKOUT; maximum = 12
		if key == "amount" and relative.begins_with("effects.") and source["effects"][int(parts[1])].get("type") == "reserve_next_card":
			var reservation_kind: String = source["effects"][int(parts[1])].get("reservation", "")
			if reservation_kind in ["reload", "weaken", "shield_jam", "heal_jam", "swift_commit"]: minimum = 0.1; maximum = 1
			if reservation_kind in ["siphon", "mirror"]: maximum = 1
			if reservation_kind == "shield": minimum = 1; maximum = 3
			if reservation_kind == "heavy_commit": minimum = 1; maximum = 2
			if reservation_kind == "chain": minimum = 1; maximum = 1
		if key == "charges" and relative.begins_with("effects.") and source["effects"][int(parts[1])].get("type", "") == "repeat_next_card": minimum = 1; maximum = RepeatRules.MAX_CHARGES
		if key == "bleed_power" and relative.begins_with("effects."): minimum = 1.0
		if key == "regen_power" and relative.begins_with("effects."): minimum = 1.0
		minimum = minf(minimum, float(value))
		maximum = maxf(maximum, float(value))
		var label: String = String(LABELS.get(key, key.replace("_", " ")))
		if relative.begins_with("effects."): label = "%s %d / %s" % ["効果" if Localization.get_language() == "ja" else "Effect", int(parts[1]) + 1, label]
		if path.begins_with("upgrade_profile."): label = "G%d / %s" % [int(parts[-1]), label]
		elif grade > 0: label = "G%d / %s" % [grade, label]
		var combat: bool = kind == "card" or path.begins_with("parameters.") and not key.begins_with("victory_") or Array(_consumers.get(source["id"], [])).has(key)
		result.append({"path": path, "label": label if Localization.get_language() == "ja" else relative, "before": float(value), "integer": not floating, "min": minimum, "max": maximum, "combat": combat, "grade": grade})


func set_value(kind: String, id: String, path: String, value: float) -> bool:
	if not is_finite(value): return false
	for field: Dictionary in fields(kind, id):
		if field["path"] != path: continue
		if value < float(field["min"]) or value > float(field["max"]) or bool(field["integer"]) and not is_equal_approx(value, roundf(value)): return false
		var key: String = kind + ":" + id
		var row: Dictionary = Dictionary(edits.get(key, {}))
		var inherited: float = float(field["before"])
		if path.begins_with("grade_overrides."):
			var previous: Variant = row.get(path)
			row.erase(path)
			if row.is_empty(): edits.erase(key)
			else: edits[key] = row
			inherited = self.value(kind, id, path)
			if previous != null: row[path] = previous
		if is_equal_approx(value, inherited): row.erase(path)
		else: row[path] = roundi(value) if field["integer"] else value
		if row.is_empty(): edits.erase(key)
		else: edits[key] = row
		changed.emit()
		return true
	return false


func reset(kind: String = "", id: String = "") -> void:
	if kind == "": edits.clear()
	else: edits.erase(kind + ":" + id)
	changed.emit()


func reset_grade(id: String, tier: int) -> void:
	var key: String = "card:" + id
	var row: Dictionary = Dictionary(edits.get(key, {}))
	for field: Dictionary in fields("card", id):
		if int(field["grade"]) == tier or String(field["path"]).begins_with("upgrade_profile.") and String(field["path"]).get_slice(".", 2) == str(tier): row.erase(field["path"])
	if row.is_empty(): edits.erase(key)
	else: edits[key] = row
	changed.emit()


func changes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys: Array = edits.keys()
	keys.sort()
	for key: String in keys:
		var parts: PackedStringArray = key.split(":")
		for field: Dictionary in fields(parts[0], parts[1]):
			if edits[key].has(field["path"]): result.append({"kind": parts[0], "id": parts[1], "path": field["path"], "before": field["before"], "after": edits[key][field["path"]]})
	return result


func document() -> Dictionary:
	warm_catalog()
	return {"format": FORMAT, "game_version": GameVersion.get_current_version(), "source_hash": _source_hash, "changes": changes()}


func import_document(document_data: Dictionary) -> bool:
	warm_catalog()
	if document_data.get("format", "") != FORMAT or document_data.get("source_hash", "") != _source_hash or document_data.get("changes") is not Array: return false
	var candidate: BalanceDraft = BalanceDraft.new()
	for raw: Variant in document_data["changes"]:
		if raw is not Dictionary or raw.get("after") is not float and raw.get("after") is not int or raw.get("before") is not float and raw.get("before") is not int: return false
		if not candidate.set_value(String(raw.get("kind", "")), String(raw.get("id", "")), String(raw.get("path", "")), float(raw["after"])): return false
		var source: Dictionary = original(String(raw["kind"]), String(raw["id"]))
		if not is_equal_approx(float(read(source, raw["path"])), float(raw.get("before", NAN))): return false
	edits = candidate.edits.duplicate(true)
	changed.emit()
	return true


func save_draft() -> bool:
	if _backup_failed: return false
	var file: FileAccess = FileAccess.open(DRAFT_PATH + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(document(), "\t"))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(DRAFT_PATH + ".tmp", DRAFT_PATH) == OK


func load_draft() -> bool:
	if not FileAccess.file_exists(DRAFT_PATH): return true
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(DRAFT_PATH))
	var saved: Dictionary = raw if raw is Dictionary else {}
	if import_document(saved): return true
	if saved.get("format", "") == "queuequest-balance-diff-v1":
		var migrated: Dictionary = saved.duplicate(true)
		migrated["format"] = FORMAT; migrated["source_hash"] = _source_hash
		var candidate: BalanceDraft = BalanceDraft.new()
		if candidate.import_document(migrated):
			var legacy_path: String = DRAFT_PATH + ".v1-backup-%d.json" % int(Time.get_unix_time_from_system())
			if DirAccess.copy_absolute(DRAFT_PATH, legacy_path) == OK:
				edits = candidate.edits.duplicate(true)
				error_text = "旧下書きの各変更前数値を照合して移行しました。元ファイルも退避済みです。" if Localization.get_language() == "ja" else "Migrated the legacy draft after checking every original value; the source was backed up."
				return true
	var backup_path: String = DRAFT_PATH + ".incompatible-%d.json" % int(Time.get_unix_time_from_system())
	_backup_failed = DirAccess.copy_absolute(DRAFT_PATH, backup_path) != OK
	error_text = "旧下書きは適用せず別ファイルに退避しました。" if Localization.get_language() == "ja" else "An incompatible draft was retained in a separate backup without applying it."
	if _backup_failed: error_text = "Draft backup failed; autosave is blocked to preserve the old file."
	return false


func frozen() -> BalanceDraft:
	var result: BalanceDraft = BalanceDraft.new()
	result.edits = edits.duplicate(true)
	return result


func batch_candidate(kind: String, target_ids: Array[String], path: String, operation: int, amount: float) -> BalanceDraft:
	var candidate: BalanceDraft = frozen()
	for id: String in target_ids:
		for field: Dictionary in fields(kind, id):
			if field["path"] != path: continue
			var old: float = self.value(kind, id, path)
			var value: float = old * amount if operation == 0 else (old + amount if operation == 1 else amount)
			if field["integer"]: value = roundf(value)
			else: value = snappedf(value, 0.001)
			candidate.set_value(kind, id, path, value)
	return candidate


func card(id: String, tier: int = 0) -> CardDef:
	var result: CardDef = source_card(id)
	if result.id == "": return null
	return CardUpgradeResolver.build_card_at_tier(id, tier, result)


func source_card(id: String) -> CardDef:
	var result: CardDef = CardDef.from_dict(data("card", id))
	if result.id != "": result.name = Database.get_card(id).name
	return result


func relic_value(id: String, key: String, fallback: float) -> float:
	var row: Dictionary = Dictionary(edits.get("relic:" + id, {}))
	for path: String in row:
		if path == "parameters." + key or path == "effects.0." + key: return float(row[path])
	return fallback


static func read(source: Dictionary, path: String) -> Variant:
	var current: Variant = source
	for key: String in path.split("."):
		current = current[int(key)] if current is Array else current.get(key)
	return current


static func _write(source: Dictionary, path: String, value: Variant) -> void:
	var parts: PackedStringArray = path.split(".")
	var current: Variant = source
	for index: int in parts.size() - 1:
		if current is Array: current = current[int(parts[index])]
		else:
			if not current.has(parts[index]): current[parts[index]] = {}
			current = current[parts[index]]
	if current is Array: current[int(parts[-1])] = value
	else: current[parts[-1]] = value
