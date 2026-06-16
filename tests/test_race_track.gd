extends GutTest

## Tests for RaceTrack: gate order, lap counting, between-the-posts crossing,
## finish detection. A gate is two posts; a racer passes by flying between them.

const TRACK_ID := "asteroid_sprint"

var _track: Dictionary


func before_each() -> void:
	_track = RaceTrack.load_track(TRACK_ID)
	assert_false(_track.is_empty(), "Track loaded")


## Travel axis through gate i (perpendicular to the post-to-post opening).
func _cross_axis(i: int) -> Vector2:
	var t: Vector2 = RaceTrack.gate_tangent(_track, i)
	return Vector2(-t.y, t.x)


## A short movement segment that flies between gate i's posts (through midpoint).
func _pass_through(i: int) -> Array:
	var center: Vector2 = RaceTrack.marker_position(_track, i)
	var axis: Vector2 = _cross_axis(i)
	return [center - axis * 60.0, center + axis * 60.0]


# ── Gate ordering ────────────────────────────────────────────────────────────

func test_passing_markers_in_order_increments_count() -> void:
	var state: Dictionary = RaceTrack.make_race_state("s0", "c0")
	var n: int = RaceTrack.marker_count(_track)
	for i in range(n):
		var seg: Array = _pass_through(i)
		state = RaceTrack.advance_progress(state, _track, seg[0], seg[1], float(i + 1) * 10.0)
	assert_eq(state.markers_passed, n, "Passing all gates in order increments count")


func test_out_of_order_proximity_does_not_advance() -> void:
	var state: Dictionary = RaceTrack.make_race_state("s0", "c0")
	# Try to pass gate 2 while still expecting gate 0.
	var seg: Array = _pass_through(2)
	state = RaceTrack.advance_progress(state, _track, seg[0], seg[1], 5.0)
	assert_eq(state.markers_passed, 0, "Out-of-order gate does not count")
	assert_eq(state.next_marker, 0, "Still waiting for gate 0")


# ── Lap counting ─────────────────────────────────────────────────────────────

func test_full_marker_cycle_increments_lap_and_records_time() -> void:
	var state: Dictionary = RaceTrack.make_race_state("s0", "c0")
	var n: int = RaceTrack.marker_count(_track)
	var t: float = 0.0
	for i in range(n):
		t += 10.0
		var seg: Array = _pass_through(i)
		state = RaceTrack.advance_progress(state, _track, seg[0], seg[1], t)
	assert_eq(state.lap, 1, "One lap completed after all gates")
	assert_eq(state.lap_times.size(), 1, "One lap time recorded")
	assert_gt(float(state.lap_times[0]), 0.0, "Lap time is positive")


func test_total_markers_to_finish_equals_laps_times_marker_count() -> void:
	var laps: int = int(_track.get("laps", 1))
	var expected: int = laps * RaceTrack.marker_count(_track)
	assert_eq(RaceTrack.total_markers_to_finish(_track), expected,
		"Total gates = laps × gate count")


# ── Between-the-posts crossing ────────────────────────────────────────────────

func test_gate_crossing_detects_fast_pass() -> void:
	var idx: int = 0
	var center: Vector2 = RaceTrack.marker_position(_track, idx)
	var axis: Vector2 = _cross_axis(idx)
	# Large step that skips over the centre entirely but still passes between posts.
	assert_true(RaceTrack.crossed_gate(_track, idx, center - axis * 300.0, center + axis * 300.0),
		"Fast segment crossing between the posts is detected")


func test_crossing_from_either_direction_counts() -> void:
	var idx: int = 0
	var seg: Array = _pass_through(idx)
	var fwd: bool = RaceTrack.crossed_gate(_track, idx, seg[0], seg[1])
	var rev: bool = RaceTrack.crossed_gate(_track, idx, seg[1], seg[0])
	assert_true(fwd and rev, "Passing between the posts counts from either direction")


func test_lateral_miss_not_counted() -> void:
	var idx: int = 0
	var center: Vector2 = RaceTrack.marker_position(_track, idx)
	var axis: Vector2 = _cross_axis(idx)
	var tangent: Vector2 = RaceTrack.gate_tangent(_track, idx)
	var half: float = RaceTrack.gate_half_width(_track, idx)
	# Cross the gate's LINE but outside the posts — should not count.
	var off: Vector2 = tangent * (half + 150.0)
	assert_false(RaceTrack.crossed_gate(_track, idx,
		center - axis * 60.0 + off, center + axis * 60.0 + off),
		"Crossing outside the two posts is not counted")


# ── Full finish detection ─────────────────────────────────────────────────────

func test_racer_finishes_after_all_laps() -> void:
	var state: Dictionary = RaceTrack.make_race_state("s0", "c0")
	var n: int = RaceTrack.marker_count(_track)
	var laps: int = int(_track.get("laps", 1))
	var t: float = 0.0
	for _lap in range(laps):
		for i in range(n):
			t += 10.0
			var seg: Array = _pass_through(i)
			state = RaceTrack.advance_progress(state, _track, seg[0], seg[1], t)
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
			assert_ne(grid[i].position, grid[j].position, "All grid positions are distinct")
