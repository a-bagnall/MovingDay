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


# --- Handling: how it feels to move and to carry ------------------------------------------
## Every character shares one controller, so these apply to all of them. If it feels floaty:
## raise PLAYER_BRAKING (stops sooner), raise CARRY_STIFFNESS (the item keeps up with you),
## raise HELD_ANGULAR_DAMP (it swings less) or raise HOLD_GRAVITY_SCALE (it floats less).

## Walking. Acceleration and braking are m/s per second; the top speed is 5 m/s.
const PLAYER_ACCELERATION := 20.0
const PLAYER_BRAKING := 16.0
## Below 1 makes reversing direction sluggish (and can cause a stumble at speed).
const REVERSAL_PENALTY := 0.8
## While carrying, how fast you speed up and brake scales between this and 1.0 by how
## little the load slows you. 1.0 = carrying never dulls the controls.
const CARRY_RESPONSE_FLOOR := 0.85

## The spring that pulls a held item to the player. Critical damping (no bounce, no lag)
## is 2 * sqrt(stiffness), so keep CARRY_DAMPING at or just above that.
const CARRY_STIFFNESS := 90.0
const CARRY_DAMPING := 19.0
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
const SOLO_HEAVY_SPEED := 0.45


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
