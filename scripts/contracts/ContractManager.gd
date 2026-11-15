extends Node
## Evaluates contract completion, damage penalties, and triggers commute time progression.
## Aligns with GDD Section 7 (Contract Results) and Section 10 (scripts/contracts/).

signal contract_finished(summary: Dictionary)

@export var base_payout: float = 250.0

var required_items_total: int = 0
var delivered_items_count: int = 0
var total_damage_cost: float = 0.0
var optional_objectives_completed: int = 0

func setup_contract(total_items: int, payout: float) -> void:
	required_items_total = total_items
	base_payout = payout
	delivered_items_count = 0
	total_damage_cost = 0.0
	optional_objectives_completed = 0

func register_item_delivered(item_value: float) -> void:
	delivered_items_count += 1

func register_item_damaged(damage_penalty: float) -> void:
	total_damage_cost += damage_penalty

func complete_contract() -> Dictionary:
	# 1. Emulate travel/commute time progression (10 - 20 seconds)
	var commute_seconds: float = 0.0
	var game_flow = get_node_or_null("/root/GameFlow")
	if game_flow and game_flow.has_method("apply_commute_time_skip"):
		commute_seconds = game_flow.apply_commute_time_skip()
	
	# 2. Calculate GDD Section 7 Contract Results
	var completion_ratio: float = 1.0 if required_items_total == 0 else clamp(float(delivered_items_count) / float(required_items_total), 0.0, 1.0)
	var gross_pay: float = base_payout * completion_ratio
	var bonus_pay: float = optional_objectives_completed * 50.0
	var final_payout: float = max(0.0, gross_pay + bonus_pay - total_damage_cost)
	
	var summary := {
		"completion_pct": completion_ratio * 100.0,
		"delivered": delivered_items_count,
		"total_required": required_items_total,
		"damage_penalty": total_damage_cost,
		"commute_time_added": commute_seconds,
		"final_payout": final_payout
	}
	
	emit_signal("contract_finished", summary)
	
	if game_flow and game_flow.has_method("finish_day"):
		game_flow.finish_day(summary)
		
	return summary
