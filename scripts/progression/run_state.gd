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
## "Choose one" modifiers picked so far this run (see RunModifiers), and the day the
## last one was picked, so a choice is not offered twice for the same hub visit.
var modifiers: Array[String] = []
var modifier_day := 0
## Lifetime stats of this run, updated when a day ends.
var contracts_completed := 0
var total_earned := 0.0
var total_damage := 0.0
var best_day := 0.0   # biggest take-home of any single day
## One-day shop boosts. The day number prevents them carrying into later jobs.
var speed_boost_day := 0
var speed_boost := 1.0
var acceleration_boost_day := 0
var acceleration_boost := 1.0


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"slot": slot,
		"wallet": wallet,
		"day": day,
		"perks": perks.duplicate(),
		"modifiers": modifiers.duplicate(),
		"modifier_day": modifier_day,
		"contracts_completed": contracts_completed,
		"total_earned": total_earned,
		"total_damage": total_damage,
		"best_day": best_day,
		"speed_boost_day": speed_boost_day,
		"speed_boost": speed_boost,
		"acceleration_boost_day": acceleration_boost_day,
		"acceleration_boost": acceleration_boost,
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
	# Optional for backwards compatibility with existing version-1 save slots.
	state.contracts_completed = int(data.get("contracts_completed", 0))
	state.total_earned = float(data.get("total_earned", 0.0))
	state.total_damage = float(data.get("total_damage", 0.0))
	state.best_day = float(data.get("best_day", 0.0))
	state.speed_boost_day = int(data.get("speed_boost_day", 0))
	state.speed_boost = float(data.get("speed_boost", 1.0))
	state.acceleration_boost_day = int(data.get("acceleration_boost_day", 0))
	state.acceleration_boost = float(data.get("acceleration_boost", 1.0))
	state.modifier_day = int(data.get("modifier_day", 0))
	var saved_modifiers: Variant = data.get("modifiers", [])
	if typeof(saved_modifiers) == TYPE_ARRAY:   # optional: older saves have none
		for id in saved_modifiers:
			if typeof(id) == TYPE_STRING:   # unknown ids are kept: they show by id
				state.modifiers.append(id)
	for perk in data["perks"]:
		if typeof(perk) != TYPE_STRING:
			push_error("RunState: 'perks' contains a non-string entry")
			return null
		state.perks.append(perk)
	return state


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
