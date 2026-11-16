class_name RunModifiers
## "Choose one" run modifiers: every few days the team picks one of three, and it stays
## for the rest of the run. Each one makes the run harder in its own way. They are
## stored on RunState (`modifiers`, as ids), so they save, resume and mirror to clients
## like the rest of the run.
##
## Effects are looked up here by whoever needs them (Furniture, Player, StickyLinks...),
## so adding a modifier means one entry below and one multiplier function.

## A new choice is offered every this many days (it comes with the hub visit).
const CHOOSE_EVERY_N_DAYS := 3
const OFFER_SIZE := 3

const ENTRIES := {
	"butterfingers": {
		"name": "Butterfingers",
		"description": "Grip drains 40% faster when you carry.",
	},
	"slippery_soles": {
		"name": "Slippery Soles",
		"description": "Everyone speeds up and stops 35% more slowly.",
	},
	"glass_cargo": {
		"name": "Glass Cargo",
		"description": "Everything breaks 40% more easily.",
	},
	"heavy_lifting": {
		"name": "Heavy Lifting",
		"description": "All furniture is 25% heavier.",
	},
	"extra_gum": {
		"name": "Gum Everywhere",
		"description": "One extra pair of items is stuck together, even before day 3.",
	},
}


static func active() -> Array[String]:
	if SaveManager.run == null:
		return []
	return SaveManager.run.modifiers


static func has(id: String) -> bool:
	return active().has(id)


static func modifier_name(id: String) -> String:
	return ENTRIES[id]["name"] if ENTRIES.has(id) else id


static func names(ids: Array[String]) -> String:
	var parts := PackedStringArray()
	for id in ids:
		parts.append(modifier_name(id))
	return ", ".join(parts)


## True if the hub before `day` should offer a choice the run has not made yet.
static func choice_due(run: RunState) -> bool:
	return run != null and run.day > 1 and (run.day - 1) % CHOOSE_EVERY_N_DAYS == 0 \
		and run.modifier_day != run.day and not offer(run).is_empty()


## The ids on offer: up to three the run does not have yet. Chosen from the run's slot and
## day, so it is the same every time the screen is opened (no rerolling by reloading).
static func offer(run: RunState) -> Array[String]:
	var pool: Array[String] = []
	for id: String in ENTRIES:
		if not run.modifiers.has(id):
			pool.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("modifiers_%d_%d" % [run.slot, run.day])
	var result: Array[String] = []
	while result.size() < OFFER_SIZE and not pool.is_empty():
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result


# --- effects -----------------------------------------------------------------

static func grip_drain_multiplier() -> float:
	return 1.4 if has("butterfingers") else 1.0


## Scales how fast players speed up and brake.
static func control_multiplier() -> float:
	return 0.65 if has("slippery_soles") else 1.0


static func damage_multiplier() -> float:
	return 1.4 if has("glass_cargo") else 1.0


static func mass_multiplier() -> float:
	return 1.25 if has("heavy_lifting") else 1.0


static func extra_sticky_pairs() -> int:
	return 1 if has("extra_gum") else 0
