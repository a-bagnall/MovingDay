extends Node
## Autoload "GameFlow". Owns the in-memory day loop and scene transitions.
## A day contains multiple contracts; saves are written only at day boundaries.
##
## Online, only the host runs the loop. Every scene change it makes is sent to the
## clients together with a snapshot of the run and the day (so their briefing, hub and
## job screens show the same thing), and the clients change scene with it. Clients that
## want something to happen (continue past the briefing) ask the host.

const DAY_LENGTH := 10.0
const HUB_EVERY_N_DAYS := 3

const MAIN_MENU_SCENE := "res://scenes/main/main_menu.tscn"
const HUB_SCENE := "res://scenes/levels/hub.tscn"
const JOB_SCENE := "res://scenes/levels/test_house.tscn"
const BRIEFING_SCENE := "res://scenes/ui/briefing.tscn"

const _SCENES := [MAIN_MENU_SCENE, HUB_SCENE, JOB_SCENE, BRIEFING_SCENE]

var day_time_remaining := DAY_LENGTH
var day_clock_running := false
var day_contract_count := 0
var day_total: Dictionary = {}
var previous_contract_result: Dictionary = {}
var current_contract: Contract

## Counts scene changes. Messages about a scene carry it, so a late one from the
## previous scene is recognised and ignored.
var scene_serial := 0

var _peer_serial: Dictionary = {}   # host: peer id -> last scene serial that peer reported loaded


func _ready() -> void:
	NetworkManager.connection_lost.connect(_on_connection_lost)


func _process(delta: float) -> void:
	if day_clock_running:
		day_time_remaining = maxf(0.0, day_time_remaining - delta)


## True when this machine decides what happens next: offline, or the host.
func is_authority() -> bool:
	return not NetworkManager.is_online() or NetworkManager.is_host()


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


## Called by the briefing when a player presses continue. A client asks the host.
func continue_from_briefing() -> void:
	if is_authority():
		if current_contract != null:
			launch_next_contract()
		else:
			finish_day()
	elif NetworkManager.can_send():
		_request_continue.rpc_id(1, scene_serial)


## Called by the end-of-day briefing after the team dismisses the day summary.
func finish_day() -> void:
	assert(SaveManager.run != null, "finish_day called with no active run")
	assert(day_contract_count > 0, "Cannot finish a day without completing a contract")
	day_clock_running = false
	SaveManager.end_day(day_total)
	_reset_day_state()
	_enter_day()


## Returns to the main menu without touching any run.
func open_main_menu() -> void:
	_go(MAIN_MENU_SCENE)


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
		"style_bonus": 0.0,
		"damage": 0.0,
		"time": 0.0,
		"contracts_completed": 0,
	}
	previous_contract_result.clear()
	current_contract = null


func _accumulate_day_result(result: Dictionary) -> void:
	for key in ["payment", "base_pay", "time_bonus", "style_bonus", "damage", "time"]:
		day_total[key] = float(day_total.get(key, 0.0)) + float(result.get(key, 0.0))
	day_total["contracts_completed"] = day_contract_count


func _go(path: String) -> void:
	scene_serial += 1
	# A run in progress cannot take newcomers; the main menu can.
	NetworkManager.set_accepting_connections(path == MAIN_MENU_SCENE)
	if NetworkManager.is_host() and NetworkManager.peer_count() > 1:
		_net_go.rpc(path, scene_serial, _snapshot())
	_change_scene(path)


func _change_scene(path: String) -> void:
	var err := get_tree().change_scene_to_file(path)
	assert(err == OK, "Could not load %s: %s" % [path, error_string(err)])


# --- online ---------------------------------------------------------------

## Host: sends the run (wallet, boosts) to the clients again, e.g. after a hub purchase.
func sync_run() -> void:
	if NetworkManager.is_host() and NetworkManager.peer_count() > 1 and SaveManager.run != null:
		_net_run.rpc(SaveManager.run.to_dict())


## Client: call once the new scene is loaded, so the host starts sending it state.
func report_scene_ready() -> void:
	if NetworkManager.mode == NetworkManager.Mode.CLIENT and NetworkManager.can_send():
		_client_scene_ready.rpc_id(1, scene_serial)


## Host: whether `peer_id` has loaded the scene that is current now.
func is_peer_ready(peer_id: int) -> bool:
	return _peer_serial.get(peer_id, -1) == scene_serial


func _snapshot() -> Dictionary:
	return {
		"run": SaveManager.run.to_dict() if SaveManager.run != null else {},
		"day_time_remaining": day_time_remaining,
		"day_clock_running": day_clock_running,
		"day_contract_count": day_contract_count,
		"day_total": day_total.duplicate(true),
		"previous": previous_contract_result.duplicate(true),
		"contract": _contract_to_dict(current_contract),
	}


func _apply_snapshot(snapshot: Dictionary) -> void:
	var run_data: Dictionary = snapshot.get("run", {})
	if run_data.is_empty():
		SaveManager.clear_mirror()
	else:
		SaveManager.mirror_run(run_data)
	day_time_remaining = float(snapshot.get("day_time_remaining", DAY_LENGTH))
	day_clock_running = bool(snapshot.get("day_clock_running", false))
	day_contract_count = int(snapshot.get("day_contract_count", 0))
	day_total = snapshot.get("day_total", {})
	previous_contract_result = snapshot.get("previous", {})
	current_contract = _contract_from_dict(snapshot.get("contract", {}))


static func _contract_to_dict(contract: Contract) -> Dictionary:
	if contract == null:
		return {}
	return {
		"contract_number": contract.contract_number,
		"client_name": contract.client_name,
		"letter_text": contract.letter_text,
		"payout": contract.payout,
	}


static func _contract_from_dict(data: Dictionary) -> Contract:
	if data.is_empty():
		return null
	var contract := Contract.new()
	contract.contract_number = int(data.get("contract_number", 1))
	contract.client_name = str(data.get("client_name", ""))
	contract.letter_text = str(data.get("letter_text", ""))
	contract.payout = float(data.get("payout", 0.0))
	return contract


## Host -> clients: change scene, and bring the run and the day along.
@rpc("authority", "call_remote", "reliable")
func _net_go(path: String, serial: int, snapshot: Dictionary) -> void:
	if not _SCENES.has(path):
		return
	scene_serial = serial
	_apply_snapshot(snapshot)
	_change_scene(path)


## Host -> clients: the run changed without a scene change.
@rpc("authority", "call_remote", "reliable")
func _net_run(data: Dictionary) -> void:
	SaveManager.mirror_run(data)


## Client -> host: "I have loaded scene `serial`".
@rpc("any_peer", "call_remote", "reliable")
func _client_scene_ready(serial: int) -> void:
	if NetworkManager.is_host():
		_peer_serial[multiplayer.get_remote_sender_id()] = serial


## Client -> host: "someone here pressed continue on the briefing".
@rpc("any_peer", "call_remote", "reliable")
func _request_continue(serial: int) -> void:
	# Compared by scene path, not by the Briefing class: Briefing uses GameFlow, so naming the
	# class here makes the two scripts depend on each other and neither compiles.
	var scene := get_tree().current_scene
	if NetworkManager.is_host() and serial == scene_serial and scene != null \
			and scene.scene_file_path == BRIEFING_SCENE:
		continue_from_briefing()


## The host went away: drop its run and go back to the main menu.
func _on_connection_lost() -> void:
	SaveManager.clear_mirror()
	_reset_day_state()
	_peer_serial.clear()
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != MAIN_MENU_SCENE:
		_change_scene(MAIN_MENU_SCENE)
