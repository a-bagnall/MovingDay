extends Resource
class_name ProfileState
## Data that persists across runs: unlocks and owned cosmetics. Stored apart from
## the run slots so a dead run can be wiped without touching it.
##
## Pure data: no file I/O here. SaveManager reads and writes it, and only at
## day boundaries.

const VERSION := 1

var unlocks: Array[String] = []
var cosmetics: Array[String] = []
var equipped_outfit := ""
## Preferred character (CharacterCatalog index) for the 1st, 2nd... player on this
## computer, so a pick is remembered next launch. Optional in the file.
var characters: Array[int] = []
## Lifetime run record, for comparing playtest runs. Optional in the file.
var best_run_day := 0      # most days completed in any run that ended
var runs_ended := 0


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"unlocks": unlocks.duplicate(),
		"cosmetics": cosmetics.duplicate(),
		"equipped_outfit": equipped_outfit,
		"characters": characters.duplicate(),
		"best_run_day": best_run_day,
		"runs_ended": runs_ended,
	}


## Expects a Dictionary parsed from JSON. Returns null and pushes an error
## naming the problem if the data is not a valid ProfileState.
static func from_dict(data: Dictionary) -> ProfileState:
	if typeof(data.get("version")) not in [TYPE_INT, TYPE_FLOAT] or int(data["version"]) != VERSION:
		push_error("ProfileState: unsupported version %s (expected %d)" % [data.get("version"), VERSION])
		return null

	var state := ProfileState.new()
	if not _read_strings(data, "unlocks", state.unlocks):
		return null
	if not _read_strings(data, "cosmetics", state.cosmetics):
		return null
	var equipped: Variant = data.get("equipped_outfit", "")
	if typeof(equipped) != TYPE_STRING:
		push_error("ProfileState: 'equipped_outfit' is not a string")
		return null
	state.equipped_outfit = equipped
	var saved_characters: Variant = data.get("characters", [])
	if typeof(saved_characters) == TYPE_ARRAY:   # lenient: older files have none, bad entries are skipped
		for entry in saved_characters:
			if typeof(entry) in [TYPE_INT, TYPE_FLOAT]:
				state.characters.append(int(entry))
	state.best_run_day = int(data.get("best_run_day", 0))
	state.runs_ended = int(data.get("runs_ended", 0))
	if state.equipped_outfit != "" and not state.cosmetics.has(state.equipped_outfit):
		push_error("ProfileState: equipped outfit is not owned")
		return null
	return state


static func _read_strings(data: Dictionary, key: String, out: Array[String]) -> bool:
	if typeof(data.get(key)) != TYPE_ARRAY:
		push_error("ProfileState: '%s' is missing or not an array" % key)
		return false
	for entry in data[key]:
		if typeof(entry) != TYPE_STRING:
			push_error("ProfileState: '%s' contains a non-string entry" % key)
			return false
		out.append(entry)
	return true
