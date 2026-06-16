class_name RaceSimulator
extends RefCounted

## Headless, deterministic race orchestrator.
##
## Drives each racer with the REAL flight AI (no race-specific flight math):
## crew skills are mapped to flight via CrewIntegrationSystem.apply_pilot_skill_modifiers
## (same as combat), and each tick steers toward the next marker through
## MovementSystem.calculate_blended_control + apply_space_physics. The only
## race-specific logic is lap/gate progress, telemetry, and finishing rules.
##
## Used by both the visible race scene and the betting flow — one code path.

## Fixed physics step for determinism (independent of frame rate).
const FIXED_STEP := 1.0 / 60.0
## Hard safety cap to prevent infinite loops.
const MAX_SIM_SECONDS := 600.0
## Estimate one fast lap at this speed (units/sec) for the DNF time limit.
const ESTIMATE_FAST_SPEED := 250.0
## Synthetic target id for the gate a racer is currently flying through.
const GATE_TARGET_ID := "__race_gate__"


## Steering order block that drives pure waypoint pursuit through the shared
## flight model: pursue-only weights, zero standoff = "fly through this point".
## The per-tick goal (gate posts + prev/next) is stamped onto orders in step_one.
static func pursuit_orders() -> Dictionary:
	"""Return the steady steering order for a racer (goal points added per tick)."""
	return {
		"current_order": "tactical",
		"engagement_target": GATE_TARGET_ID,
		"target_id": GATE_TARGET_ID,
		"goal_weights": {"pursue": 1.0, "keep_range": 0.0, "evade": 0.0, "formation": 0.0},
		"preferred_range": 0.0,
		"facing_mode": "auto",
		"formation_slot": Vector2.ZERO,
		"anchor_position": Vector2.ZERO,
		"support_pos": null,
	}


## Run a complete race headlessly. entrants is an Array of {ship, crew}.
## seed is recorded for reproducibility (flight is deterministic; the seed
## only varies which field the caller generated). Returns RaceTelemetry results.
static func run(track: Dictionary, entrants: Array, seed: int) -> Dictionary:
	"""Run the full race and return results. Deterministic for given entrants."""
	var field: Dictionary = setup_field(track, entrants, seed)
	var ships: Array = field.ships
	var states: Dictionary = field.states
	var time_limit: float = _time_limit(track)
	var time: float = 0.0

	while time < time_limit and not _all_finished(states):
		time += FIXED_STEP
		for ship_ref in ships:
			step_one(ship_ref, states, ships, track, time, field.session)

	for sid in states:
		if not states[sid].finished:
			states[sid].dnf = true

	return RaceTelemetry.finalize(field.session, states, time)


## Build the racer field on the starting grid. Shared by run() (headless) and
## the visible scene so both drive identical ships through the same flight path.
## Returns {ships, states, crews, session}.
static func setup_field(track: Dictionary, entrants: Array, seed: int) -> Dictionary:
	"""Place entrants on the grid, applying the real crew-skill flight mapping."""
	var ships: Array = []
	var states: Dictionary = {}
	var crews: Dictionary = {}
	var grid: Array = RaceTrack.starting_grid(track, entrants.size())

	for i in range(entrants.size()):
		var e: Dictionary = entrants[i]
		var crew: Dictionary = e.crew.duplicate(true)
		# Apply the real crew-skill → flight mapping used in combat, so piloting
		# skill drives turn/accel/lateral/dampening through the normal model.
		var ship: Dictionary = CrewIntegrationSystem.apply_pilot_skill_modifiers(
			e.ship.duplicate(true), crew)
		var slot: Dictionary = grid[i] if i < grid.size() else {"position": Vector2.ZERO, "heading": 0.0}
		ship.position = slot.position
		ship.rotation = slot.heading
		ship.velocity = Vector2.ZERO
		# No operating area on a race track — let the racer roam the whole circuit.
		ship.erase("assigned_area")
		# Drive the racer like a ship pursuing a waypoint via the real steering.
		ship["orders"] = pursuit_orders()
		ships.append(ship)
		states[ship.ship_id] = RaceTrack.make_race_state(ship.ship_id, crew.get("crew_id", ""))
		crews[ship.ship_id] = crew

	var session: Dictionary = RaceTelemetry.new_session(entrants, track)
	session["seed"] = seed
	return {"ships": ships, "states": states, "crews": crews, "session": session}


## Advance one racer by one fixed timestep: steer → move → progress → telemetry.
## Mutates ship_ref and states[sid] in place. Exported so the visible scene
## drives racers through the exact same code path as the headless sim.
static func step_one(ship_ref: Dictionary, states: Dictionary,
		all_ships: Array, track: Dictionary, time: float, session: Dictionary) -> void:
	"""One racer × one tick using the real flight AI."""
	var sid: String = ship_ref.ship_id
	var state: Dictionary = states[sid]
	if state.finished or state.dnf:
		return

	var idx: int = state.next_marker
	var n: int = RaceTrack.marker_count(track)
	var gate_mid: Vector2 = RaceTrack.marker_position(track, idx)
	var prev_pos: Vector2 = ship_ref.position

	# The race-specific part is only DEFINING THE GOAL: fly through this gate at the
	# spot that sets up the next one. The shared nav brain + flight model do the rest.
	ship_ref.orders["gate_a"] = RaceTrack.gate_post_a(track, idx)
	ship_ref.orders["gate_b"] = RaceTrack.gate_post_b(track, idx)
	ship_ref.orders["prev_objective"] = RaceTrack.marker_position(track, posmod(idx - 1, n))
	ship_ref.orders["next_objective"] = RaceTrack.marker_position(track, posmod(idx + 1, n))

	var target := {"ship_id": GATE_TARGET_ID, "position": gate_mid, "velocity": Vector2.ZERO}
	var pilot_control: Dictionary = MovementSystem.calculate_blended_control(
		ship_ref, target, [], all_ships, [], FIXED_STEP)
	var updated: Dictionary = MovementSystem.apply_space_physics(ship_ref, pilot_control, FIXED_STEP)
	ship_ref.position = updated.position
	ship_ref.velocity = updated.velocity
	ship_ref.rotation = updated.rotation
	ship_ref.brake_current_heat = updated.get("brake_current_heat", 0.0)
	ship_ref.brake_overheated = updated.get("brake_overheated", false)

	# Lap/gate progress, then telemetry.
	var new_state: Dictionary = RaceTrack.advance_progress(
		state, track, prev_pos, ship_ref.position, time)
	states[sid] = new_state
	RaceTelemetry.sample(session, new_state, ship_ref, gate_mid, time, prev_pos)


## Time limit for the race: estimated ideal lap time × laps × FINISH_TIME_LIMIT_MULT.
static func _time_limit(track: Dictionary) -> float:
	"""Compute the DNF cutoff time for a race."""
	var ideal_lap: float = _estimate_ideal_lap_time(track)
	var laps: int = track.get("laps", 1)
	return min(ideal_lap * float(laps) * RaceTrack.FINISH_TIME_LIMIT_MULT, MAX_SIM_SECONDS)


## Rough estimate of ideal lap time: straight-line marker perimeter / fast speed.
static func _estimate_ideal_lap_time(track: Dictionary) -> float:
	"""Estimate time for one fast lap (straight-line distances at ESTIMATE_FAST_SPEED)."""
	var n: int = RaceTrack.marker_count(track)
	if n == 0:
		return 60.0
	var total: float = 0.0
	for i in range(n):
		total += RaceTrack.marker_position(track, i).distance_to(
			RaceTrack.marker_position(track, (i + 1) % n))
	return total / ESTIMATE_FAST_SPEED


## True when every racer has either finished or is marked DNF.
static func _all_finished(states: Dictionary) -> bool:
	"""Check whether the race is over (all finished or DNF)."""
	for sid in states:
		var s: Dictionary = states[sid]
		if not s.finished and not s.dnf:
			return false
	return true
