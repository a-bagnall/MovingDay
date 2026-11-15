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


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"unlocks": unlocks.duplicate(),
		"cosmetics": cosmetics.duplicate(),
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
