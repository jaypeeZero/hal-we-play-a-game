extends RefCounted

## Ship-race debug harness core. Launched via tools/run_race.gd.
##
## Runs one seeded race of generated ships+pilots around a marker track and
## prints per-pilot / per-ship telemetry. This is the flight-tuning surface:
## races exercise the REAL combat steering (see RaceSimulator), so the standings
## and metrics here measure how ship stats and pilot skills fly the same model.

const DEFAULT_TRACK := "asteroid_sprint"
const DEFAULT_SEED := 42
const DEFAULT_FIELD := ["fighter", "fighter", "corvette"]
const DEFAULT_SKILL := 0.5
const LOGS_DIR := "user://races/"
const LOG_FILE_PREFIX := "race_"
## Spread of generated pilot skill around the midpoint, per stat.
const SKILL_SPREAD := 0.3


## Entry point. Returns a process exit code (0 = success).
func run(tree: SceneTree, args: PackedStringArray) -> int:
	"""Parse args, run one race, print standings + telemetry, write a JSONL log."""
	# Silence the event logger: per-event printing/JSONL would add noise and I/O
	# across the whole race. Systems guard logging with the autoload's service.
	var logger_autoload := tree.root.get_node_or_null("BattleEventLoggerAutoload")
	if logger_autoload != null and logger_autoload.service != null:
		logger_autoload.service.queue_free()
		logger_autoload.service = null

	var config := _parse_args(args)
	var track: Dictionary = RaceTrack.load_track(config.track_id)
	if track.is_empty():
		push_error("run_race: cannot load track '%s'" % config.track_id)
		return 1

	print("=== Ship Race Debug Harness ===")
	print("Track: %s | Seed: %d | Field: %s" % [config.track_id, config.seed, str(config.field)])
	print("")

	var entrants := _build_entrants(config.field, config.seed)
	if entrants.is_empty():
		push_error("run_race: no valid entrants (check ship type names)")
		return 1

	var results: Dictionary = RaceSimulator.run(track, entrants, config.seed)
	_print_standings(results)
	_write_log(results)
	return 0


## Parse --track=, --seed=, --field= (comma-separated ship types).
func _parse_args(args: PackedStringArray) -> Dictionary:
	"""Read CLI args into a {track_id, seed, field} config dict."""
	var config := {
		"track_id": DEFAULT_TRACK,
		"seed": DEFAULT_SEED,
		"field": DEFAULT_FIELD.duplicate(),
	}
	for arg in args:
		if arg.begins_with("--track="):
			config.track_id = arg.substr("--track=".length())
		elif arg.begins_with("--seed="):
			config.seed = int(arg.substr("--seed=".length()))
		elif arg.begins_with("--field="):
			var raw: String = arg.substr("--field=".length())
			# Accept "ship_types:a,b" or a plain "a,b" list.
			if raw.begins_with("ship_types:"):
				raw = raw.substr("ship_types:".length())
			var types: Array = []
			for t in raw.split(","):
				var trimmed: String = t.strip_edges()
				if not trimmed.is_empty():
					types.append(trimmed)
			if not types.is_empty():
				config.field = types
	return config


## Build {ship, crew} entrants for the given ship-type field with generated crews.
func _build_entrants(field: Array, seed: int) -> Array:
	"""Create ships of the given types, each with a seeded generated pilot."""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1000
	var entrants: Array = []
	for i in range(field.size()):
		var stype: String = str(field[i]).strip_edges()
		var ship: Dictionary = ShipData.create_ship_instance(stype, i, Vector2.ZERO)
		if ship.is_empty():
			push_error("run_race: unknown ship type '%s'" % stype)
			continue
		entrants.append({"ship": ship, "crew": _generate_pilot(i, rng)})
	return entrants


## Generate a pilot crew with seeded, varied skills.
func _generate_pilot(index: int, rng: RandomNumberGenerator) -> Dictionary:
	"""Return a full pilot crew dict with randomized flight-relevant skills."""
	var callsigns := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
		"Golf", "Hotel"]
	var mid := 0.5
	return {
		"crew_id": "debug_pilot_%d" % index,
		"callsign": callsigns[index % callsigns.size()],
		"role": CrewData.Role.PILOT,
		"qualified_roles": [CrewData.Role.PILOT],
		"stats": {
			"stress": 0.0,
			"fatigue": 0.0,
			"reaction_time": 0.15,
			"skills": {
				"piloting": clampf(mid + rng.randf_range(-SKILL_SPREAD, SKILL_SPREAD), 0.1, 1.0),
				"awareness": clampf(mid + rng.randf_range(-SKILL_SPREAD, SKILL_SPREAD), 0.1, 1.0),
				"composure": clampf(mid + rng.randf_range(-SKILL_SPREAD, SKILL_SPREAD), 0.1, 1.0),
				"aggression": rng.randf(),
				"aim": DEFAULT_SKILL,
				"tactics": DEFAULT_SKILL,
				"machinery": DEFAULT_SKILL,
			},
		},
	}


## Print the standings table and lap record.
func _print_standings(results: Dictionary) -> void:
	"""Print a readable per-racer telemetry table."""
	print("--- Standings ---")
	for entry in results.standings:
		var status: String = "DNF" if entry.dnf else ("%.1fs" % entry.finish_time)
		print("[%d] %-8s %-9s %-6s | eff=%.2f | avg_spd=%4.0f | hdg_err=%4.1f° | overshoots=%d | corrections=%d | piloting=%.2f" % [
			entry.rank,
			entry.callsign,
			entry.ship_type,
			status,
			entry.path_efficiency,
			entry.avg_speed,
			entry.avg_heading_error_deg,
			entry.overshoots,
			entry.corrections,
			float(entry.crew_skills_snapshot.get("piloting", 0.0)),
		])
	if not results.lap_record.is_empty():
		print("")
		print("Lap record: %s — Lap %d — %.2fs" % [
			results.lap_record.get("ship_id", "?"),
			results.lap_record.get("lap", 0),
			results.lap_record.get("time", 0.0),
		])
	print("")
	print("Sim time: %.1fs | Winner: %s" % [results.sim_seconds, results.winner_ship_id])


## Write the full results dict as one JSONL line to user://races/.
func _write_log(results: Dictionary) -> void:
	"""Persist results as JSONL for offline analysis."""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOGS_DIR))
	var path := LOGS_DIR + LOG_FILE_PREFIX + str(results.get("seed", 0)) + ".jsonl"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("run_race: cannot write log to %s" % path)
		return
	f.store_line(JSON.stringify(results))
	f.close()
	print("Log written: %s" % ProjectSettings.globalize_path(path))
