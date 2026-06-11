extends RefCounted

## Elite-vs-rookie duel harness core (DOCS/plans/07, increment 1).
## Launched via tools/duel_sim.gd — see that file for usage.
##
## Runs N seeded 1v1 fighter duels per skill matchup, headless and decoupled
## from the wall clock, and reports win rate, time-to-kill, and gunnery
## accuracy. This is the skill-gap meter: flight-model changes are judged by
## how far they move elite-vs-rookie outcomes away from a coin flip.
##
## The per-frame orchestration deliberately mirrors SpaceBattleGame._process
## (scripts/space/space_battle_game.gd) minus rendering, entities, obstacles,
## and squadron succession — if that loop changes shape, change this one too.
##
## Determinism: each duel seeds Godot's RNG with (base seed + duel index);
## game logic reads only simulated time, so a given seed always replays the
## same battle.

## Simulation tick. 30 Hz halves the frame count of a 60 Hz run; safe because
## hit detection sweeps the full per-frame projectile segment (see
## CollisionSystem._swept_projectile_hits_circle) instead of point-sampling.
const SIM_TICK := 1.0 / 30.0
const MAX_DUEL_SECONDS := 120.0
const SPAWN_DISTANCE_MIN := 2200.0
const SPAWN_DISTANCE_MAX := 2800.0
const WING_REFORM_INTERVAL := 0.5
const DEFAULT_DUELS_PER_MATCHUP := 30
const DEFAULT_BASE_SEED := 1000
## Skill level for every non-isolated stat in piloting-only matchups.
const ISOLATION_BASE_SKILL := 0.5
## Default matrix: a ladder from total skill gap down to the mirror control
## (which must sit near 50% or the harness itself is biased), plus a
## piloting-only matchup that isolates FLIGHT skill — both crews get
## identical aim, awareness, tactics, composure, aggression, and reaction
## times; only the piloting stat differs.
const DEFAULT_MATCHUPS := [
	{"a": 1.0, "b": 0.0, "isolate": ""},
	{"a": 0.85, "b": 0.15, "isolate": ""},
	{"a": 0.7, "b": 0.3, "isolate": ""},
	{"a": 0.55, "b": 0.45, "isolate": ""},
	{"a": 0.5, "b": 0.5, "isolate": ""},
	{"a": 1.0, "b": 0.0, "isolate": "piloting"},
]

func run(tree: SceneTree, args: PackedStringArray) -> int:
	# Silence the event logger: per-event printing and JSONL writes would
	# dominate runtime across millions of simulated frames. All systems guard
	# logging with `if BattleEventLoggerAutoload.service`.
	var logger_autoload := tree.root.get_node_or_null("BattleEventLoggerAutoload")
	if logger_autoload != null and logger_autoload.service != null:
		logger_autoload.service.queue_free()
		logger_autoload.service = null

	var config := _parse_args(args)
	print("Duel harness: %d duels per matchup, base seed %d, tick %.4fs, cap %.0fs"
		% [config.duels, config.base_seed, SIM_TICK, MAX_DUEL_SECONDS])

	for matchup in config.matchups:
		var report := _run_matchup(matchup, config.duels, config.base_seed)
		_print_report(matchup, report)

	return 0

func _parse_args(args: PackedStringArray) -> Dictionary:
	var config := {
		"duels": DEFAULT_DUELS_PER_MATCHUP,
		"matchups": DEFAULT_MATCHUPS,
		"base_seed": DEFAULT_BASE_SEED,
	}
	var skill_a := -1.0
	var skill_b := -1.0
	var isolate := ""
	var i := 0
	while i < args.size():
		match args[i]:
			"--duels":
				i += 1
				config.duels = int(args[i])
			"--skill-a":
				i += 1
				skill_a = float(args[i])
			"--skill-b":
				i += 1
				skill_b = float(args[i])
			"--seed":
				i += 1
				config.base_seed = int(args[i])
			"--piloting-only":
				isolate = "piloting"
		i += 1
	if skill_a >= 0.0 and skill_b >= 0.0:
		config.matchups = [{"a": skill_a, "b": skill_b, "isolate": isolate}]
	return config

# ============================================================================
# MATCHUP AGGREGATION
# ============================================================================

func _run_matchup(matchup: Dictionary, duels: int, base_seed: int) -> Dictionary:
	var totals := {
		"wins": [0, 0],
		"draws": 0,
		"decided_duration": 0.0,
		"shots": [0, 0],
		"hits": [0, 0],
		"damage": [0.0, 0.0],
	}
	for i in duels:
		var result := _run_duel(matchup, base_seed + i)
		if result.winner < 0:
			totals.draws += 1
		else:
			totals.wins[result.winner] += 1
			totals.decided_duration += result.duration
		for team in 2:
			totals.shots[team] += result.shots[team]
			totals.hits[team] += result.hits[team]
			totals.damage[team] += result.damage[team]
	return totals

func _print_report(matchup: Dictionary, totals: Dictionary) -> void:
	var duels: int = totals.wins[0] + totals.wins[1] + totals.draws
	var decided: int = totals.wins[0] + totals.wins[1]
	var scope := "crew skill" if matchup.isolate == "" else "%s ONLY, rest at %.2f" % [matchup.isolate, ISOLATION_BASE_SKILL]
	print("")
	print("=== A (%s %.2f) vs B (%s %.2f) — %d duels ===" % [scope, matchup.a, scope, matchup.b, duels])
	print("  A wins %d (%.0f%% of decided)  |  B wins %d  |  draws %d"
		% [totals.wins[0], 100.0 * totals.wins[0] / maxf(decided, 1), totals.wins[1], totals.draws])
	if decided > 0:
		print("  avg time-to-kill (decided): %.1fs" % (totals.decided_duration / decided))
	for team in 2:
		var label := "A" if team == 0 else "B"
		var hit_rate: float = 100.0 * totals.hits[team] / maxf(totals.shots[team], 1)
		print("  %s: %5d shots, %4d hits (%.1f%%), %.0f damage dealt"
			% [label, totals.shots[team], totals.hits[team], hit_rate, totals.damage[team]])

# ============================================================================
# SINGLE DUEL — frame loop mirrors SpaceBattleGame._process
# ============================================================================

func _run_duel(matchup: Dictionary, duel_seed: int) -> Dictionary:
	seed(duel_seed)
	var bearing := randf() * TAU
	var spawn_distance := randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)
	var pos_a := Vector2.ZERO
	var pos_b := Vector2.from_angle(bearing) * spawn_distance

	var ship_a: Dictionary = ShipData.create_ship_instance("fighter", 0, pos_a)
	var ship_b: Dictionary = ShipData.create_ship_instance("fighter", 1, pos_b)
	ship_a.rotation = MovementSystem.direction_to_heading(pos_b - pos_a)
	ship_b.rotation = MovementSystem.direction_to_heading(pos_a - pos_b)

	var ships: Array = [ship_a, ship_b]
	var crew_list: Array = []
	crew_list.append_array(_create_crew(ship_a, matchup.a, matchup.isolate))
	crew_list.append_array(_create_crew(ship_b, matchup.b, matchup.isolate))

	var projectiles: Array = []
	var mailboxes: Dictionary = {}
	var wings: Array = []
	var wings_formed_at := -1.0
	var weapon_timer := 0.0
	var sim_time := 0.0

	var stats := {
		"winner": -1,
		"duration": MAX_DUEL_SECONDS,
		"shots": [0, 0],
		"hits": [0, 0],
		"damage": [0.0, 0.0],
	}

	while sim_time < MAX_DUEL_SECONDS:
		sim_time += SIM_TICK

		# 0. CREW AI on pre-movement grids
		var pre_ship_grid: Dictionary = SpatialGridSystem.build(ships, SpaceBattleGame.GRID_CELL_SIZE)
		var pre_proj_grid: Dictionary = SpatialGridSystem.build(projectiles, SpaceBattleGame.GRID_CELL_SIZE)
		crew_list = CommandChainSystem.process_command_chain(crew_list)
		if wings_formed_at < 0.0 or sim_time - wings_formed_at >= WING_REFORM_INTERVAL:
			wings = WingFormationSystem.form_wings(ships, crew_list, wings)
			wings_formed_at = sim_time
		var sched: Dictionary = CrewSchedulerSystem.tick_with_awareness(
			crew_list, sim_time, mailboxes, ships, projectiles, wings,
			pre_ship_grid, pre_proj_grid)
		crew_list = sched.crew_list
		mailboxes = sched.mailboxes
		ships = _apply_decisions(ships, crew_list, sched.decisions, sim_time)

		# 0a. PENDING INTENTS whose commit_at has passed
		var intents: Dictionary = PendingIntentSystem.commit_due(ships, sim_time)
		ships = intents.ships

		# 1. MOVEMENT
		ships = MovementSystem.update_all_ships(ships, SIM_TICK, sim_time)
		var ship_grid: Dictionary = SpatialGridSystem.build(ships, SpaceBattleGame.GRID_CELL_SIZE)

		# 1b. SENSOR CONTACT TRIGGERS
		var triggers: Dictionary = _check_spatial_triggers(crew_list, ships, ship_grid, mailboxes, sim_time)
		crew_list = triggers.crew_list
		mailboxes = triggers.mailboxes

		# 2-3. WEAPONS on the same cadence as the game loop
		weapon_timer += SIM_TICK
		if weapon_timer >= SpaceBattleGame.WEAPON_UPDATE_INTERVAL:
			weapon_timer = 0.0
			for i in ships.size():
				if ships[i].status in ["disabled", "destroyed"]:
					continue
				var weapon_result: Dictionary = WeaponSystem.update_weapons(ships[i], ships, SIM_TICK)
				var team: int = ships[i].team
				ships[i] = weapon_result.ship_data
				for fire_command in weapon_result.fire_commands:
					projectiles.append(ProjectileSystem.create_projectile(fire_command, team))
					stats.shots[team] += 1

		# 4. PROJECTILE ADVANCE + expiry
		var advance: Dictionary = ProjectileSystem.advance_all_projectiles_in_place(projectiles, SIM_TICK)
		if not advance.expired_ids.is_empty():
			var expired := {}
			for id in advance.expired_ids:
				expired[id] = true
			projectiles = projectiles.filter(
				func(p): return p != null and not expired.has(p.projectile_id))

		# 5. PROJECTILE HITS
		var collisions: Dictionary = CollisionSystem.process_collisions(ships, projectiles, [], ship_grid, {})
		ships = collisions.ships
		projectiles = collisions.projectiles
		for hit in collisions.hits:
			var victim: Dictionary = _find_ship(ships, hit.get("ship_id", ""))
			if victim.is_empty():
				continue
			var shooter_team: int = 1 - int(victim.team)
			stats.hits[shooter_team] += 1
			stats.damage[shooter_team] += hit.get("damage", 0.0)
		mailboxes = _emit_damage_events(crew_list, collisions.hits, mailboxes, sim_time)

		# 5a. PHYSICAL COLLISIONS (ship-ship ramming)
		var physical: Dictionary = CollisionSystem.process_physical_collisions(ships, [])
		ships = physical.ships

		# 7+9. CLEANUP + WIN CHECK
		var alive := [0, 0]
		var survivors: Array = []
		for ship in ships:
			if DamageResolver.is_ship_destroyed(ship):
				crew_list = crew_list.filter(func(c): return c.assigned_to != ship.ship_id)
				continue
			survivors.append(ship)
			alive[int(ship.team)] += 1
		ships = survivors

		if alive[0] == 0 or alive[1] == 0:
			stats.duration = sim_time
			if alive[0] > 0:
				stats.winner = 0
			elif alive[1] > 0:
				stats.winner = 1
			break

	return stats

## Create a ship's crew at `skill`, or — when isolating a single stat — at
## ISOLATION_BASE_SKILL for everything (including reaction/decision times,
## which derive from the creation skill) with only the isolated stat at
## `skill`.
func _create_crew(ship: Dictionary, skill: float, isolate: String) -> Array:
	if isolate == "":
		return ShipData.create_crew_for_ship(ship, skill)
	var crew := ShipData.create_crew_for_ship(ship, ISOLATION_BASE_SKILL)
	for member in crew:
		member.stats.skills[isolate] = skill
	return crew

# ============================================================================
# MIRRORS OF SpaceBattleGame PRIVATE STEPS
# ============================================================================

## Mirrors SpaceBattleGame._apply_crew_decisions (minus event logging).
func _apply_decisions(ships: Array, crew_list: Array, decisions: Array, sim_time: float) -> Array:
	if decisions.is_empty():
		return ships
	var immediate: Array = []
	for decision in decisions:
		if decision.has("commit_at") and decision.commit_at > sim_time:
			var ship_idx: int = CrewIntegrationSystem.find_ship_index(ships, decision.get("entity_id", ""))
			if ship_idx < 0:
				continue
			var crew_snapshot: Dictionary = CrewIntegrationSystem.find_crew_by_id(crew_list, decision.get("crew_id", ""))
			var payload := {"decision": decision, "crew_snapshot": crew_snapshot}
			ships[ship_idx] = PendingIntentSystem.attach(
				ships[ship_idx], decision.get("intent_type", ""), payload, decision.commit_at)
		else:
			immediate.append(decision)
	if not immediate.is_empty():
		ships = CrewIntegrationSystem.apply_crew_decisions_to_ships(ships, crew_list, immediate).ships
	return ships

## Mirrors SpaceBattleGame._check_spatial_awareness_triggers.
func _check_spatial_triggers(crew_list: Array, ships: Array, ship_grid: Dictionary, mailboxes: Dictionary, sim_time: float) -> Dictionary:
	for i in crew_list.size():
		var crew: Dictionary = crew_list[i]
		var assigned: String = crew.assigned_to if crew.assigned_to != null else ""
		var ship: Dictionary = _find_ship(ships, assigned)
		if ship.is_empty():
			continue
		var sensor_range: float = float(crew.get("stats", {}).get("awareness_range", 800.0))
		var previous: Dictionary = crew.awareness.get("_spatial_seen", {})
		var current: Dictionary = {}
		for other in SpatialGridSystem.query_radius(ship_grid, ship.position, sensor_range):
			if other.ship_id == ship.ship_id or other.team == ship.team:
				continue
			var distance: float = ship.position.distance_to(other.position)
			if distance <= sensor_range:
				current[other.ship_id] = true
				if not previous.has(other.ship_id):
					var awareness: float = clamp(float(crew.get("stats", {}).get("skills", {}).get("awareness", 0.5)), 0.0, 1.0)
					var latency: float = (1.0 - awareness) * WingConstants.MAX_DETECTION_LAG
					mailboxes = _post_event(mailboxes, crew.crew_id, "threat_appeared", {
						"enemy_id": other.ship_id,
						"position": other.position,
						"distance": distance,
					}, sim_time, latency)
		for previous_id in previous.keys():
			if not current.has(previous_id):
				mailboxes = _post_event(mailboxes, crew.crew_id, "target_lost", {
					"enemy_id": previous_id,
				}, sim_time, 0.0)
		var updated: Dictionary = crew.duplicate(true)
		updated.awareness["_spatial_seen"] = current
		crew_list[i] = updated
	return {"crew_list": crew_list, "mailboxes": mailboxes}

## Mirrors SpaceBattleGame._emit_damage_events.
func _emit_damage_events(crew_list: Array, hits: Array, mailboxes: Dictionary, sim_time: float) -> Dictionary:
	for hit in hits:
		var target_id: String = hit.get("ship_id", "")
		if target_id.is_empty():
			continue
		for crew in crew_list:
			if crew.assigned_to == target_id:
				var awareness: float = clamp(float(crew.get("stats", {}).get("skills", {}).get("awareness", 0.5)), 0.0, 1.0)
				var latency: float = (1.0 - awareness) * WingConstants.MAX_DAMAGE_PERCEPTION_LAG
				mailboxes = _post_event(mailboxes, crew.crew_id, "ship_damaged", {
					"damage": hit.get("damage", 0),
					"section": hit.get("section", ""),
					"attacker": hit.get("projectile_id", ""),
				}, sim_time, latency)
	return mailboxes

## Mirrors SpaceBattleGame._queue_crew_event with simulated time.
func _post_event(mailboxes: Dictionary, crew_id: String, event_type: String, data: Dictionary, sim_time: float, latency_seconds: float) -> Dictionary:
	var event: Dictionary = {"type": event_type, "data": data}
	if latency_seconds > 0.0:
		event["deliver_at"] = sim_time + latency_seconds
	return CrewMailboxSystem.post_event(mailboxes, crew_id, event)

func _find_ship(ships: Array, ship_id: String) -> Dictionary:
	for ship in ships:
		if ship.ship_id == ship_id:
			return ship
	return {}
