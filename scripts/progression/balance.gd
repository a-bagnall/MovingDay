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
