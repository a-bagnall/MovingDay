extends Node
## Autoload "GameFlow". Moves between the main menu, the hub and the job scene.
## Saving stays in SaveManager (day boundaries only); this only picks the next scene.
##
## Day order: days 1..N are jobs, then a hub visit, then N more jobs, and so on,
## where N is HUB_EVERY_N_DAYS. The hub is in-run only.

const HUB_EVERY_N_DAYS := 3

const MAIN_MENU_SCENE := "res://scenes/main/main_menu.tscn"
const HUB_SCENE := "res://scenes/levels/hub.tscn"
const JOB_SCENE := "res://scenes/levels/test_house.tscn"


## True if the hub comes before `day` (never before day 1).
func is_hub_day(day: int) -> bool:
	return day > 1 and (day - 1) % HUB_EVERY_N_DAYS == 0


## Starts a fresh run in an empty slot. Day 1 is always a job.
func new_run(slot: int) -> void:
	SaveManager.new_run(slot)
	_go(JOB_SCENE)


## Resumes a saved run from the start of its current day.
func continue_run(slot: int) -> void:
	SaveManager.continue_run(slot)
	_enter_day()


## Leaves the hub for the job of the current day.
func start_job() -> void:
	_go(JOB_SCENE)


## Called when the results screen is dismissed: saves the finished day and moves on.
func finish_day(result: Dictionary) -> void:
	SaveManager.end_day(result)
	_enter_day()


## Ends the run (deletes its slot, keeps the profile) and returns to the main menu.
func end_run() -> void:
	SaveManager.end_run()
	_go(MAIN_MENU_SCENE)


func _enter_day() -> void:
	_go(HUB_SCENE if is_hub_day(SaveManager.run.day) else JOB_SCENE)


func _go(path: String) -> void:
	var err := get_tree().change_scene_to_file(path)
	assert(err == OK, "Could not load %s: %s" % [path, error_string(err)])
