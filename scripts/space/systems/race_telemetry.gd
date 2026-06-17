class_name RaceTelemetry
extends RefCounted

## Accumulates per-racer flight metrics during a race and finalizes results.
## Pure static API — no object state; the session dict carries all accumulators.

## Minimum path_efficiency (guards against zero-ideal-distance edge cases).
const MIN_PATH_EFFICIENCY := 0.01
## Throttle at or above this counts as "full throttle" for utilisation stats.
const FULL_THROTTLE_THRESHOLD := 0.9
## Per-tick heading change (radians) above which a turn is "deliberate" — used
## to count steering reversals (corrections) rather than tiny numerical jitter.
const CORRECTION_MIN_TURN := 0.035
## A racer is "near" its target marker within this distance — overshoots (flying
## past then doubling back) are only counted inside this band.
const OVERSHOOT_NEAR_RANGE := 400.0


## Create a fresh telemetry session dict for a race.
## entrants: Array of {ship: Dictionary, crew: Dictionary}.
static func new_session(entrants: Array, track: Dictionary) -> Dictionary:
	"""Initialize accumulators for all entrants before the sim starts."""
	var per_racer: Dictionary = {}
	for e in entrants:
		var ship: Dictionary = e.ship
		var crew: Dictionary = e.crew
		var sid: String = ship.ship_id
		var skills: Dictionary = crew.get("stats", {}).get("skills", {})
		per_racer[sid] = {
			"ship_id": sid,
			"crew_id": crew.get("crew_id", ""),
			"callsign": crew.get("callsign", "Unknown"),
			"ship_type": ship.get("type", "fighter"),
			# Running accumulators.
			"_total_distance": 0.0,
			"_prev_position": ship.position,
			"_total_speed": 0.0,
			"_max_speed_reached": 0.0,
			"_frames_at_full_throttle": 0,
			"_total_frames": 0,
			"_heading_error_sum": 0.0,
			"_heading_error_frames": 0,
			"_overshoot_count": 0,
			"_correction_count": 0,
			# Real-flight trackers (steering reversals + marker overshoot).
			"_prev_heading": float(ship.get("rotation", 0.0)),
			"_has_prev_heading": false,
			"_prev_heading_delta": 0.0,
			"_last_marker": -1,
			"_prev_dist_to_marker": INF,
			"_dist_was_decreasing": false,
			# Snapshots for final results.
			"crew_skills_snapshot": {
				"piloting": float(skills.get("piloting", 0.5)),
				"awareness": float(skills.get("awareness", 0.5)),
				"composure": float(skills.get("composure", 0.5)),
				"aggression": float(skills.get("aggression", 0.5)),
			},
			"ship_stats_snapshot": {
				"max_speed": float(ship.stats.get("max_speed", 0.0)),
				"acceleration": float(ship.stats.get("acceleration", 0.0)),
				"turn_rate": float(ship.stats.get("turn_rate", 0.0)),
			},
		}

	# Pre-compute ideal lap distance (straight marker-to-marker sum).
	var ideal_lap_dist: float = _ideal_lap_distance(track)

	return {
		"per_racer": per_racer,
		"ideal_lap_distance": ideal_lap_dist,
		"track_laps": track.get("laps", 1),
		"events": [],
		"track_id": track.get("track_id", ""),
		"track_name": track.get("name", ""),
	}


## Sample one racer's accumulators for this tick. marker_pos is the marker the
## racer is currently chasing (the real steering target). Updated in place.
static func sample(session: Dictionary, state: Dictionary, ship: Dictionary,
		marker_pos: Vector2, time: float, prev_pos: Vector2) -> void:
	"""Update running accumulators for one racer this tick."""
	var sid: String = state.ship_id
	if not session.per_racer.has(sid):
		return
	var acc: Dictionary = session.per_racer[sid]

	# Distance traveled this tick.
	acc._total_distance += prev_pos.distance_to(ship.position)

	# Speed stats.
	var speed: float = ship.velocity.length()
	acc._total_speed += speed
	acc._total_frames += 1
	if speed > acc._max_speed_reached:
		acc._max_speed_reached = speed

	# Throttle tracking (via pilot state stored by apply_space_physics).
	var pilot_state: Dictionary = ship.get("_pilot_state", {})
	if float(pilot_state.get("throttle", 0.0)) >= FULL_THROTTLE_THRESHOLD:
		acc._frames_at_full_throttle += 1

	# Heading error: angle between ship facing and direction to the target marker.
	var to_marker: Vector2 = marker_pos - ship.position
	var dist_to_marker: float = to_marker.length()
	if dist_to_marker > 1.0:
		var facing: Vector2 = MovementSystem.get_visual_forward(ship.rotation)
		acc._heading_error_sum += rad_to_deg(abs(facing.angle_to(to_marker.normalized())))
		acc._heading_error_frames += 1

	# Steering corrections: deliberate turn that reverses the previous turn's
	# direction. A cleaner flier (or smoother AI) produces fewer of these.
	var heading_delta: float = wrapf(float(ship.rotation) - acc._prev_heading, -PI, PI)
	if acc._has_prev_heading and absf(heading_delta) > CORRECTION_MIN_TURN \
			and absf(acc._prev_heading_delta) > CORRECTION_MIN_TURN \
			and signf(heading_delta) != signf(acc._prev_heading_delta):
		acc._correction_count += 1
	if absf(heading_delta) > CORRECTION_MIN_TURN:
		acc._prev_heading_delta = heading_delta
	acc._prev_heading = float(ship.rotation)
	acc._has_prev_heading = true

	# Overshoot: distance to the target marker bottoms out then grows again while
	# still near it — the racer flew past and has to double back.
	if state.next_marker != acc._last_marker:
		acc._last_marker = state.next_marker
		acc._prev_dist_to_marker = dist_to_marker
		acc._dist_was_decreasing = false
	else:
		if dist_to_marker < acc._prev_dist_to_marker:
			acc._dist_was_decreasing = true
		elif acc._dist_was_decreasing and dist_to_marker < OVERSHOOT_NEAR_RANGE:
			acc._overshoot_count += 1
			acc._dist_was_decreasing = false
			_log_event(session, time, "overshoot", sid, {})
		acc._prev_dist_to_marker = dist_to_marker

	# Record lap events.
	var lap_times: Array = state.get("lap_times", [])
	if lap_times.size() > acc.get("_laps_logged", 0):
		var lap_idx: int = lap_times.size() - 1
		_log_event(session, time, "lap_completed", sid, {"lap": lap_idx + 1, "lap_time": lap_times[lap_idx]})
		acc["_laps_logged"] = lap_times.size()

	if state.get("finished", false) and not acc.get("_finish_logged", false):
		_log_event(session, time, "finished", sid, {"finish_time": state.finish_time})
		acc["_finish_logged"] = true

	if state.get("dnf", false) and not acc.get("_dnf_logged", false):
		_log_event(session, time, "dnf", sid, {})
		acc["_dnf_logged"] = true


## Finalize the session into the full results dict, with standings and derived metrics.
static func finalize(session: Dictionary, states: Dictionary, sim_time: float) -> Dictionary:
	"""Derive per-racer results, rank, and assemble the top-level results dict."""
	var ideal_total: float = session.ideal_lap_distance * float(session.track_laps)
	var standings: Array = []
	var lap_record: Dictionary = {}

	for sid in session.per_racer:
		var acc: Dictionary = session.per_racer[sid]
		var state: Dictionary = states.get(sid, {})

		var total_dist: float = acc._total_distance
		var path_eff: float = MIN_PATH_EFFICIENCY
		if total_dist > 0.0:
			path_eff = clamp(ideal_total / total_dist, MIN_PATH_EFFICIENCY, 1.0)

		var avg_speed: float = 0.0
		if acc._total_frames > 0:
			avg_speed = acc._total_speed / float(acc._total_frames)

		var throttle_pct: float = 0.0
		if acc._total_frames > 0:
			throttle_pct = float(acc._frames_at_full_throttle) / float(acc._total_frames)

		var avg_heading_err: float = 0.0
		if acc._heading_error_frames > 0:
			avg_heading_err = acc._heading_error_sum / float(acc._heading_error_frames)

		# Lap-time standard deviation (composure signal).
		var lap_times: Array = state.get("lap_times", [])
		var lap_stdev: float = _stdev(lap_times)

		# Best lap across the field for the lap record.
		var best_lap: float = state.get("best_lap", -1.0)
		if best_lap > 0.0:
			var lap_idx: int = _best_lap_index(lap_times, best_lap)
			if lap_record.is_empty() or best_lap < float(lap_record.get("time", INF)):
				lap_record = {"ship_id": sid, "lap": lap_idx + 1, "time": best_lap}

		var racer_result: Dictionary = {
			"ship_id": sid,
			"crew_id": acc.crew_id,
			"callsign": acc.callsign,
			"ship_type": acc.ship_type,
			"rank": 0,  # filled in below
			"finished": state.get("finished", false),
			"dnf": state.get("dnf", false),
			"finish_time": state.get("finish_time", -1.0),
			"lap_times": lap_times.duplicate(),
			"best_lap": best_lap,
			"total_distance": total_dist,
			"ideal_distance": ideal_total,
			"path_efficiency": path_eff,
			"avg_speed": avg_speed,
			"max_speed_reached": acc._max_speed_reached,
			"time_at_full_throttle_pct": throttle_pct,
			"avg_heading_error_deg": avg_heading_err,
			"overshoots": acc._overshoot_count,
			"corrections": acc._correction_count,
			"lap_time_stdev": lap_stdev,
			"markers_passed": state.get("markers_passed", 0),
			"crew_skills_snapshot": acc.crew_skills_snapshot.duplicate(),
			"ship_stats_snapshot": acc.ship_stats_snapshot.duplicate(),
		}
		standings.append(racer_result)

	# Rank: finishers by finish_time asc, then DNFs by markers_passed desc.
	standings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.finished:
			return true
		if b.finished:
			return false
		return a.markers_passed > b.markers_passed
	)
	for i in range(standings.size()):
		standings[i].rank = i + 1

	var winner_id: String = standings[0].ship_id if not standings.is_empty() else ""

	return {
		"track_id": session.track_id,
		"track_name": session.track_name,
		"laps": session.track_laps,
		"seed": session.get("seed", 0),
		"sim_seconds": sim_time,
		"standings": standings,
		"winner_ship_id": winner_id,
		"lap_record": lap_record,
		"events": session.events.duplicate(),
	}


static func _log_event(session: Dictionary, time: float, event_type: String,
		ship_id: String, data: Dictionary) -> void:
	"""Append a timestamped event to the session event log."""
	session.events.append({
		"t": time,
		"type": event_type,
		"ship_id": ship_id,
		"data": data,
	})


## Sum of straight-line distances between consecutive markers (one lap).
static func _ideal_lap_distance(track: Dictionary) -> float:
	"""Compute straight-line marker-to-marker total for one lap."""
	var n: int = RaceTrack.marker_count(track)
	if n < 2:
		return 0.0
	var total: float = 0.0
	for i in range(n):
		var a: Vector2 = RaceTrack.marker_position(track, i)
		var b: Vector2 = RaceTrack.marker_position(track, (i + 1) % n)
		total += a.distance_to(b)
	return total


## Population standard deviation of an array of floats.
static func _stdev(values: Array) -> float:
	"""Compute standard deviation of lap times."""
	if values.size() < 2:
		return 0.0
	var mean: float = 0.0
	for v in values:
		mean += float(v)
	mean /= float(values.size())
	var variance: float = 0.0
	for v in values:
		var diff: float = float(v) - mean
		variance += diff * diff
	variance /= float(values.size())
	return sqrt(variance)


## Index of the lap with the best (lowest) time in the array.
static func _best_lap_index(lap_times: Array, best_lap: float) -> int:
	"""Find the index of the lap matching best_lap time."""
	for i in range(lap_times.size()):
		if abs(float(lap_times[i]) - best_lap) < 0.0001:
			return i
	return 0
