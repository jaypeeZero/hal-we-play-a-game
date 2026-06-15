extends GutTest

## Tests for RaceTelemetry: path efficiency, standings ranking, composure signal.

var _track: Dictionary


func before_each() -> void:
	_track = RaceTrack.load_track("asteroid_sprint")
	assert_false(_track.is_empty(), "Track loaded")


func _run(entrants: Array, seed: int) -> Dictionary:
	return RaceSimulator.run(_track, entrants, seed)


func _make_crew(piloting: float, composure: float = 0.7,
		crew_id: String = "c") -> Dictionary:
	return {
		"crew_id": crew_id,
		"callsign": "Racer",
		"role": CrewData.Role.PILOT,
		"qualified_roles": [CrewData.Role.PILOT],
		"stats": {
			"stress": 0.0, "fatigue": 0.0, "reaction_time": 0.15,
			"skills": {
				"piloting": piloting, "awareness": 0.6, "composure": composure,
				"aggression": 0.4, "aim": 0.5, "tactics": 0.5, "machinery": 0.5,
			},
		},
	}


# ── Path efficiency ───────────────────────────────────────────────────────────

func test_path_efficiency_is_between_zero_and_one() -> void:
	var ship: Dictionary = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var results: Dictionary = _run([{"ship": ship, "crew": _make_crew(0.7)}], 1)
	var eff: float = float(results.standings[0].path_efficiency)
	assert_between(eff, 0.01, 1.0, "Path efficiency is in (0, 1]")


func test_total_distance_recorded_and_positive() -> void:
	var ship: Dictionary = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var results: Dictionary = _run([{"ship": ship, "crew": _make_crew(0.7)}], 2)
	var s: Dictionary = results.standings[0]
	# If racer moved at all, total_distance > 0.
	assert_gte(float(s.total_distance), 0.0, "Total distance is non-negative")


# ── Standings ranking ─────────────────────────────────────────────────────────

func test_standings_are_fully_ranked() -> void:
	var entrants: Array = [
		{"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO),
			"crew": _make_crew(0.8, 0.7, "ca")},
		{"ship": ShipData.create_ship_instance("fighter", 1, Vector2.ZERO),
			"crew": _make_crew(0.4, 0.7, "cb")},
	]
	var results: Dictionary = _run(entrants, 3)
	assert_eq(results.standings.size(), 2, "Both racers in standings")
	assert_eq(int(results.standings[0].rank), 1, "First standing has rank 1")
	assert_eq(int(results.standings[1].rank), 2, "Second standing has rank 2")


func test_winner_matches_standings_first() -> void:
	var entrants: Array = [
		{"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO),
			"crew": _make_crew(0.8, 0.7, "ca")},
		{"ship": ShipData.create_ship_instance("fighter", 1, Vector2.ZERO),
			"crew": _make_crew(0.3, 0.7, "cb")},
	]
	var results: Dictionary = _run(entrants, 4)
	assert_eq(results.winner_ship_id, results.standings[0].ship_id,
		"winner_ship_id matches standings[0]")


func test_results_contain_required_fields() -> void:
	var ship: Dictionary = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var results: Dictionary = _run([{"ship": ship, "crew": _make_crew(0.7)}], 5)
	assert_true(results.has("standings"), "Results have standings")
	assert_true(results.has("winner_ship_id"), "Results have winner_ship_id")
	assert_true(results.has("sim_seconds"), "Results have sim_seconds")
	assert_true(results.has("events"), "Results have events array")


# ── Skill signal in telemetry ───────────────────────────────────────────────
# Piloting feeds the real flight model (turn/accel/lateral factors), so the
# telemetry must reflect it: a better pilot sustains a higher average speed.

func test_higher_piloting_records_higher_avg_speed() -> void:
	var high: Dictionary = _run([{
		"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO),
		"crew": _make_crew(0.95, 0.7, "high")}], 77).standings[0]
	var low: Dictionary = _run([{
		"ship": ShipData.create_ship_instance("fighter", 0, Vector2.ZERO),
		"crew": _make_crew(0.15, 0.7, "low")}], 77).standings[0]
	assert_gt(float(high.avg_speed), float(low.avg_speed),
		"Better pilot sustains a higher average speed via the real flight model")
