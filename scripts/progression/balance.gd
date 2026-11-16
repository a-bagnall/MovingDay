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
const DAY_LENGTH := 10.0
## The team visits the hub (shop and Pick One) before every Nth day.
const HUB_EVERY_N_DAYS := 3
## Day 1 spawns a single easy Box only, to keep the first job gentle while testing.
## Set false to play day 1 with the whole house.
const DAY_ONE_SINGLE_ITEM := true


# --- Pay ------------------------------------------------------------------------------

## Seconds under which a time bonus is earned, and dollars earned per second under it.
const PAR_TIME := 120.0
const TIME_BONUS_RATE := 2.0
## Extra pay, as a fraction of base + time bonus, for the outfit worn on the day.
const WORKWEAR_STYLE_BONUS := 0.10
const ENCHANTED_WORKWEAR_STYLE_BONUS := 0.15


# --- Running costs (what ends a run) ---------------------------------------------------

## At the end of each day the company pays running costs (fuel, wages, rent). If that
## takes the wallet below zero the company goes bankrupt and the run is over.
const OVERHEAD_BASE := 150.0
const OVERHEAD_PER_DAY := 60.0


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


# --- Solo play ------------------------------------------------------------------------

## One player can do every job. When a single player is the whole team, a two-player item can
## be carried alone, with no grip loss, at this fraction of walking speed (a one-player item
## alone moves at up to 0.7, a team of two at up to 0.95). Lower = harder.
const SOLO_HEAVY_SPEED := 0.45


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
