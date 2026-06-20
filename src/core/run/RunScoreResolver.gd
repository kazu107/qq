extends RefCounted
class_name RunScoreResolver

const MAX_SCORE: int = 10000
const PROGRESS_MAX: int = 6000
const SURVIVAL_MAX: int = 1500
const EFFICIENCY_MAX: int = 1500
const CHALLENGE_MAX: int = 1000
const PRE_BOSS_PROGRESS_MAX: int = 4200
const BOSS_CLEAR_SCORE: int = 1800

const ENEMY_PAR_TIMES: Dictionary = {
	"scout": 32.0,
	"brute": 61.0,
	"disruptor": 35.0,
	"guardian": 97.0,
	"raider": 36.0,
	"medic_drone": 90.0,
	"chronoguard": 57.0,
	"boss_timekeeper": 80.0,
	"phase_stalker": 72.0,
	"void_bastion": 112.0,
	"echo_revenant": 86.0,
	"boss_paradox_core": 145.0,
}


func calculate(run_state: RunState) -> Dictionary:
	if run_state == null:
		return _empty_score()

	var cleared: bool = run_state.run_complete and not run_state.defeated
	var progress_score: int = _calculate_progress(run_state, cleared)
	var survival_score: int = _calculate_survival(run_state, cleared)
	var efficiency_score: int = _calculate_efficiency(run_state.battle_history)
	var challenge_score: int = _calculate_challenge(run_state.map_state)
	var total_score: int = clampi(
		progress_score + survival_score + efficiency_score + challenge_score,
		0,
		MAX_SCORE
	)

	return {
		"total_score": total_score,
		"max_score": MAX_SCORE,
		"rank": _resolve_rank(total_score, cleared),
		"cleared": cleared,
		"progress": progress_score,
		"progress_max": PROGRESS_MAX,
		"survival": survival_score,
		"survival_max": SURVIVAL_MAX,
		"efficiency": efficiency_score,
		"efficiency_max": EFFICIENCY_MAX,
		"challenge": challenge_score,
		"challenge_max": CHALLENGE_MAX,
	}


func _calculate_progress(run_state: RunState, cleared: bool) -> int:
	var total_steps: int = maxi(1, Array(run_state.map_state.get("steps", [])).size())
	var pre_boss_step_count: int = maxi(1, total_steps - 1)
	var completed_steps: int = clampi(
		int(run_state.map_state.get("current_step", 0)),
		0,
		pre_boss_step_count
	)
	var score: int = roundi(float(PRE_BOSS_PROGRESS_MAX * completed_steps) / float(pre_boss_step_count))
	if cleared:
		score += BOSS_CLEAR_SCORE
	return mini(score, PROGRESS_MAX)


func _calculate_survival(run_state: RunState, cleared: bool) -> int:
	if not cleared or run_state.max_hp <= 0:
		return 0
	var hp_ratio: float = clampf(float(run_state.player_hp) / float(run_state.max_hp), 0.0, 1.0)
	return roundi(float(SURVIVAL_MAX) * hp_ratio)


func _calculate_efficiency(battle_history: Array[Dictionary]) -> int:
	var weighted_total: float = 0.0
	var weight_total: float = 0.0
	for battle: Dictionary in battle_history:
		var battle_time: float = float(battle.get("battle_time", 0.0))
		if battle_time <= 0.0:
			continue
		var enemy_id: String = String(battle.get("enemy_id", ""))
		var par_time: float = float(ENEMY_PAR_TIMES.get(enemy_id, 60.0))
		var efficiency_ratio: float = clampf((par_time * 2.0 - battle_time) / par_time, 0.0, 1.0)
		var weight: float = _get_battle_weight(String(battle.get("node_type", "normal_battle")))
		weighted_total += efficiency_ratio * weight
		weight_total += weight
	if weight_total <= 0.0:
		return 0
	return clampi(roundi(float(EFFICIENCY_MAX) * weighted_total / weight_total), 0, EFFICIENCY_MAX)


func _calculate_challenge(map_state: Dictionary) -> int:
	var score: int = 0
	for raw_step in Array(map_state.get("steps", [])):
		var step_data: Dictionary = Dictionary(raw_step)
		for raw_node in Array(step_data.get("nodes", [])):
			var node_data: Dictionary = Dictionary(raw_node)
			if String(node_data.get("status", "")) != "completed":
				continue
			match String(node_data.get("type", "")):
				"elite_battle":
					if int(node_data.get("area", 1)) >= 3:
						score += 450
					else:
						score += 400
				"hazard":
					var wave_count: int = Array(node_data.get("hazard_queue", [])).size()
					var cleared_waves: int = int(node_data.get("hazard_cleared_waves", 0))
					if wave_count > 0 and cleared_waves >= wave_count:
						score += 550
	return mini(score, CHALLENGE_MAX)


func _get_battle_weight(node_type: String) -> float:
	match node_type:
		"elite_battle":
			return 1.25
		"hazard":
			return 1.15
		"boss":
			return 1.5
		_:
			return 1.0


func _resolve_rank(total_score: int, cleared: bool) -> String:
	if total_score >= 9000:
		return "S" if cleared else "C"
	if total_score >= 8000:
		return "A" if cleared else "C"
	if total_score >= 7000:
		return "B" if cleared else "C"
	if total_score >= 6000:
		return "C"
	if total_score >= 4000:
		return "D"
	return "E"


func _empty_score() -> Dictionary:
	return {
		"total_score": 0,
		"max_score": MAX_SCORE,
		"rank": "E",
		"cleared": false,
		"progress": 0,
		"progress_max": PROGRESS_MAX,
		"survival": 0,
		"survival_max": SURVIVAL_MAX,
		"efficiency": 0,
		"efficiency_max": EFFICIENCY_MAX,
		"challenge": 0,
		"challenge_max": CHALLENGE_MAX,
	}
