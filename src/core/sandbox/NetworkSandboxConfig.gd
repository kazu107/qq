extends RefCounted
class_name NetworkSandboxConfig

const MAX_CARDS: int = 16
const MAX_RELICS: int = 8
const MAX_ACTIVE: int = 32


static func rules(raw: Dictionary) -> Dictionary:
	var normalized: Dictionary = SandboxConfig.normalize({"rules":raw})["rules"]
	for key: String in ["player_ai","enemy_ai","boss_passive"]: normalized[key]=false
	normalized["power"]=0
	normalized["edit_opponents"]=raw.get("edit_opponents",false)==true
	return normalized


static func side(raw: Dictionary) -> Dictionary:
	var result: Dictionary=SandboxConfig.normalize({"player":raw})["player"]
	result["cards"]=Array(result["cards"]).slice(0,MAX_CARDS)
	result["relics"]=Array(result["relics"]).slice(0,MAX_RELICS)
	result["max_hp"]=mini(100000,int(result["max_hp"]))
	result["hp"]=mini(int(result["hp"]),int(result["max_hp"]))
	result["attack"]=mini(10000,int(result["attack"]))
	result["slots"]=mini(16,int(result["slots"]))
	return result


static func match_config(player: Dictionary, enemy: Dictionary, shared: Dictionary) -> Dictionary:
	var result: Dictionary=SandboxConfig.defaults()
	result["player"]=side(player);result["enemy"]=side(enemy);result["rules"]=rules(shared)
	return result


static func valid(value: Dictionary, shared: Dictionary) -> bool:
	return SandboxConfig.errors(match_config(value,value,shared)).is_empty()


static func advance(engine: RealtimeBattleEngine, seconds: float, ais: Array = []) -> bool:
	var remaining: float=clampf(seconds,0.0,2.0)
	while remaining>0.000001 and engine.battle_state.winner=="":
		var step: float=minf(.05,remaining)
		for ai: EnemyAI in ais: ai.update(engine,step)
		engine.update(step);remaining-=step
		if engine.balance_limit_reached or engine.battle_state.active_instances.size()>=MAX_ACTIVE:return false
		for unit: UnitState in [engine.battle_state.player,engine.battle_state.enemy]:
			if unit.next_attack_multiplier>1000000 or unit.attack>1000000000 or unit.shield>1000000000:return false
	return true
