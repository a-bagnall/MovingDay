extends Node
## Manages the roguelite run loop, consecutive days, hub intervals, and commute time skips.
## Aligns with GDD Section 7 (Run Structure: Days, Perks and Modifiers) and Section 10.

signal time_updated(remaining_seconds: float, formatted_time: String)
signal day_completed(day_number: int, results: Dictionary)
signal hub_reached(day_number: int)
signal modifier_selection_required(day_number: int)

const HUB_EVERY_N_DAYS: int = 3 # From GDD: Reach Hub every N days

@export var default_contract_duration: float = 180.0
@export var commute_skip_min: float = 10.0
@export var commute_skip_max: float = 20.0

var current_day: int = 1
var company_money: float = 0.0
var reputation: int = 0
var remaining_job_time: float = 0.0
var is_job_active: bool = false

# Active run state (GDD Section 7)
var equipped_perks: Array[String] = [] # Up to 2 perks initially
var active_modifiers: Array[String] = []

func start_day(contract_duration: float = -1.0) -> void:
	remaining_job_time = contract_duration if contract_duration > 0.0 else default_contract_duration
	is_job_active = true
	
	# GDD Rule: From day 3 onwards, sticky objects modifier/mechanic activates
	if current_day >= 3 and not active_modifiers.has("sticky_objects"):
		active_modifiers.append("sticky_objects")

func _process(delta: float) -> void:
	if not is_job_active:
		return
	advance_clock(delta)

func advance_clock(seconds: float) -> void:
	remaining_job_time = max(0.0, remaining_job_time - seconds)
	emit_signal("time_updated", remaining_job_time, get_formatted_time())
	
	if remaining_job_time <= 0.0:
		finish_day({})

func apply_commute_time_skip() -> float:
	# Advances clock by 10-20s to emulate travel/commute time when completing a contract
	var skip_amount: float = randf_range(commute_skip_min, commute_skip_max)
	advance_clock(skip_amount)
	return skip_amount

func finish_day(contract_results: Dictionary) -> void:
	is_job_active = false
	var payout: float = contract_results.get("final_payout", 0.0)
	company_money += payout
	
	emit_signal("day_completed", current_day, contract_results)
	
	# Check Hub cadence (every N days, e.g., Day 3, 6, 9...)
	if current_day % HUB_EVERY_N_DAYS == 0:
		emit_signal("hub_reached", current_day)
		emit_signal("modifier_selection_required", current_day)
	
	current_day += 1

func get_formatted_time() -> String:
	var mins: int = int(remaining_job_time) / 60
	var secs: int = int(remaining_job_time) % 60
	return "%02d:%02d" % [mins, secs]
