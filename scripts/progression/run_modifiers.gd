class_name RunModifiers
## "Pick One" run modifiers: every few days the team picks one of three, and it stays
## for the rest of the run. Each one is a detriment that adds chaos or pressure in its own
## way. Perks (the helpful kind) are a separate future system and are never listed here.
##
## Modifiers are stored on RunState (`modifiers`, as ids), so they save, resume and
## mirror to clients like the rest of the run.
##
## All the numbers live in Balance. Effects are looked up here by whoever needs them
## (Furniture, Player, StickyLinks, GameFlow...), so adding a modifier means one entry
## below, one line in `description`, and one multiplier function.

## Display data. Descriptions are built from Balance by `description()`.
const ENTRIES := {
	"butterfingers": {"tag": "GRIP", "name": "Butterfingers"},
	"slippery_soles": {"tag": "MOVEMENT", "name": "Slippery Soles"},
	"glass_cargo": {"tag": "DAMAGE", "name": "Glass Cargo"},
	"heavy_lifting": {"tag": "WEIGHT", "name": "Heavy Lifting"},
	"extra_gum": {"tag": "STICKY", "name": "Gum Everywhere"},
	"greedy_landlord": {"tag": "COSTS", "name": "Greedy Landlord"},
	"cheapskate_clients": {"tag": "PAY", "name": "Cheapskate Clients"},
	"wet_floors": {"tag": "FLOORS", "name": "Wet Floors"},
}


static func active() -> Array[String]:
	if SaveManager.run == null:
		return []
	return SaveManager.run.modifiers


static func has(id: String) -> bool:
	return active().has(id)


static func modifier_name(id: String) -> String:
	return ENTRIES[id]["name"] if ENTRIES.has(id) else id


## Short category shown on the pick card (GRIP, DAMAGE...).
static func tag(id: String) -> String:
	return ENTRIES[id]["tag"] if ENTRIES.has(id) else "?"


## What the modifier does, in words, from the current Balance numbers.
static func description(id: String) -> String:
	match id:
		"butterfingers":
			return "Grip drains %d%% faster when you carry." % _more(Balance.BUTTERFINGERS_GRIP_DRAIN)
		"slippery_soles":
			return "Everyone has %d%% less control: slower to speed up, slower to stop." % _less(Balance.SLIPPERY_SOLES_CONTROL)
		"glass_cargo":
			return "Everything breaks %d%% more easily." % _more(Balance.GLASS_CARGO_DAMAGE)
		"heavy_lifting":
			return "All furniture is %d%% heavier." % _more(Balance.HEAVY_LIFTING_MASS)
		"extra_gum":
			return "%d extra pairs of items are stuck together, even before day %d." % [
				Balance.EXTRA_GUM_PAIRS, Balance.STICKY_FIRST_DAY]
		"greedy_landlord":
			return "Daily running costs are %d%% higher. Bankruptcy comes sooner." % _more(Balance.GREEDY_LANDLORD_COSTS)
		"cheapskate_clients":
			return "Clients pay %d%% less for every job." % _less(Balance.CHEAPSKATE_CLIENTS_PAY)
		"wet_floors":
			return "%d slick puddles appear on the way to the truck. Step in one and you can barely steer or stop." % Balance.WET_FLOORS_PUDDLES
	return ""


static func names(ids: Array[String]) -> String:
	var parts := PackedStringArray()
	for id in ids:
		parts.append(modifier_name(id))
	return ", ".join(parts)


## True if the hub before `day` should offer a choice the run has not made yet.
static func choice_due(run: RunState) -> bool:
	return run != null and run.day > 1 and (run.day - 1) % Balance.MODIFIER_EVERY_N_DAYS == 0 \
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
	while result.size() < Balance.MODIFIER_OFFER_SIZE and not pool.is_empty():
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result


# --- effects -----------------------------------------------------------------

static func grip_drain_multiplier() -> float:
	return Balance.BUTTERFINGERS_GRIP_DRAIN if has("butterfingers") else 1.0


## Scales how fast players speed up and brake.
static func control_multiplier() -> float:
	return Balance.SLIPPERY_SOLES_CONTROL if has("slippery_soles") else 1.0


static func damage_multiplier() -> float:
	return Balance.GLASS_CARGO_DAMAGE if has("glass_cargo") else 1.0


static func mass_multiplier() -> float:
	return Balance.HEAVY_LIFTING_MASS if has("heavy_lifting") else 1.0


static func extra_sticky_pairs() -> int:
	return Balance.EXTRA_GUM_PAIRS if has("extra_gum") else 0


## Scales the end-of-day running costs.
static func overhead_multiplier() -> float:
	return Balance.GREEDY_LANDLORD_COSTS if has("greedy_landlord") else 1.0


## Scales a contract's base pay.
static func pay_multiplier() -> float:
	return Balance.CHEAPSKATE_CLIENTS_PAY if has("cheapskate_clients") else 1.0


# --- helpers -----------------------------------------------------------------

## 1.6 -> 60 ("60% more").
static func _more(multiplier: float) -> int:
	return roundi((multiplier - 1.0) * 100.0)


## 0.55 -> 45 ("45% less").
static func _less(multiplier: float) -> int:
	return roundi((1.0 - multiplier) * 100.0)
