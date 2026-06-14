class_name SteeringBlender
extends RefCounted

## Pure brain-side logic: converts resolved tactics + live situation into a
## directive dict on ship.orders.
##
## Directive fields produced:
##   engagement_target  : String   — ship_id to fight; "" = none
##   goal_weights       : Dictionary — {pursue, keep_range, evade, formation, support} ≥ 0
##   preferred_range    : float    — desired distance to engagement_target
##   facing_mode        : String   — "auto" / "nose_on" / "broadside"
##
## formation_slot and anchor_position are NOT set here — FormationSystem stamps
## them each frame with live positions (the enemy centroid moves every tick).
## The brain only sets the formation *weight* in goal_weights (from duty).
##
## All inputs are read-only. Nothing here mutates ship or tactics state.

# ---------------------------------------------------------------------------
# Preferred-range mapping (range_scalar 0..1 → world-unit range)
# ---------------------------------------------------------------------------

## At range_scalar = 0 (knife), desired range is this multiplier × weapon_optimal.
## < 0.5 so the brawler dives well inside mid-range while remaining in firing range.
const KNIFE_RANGE_MULTIPLIER := 0.35

## At range_scalar = 1 (kite), desired range is this multiplier × weapon_optimal.
## Capped ≤ 1.0 so a kiter fights at the FAR EDGE of its weapon envelope, never
## beyond it. The old 2.5× value put ships 2.5× past max weapon range so they
## orbited uselessly and never fired — the core correctness bug this fixes.
const KITE_RANGE_MULTIPLIER := 0.9

## Minimum preferred_range floor regardless of weapon_optimal or scalar.
## Prevents a degenerate 0-range goal when weapon_optimal is very small.
const MIN_PREFERRED_RANGE := 200.0

# ---------------------------------------------------------------------------
# Weight bases and situational scales
# ---------------------------------------------------------------------------

## Base pursue weight when mentality_scalar = 0 (fully defensive).
## Even a defensive ship nudges toward its target so it doesn't flee passively.
const PURSUE_WEIGHT_AT_ZERO_MENTALITY := 0.05

## How much extra pursue weight a fully aggressive ship (mentality_scalar=1) adds.
## Total pursue = BASE + mentality_scalar × SCALE.
const PURSUE_WEIGHT_MENTALITY_SCALE := 0.95

## keep_range weight is constant — orbit geometry is always active.
## This is intentional: both brawl (short range) and kite (long range) emerge
## from preferred_range, not from changing this weight.
const KEEP_RANGE_WEIGHT := 0.4

## Evade base weight: minimum evasion even in calm situations.
const EVADE_WEIGHT_BASE := 0.05

## Extra evade added when the ship is actively being targeted by an enemy.
## "Targeted" = ship_id appears in at least one threat's targeting list.
const EVADE_WEIGHT_TARGETED := 0.25

## Extra evade added when hull condition is critical (below HULL_CRITICAL_THRESHOLD).
const EVADE_WEIGHT_LOW_HULL := 0.35

## Hull fraction below which the ship is treated as "low hull."
## Using fraction so it works regardless of absolute hull values.
const HULL_CRITICAL_THRESHOLD := 0.3

## Extra evade added per outnumbering enemy beyond parity.
## Caps at EVADE_OUTNUMBER_CAP_ENEMIES excess enemies to avoid runaway weight.
const EVADE_WEIGHT_PER_EXTRA_ENEMY := 0.08
const EVADE_OUTNUMBER_CAP_ENEMIES := 3

## Formation weights by duty — how strongly a ship holds its formation slot.
## hold   → high formation: the ship is an anchor for the line; keeps shape.
## support → moderate formation: flexibility between holding and engaging.
## press  → low formation: the ship breaks toward targets; shape loosens.
const FORMATION_WEIGHT_HOLD    := 0.6
const FORMATION_WEIGHT_SUPPORT := 0.3
const FORMATION_WEIGHT_PRESS   := 0.05

## Weight of the escort-pull goal toward the supported ally.
## Blended alongside engage/evade so the pilot orbits near the ally while
## still fighting — not a discrete maneuver, just a directional bias.
## Set to zero automatically when no support_assignment is active.
const SUPPORT_WEIGHT := 0.45

# Posture weight sets — applied ON TOP of tactics-derived weights when a
# commander order has set crew["posture"].  Empty posture → no override.

## withdraw: commanded disengage — evade-dominant blend, not a hard flee reflex.
## pursue ≈ 0 so the ship stops closing; formation stays low (moving away, not
## holding line); evade high so MovementSystem biases toward the team's rear.
const POSTURE_WITHDRAW := {
	"pursue":     0.02,   # near-zero — stop chasing
	"keep_range": 0.4,    # unchanged — maintain orbit geometry
	"evade":      0.8,    # dominant — bias toward exit
	"formation":  0.05,   # low — breaking from formation to withdraw
}

## hold: hold the line — formation-dominant, don't chase past the line.
## pursue reduced so the ship won't break rank; evade normal; formation high
## so MovementSystem keeps the ship in its slot rather than drifting forward.
const POSTURE_HOLD := {
	"pursue":     0.1,    # reduced — don't abandon position to chase
	"keep_range": 0.4,    # unchanged — orbit still active
	"evade":      0.2,    # normal — still reacts to incoming fire
	"formation":  0.7,    # dominant — anchor the line
}

## press: an active press-attack posture (captain/commander press-attack, or a
## fleet all-out order). Close NOW and brawl — the aggressive counterpart to withdraw.
## pursue dominant, keep_range/evade minimal so the ship dives inside firing
## range and stays there rather than orbiting or peeling off.
const POSTURE_PRESS := {
	"pursue":     0.7,    # dominant — drive in and close
	"keep_range": 0.3,    # retained — still respects weapon range, avoids piling onto one point
	"evade":      0.1,    # low — commits, but not blind to incoming fire
	"formation":  0.15,   # some cohesion kept so a pressing wing doesn't fully clump
}

# facing_mode per role
## Maps a ship role to its facing_mode string.
## artillery presents broadside so its side batteries bear on the target.
## anchor/brawler/screen go nose-on to tank bow armor and bring forward guns.
## skirmisher/interceptor/flanker use the inherited fighter "auto" rule.
## Any unknown role falls back to "auto" — safest default, preserves prior behavior.
const FACING_MODE_BY_ROLE := {
	"artillery":   "broadside",
	"anchor":      "nose_on",
	"brawler":     "nose_on",
	"screen":      "nose_on",
	"skirmisher":  "auto",
	"interceptor": "auto",
	"flanker":     "auto",
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Build a directive dict from the current ship state, resolved tactics, and
## the live target/threat picture.
##
## Parameters
##   ship               : Dictionary — ship_data with at least .ship_id, .stats,
##                        and optionally .internals for hull fraction
##   tactics            : Dictionary — resolved tactics block (from TacticsSystem);
##                        must contain mentality_scalar and range_scalar
##   target             : Dictionary — target ship_data (may be {})
##   threats            : Array[Dictionary] — threat entries from awareness;
##                        each may carry .target_id for "is this ship targeted?" checks
##   weapon_optimal_range : float — preferred firing range for this ship's weapons
##   posture            : String — commander-ordered posture ("withdraw", "hold", "")
##   support_pos        : Variant — Vector2 ally position from FormationSystem, or null
##
## Returns all Phase-2 contract fields. formation_slot and anchor_position
## are zero here — FormationSystem stamps live values onto orders each frame.
static func build_directive(
	ship: Dictionary,
	tactics: Dictionary,
	target: Dictionary,
	threats: Array,
	weapon_optimal_range: float,
	posture: String = "",
	support_pos: Variant = null
) -> Dictionary:
	var mentality_scalar: float = tactics.get("mentality_scalar", 0.5)
	var range_scalar: float     = tactics.get("range_scalar",     0.5)

	var engagement_target: String = target.get("ship_id", "")

	var preferred_range: float = _compute_preferred_range(range_scalar, weapon_optimal_range)
	var goal_weights: Dictionary = _compute_goal_weights(ship, mentality_scalar, tactics, threats, posture, support_pos)
	var facing_mode: String = _compute_facing_mode(tactics)

	return {
		"engagement_target": engagement_target,
		"goal_weights":      goal_weights,
		"preferred_range":   preferred_range,
		"facing_mode":       facing_mode,
		# FormationSystem owns these; zero here so callers can read safely
		# without a null check before MovementSystem runs.
		"formation_slot":    Vector2.ZERO,
		"anchor_position":   Vector2.ZERO,
		# support_pos echoed through so MovementSystem can blend toward it.
		# Null means no escort assignment is active.
		"support_pos":       support_pos,
	}


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Map range_scalar [0..1] onto preferred_range in world units.
## 0 (knife) → KNIFE_RANGE_MULTIPLIER × optimal  (short  — brawl; dives in close)
## 1 (kite)  → KITE_RANGE_MULTIPLIER  × optimal  (far edge — just inside weapon range)
## Both multipliers are ≤ 1.0, so preferred_range is ALWAYS within the weapon envelope.
## A kiter orbits at 90% of max weapon range — far enough to frustrate brawlers but
## close enough to fire every pass. Lerp gives a continuous dial.
static func _compute_preferred_range(range_scalar: float, weapon_optimal_range: float) -> float:
	var multiplier: float = lerp(KNIFE_RANGE_MULTIPLIER, KITE_RANGE_MULTIPLIER, range_scalar)
	return maxf(weapon_optimal_range * multiplier, MIN_PREFERRED_RANGE)


## Compute goal_weights from mentality, duty, and live situation.
##
## pursue:     rises with mentality_scalar — aggressive ships chase hard
## keep_range: constant — orbit geometry is always in play
## evade:      floor + situational bumps (targeted, low hull, outnumbered)
## formation:  set from duty — hold keeps the line; press breaks to chase;
##             support sits between. FormationSystem supplies the actual slot
##             position each frame, so a high weight really does hold the shape.
## support:    SUPPORT_WEIGHT when escort active; 0.0 otherwise.
##             Pulls the ship toward the protected ally's live position (support_pos).
##             The pilot still engages threats near the ally — this is a bias, not a lock.
##
## Weights are not normalized here; the converter normalizes on use.
static func _compute_goal_weights(
	ship: Dictionary,
	mentality_scalar: float,
	tactics: Dictionary,
	threats: Array,
	posture: String = "",
	support_pos: Variant = null
) -> Dictionary:
	# When a command posture is active, return its pre-set weight set directly.
	# Posture is a commanded directive bias — it overrides the tactics-derived
	# weights entirely so the pilot's blend reflects the order, not its own
	# aggression/duty. Empty posture falls through to the normal path (no regression).
	# Support weight is appended even in posture mode so escort pull is never lost.
	var support_weight: float = SUPPORT_WEIGHT if support_pos != null else 0.0
	match posture:
		"withdraw":
			var w := POSTURE_WITHDRAW.duplicate()
			w["support"] = support_weight
			return w
		"hold":
			var w := POSTURE_HOLD.duplicate()
			w["support"] = support_weight
			return w
		"press":
			var w := POSTURE_PRESS.duplicate()
			w["support"] = support_weight
			return w

	# Normal tactics-derived path — unchanged from pre-posture baseline.

	# pursue: scales linearly from near-zero (defensive) to near-full (all_out)
	var pursue: float = PURSUE_WEIGHT_AT_ZERO_MENTALITY + mentality_scalar * PURSUE_WEIGHT_MENTALITY_SCALE

	var evade: float = EVADE_WEIGHT_BASE

	# Situational bump: is this ship explicitly being targeted by an enemy?
	if _is_ship_targeted(ship, threats):
		evade += EVADE_WEIGHT_TARGETED

	# Situational bump: low hull — survival starts mattering more than offence
	if _hull_fraction(ship) < HULL_CRITICAL_THRESHOLD:
		evade += EVADE_WEIGHT_LOW_HULL

	# Situational bump: outnumbered — each extra enemy above parity adds pressure
	var extra_enemies: int = mini(threats.size() - 1, EVADE_OUTNUMBER_CAP_ENEMIES)
	if extra_enemies > 0:
		evade += extra_enemies * EVADE_WEIGHT_PER_EXTRA_ENEMY

	# Formation weight from duty: hold → line holds; press → ship chases; support → mid.
	# This composes with pursue/evade — a hold ship still fires but won't abandon its slot.
	var duty: String = tactics.get("duty", "support")
	var formation: float
	match duty:
		"hold":    formation = FORMATION_WEIGHT_HOLD
		"press":   formation = FORMATION_WEIGHT_PRESS
		_:         formation = FORMATION_WEIGHT_SUPPORT   # "support" and any unknown duty

	return {
		"pursue":     pursue,
		"keep_range": KEEP_RANGE_WEIGHT,
		"evade":      evade,
		"formation":  formation,
		"support":    support_weight,
	}


## True if any threat's target_id matches this ship's ship_id.
## Threats that don't carry target_id are ignored (conservative — avoids
## false positives from non-targeting threats like area effects).
static func _is_ship_targeted(ship: Dictionary, threats: Array) -> bool:
	var my_id: String = ship.get("ship_id", "")
	if my_id.is_empty():
		return false
	for threat in threats:
		if threat.get("target_id", "") == my_id:
			return true
	return false


## Derive facing_mode from the ship's resolved role.
## The role encodes the ship's combat identity, which directly determines how
## it should orient: artillery keeps its side batteries on the enemy (broadside),
## tanks/screens keep their bow armor forward (nose_on), and fast movers defer
## to the existing auto rule so their dogfighting logic is undisturbed.
static func _compute_facing_mode(tactics: Dictionary) -> String:
	var role: String = tactics.get("role", "")
	return FACING_MODE_BY_ROLE.get(role, "auto")


## Hull fraction: ratio of surviving internal health to total max health.
## Falls back to 1.0 (healthy) when no internals are present so that ships
## without health data are not treated as critically damaged.
static func _hull_fraction(ship: Dictionary) -> float:
	var internals: Array = ship.get("internals", [])
	if internals.is_empty():
		return 1.0
	var total_max: float = 0.0
	var total_cur: float = 0.0
	for comp in internals:
		total_max += float(comp.get("max_health", 0))
		total_cur += float(comp.get("current_health", 0))
	if total_max <= 0.0:
		return 1.0
	return total_cur / total_max
