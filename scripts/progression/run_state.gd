extends Resource
class_name RunState
## State of one run (a sequence of days). Lives in a run slot and is wiped when
## the run dies; anything that must outlive a run belongs in ProfileState.
##
## Pure data: no file I/O here. SaveManager reads and writes it, and only at
## day boundaries.

const VERSION := 1

var slot := 1
var wallet := 0.0
var day := 1
var perks: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"slot": slot,
		"wallet": wallet,
		"day": day,
		"perks": perks.duplicate(),
	}


## Expects a Dictionary parsed from JSON (so numbers are floats). Returns null
## and pushes an error naming the problem if the data is not a valid RunState.
static func from_dict(data: Dictionary) -> RunState:
	if not _is_number(data.get("version")) or int(data["version"]) != VERSION:
		push_error("RunState: unsupported version %s (expected %d)" % [data.get("version"), VERSION])
		return null
	for key in ["slot", "wallet", "day"]:
		if not _is_number(data.get(key)):
			push_error("RunState: '%s' is missing or not a number" % key)
			return null
	if typeof(data.get("perks")) != TYPE_ARRAY:
		push_error("RunState: 'perks' is missing or not an array")
		return null

	var state := RunState.new()
	state.slot = int(data["slot"])
	state.wallet = float(data["wallet"])
	state.day = int(data["day"])
	for perk in data["perks"]:
		if typeof(perk) != TYPE_STRING:
			push_error("RunState: 'perks' contains a non-string entry")
			return null
		state.perks.append(perk)
	return state


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
