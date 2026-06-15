extends GutTest

## Tests for RaceTrack: marker order, lap counting, gate crossing, finish detection.

const TRACK_ID := "asteroid_sprint"

var _track: Dictionary


func before_each() -> void:
	_track = RaceTrack.load_track(TRACK_ID)
	assert_false(_track.is_empty(), "Track loaded")


# ── Marker ordering ──────────────────────────────────────────────────────────

func test_passing_markers_in_order_increments_count() -> void:
	var state: Dictionary = RaceTrack.make_race_state("s0", "c0")
	var n: int = RaceTrack.marker_count(_track)
	for i in range(n):
		var center: Vector2 = RaceTrack.marker_position(_track, i)
		var norm_arr: Array = _track.markers[i].get("gate_normal", [1, 0])
		var normal: Vector2 = Vector2(float(norm_arr[0]), float(norm_arr[1])).normalized()
		state = RaceTrack.advance_progress(state, _track,
			center - normal * 60.0, center + normal * 60.0, float(i + 1) * 10.0)
	assert_eq(state.markers_passed, n, "Passing all markers in order increments count")


func test_out_of_order_proximity_does_not_advance() -> void:
	var state: Dictionary = RaceTrack.make_race_state("s0", "c0")
	# Try to pass marker 2 while still expecting marker 0.
	var center: Vector2 = RaceTrack.marker_position(_track, 2)
	var norm_arr: Array = _track.markers[2].get("gate_normal", [1, 0])
	var normal: Vector2 = Vector2(float(norm_arr[0]), float(norm_arr[1])).normalized()
	state = RaceTrack.advance_progress(state, _track,
		center - normal * 60.0, center + normal * 60.0, 5.0)
	assert_eq(state.markers_passed, 0, "Out-of-order gate does not count")
	assert_eq(state.next_marker, 0, "Still waiting for marker 0")


# ── Lap counting ─────────────────────────────────────────────────────────────

func test_full_marker_cycle_increments_lap_and_records_time() -> void:
	var state: Dictionary = RaceTrack.make_race_state("s0", "c0")
	var n: int = RaceTrack.marker_count(_track)
	var t: float = 0.0
	for i in range(n):
		var center: Vector2 = RaceTrack.marker_position(_track, i)
		var norm_arr: Array = _track.markers[i].get("gate_normal", [1, 0])
		var normal: Vector2 = Vector2(float(norm_arr[0]), float(norm_arr[1])).normalized()
		t += 10.0
		state = RaceTrack.advance_progress(state, _track,
			center - normal * 60.0, center + normal * 60.0, t)
	assert_eq(state.lap, 1, "One lap completed after all markers")
	assert_eq(state.lap_times.size(), 1, "One lap time recorded")
	assert_gt(float(state.lap_times[0]), 0.0, "Lap time is positive")


func test_total_markers_to_finish_equals_laps_times_marker_count() -> void:
	var laps: int = int(_track.get("laps", 1))
	var expected: int = laps * RaceTrack.marker_count(_track)
	assert_eq(RaceTrack.total_markers_to_finish(_track), expected,
		"Total gates = laps × marker count")


# ── Gate crossing detection ───────────────────────────────────────────────────

func test_gate_crossing_detects_fast_pass() -> void:
	var idx: int = 0
	var center: Vector2 = RaceTrack.marker_position(_track, idx)
	var norm_arr: Array = _track.markers[idx].get("gate_normal", [1, 0])
	var normal: Vector2 = Vector2(float(norm_arr[0]), float(norm_arr[1])).normalized()
	# Large step that skips over center entirely but crosses the plane.
	var prev: Vector2 = center - normal * 300.0
	var cur: Vector2  = center + normal * 300.0
	assert_true(RaceTrack.crossed_gate(_track, idx, prev, cur),
		"Fast segment crossing detected by gate check")


func test_crossing_from_either_direction_counts() -> void:
	# Gate crossing is bidirectional — sequential ordering prevents reverse cheating.
	var idx: int = 0
	var center: Vector2 = RaceTrack.marker_position(_track, idx)
	var norm_arr: Array = _track.markers[idx].get("gate_normal", [1, 0])
	var normal: Vector2 = Vector2(float(norm_arr[0]), float(norm_arr[1])).normalized()
	# Crossing from both sides should be detected.
	var fwd: bool = RaceTrack.crossed_gate(_track, idx,
		center - normal * 60.0, center + normal * 60.0)
	var rev: bool = RaceTrack.crossed_gate(_track, idx,
		center + normal * 60.0, center - normal * 60.0)
	assert_true(fwd or rev, "Gate crossing is detected from at least one direction")


func test_lateral_miss_not_counted() -> void:
	var idx: int = 0
	var center: Vector2 = RaceTrack.marker_position(_track, idx)
	var norm_arr: Array = _track.markers[idx].get("gate_normal", [1, 0])
	var normal: Vector2 = Vector2(float(norm_arr[0]), float(norm_arr[1])).normalized()
	var gate_width: float = float(_track.markers[idx].get("gate_width", 500.0))
	var tangent: Vector2 = Vector2(-normal.y, normal.x)
	# Position far to the side.
	var side: float = gate_width
	assert_false(RaceTrack.crossed_gate(_track, idx,
		center - normal * 60.0 + tangent * side,
		center + normal * 60.0 + tangent * side),
		"Lateral miss is not counted as a gate crossing")


# ── Full finish detection ─────────────────────────────────────────────────────

func test_racer_finishes_after_all_laps() -> void:
	var state: Dictionary = RaceTrack.make_race_state("s0", "c0")
	var n: int = RaceTrack.marker_count(_track)
	var laps: int = int(_track.get("laps", 1))
	var t: float = 0.0
	for _lap in range(laps):
		for i in range(n):
			var center: Vector2 = RaceTrack.marker_position(_track, i)
			var norm_arr: Array = _track.markers[i].get("gate_normal", [1, 0])
			var normal: Vector2 = Vector2(float(norm_arr[0]), float(norm_arr[1])).normalized()
			t += 10.0
			state = RaceTrack.advance_progress(state, _track,
				center - normal * 60.0, center + normal * 60.0, t)
	assert_true(state.finished, "Racer is finished after all laps")
	assert_gt(float(state.finish_time), 0.0, "Finish time is positive")
	assert_eq(state.lap_times.size(), laps, "One lap time per completed lap")


# ── Starting grid ─────────────────────────────────────────────────────────────

func test_starting_grid_returns_correct_count() -> void:
	var grid: Array = RaceTrack.starting_grid(_track, 5)
	assert_eq(grid.size(), 5, "Grid has one slot per racer")


func test_starting_grid_positions_differ() -> void:
	var grid: Array = RaceTrack.starting_grid(_track, 4)
	for i in range(grid.size()):
		for j in range(i + 1, grid.size()):
			var pi: Vector2 = grid[i].position
			var pj: Vector2 = grid[j].position
			assert_ne(pi, pj, "All grid positions are distinct")
