extends Node
## Autoload "SaveManager". Owns the active run and persistent profile, and
## reads/writes JSON in user://. The run is committed at day boundaries only.

const SLOT_COUNT := 3
const PROFILE_PATH := "user://profile.json"

var profile: ProfileState
var run: RunState
## True on a client playing in the host's run: `run` is a copy the host sent, and
## nothing is ever written to disk from it.
var is_mirror := false
var _day_open := false


func _ready() -> void:
	profile = _read_profile()


# --- run slots ------------------------------------------------------------

func has_run(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


## Reads a slot without making it the active run (for menus). Null if empty.
func peek_run(slot: int) -> RunState:
	if not has_run(slot):
		return null
	var state := RunState.from_dict(_read_json(_slot_path(slot)))
	if state == null:
		_fail("Run slot %d is invalid (see error above)" % slot)
		return null
	assert(state.slot == slot, "Run slot %d file says it belongs to slot %d" % [slot, state.slot])
	return state


func continue_run(slot: int) -> void:
	var state := peek_run(slot)
	assert(state != null, "continue_run: slot %d is empty" % slot)
	run = state
	_day_open = false


## Client: replaces the run with the host's copy. Never saved.
func mirror_run(data: Dictionary) -> void:
	var state := RunState.from_dict(data)
	assert(state != null, "mirror_run: the host sent an invalid run")
	is_mirror = true
	run = state
	_day_open = true   # begin_day() then has nothing to do


## Client: forgets the host's run (the host ended it, or the connection went).
func clear_mirror() -> void:
	if is_mirror:
		is_mirror = false
		run = null
		_day_open = false


## Starts a fresh run in memory. Nothing is written until the first day begins.
func new_run(slot: int) -> void:
	_slot_path(slot)
	run = RunState.new()
	run.slot = slot
	_day_open = false


## Writes the day-start snapshot once. Calls from individual house scenes are
## harmless, so existing scene setup remains compatible with the multi-job loop.
func begin_day() -> void:
	assert(run != null, "begin_day called with no active run")
	if _day_open:
		return
	_write_run()
	_write_profile()
	_day_open = true


## `result` is the accumulated day summary, not an individual contract result.
func end_day(result: Dictionary) -> void:
	assert(run != null, "end_day called with no active run")
	assert(result.has("payment"), "end_day: result has no 'payment'")
	run.wallet += float(result["payment"])
	run.contracts_completed += int(result.get("contracts_completed", 0))
	run.total_earned += float(result["payment"])
	run.total_damage += float(result.get("damage", 0.0))
	run.best_day = maxf(run.best_day, float(result["payment"]))
	run.day += 1
	_day_open = false
	_write_run()
	_write_profile()


## Deletes the saved run in `slot` to free it. The profile is untouched. If that run is
## the active one it is cleared too.
func delete_run(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			_fail("Could not delete %s: %s" % [path, error_string(err)])
			return
	if run != null and not is_mirror and run.slot == slot:
		run = null
		_day_open = false


## When the run in `slot` was last written (unix time, local), or 0 if the slot is empty.
func slot_saved_at(slot: int) -> int:
	var path := _slot_path(slot)
	return int(FileAccess.get_modified_time(path)) if FileAccess.file_exists(path) else 0


## Ends the run (deletes its slot, keeps the profile) and clears the active run.
func end_run() -> void:
	assert(run != null, "end_run called with no active run")
	var path := _slot_path(run.slot)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			_fail("Could not delete %s: %s" % [path, error_string(err)])
			return
	run = null
	_day_open = false
	_write_profile()


# --- files ----------------------------------------------------------------

func _slot_path(slot: int) -> String:
	assert(slot >= 1 and slot <= SLOT_COUNT, "Run slot %d is out of range 1..%d" % [slot, SLOT_COUNT])
	return "user://run_slot_%d.json" % slot


func _read_profile() -> ProfileState:
	if not FileAccess.file_exists(PROFILE_PATH):
		return ProfileState.new()
	var state := ProfileState.from_dict(_read_json(PROFILE_PATH))
	if state == null:
		_fail("Profile %s is invalid (see error above)" % PROFILE_PATH)
		return ProfileState.new()
	return state


func _write_run() -> void:
	if is_mirror:
		return
	_write_json(_slot_path(run.slot), run.to_dict())


func _write_profile() -> void:
	if is_mirror:
		return
	_write_json(PROFILE_PATH, profile.to_dict())


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var parser := JSON.new()
	var err := parser.parse(file.get_as_text())
	if err != OK:
		_fail("%s is not valid JSON (line %d): %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		_fail("%s does not contain a JSON object" % path)
		return {}
	return parser.data


## Writes to a temp file and renames it over the target, so a crash mid-write
## cannot leave a half-written save.
func _write_json(path: String, data: Dictionary) -> void:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		_fail("Could not open %s for writing: %s" % [temp, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(temp, path)
	if err != OK:
		_fail("Could not move %s to %s: %s" % [temp, path, error_string(err)])


func _fail(message: String) -> void:
	push_error("SaveManager: " + message)
	assert(false, message)
