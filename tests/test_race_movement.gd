extends GutTest

## Behavioral tests for racing flight. Racers fly via the REAL combat steering
## (MovementSystem.calculate_blended_control + apply_space_physics — the same path
## battle uses), so these assert capabilities, not values: ships close on gates,
## skill and ship stats change outcomes, and the sim is deterministic.

const TICKS := 600
const DELTA := RaceSimulator.FIXED_STEP

var _track: Dictionary


func before_each() -> void:
	_track = RaceTrack.load_track("asteroid_sprint")
	assert_false(_track.is_empty(), "Track loaded")


func _make_crew(piloting: float = 0.7) -> Dictionary:
	return {
		"crew_id": "c_%d" % int(piloting * 100),
		"callsign": "Pilot",
		"role": CrewData.Role.PILOT,
		"qualified_roles": [CrewData.Role.PILOT],
		"stats": {
			"stress": 0.0, "fatigue": 0.0, "reaction_time": 0.15,
			"skills": {
				"piloting": piloting, "awareness": 0.7, "composure": 0.7,
				"aggression": 0.4, "aim": 0.5, "tactics": 0.5, "machinery": 0.5,
			},
		},
	}


func _solo(piloting: float, ship_type: String = "fighter") -> Dictionary:
	"""Run a single racer and return its standings entry."""
	var entrants: Array = [{
		"ship": ShipData.create_ship_instance(ship_type, 0, Vector2.ZERO),
		"crew": _make_crew(piloting),
	}]
	return RaceSimulator.run(_track, entrants, 1).standings[0]


# ── Flight closes on the marker ─────────────────────────────────────────────

func test_racer_closes_distance_to_marker() -> void:
	var ship: Dictionary = ShipData.create_ship_instance("fighter", 0, Vector2(100, 100))
	ship.erase("assigned_area")
	ship["orders"] = RaceSimulator.pursuit_orders()
	var gate_mid: Vector2 = RaceTrack.marker_position(_track, 0)
	ship.orders["gate_a"] = RaceTrack.gate_post_a(_track, 0)
	ship.orders["gate_b"] = RaceTrack.gate_post_b(_track, 0)
	ship.orders["prev_objective"] = RaceTrack.marker_position(_track, 1)
	ship.orders["next_objective"] = RaceTrack.marker_position(_track, 1)
	var initial: float = ship.position.distance_to(gate_mid)

	for _i in range(TICKS):
		var target := {"ship_id": "g", "position": gate_mid, "velocity": Vector2.ZERO}
		var pc: Dictionary = MovementSystem.calculate_blended_control(ship, target, [], [], [], DELTA)
		var updated: Dictionary = MovementSystem.apply_space_physics(ship, pc, DELTA)
		ship.position = updated.position
		ship.velocity = updated.velocity
		ship.rotation = updated.rotation

	assert_lt(ship.position.distance_to(gate_mid), initial, "Racer closes on the gate over time")


# ── A racer progresses around the track ─────────────────────────────────────

func test_racer_passes_markers_during_sim() -> void:
	var standing: Dictionary = _solo(0.8)
	assert_gt(standing.markers_passed, 0, "Racer passes at least one marker")


func test_capable_racer_finishes_the_race() -> void:
	var standing: Dictionary = _solo(0.9)
	assert_true(standing.finished, "A skilled pilot completes all laps within the time limit")


# ── Pilot skill changes the outcome (the point of the screen) ────────────────

func test_higher_piloting_is_at_least_as_fast() -> void:
	var good: Dictionary = _solo(0.95)
	var poor: Dictionary = _solo(0.2)
	if good.finished and poor.finished:
		assert_lt(good.finish_time, poor.finish_time, "Better pilot finishes sooner")
	else:
		assert_gte(good.markers_passed, poor.markers_passed, "Better pilot gets at least as far")


# ── Ship stats change the outcome ───────────────────────────────────────────

func test_faster_ship_outprogresses_slower_ship() -> void:
	# Identical crew; a nimble fighter should cover at least as much as a corvette.
	var fighter: Dictionary = _solo(0.7, "fighter")
	var corvette: Dictionary = _solo(0.7, "corvette")
	assert_gte(fighter.markers_passed, corvette.markers_passed,
		"Faster/nimbler ship progresses at least as far with the same pilot")


# ── Determinism ─────────────────────────────────────────────────────────────

func test_same_field_produces_same_result() -> void:
	var entrants: Array = [
		{"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO), "crew": _make_crew(0.8)},
		{"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO), "crew": _make_crew(0.5)},
	]
	var a: Dictionary = RaceSimulator.run(_track, entrants, 42)
	var b: Dictionary = RaceSimulator.run(_track, entrants, 42)
	assert_eq(a.winner_ship_id, b.winner_ship_id, "Same field yields the same winner")
	assert_eq(a.standings[0].finish_time, b.standings[0].finish_time,
		"Same field yields identical timing (deterministic flight)")
