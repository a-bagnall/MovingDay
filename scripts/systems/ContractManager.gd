extends Node
## Handles active contracts, payouts, and triggering commute travel time upon completion.

signal contract_completed(contract_data: Dictionary)
signal balance_updated(new_balance: float)

# Configure travel/commute time between jobs (10 - 20 seconds as requested)
@export var min_commute_seconds: float = 10.0
@export var max_commute_seconds: float = 20.0

var player_balance: float = 0.0
var active_contracts: Dictionary = {}
var completed_contracts: Array[Dictionary] = []

func accept_contract(contract_id: String, client_name: String, payout: float, travel_time: float = -1.0) -> void:
	var commute = travel_time if travel_time > 0.0 else randf_range(min_commute_seconds, max_commute_seconds)
	active_contracts[contract_id] = {
		"id": contract_id,
		"client": client_name,
		"payout": payout,
		"commute_time": commute,
		"completed": false
	}

func complete_contract(contract_id: String) -> void:
	if not active_contracts.has(contract_id):
		push_warning("Contract ID not found: " + contract_id)
		return
		
	var contract: Dictionary = active_contracts[contract_id]
	contract["completed"] = true
	
	# Add reward
	player_balance += contract["payout"]
	emit_signal("balance_updated", player_balance)
	
	# Advance game clock by commute duration
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager and time_manager.has_method("advance_time"):
		time_manager.advance_time(contract["commute_time"])
	else:
		print("Commute time elapsed: ", contract["commute_time"], "s")
		
	completed_contracts.append(contract)
	active_contracts.erase(contract_id)
	emit_signal("contract_completed", contract)
