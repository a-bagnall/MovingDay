extends Node
## Autoload "GameFlow". Owns the in-memory day loop and scene transitions.
## A day contains multiple contracts; saves are written only at day boundaries.

const DAY_LENGTH := 10.0
const HUB_EVERY_N_DAYS := 3

const MAIN_MENU_SCENE := "res://scenes/main/main_menu.tscn"
const HUB_SCENE := "res://scenes/levels/hub.tscn"
const JOB_SCENE := "res://scenes/levels/test_house.tscn"
const BRIEFING_SCENE := "res://scenes/ui/briefing.tscn"

var day_time_remaining := DAY_LENGTH
var day_clock_running := false
var day_contract_count := 0
var day_total: Dictionary = {}
var previous_contract_result: Dictionary = {}
var current_contract: Contract


func _process(delta: float) -> void:
	if day_clock_running:
		day_time_remaining = maxf(0.0, day_time_remaining - delta)


## True if the hub comes before `day` (never before day 1).
func is_hub_day(day: int) -> bool:
	return day > 1 and (day - 1) % HUB_EVERY_N_DAYS == 0


## Starts a fresh run in an empty slot. Day 1 opens with its first briefing.
func new_run(slot: int) -> void:
	SaveManager.new_run(slot)
	_begin_day()


## Resumes a saved run from the start of its current day.
func continue_run(slot: int) -> void:
	SaveManager.continue_run(slot)
	_reset_day_state()
	_enter_day()


## Called by the hub. A new day begins with a briefing, not directly in the house.
func start_job() -> void:
	_begin_day()


## Called by the briefing after the team has reviewed the next contract.
func launch_next_contract() -> void:
	assert(SaveManager.run != null, "launch_next_contract called with no active run")
	assert(current_contract != null, "launch_next_contract called without a contract")
	assert(day_time_remaining > 0.0, "Cannot start a contract after the day has ended")
	day_clock_running = true
	_go(JOB_SCENE)


## Called once when a house is fully cleared. The day clock pauses during the briefing.
func finish_contract(result: Dictionary) -> void:
	assert(SaveManager.run != null, "finish_contract called with no active run")
	assert(not result.is_empty(), "finish_contract received an empty result")
	day_clock_running = false
	previous_contract_result = result.duplicate(true)
	day_contract_count += 1
	_accumulate_day_result(result)

	if day_time_remaining > 0.0:
		current_contract = ContractGenerator.generate_contract(day_contract_count + 1)
	else:
		current_contract = null
	_go(BRIEFING_SCENE)


## Called by the end-of-day briefing after the team dismisses the day summary.
func finish_day() -> void:
	assert(SaveManager.run != null, "finish_day called with no active run")
	assert(day_contract_count > 0, "Cannot finish a day without completing a contract")
	day_clock_running = false
	SaveManager.end_day(day_total)
	_reset_day_state()
	_enter_day()


## Ends the run (deletes its slot, keeps the profile) and returns to the main menu.
func end_run() -> void:
	day_clock_running = false
	SaveManager.end_run()
	_reset_day_state()
	_go(MAIN_MENU_SCENE)


func _begin_day() -> void:
	_reset_day_state()
	SaveManager.begin_day()
	current_contract = ContractGenerator.generate_contract(1)
	_go(BRIEFING_SCENE)


func _enter_day() -> void:
	if is_hub_day(SaveManager.run.day):
		_go(HUB_SCENE)
	else:
		_begin_day()


func _reset_day_state() -> void:
	day_time_remaining = DAY_LENGTH
	day_clock_running = false
	day_contract_count = 0
	day_total = {
		"payment": 0.0,
		"base_pay": 0.0,
		"time_bonus": 0.0,
		"damage": 0.0,
		"time": 0.0,
		"contracts_completed": 0,
	}
	previous_contract_result.clear()
	current_contract = null


func _accumulate_day_result(result: Dictionary) -> void:
	for key in ["payment", "base_pay", "time_bonus", "damage", "time"]:
		day_total[key] = float(day_total.get(key, 0.0)) + float(result.get(key, 0.0))
	day_total["contracts_completed"] = day_contract_count


func _go(path: String) -> void:
	var err := get_tree().change_scene_to_file(path)
	assert(err == OK, "Could not load %s: %s" % [path, error_string(err)])
