class_name Balance
extends RefCounted
## Every tuning number for the run in one place. Edit a value, press F5, play.
##
## Nothing here has logic apart from `overhead_for_day`. Other scripts read these
## constants (RunModifiers, ContractTracker, GameFlow, Hub, StickyLinks), and the text on
## the Pick One cards and shop pads is built from them, so a changed number never leaves
## stale text behind.
##
## Rough economy at the defaults, assuming one contract a day (see DAY_LENGTH): a clean job
## pays about $500-$800, running costs start at $150 and climb $60 a day, so a careful team
## stays solvent into the low teens and a sloppy one (or one with a few modifiers) goes
## bankrupt around days 8-12. If runs end too early or too late, tune OVERHEAD_* first.


# --- Day and run structure ------------------------------------------------------------

## Seconds of job time in a day. A contract that finishes after the clock hits zero is the
## day's last. NOTE: 10 s means every day is exactly one contract (the clock was this short
## while the loop was being built). Try 240-400 for two or three contracts a day, and then
## raise OVERHEAD_* too, since there is more money to be made per day.
static var DAY_LENGTH := 240.0
## The team visits the hub (shop and Pick One) before every Nth day.
const HUB_EVERY_N_DAYS := 3

## Contract workload ramps by contract attempt across the whole run.
static var CONTRACT_START_ITEMS := 1
static var CONTRACT_ITEMS_PER_STEP := 1
static var CONTRACT_ITEMS_EVERY := 1
static var CONTRACT_MAX_ITEMS := 7
const CONTRACT_ITEM_ORDER := ["Box", "Chair", "Lamp", "TV", "Cabinet", "Sofa", "Fridge"]

## A missed contract pays for delivered items, then deducts this penalty.
static var FAILED_CONTRACT_BASE_PENALTY := 150.0
static var FAILED_CONTRACT_PER_MISSING_ITEM_PENALTY := 75.0
static var CONTRACT_PAYOUT_MULTIPLIER := 1.0


# --- Pay ------------------------------------------------------------------------------

## Seconds under which a time bonus is earned, and dollars earned per second under it.
static var PAR_TIME := 120.0
static var TIME_BONUS_RATE := 2.0
## Extra pay, as a fraction of base + time bonus, for the outfit worn on the day.
const WORKWEAR_STYLE_BONUS := 0.10
const ENCHANTED_WORKWEAR_STYLE_BONUS := 0.15


# --- Running costs (what ends a run) ---------------------------------------------------

## At the end of each day the company pays running costs (fuel, wages, rent). If that
## takes the wallet below zero the company goes bankrupt and the run is over.
static var OVERHEAD_BASE := 150.0
static var OVERHEAD_PER_DAY := 60.0


static func overhead_for_day(day: int) -> float:
	return OVERHEAD_BASE + OVERHEAD_PER_DAY * float(maxi(day - 1, 0))


# --- Pick One modifiers ----------------------------------------------------------------

## A choice is offered at the hub every this many days; it shows this many cards.
const MODIFIER_EVERY_N_DAYS := 3
const MODIFIER_OFFER_SIZE := 3

## Multipliers (1.0 = no change). Higher is worse unless noted.
const BUTTERFINGERS_GRIP_DRAIN := 1.6      # grip drains this much faster
const SLIPPERY_SOLES_CONTROL := 0.55       # LOWER is worse: players accelerate and brake at this fraction
const GLASS_CARGO_DAMAGE := 1.6            # damage taken
const HEAVY_LIFTING_MASS := 1.35           # furniture mass
const EXTRA_GUM_PAIRS := 2                 # extra stuck-together pairs (still capped by STICKY_MAX_PAIRS)
const GREEDY_LANDLORD_COSTS := 1.35        # running costs
const CHEAPSKATE_CLIENTS_PAY := 0.8        # LOWER is worse: base contract pay

## Wet Floors: slick puddles on the ground floor, on the way from the furniture to the truck.
const WET_FLOORS_PUDDLES := 4              # how many
const WET_FLOORS_RADIUS := 0.9             # metres
const WET_FLOORS_CONTROL := 0.2            # LOWER is worse: control (acceleration and braking) while standing in one


# --- Handling: how it feels to move and to carry ------------------------------------------
## Every character shares one controller, so these apply to all of them. If it feels floaty:
## raise PLAYER_BRAKING (stops sooner), raise CARRY_STIFFNESS (the item keeps up with you),
## raise HELD_ANGULAR_DAMP (it swings less) or raise HOLD_GRAVITY_SCALE (it floats less).

## Walking. Acceleration and braking are m/s per second; the top speed is 5 m/s.
static var PLAYER_ACCELERATION := 20.0
static var PLAYER_BRAKING := 16.0
## Below 1 makes reversing direction sluggish (and can cause a stumble at speed).
const REVERSAL_PENALTY := 0.8
## While carrying, how fast you speed up and brake scales between this and 1.0 by how
## little the load slows you. 1.0 = carrying never dulls the controls.
const CARRY_RESPONSE_FLOOR := 0.85

## The spring that pulls a held item to the player. Critical damping (no bounce, no lag)
## is 2 * sqrt(stiffness), so keep CARRY_DAMPING at or just above that.
static var CARRY_STIFFNESS := 90.0
static var CARRY_DAMPING := 19.0
## Cap (m/s^2) on how hard that spring can accelerate an item.
const MAX_CARRY_ACCEL := 70.0
## Gravity on a fully lifted item (1.0 = full weight; lower floats). And rotational drag
## while held (higher = less swing).
const HOLD_GRAVITY_SCALE := 0.85
const HELD_ANGULAR_DAMP := 7.0


# --- Solo play ------------------------------------------------------------------------

## One player can do every job. When a single player is the whole team, a two-player item can
## be carried alone, with no grip loss, at this fraction of walking speed (a one-player item
## alone moves at up to 0.7, a team of two at up to 0.95). Lower = harder.
static var SOLO_HEAVY_SPEED := 0.45


# --- Lift (hold the Lift button while carrying) ----------------------------------------

## How much higher (metres) a carried item rides while its holder holds Lift: enough to
## clear a rail or a counter.
const LIFT_EXTRA_HEIGHT := 0.65
## Extra grip lost per second while someone holds Lift, so it is a move, not a pose.
const LIFT_GRIP_DRAIN := 0.12


# --- Shove (the Action button with empty hands) -----------------------------------------

## Seconds before the same player can shove again, and how far in front a shove reaches (m).
const SHOVE_COOLDOWN := 1.0
const SHOVE_REACH := 1.5
## A shoved player is knocked this fast (m/s) and stumbles briefly.
const SHOVE_PLAYER_SPEED := 5.0
## A shoved item gets this impulse (kg m/s), so a light box flies and a sofa barely budges.
const SHOVE_FURNITURE_IMPULSE := 28.0
## Chance a shove damages an item: fragility times this, never below the minimum. Anything
## in the Fragile tier is always damaged, and a sturdy item only rarely.
const SHOVE_BREAK_CHANCE_PER_FRAGILITY := 1.5
const SHOVE_MIN_BREAK_CHANCE := 0.1
## When it does, the damage is this fraction of the item's value, between sturdy (0 fragility)
## and fully fragile (1.0).
const SHOVE_DAMAGE_MIN_FRACTION := 0.05
const SHOVE_DAMAGE_MAX_FRACTION := 0.7


# --- Throw (hold Action while carrying a light item, release to throw) -------------------

## Only items this light, and needing one player, can be thrown.
const THROW_MAX_MASS := 10.0
## Seconds of holding Action for a full-strength throw; a quick tap is a short toss.
const THROW_CHARGE_TIME := 0.8
const THROW_MIN_SPEED := 3.5
const THROW_MAX_SPEED := 10.0
## Upward speed as a fraction of the throw speed, for an arc.
const THROW_ARC := 0.45
## Seconds before the same player can start another throw.
const THROW_COOLDOWN := 0.6


# --- Heave-ho (two carriers press the Heave button together) -----------------------------

## Both carriers must press within this many seconds of each other.
const HEAVE_WINDOW := 0.35
## The burst: the team moves this much faster for this long, and its grip is restored.
const HEAVE_SPEED_BOOST := 1.35
const HEAVE_DURATION := 1.2
## Seconds before the same item can be heaved again.
const HEAVE_COOLDOWN := 4.0


# --- Sticky pairs ---------------------------------------------------------------------

const STICKY_FIRST_DAY := 3
const STICKY_PAIR_EVERY_DAYS := 5   # one more pair this many days after the last
const STICKY_MAX_PAIRS := 4


# --- Hub shop -------------------------------------------------------------------------

const COFFEE_PRICE := 50
const COFFEE_SPEED := 1.15
const ENERGY_PRICE := 60
const ENERGY_ACCELERATION := 1.20
const WORKWEAR_PRICE := 150
const ENCHANTED_WORKWEAR_PRICE := 400


# --- HUD ------------------------------------------------------------------------------

## The day clock turns pink under this many seconds.
const LOW_TIME_WARNING := 60.0



## Number of easiest furniture items requested by a contract attempt.
static func contract_item_target(contract_number: int) -> int:
	var step := floori(float(maxi(contract_number - 1, 0)) / float(maxi(CONTRACT_ITEMS_EVERY, 1)))
	return clampi(CONTRACT_START_ITEMS + step * CONTRACT_ITEMS_PER_STEP, 1, CONTRACT_MAX_ITEMS)


## Controls shown by the in-game F4 Balance Lab. Changes last for this play session.
static func debug_controls() -> Array[Dictionary]:
	return [
		{"id":"DAY_LENGTH","label":"Day length (sec)","min":30.0,"max":900.0,"step":15.0,"value":DAY_LENGTH},
		{"id":"CONTRACT_START_ITEMS","label":"Starting items","min":1.0,"max":7.0,"step":1.0,"value":CONTRACT_START_ITEMS},
		{"id":"CONTRACT_ITEMS_PER_STEP","label":"Items added per step","min":1.0,"max":3.0,"step":1.0,"value":CONTRACT_ITEMS_PER_STEP},
		{"id":"CONTRACT_ITEMS_EVERY","label":"Contracts per step","min":1.0,"max":5.0,"step":1.0,"value":CONTRACT_ITEMS_EVERY},
		{"id":"CONTRACT_MAX_ITEMS","label":"Maximum items","min":1.0,"max":7.0,"step":1.0,"value":CONTRACT_MAX_ITEMS},
		{"id":"FAILED_CONTRACT_BASE_PENALTY","label":"Failure base penalty ($)","min":0.0,"max":1000.0,"step":25.0,"value":FAILED_CONTRACT_BASE_PENALTY},
		{"id":"FAILED_CONTRACT_PER_MISSING_ITEM_PENALTY","label":"Penalty per missed item ($)","min":0.0,"max":500.0,"step":10.0,"value":FAILED_CONTRACT_PER_MISSING_ITEM_PENALTY},
		{"id":"CONTRACT_PAYOUT_MULTIPLIER","label":"Contract payout multiplier","min":0.1,"max":3.0,"step":0.05,"value":CONTRACT_PAYOUT_MULTIPLIER},
		{"id":"PAR_TIME","label":"Par time (sec)","min":10.0,"max":600.0,"step":10.0,"value":PAR_TIME},
		{"id":"TIME_BONUS_RATE","label":"Time bonus ($/sec)","min":0.0,"max":20.0,"step":0.5,"value":TIME_BONUS_RATE},
		{"id":"OVERHEAD_BASE","label":"Base daily overhead ($)","min":0.0,"max":1500.0,"step":25.0,"value":OVERHEAD_BASE},
		{"id":"OVERHEAD_PER_DAY","label":"Overhead growth/day ($)","min":0.0,"max":500.0,"step":10.0,"value":OVERHEAD_PER_DAY},
		{"id":"PLAYER_ACCELERATION","label":"Player acceleration","min":2.0,"max":40.0,"step":1.0,"value":PLAYER_ACCELERATION},
		{"id":"PLAYER_BRAKING","label":"Player braking","min":2.0,"max":40.0,"step":1.0,"value":PLAYER_BRAKING},
		{"id":"CARRY_STIFFNESS","label":"Carry stiffness","min":10.0,"max":200.0,"step":5.0,"value":CARRY_STIFFNESS},
		{"id":"CARRY_DAMPING","label":"Carry damping","min":2.0,"max":40.0,"step":1.0,"value":CARRY_DAMPING},
		{"id":"SOLO_HEAVY_SPEED","label":"Solo heavy speed","min":0.1,"max":1.0,"step":0.05,"value":SOLO_HEAVY_SPEED},
	]


static func set_debug_value(id: String, value: float) -> void:
	match id:
		"DAY_LENGTH": DAY_LENGTH = value
		"CONTRACT_START_ITEMS": CONTRACT_START_ITEMS = roundi(value)
		"CONTRACT_ITEMS_PER_STEP": CONTRACT_ITEMS_PER_STEP = roundi(value)
		"CONTRACT_ITEMS_EVERY": CONTRACT_ITEMS_EVERY = roundi(value)
		"CONTRACT_MAX_ITEMS": CONTRACT_MAX_ITEMS = roundi(value)
		"FAILED_CONTRACT_BASE_PENALTY": FAILED_CONTRACT_BASE_PENALTY = value
		"FAILED_CONTRACT_PER_MISSING_ITEM_PENALTY": FAILED_CONTRACT_PER_MISSING_ITEM_PENALTY = value
		"CONTRACT_PAYOUT_MULTIPLIER": CONTRACT_PAYOUT_MULTIPLIER = value
		"PAR_TIME": PAR_TIME = value
		"TIME_BONUS_RATE": TIME_BONUS_RATE = value
		"OVERHEAD_BASE": OVERHEAD_BASE = value
		"OVERHEAD_PER_DAY": OVERHEAD_PER_DAY = value
		"PLAYER_ACCELERATION": PLAYER_ACCELERATION = value
		"PLAYER_BRAKING": PLAYER_BRAKING = value
		"CARRY_STIFFNESS": CARRY_STIFFNESS = value
		"CARRY_DAMPING": CARRY_DAMPING = value
		"SOLO_HEAVY_SPEED": SOLO_HEAVY_SPEED = value
