extends RefCounted
class_name ActiveCardInstance

var instance_id: int = 0
var owner_side: String = ""
var runtime_id: String = ""
var card_id: String = ""
var card_name: String = ""
var scheduled_time: float = 0.0
var sort_key: float = 0.0
var priority_modifier: float = 0.0
var slot_cost: int = 1
var interruptible: bool = false
var actor_speed: int = 0
var target_type: String = "enemy"
var created_at: float = 0.0


func get_remaining(current_time: float) -> float:
	return max(0.0, scheduled_time - current_time)


func shift_schedule(delta_amount: float, battle_time: float) -> void:
	scheduled_time = max(battle_time, scheduled_time + delta_amount)
	sort_key = scheduled_time - priority_modifier
