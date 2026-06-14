extends RefCounted
class_name TimelineEntry

var instance_id: int = 0
var owner_side: String = ""
var runtime_id: String = ""
var card_id: String = ""
var card_name: String = ""
var scheduled_time: float = 0.0
var created_at: float = 0.0
var sort_key: float = 0.0
var priority_modifier: float = 0.0
var actor_speed: int = 0
var slot_cost: int = 1
var interruptible: bool = false
var continuous_shift_battle_time: float = -1.0
var continuous_shift_amount: float = 0.0


static func from_instance(instance: ActiveCardInstance) -> TimelineEntry:
	var entry := TimelineEntry.new()
	entry.instance_id = instance.instance_id
	entry.owner_side = instance.owner_side
	entry.runtime_id = instance.runtime_id
	entry.card_id = instance.card_id
	entry.card_name = instance.card_name
	entry.scheduled_time = instance.scheduled_time
	entry.created_at = instance.created_at
	entry.sort_key = instance.sort_key
	entry.priority_modifier = instance.priority_modifier
	entry.actor_speed = instance.actor_speed
	entry.slot_cost = instance.slot_cost
	entry.interruptible = instance.interruptible
	entry.continuous_shift_battle_time = instance.continuous_shift_battle_time
	entry.continuous_shift_amount = instance.continuous_shift_amount
	return entry
