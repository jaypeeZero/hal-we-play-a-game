extends RefCounted
class_name LargeShipPilotAI

## LargeShipPilotAI - Corvette and capital ship pilot behavior.
##
## A capital does not dogfight; it manages range and arcs. The pilot loops
## through an engagement-cycle FSM (closing → broadside → kiting →
## repositioning → fighting_withdrawal) modulated by skill, aggression, and
## composure, with a self-preservation overlay and a tactical-break interrupt
## for arc threats. Same shape as `fighter_pilot_ai.gd`; different numbers and
## states because broadside warfare is a different problem.

## ---------------------------------------------------------------------------
## RANGE BANDS — broadside warfare lives in a wider, slower band than fighters,
## but the bands have to fit inside the patrol-area leash radius for large
## ships, otherwise the leash forcibly rotates the ship homeward and kills
## any perpendicular broadside heading the FSM is asking for.
## ---------------------------------------------------------------------------
const BROADSIDE_FAR_RANGE = 2200.0          # Beyond this we are still closing
const BROADSIDE_OPTIMAL_RANGE = 1200.0      # Sweet spot for arc-on broadside
const BROADSIDE_TOO_CLOSE = 500.0           # Inside this we must reposition
const BROADSIDE_ARC_DOT = 0.30              # cos(~72°) — perpendicular ±18°
const SAFE_RANGE_VS_FIGHTERS = 1100.0       # Inside this fighters are kited

## Phase-machine timing
const PHASE_MIN_DURATION = 1.0              # Commit briefly before re-evaluating
const PHASE_REPOSITION_TIMEOUT = 6.0        # Cap reposition phase length
const PERSONALITY_TIMING_SPREAD = 1.6       # Hot vs. cold timing multiplier

## Personality range modulation: ±20% on optimal/safe ranges via aggression
const RANGE_AGGRESSION_SPREAD = 0.20

## ---------------------------------------------------------------------------
## SELF-PRESERVATION — capital ships withdraw rather than bail
## ---------------------------------------------------------------------------
const SECTION_CRITICAL_RATIO = 0.20         # Any principal section below this → withdraw
const OUTGUNNED_RANGE = 4000.0              # Local capital balance evaluated within this
const OUTGUNNED_AGGRESSION_THRESHOLD = 0.7  # Heroic captains ignore the count

## ---------------------------------------------------------------------------
## TACTICAL BREAK — interrupts the FSM regardless of phase
## ---------------------------------------------------------------------------
const TACTICAL_BREAK_RANGE_LARGE = 800.0    # Capital-class threat radius for break
const TACTICAL_BREAK_ARC_DOT = 0.85         # cos(~32°) — they have us in arc

## ---------------------------------------------------------------------------
## AREA LEASH — pull a wandering capital home (matches fighter convention)
## ---------------------------------------------------------------------------
const AREA_HARD_RETURN_MULTIPLIER = 1.5     # Beyond 1.5x leash → drop fight, go home

## ---------------------------------------------------------------------------
## DECISION CADENCE
## ---------------------------------------------------------------------------
const DECISION_DELAY_NORMAL_MIN = 0.5
const DECISION_DELAY_NORMAL_MAX = 1.0
const DECISION_DELAY_URGENT = 0.3           # Tactical break / withdrawal
const DECISION_DELAY_IDLE_MIN = 1.0
const DECISION_DELAY_IDLE_MAX = 2.0

## Composure stress impact (mirrors FighterPilotAI)
const COMPOSURE_STRESS_DECAY = 0.5

## Fallback tactics for un-configured crew (mirrors AttackAction.FALLBACK_TACTICS).
## Produces coherent mid-range balanced behavior so a capital without a doctrine block
## still drives through the blender rather than crashing.
const FALLBACK_TACTICS := {
	"mentality_scalar": 0.5,
	"range_scalar":     0.5,
}

## ---------------------------------------------------------------------------
## MAIN ENTRY
## ---------------------------------------------------------------------------
static func make_decision(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float) -> Dictionary:
	# ESCAPE BOUNDARY (hardest override) — a committed flee runs for the exit
	# and a returning ship heads back inward, both above the area leash and
	# the engagement FSM. Same one-time decision the fighters make.
	var flee := _reflex_edge_boundary(crew_data, ship_data, all_ships, game_time)
	if not flee.is_empty():
		return flee

	# AREA LEASH (hard override) — same shape as FighterPilotAI: a capital
	# holding broadside at the edge of its zone runs at low throttle, so the
	# physics-layer leash isn't enough to bring it home. Beyond
	# AREA_HARD_RETURN_MULTIPLIER x radius, drop the fight and burn back.
	if _is_far_outside_area(ship_data):
		return _make_return_to_area_decision(crew_data, ship_data, game_time)

	var target := _find_best_target(crew_data, ship_data, all_ships)
	if target.is_empty():
		return _make_idle_decision(crew_data, game_time)

	# SELF-PRESERVATION — assessed every tick. Triggers force the FSM to
	# fighting_withdrawal until the trigger clears (hull stabilises or contact
	# is broken).
	var survival_mode := _assess_survival_state(crew_data, ship_data, all_ships)

	# Step the FSM. The phase persists in crew_data.combat_state across ticks.
	var phase_info := _step_engagement_phase(crew_data, ship_data, target, survival_mode, game_time)
	var phase: String = phase_info.phase

	# TACTICAL BREAK — overrides the current phase for one decision when the
	# threat sensor finds a capital-class nose on us at close range.
	var threat := _check_tactical_break(ship_data, all_ships, crew_data)
	if not threat.is_empty():
		return _make_tactical_break_decision(crew_data, ship_data, threat, game_time)

	return _emit_phase_maneuver(crew_data, ship_data, target, phase, game_time)


## ---------------------------------------------------------------------------
## TARGETING
## ---------------------------------------------------------------------------
static func _find_best_target(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array) -> Dictionary:
	var my_team: int = ship_data.get("team", -1)
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var best_target := {}
	var best_score: float = -INF

	for ship in all_ships:
		if ship.get("team", -1) == my_team:
			continue
		var status := str(ship.get("status", ""))
		if status == "destroyed" or status == "exploding" or status == "disabled":
			continue

		var distance: float = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		var score: float = 10000.0 - distance

		# Soft-damaged targets (anything wounded) are a little more attractive.
		if status == "damaged":
			score += 5000.0

		if score > best_score:
			best_score = score
			best_target = ship

	return best_target


## ---------------------------------------------------------------------------
## ENGAGEMENT-CYCLE FSM
## ---------------------------------------------------------------------------
## Phases:
##   closing                 — beyond optimal range, close in
##   broadside               — in the optimal band with arc on target
##   kiting                  — vs fighters inside SAFE_RANGE_VS_FIGHTERS
##   repositioning           — broadside lost, swing for a new arc
##   fighting_withdrawal     — survival overlay; held until trigger clears

## Update and read the current FSM phase. Mutates crew_data.combat_state
## in place (same pattern as FighterPilotAI).
static func _step_engagement_phase(
	crew_data: Dictionary,
	ship_data: Dictionary,
	target: Dictionary,
	survival_mode: String,
	game_time: float
) -> Dictionary:
	var combat_state: Dictionary = crew_data.get("combat_state", {})
	if not crew_data.has("combat_state"):
		crew_data["combat_state"] = combat_state

	var target_id: String = str(target.get("ship_id", ""))
	var prev_target: String = str(combat_state.get("phase_target_id", ""))
	var phase: String = str(combat_state.get("engagement_phase", "closing"))
	var phase_started_at: float = float(combat_state.get("phase_started_at", game_time))

	# New target → reset cycle
	if target_id != prev_target:
		phase = "closing"
		phase_started_at = game_time

	var phase_age: float = max(0.0, game_time - phase_started_at)
	var next_phase: String = _compute_next_phase(phase, phase_age, ship_data, target, crew_data, survival_mode)
	if next_phase != phase:
		phase_started_at = game_time
		phase = next_phase

	combat_state["engagement_phase"] = phase
	combat_state["phase_started_at"] = phase_started_at
	combat_state["phase_target_id"] = target_id

	return {"phase": phase, "phase_age": max(0.0, game_time - phase_started_at)}


static func _compute_next_phase(
	current: String,
	age: float,
	ship_data: Dictionary,
	target: Dictionary,
	crew_data: Dictionary,
	survival_mode: String
) -> String:
	# Survival overlay forces fighting_withdrawal; once cleared we re-enter
	# the cycle from closing so the captain reacquires posture before fighting.
	if survival_mode == "withdraw":
		return "fighting_withdrawal"
	if current == "fighting_withdrawal":
		# Survival is no longer active — exit to closing and let the normal
		# phase rules take over from there.
		if age < PHASE_MIN_DURATION:
			return "fighting_withdrawal"
		return "closing"

	var aggression: float = _read_aggression(crew_data)
	var optimal: float = _scaled_optimal_range(aggression)
	var safe_vs_fighters: float = _scaled_safe_range(aggression)
	var timing_factor: float = _phase_timing_factor(aggression)

	var distance: float = ship_data.get("position", Vector2.ZERO).distance_to(target.get("position", Vector2.ZERO))
	var fighter_target: bool = FleetDataManager.is_fighter_class(str(target.get("type", "")))
	var arc_on_target: bool = _has_broadside_arc(ship_data, target)

	# Fighter-swarm rule overrides everything below: if a fighter wanders
	# inside our safety bubble, we kite regardless of the prior phase.
	if fighter_target and distance < safe_vs_fighters:
		return "kiting"

	match current:
		"closing":
			if distance <= optimal:
				return "broadside"
			if distance <= BROADSIDE_FAR_RANGE and arc_on_target:
				return "broadside"
			return "closing"

		"broadside":
			if age < PHASE_MIN_DURATION:
				return "broadside"
			if distance < BROADSIDE_TOO_CLOSE:
				return "repositioning"
			if not arc_on_target:
				return "repositioning"
			if distance > BROADSIDE_FAR_RANGE:
				return "closing"
			return "broadside"

		"kiting":
			if fighter_target and distance < safe_vs_fighters:
				return "kiting"
			if distance > BROADSIDE_FAR_RANGE:
				return "closing"
			return "broadside"

		"repositioning":
			if age > PHASE_REPOSITION_TIMEOUT * timing_factor:
				return "broadside" if distance <= BROADSIDE_FAR_RANGE else "closing"
			if arc_on_target and distance <= BROADSIDE_FAR_RANGE and distance >= BROADSIDE_TOO_CLOSE:
				return "broadside"
			return "repositioning"

		_:
			return "closing"


## Map a phase tag to a maneuver subtype consumed by MovementSystem.
static func _phase_to_maneuver(phase: String) -> String:
	match phase:
		"closing":
			return "large_ship_close_to_broadside"
		"broadside":
			return "large_ship_hold_broadside"
		"kiting":
			return "large_ship_kite"
		"repositioning":
			return "large_ship_reposition_arc"
		"fighting_withdrawal":
			return "large_ship_fighting_withdrawal"
		_:
			return "large_ship_close_to_broadside"


## ---------------------------------------------------------------------------
## PERSONALITY — skill / aggression / composure
## ---------------------------------------------------------------------------
## Same axes the fighter uses. Aggression modulates ranges and phase timing;
## composure (degraded by stress) modulates *effective* skill — it doesn't
## introduce a new axis.

static func _read_aggression(crew_data: Dictionary) -> float:
	return clamp(float(crew_data.get("stats", {}).get("skills", {}).get("aggression", 0.5)), 0.0, 1.0)

## Capital pilots are read for `tactics` (broadside warfare is range/arc
## management, not fly-by-wire). See 01_overview.md role-stat table.
static func _read_skill(crew_data: Dictionary) -> float:
	var skills: Dictionary = crew_data.get("stats", {}).get("skills", {})
	return clamp(float(skills.get("tactics", 0.5)), 0.0, 1.0)

## Effective skill — pure skill scaled by composure under stress. A stressed,
## low-composure captain misjudges the situation as if they were less skilled.
static func calculate_effective_skill(crew_data: Dictionary) -> float:
	var skill: float = _read_skill(crew_data)
	var composure: float = float(crew_data.get("stats", {}).get("skills", {}).get("composure", skill))
	var stress: float = float(crew_data.get("stats", {}).get("stress", 0.0))
	var effective_composure: float = clamp(composure * (1.0 - stress * COMPOSURE_STRESS_DECAY), 0.0, 1.0)
	return clamp(skill * effective_composure, 0.0, 1.0)

## Aggressive captains close in; cautious captains keep the gap wider.
static func _scaled_optimal_range(aggression: float) -> float:
	# (aggression-0.5)*2 → -1..+1; high aggression shrinks the optimal range.
	return BROADSIDE_OPTIMAL_RANGE * (1.0 - (aggression - 0.5) * 2.0 * RANGE_AGGRESSION_SPREAD)

static func _scaled_safe_range(aggression: float) -> float:
	# Hot captains let fighters get closer before kiting.
	return SAFE_RANGE_VS_FIGHTERS * (1.0 - (aggression - 0.5) * 2.0 * RANGE_AGGRESSION_SPREAD)

## Hot captains commit longer to phases; cold captains break early.
static func _phase_timing_factor(aggression: float) -> float:
	return lerp(1.0 / PERSONALITY_TIMING_SPREAD, PERSONALITY_TIMING_SPREAD, aggression)


## ---------------------------------------------------------------------------
## ARC GEOMETRY
## ---------------------------------------------------------------------------
## Visual forward — matches MovementSystem.get_visual_forward. Ships face "up"
## visually at rotation 0, so forward is (sin r, -cos r), not (cos r, sin r).
static func _ship_forward(ship: Dictionary) -> Vector2:
	var rot: float = float(ship.get("rotation", 0.0))
	return Vector2(sin(rot), -cos(rot))

## True when our broadside (port or starboard) is pointed at the target —
## i.e. our nose is roughly perpendicular to the line of sight.
static func _has_broadside_arc(ship_data: Dictionary, target: Dictionary) -> bool:
	var to_target: Vector2 = target.get("position", Vector2.ZERO) - ship_data.get("position", Vector2.ZERO)
	if to_target.length() < 1.0:
		return false
	var forward := _ship_forward(ship_data)
	var alignment: float = abs(forward.dot(to_target.normalized()))
	return alignment <= BROADSIDE_ARC_DOT

## Nose-on-target alignment for tactical-break detection.
static func _nose_to_target_dot(ship: Dictionary, target: Dictionary) -> float:
	var to_target: Vector2 = target.get("position", Vector2.ZERO) - ship.get("position", Vector2.ZERO)
	if to_target.length() < 1.0:
		return 0.0
	return _ship_forward(ship).dot(to_target.normalized())


## ---------------------------------------------------------------------------
## SELF-PRESERVATION
## ---------------------------------------------------------------------------
## Returns "withdraw" when the captain should disengage, "" otherwise.
## Triggers (any one fires):
##   1. Critical-section trigger    — any armor section below 20%.
##   2. Engine-damaged trigger      — engine internal damaged or destroyed.
##   3. Outgunned trigger           — local enemy capitals > friendly capitals
##                                    AND aggression below the heroic threshold.
static func _assess_survival_state(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array) -> String:
	if _has_critical_section(ship_data):
		return "withdraw"
	if _is_engine_damaged(ship_data):
		return "withdraw"
	if _is_outgunned(crew_data, ship_data, all_ships):
		return "withdraw"
	return ""

static func _has_critical_section(ship_data: Dictionary) -> bool:
	var sections: Array = ship_data.get("armor_sections", [])
	for section in sections:
		var max_armor: float = float(section.get("max_armor", 0))
		if max_armor <= 0.0:
			continue
		var current: float = float(section.get("current_armor", 0))
		if current / max_armor < SECTION_CRITICAL_RATIO:
			return true
	return false

static func _is_engine_damaged(ship_data: Dictionary) -> bool:
	var internals: Array = ship_data.get("internals", [])
	for internal in internals:
		if str(internal.get("type", "")) != "engine":
			continue
		var status := str(internal.get("status", ""))
		if status == "damaged" or status == "destroyed":
			return true
	return false

## Heroic captains (aggression ≥ threshold) never bail on bad odds; everyone
## else withdraws when the local capital balance tips against them.
static func _is_outgunned(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array) -> bool:
	var aggression: float = _read_aggression(crew_data)
	if aggression >= OUTGUNNED_AGGRESSION_THRESHOLD:
		return false

	var counts := _count_nearby_capitals(ship_data, all_ships)
	var enemies: int = counts.enemies
	# Count ourselves as a friendly so 1-1 doesn't trigger and 1v2 does.
	var friends: int = counts.friends + 1
	return enemies > friends

static func _count_nearby_capitals(ship_data: Dictionary, all_ships: Array) -> Dictionary:
	var my_team: int = ship_data.get("team", -1)
	var my_id: String = str(ship_data.get("ship_id", ""))
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var enemies: int = 0
	var friends: int = 0
	for ship in all_ships:
		if str(ship.get("ship_id", "")) == my_id:
			continue
		if str(ship.get("status", "")) != "operational":
			continue
		if not FleetDataManager.is_large_ship(str(ship.get("type", ""))):
			continue
		var d: float = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		if d > OUTGUNNED_RANGE:
			continue
		if ship.get("team", -1) == my_team:
			friends += 1
		else:
			enemies += 1
	return {"enemies": enemies, "friends": friends}


## ---------------------------------------------------------------------------
## TACTICAL BREAK
## ---------------------------------------------------------------------------
## Interrupts the FSM when a capital-class enemy is within
## TACTICAL_BREAK_RANGE_LARGE with their nose on us. Returns the offending
## threat ship dict, or {}.
static func _check_tactical_break(ship_data: Dictionary, all_ships: Array, _crew_data: Dictionary) -> Dictionary:
	var my_pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var my_id: String = str(ship_data.get("ship_id", ""))
	var my_team: int = ship_data.get("team", -1)
	for ship in all_ships:
		if str(ship.get("ship_id", "")) == my_id:
			continue
		if ship.get("team", -1) == my_team:
			continue
		if str(ship.get("status", "")) != "operational":
			continue
		if not FleetDataManager.is_large_ship(str(ship.get("type", ""))):
			continue
		var d: float = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		if d > TACTICAL_BREAK_RANGE_LARGE or d < 1.0:
			continue
		# Are they pointed at us?
		if _nose_to_target_dot(ship, ship_data) >= TACTICAL_BREAK_ARC_DOT:
			return ship
	return {}


## ---------------------------------------------------------------------------
## ESCAPE BOUNDARY
## ---------------------------------------------------------------------------
## Returns {} when the ship is not engaging the boundary, otherwise a full
## decision result (crew_data + decision) carrying the flee subtype, the locked
## flee_decision, and the steer target. Shares the flee_target contract with
## fighters so MovementSystem steers both identically.
static func _reflex_edge_boundary(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float) -> Dictionary:
	var pos: Vector2 = ship_data.get("position", Vector2.ZERO)
	var size: Vector2 = ship_data.get("battlefield_size", FleeBoundarySystem.DEFAULT_BATTLEFIELD_SIZE)
	var locked: String = ship_data.get("orders", {}).get("flee_decision", "")

	# Already committed: keep running for the exit regardless of distance.
	if locked == FleeDecisionSystem.COMMITTED:
		return _flee_decision(crew_data, ship_data, game_time, FleeDecisionSystem.COMMITTED,
			FleeBoundarySystem.outward_exit_point(pos, size))

	# Returning: keep heading inward until well clear, then release the lock.
	if locked == FleeDecisionSystem.RETURNING:
		if FleeBoundarySystem.is_clear_inside(pos, size):
			return _flee_decision(crew_data, ship_data, game_time, "", pos)
		return _flee_decision(crew_data, ship_data, game_time, FleeDecisionSystem.RETURNING,
			FleeBoundarySystem.inward_point(size))

	# No lock yet: only decide once near the edge.
	if not FleeBoundarySystem.is_near_edge(pos, size):
		return {}
	var choice := FleeDecisionSystem.decide(crew_data, ship_data, all_ships)
	var target: Vector2 = FleeBoundarySystem.outward_exit_point(pos, size) \
		if choice == FleeDecisionSystem.COMMITTED else FleeBoundarySystem.inward_point(size)
	return _flee_decision(crew_data, ship_data, game_time, choice, target)


## Wrap a flee maneuver in the large-ship decision result shape. A `choice` of
## "" clears the lock (steer-in to the cleared position, normal AI resumes next
## tick). Committed → flee_to_boundary; otherwise flee_turn_back.
static func _flee_decision(crew_data: Dictionary, ship_data: Dictionary, game_time: float, choice: String, target: Vector2) -> Dictionary:
	var subtype: String = "flee_to_boundary" if choice == FleeDecisionSystem.COMMITTED else "flee_turn_back"
	return _build_decision(crew_data, ship_data, "", subtype, game_time, DECISION_DELAY_URGENT, {
		"flee_decision": choice,
		"flee_target": target,
	})


## ---------------------------------------------------------------------------
## AREA LEASH
## ---------------------------------------------------------------------------
static func _is_far_outside_area(ship_data: Dictionary) -> bool:
	var assigned_area = ship_data.get("assigned_area")
	if assigned_area == null or not (assigned_area is Dictionary):
		return false
	var radius: float = float(assigned_area.get("radius", 0.0))
	if radius <= 0.0:
		return false
	var center: Vector2 = assigned_area.get("center", Vector2.ZERO)
	var dist: float = ship_data.get("position", Vector2.ZERO).distance_to(center)
	return dist > radius * AREA_HARD_RETURN_MULTIPLIER


## ---------------------------------------------------------------------------
## DECISION EMISSION
## ---------------------------------------------------------------------------
## Emit a decision for the current FSM phase.
##
## fighting_withdrawal is a survival reflex (driven by _assess_survival_state
## through _step_engagement_phase) and still emits its large_ship_* subtype so
## MovementSystem._calculate_large_ship_fighting_withdrawal handles it correctly.
##
## All other phases (closing, broadside, kiting, repositioning) are the
## non-reflex engage tail and now emit a unified "tactical" directive so large
## ships flow through SteeringBlender + calculate_blended_control, with
## role-derived facing_mode preserving their identity:
##   artillery  → broadside (side batteries on target, orbit at range)
##   anchor/brawler/screen → nose_on (bow armor forward, forward guns)
##   unknown    → auto (existing blended-control close/far rule)
static func _emit_phase_maneuver(
	crew_data: Dictionary,
	ship_data: Dictionary,
	target: Dictionary,
	phase: String,
	game_time: float
) -> Dictionary:
	# fighting_withdrawal is a survival reflex — keep its large_ship_* subtype
	# so the withdrawal movement function still runs (it drives away from the
	# threat while facing roughly toward it for cover fire).
	if phase == "fighting_withdrawal":
		return _build_decision(crew_data, ship_data, target.get("ship_id", ""),
			"large_ship_fighting_withdrawal", game_time, DECISION_DELAY_URGENT, {
				"engagement_phase": phase,
			})

	# Non-reflex engage path: emit a blended tactical directive.
	# Read the crew's resolved tactics block (set at spawn by TacticsSystem).
	# Fall back to balanced defaults so un-configured crew are still coherent.
	var tactics: Dictionary = crew_data.get("tactics", FALLBACK_TACTICS)

	# Weapon optimal range: per-type engagement range (same scale as fighter path).
	var weapon_optimal: float = MovementSystem.get_engagement_range(ship_data)

	# Threat list: all_ships is not available here so pass empty.
	# The converter re-gathers enemy positions per-frame (_gather_enemy_positions),
	# so evade direction stays live. The blender's is-targeted bump is a
	# nice-to-have that costs nothing to omit at decision time.
	var threats: Array = []

	var directive: Dictionary = SteeringBlender.build_directive(
		ship_data, tactics, target, threats, weapon_optimal
	)

	var delay: float = randf_range(DECISION_DELAY_NORMAL_MIN, DECISION_DELAY_NORMAL_MAX)
	var updated: Dictionary = crew_data.duplicate(true)
	updated.next_decision_time = game_time + delay

	var decision: Dictionary = {
		"type":             "maneuver",
		"subtype":          "tactical",
		"engagement_target": directive.get("engagement_target", ""),
		"goal_weights":     directive.get("goal_weights", {}),
		"preferred_range":  directive.get("preferred_range", weapon_optimal),
		"formation_slot":   directive.get("formation_slot",  Vector2.ZERO),
		"anchor_position":  directive.get("anchor_position", Vector2.ZERO),
		"facing_mode":      directive.get("facing_mode", "auto"),
		"crew_id":          crew_data.get("crew_id", ""),
		"entity_id":        ship_data.get("ship_id", ""),
		"target_id":        target.get("ship_id", ""),
		"skill_factor":     calculate_effective_skill(crew_data),
		"timestamp":        game_time,
	}
	return {"crew_data": updated, "decision": decision}

static func _make_tactical_break_decision(
	crew_data: Dictionary,
	ship_data: Dictionary,
	threat: Dictionary,
	game_time: float
) -> Dictionary:
	# Tactical break presents thickest armor (front) toward the threat. The
	# pilot may keep its locked target id; the maneuver itself orients on
	# the threat ship via target_id.
	return _build_decision(crew_data, ship_data, threat.get("ship_id", ""), "large_ship_present_thickest_armor", game_time, DECISION_DELAY_URGENT, {
		"tactical_break": true,
	})

static func _make_return_to_area_decision(crew_data: Dictionary, ship_data: Dictionary, game_time: float) -> Dictionary:
	return _build_decision(crew_data, ship_data, "", "large_ship_close_to_broadside", game_time, DECISION_DELAY_URGENT, {
		"return_to_area": true,
	})

static func _make_idle_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated: Dictionary = crew_data.duplicate(true)
	updated.next_decision_time = game_time + randf_range(DECISION_DELAY_IDLE_MIN, DECISION_DELAY_IDLE_MAX)
	return {"crew_data": updated}

static func _build_decision(
	crew_data: Dictionary,
	ship_data: Dictionary,
	target_id: Variant,
	maneuver: String,
	game_time: float,
	delay: float,
	extra: Dictionary = {}
) -> Dictionary:
	var updated: Dictionary = crew_data.duplicate(true)
	updated.next_decision_time = game_time + delay

	var decision: Dictionary = {
		"type": "maneuver",
		"subtype": maneuver,
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_id,
		"skill_factor": calculate_effective_skill(crew_data),
		"timestamp": game_time,
	}
	for key in extra.keys():
		decision[key] = extra[key]

	return {"crew_data": updated, "decision": decision}
