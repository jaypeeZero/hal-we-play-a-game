extends GutTest

const CollisionSystem = preload("res://scripts/space/systems/collision_system.gd")

## Movement behavior harness — simulates a real per-frame tick loop on two
## 4-fighter teams and measures locomotion quality.
##
## Design rationale:
##   The regression is that calculate_blended_control() has NO separation from
##   friendly ships. To expose this we place 4 teammates within 2× collision
##   radius of each other (tight cluster) and drive them all toward the same
##   enemy target. Without separation they will pile up / clip through each other.
##
## Metrics captured:
##   friendly_overlap_events  : frames where two same-team ships are closer than
##                              their combined collision_radii (hull interpenetration)
##   min_friendly_distance    : minimum same-team separation observed over the run
##   mean_speed_second_half   : average ship speed in frames 151-300 (settling check)
##
## Assertions encode "competent movement":
##   1. Friendly overlaps must stay near zero (no sustained hull-clipping)
##   2. Ships must not pile up at near-zero separation
##   3. Ships must not perpetually slide — mean speed in second half is bounded

const SIM_FRAMES   := 300
const DELTA        := 1.0 / 60.0
const TEAM_SIZE    := 4

## Team 0 fighters start tightly clustered — at the edge of their collision_radii.
## collision_radius for a fighter is 15 (from TestFactories), so combined_radii = 30.
## Spawning at 32 units means ships are just barely touching — separation must push
## them apart without requiring them to be inside each other at frame 0.
const TIGHT_SPAWN_STEP := 32.0

## Tactical weights mirroring what CrewIntegrationSystem writes for alpha_strike
const ENGAGE_WEIGHTS := {"pursue": 0.6, "keep_range": 0.4, "evade": 0.1, "formation": 0.0}
const PREFERRED_RANGE := 1500.0

## Weights for a hold/anchor doctrine with high formation pull
const FORMATION_HEAVY_WEIGHTS := {"pursue": 0.2, "keep_range": 0.1, "evade": 0.0, "formation": 0.7}
const FORMATION_HEAVY_RANGE := 1200.0

## Weights for knife-range brawling (high pursue, zero formation)
const KNIFE_FIGHT_WEIGHTS := {"pursue": 0.8, "keep_range": 0.2, "evade": 0.0, "formation": 0.0}
const KNIFE_FIGHT_RANGE := 200.0

## Combined collision radii for a same-class fighter pair
const FIGHTER_COMBINED_RADII := 30.0  # 15 + 15

## How many frames to simulate for convergence scenarios (5 seconds at 60fps)
const CONV_SIM_FRAMES := 300

func _combined_radii(a: Dictionary, b: Dictionary) -> float:
	return a.collision_radius + b.collision_radius

# --- synthetic ship factory ---------------------------------------------------

func _make_tactical_fighter(id: String, pos: Vector2, team: int, target_id: String) -> Dictionary:
	var ship := TestFactories.make_fighter(id, pos, team)
	ship["orders"] = {
		"current_order": "tactical",
		"engagement_target": target_id,
		"target_id": target_id,
		"goal_weights": ENGAGE_WEIGHTS,
		"preferred_range": PREFERRED_RANGE,
		"formation_slot": Vector2.ZERO,
		"anchor_position": Vector2.ZERO,
		"facing_mode": "auto",
	}
	ship["collision_radius"] = 15.0
	return ship

# --- simulation helpers -------------------------------------------------------

func _count_friendly_overlaps(ships: Array) -> int:
	var count := 0
	for i in range(ships.size()):
		for j in range(i + 1, ships.size()):
			var a: Dictionary = ships[i]
			var b: Dictionary = ships[j]
			if a.team != b.team:
				continue
			if a.get("status","") == "destroyed" or b.get("status","") == "destroyed":
				continue
			var dist: float = a.position.distance_to(b.position)
			if dist < _combined_radii(a, b):
				count += 1
	return count

func _min_friendly_dist(ships: Array) -> float:
	var min_d := INF
	for i in range(ships.size()):
		for j in range(i + 1, ships.size()):
			var a: Dictionary = ships[i]
			var b: Dictionary = ships[j]
			if a.team != b.team:
				continue
			if a.get("status","") == "destroyed" or b.get("status","") == "destroyed":
				continue
			var dist: float = a.position.distance_to(b.position)
			if dist < min_d:
				min_d = dist
	return min_d

func _mean_speed(ships: Array) -> float:
	if ships.is_empty():
		return 0.0
	var total := 0.0
	for s in ships:
		total += s.velocity.length()
	return total / ships.size()

# --- main harness test --------------------------------------------------------

func test_tactical_fleet_locomotion_quality():
	## Two teams: team 0 spawns in a tight cluster (25-unit spacing) all targeting
	## the same team-1 ship far to the right. Without separation, they pile up
	## immediately as they all thrust toward the same point. With separation they
	## spread out and min_friendly_distance rises above the combined_radii.

	# Two enemy ships far away on the right (team 1)
	var enemy_a := TestFactories.make_fighter("e0", Vector2(3000.0, -300.0), 1)
	var enemy_b := TestFactories.make_fighter("e1", Vector2(3000.0,  300.0), 1)
	enemy_a["collision_radius"] = 15.0
	enemy_b["collision_radius"] = 15.0

	# Four team-0 fighters, tightly clustered, all targeting enemy_a
	var ships: Array = [enemy_a, enemy_b]
	for i in range(TEAM_SIZE):
		var pos := Vector2(0.0, i * TIGHT_SPAWN_STEP)   # 0, 32, 64, 96 — just at hull-touch distance
		ships.append(_make_tactical_fighter("f%d" % i, pos, 0, "e0"))

	# Metrics
	var friendly_overlap_events := 0
	var min_friendly_distance   := INF
	var speed_sum_second_half   := 0.0
	var speed_frames_second_half := 0
	var game_time := 0.0

	for frame in range(SIM_FRAMES):
		ships = MovementSystem.update_all_ships(ships, DELTA, game_time, [])
		var phys := CollisionSystem.process_physical_collisions(ships, [])
		ships = phys.ships
		game_time += DELTA

		friendly_overlap_events += _count_friendly_overlaps(ships)

		var d := _min_friendly_dist(ships)
		if d < min_friendly_distance:
			min_friendly_distance = d

		if frame >= SIM_FRAMES / 2:
			speed_sum_second_half += _mean_speed(ships)
			speed_frames_second_half += 1

	var mean_speed_second_half: float = 0.0
	if speed_frames_second_half > 0:
		mean_speed_second_half = speed_sum_second_half / speed_frames_second_half

	gut.p("=== MOVEMENT HARNESS RESULTS ===")
	gut.p("friendly_overlap_events : %d" % friendly_overlap_events)
	gut.p("min_friendly_distance   : %.1f" % min_friendly_distance)
	gut.p("mean_speed_second_half  : %.1f" % mean_speed_second_half)
	gut.p("================================")

	# --- assertions ---

	# 1. No hull interpenetration over the run (allow a tiny grace for frame 0
	#    where the 25-unit spawn may already be inside combined_radii=30).
	#    After the fix, separation must push ships apart within the first few frames.
	assert_lt(friendly_overlap_events, 5,
		"Too many same-team hull-overlap events (%d) — ships clipping through each other"
		% friendly_overlap_events)

	# 2. Ships must not collapse on top of each other: min separation > half a combined_radii
	var combined: float = 30.0  # 15 + 15 for fighter pair
	assert_gt(min_friendly_distance, combined * 0.5,
		"Ships squeezed too close (min_dist=%.1f, threshold=%.1f)"
		% [min_friendly_distance, combined * 0.5])

	# 3. Mean speed in the second half must be below 85% of max_speed (300):
	#    ships should not be perpetually accelerating through each other
	var max_fighter_speed: float = TestFactories.SHIP_CLASS_STATS["fighter"]["max_speed"]
	assert_lt(mean_speed_second_half, max_fighter_speed * 0.85,
		"Ships still thrashing at near-max speed in the second half (mean=%.1f)"
		% mean_speed_second_half)


## Scenario 1 — Formation-convergence
## 5 same-team fighters with formation weight 0.7 and formation_slots all
## placed at the SAME point (Vector2.ZERO), so formation is actively trying to
## pile all five ships onto one pixel.  Separation must override and keep hulls
## apart.  This mirrors the real in-game clumping symptom.
func test_formation_convergence_separation_dominates():
	# One distant enemy so the ships have a pursue goal too
	var enemy := TestFactories.make_fighter("ef0", Vector2(3000.0, 0.0), 1)
	enemy["collision_radius"] = 15.0

	# 5 team-0 fighters spread ~40 units apart (just outside combined_radii=30)
	# pointing toward the shared slot at (0,0).  formation weight 0.7.
	var ships: Array = [enemy]
	for i in range(5):
		var pos := Vector2(i * 40.0 - 80.0, 0.0)  # -80, -40, 0, 40, 80
		var ship := TestFactories.make_fighter("fc%d" % i, pos, 0)
		ship["collision_radius"] = 15.0
		# All formation slots at the same central point — maximum convergence pressure
		ship["orders"] = {
			"current_order": "tactical",
			"engagement_target": "ef0",
			"target_id": "ef0",
			"goal_weights": FORMATION_HEAVY_WEIGHTS,
			"preferred_range": FORMATION_HEAVY_RANGE,
			"formation_slot": Vector2.ZERO,
			"anchor_position": Vector2.ZERO,
			"facing_mode": "auto",
		}
		ships.append(ship)

	var friendly_overlap_events := 0
	var min_friendly_distance   := INF
	var speed_sum_second_half   := 0.0
	var speed_frames_second_half := 0
	var game_time := 0.0

	for frame in range(CONV_SIM_FRAMES):
		ships = MovementSystem.update_all_ships(ships, DELTA, game_time, [])
		var phys := CollisionSystem.process_physical_collisions(ships, [])
		ships = phys.ships
		game_time += DELTA
		friendly_overlap_events += _count_friendly_overlaps(ships)
		var d := _min_friendly_dist(ships)
		if d < min_friendly_distance:
			min_friendly_distance = d
		if frame >= CONV_SIM_FRAMES / 2:
			speed_sum_second_half += _mean_speed(ships)
			speed_frames_second_half += 1

	var mean_speed_second_half := speed_sum_second_half / speed_frames_second_half if speed_frames_second_half > 0 else 0.0

	gut.p("=== FORMATION-CONVERGENCE RESULTS ===")
	gut.p("friendly_overlap_events : %d" % friendly_overlap_events)
	gut.p("min_friendly_distance   : %.1f" % min_friendly_distance)
	gut.p("mean_speed_second_half  : %.1f" % mean_speed_second_half)

	# Separation must prevent hull interpenetration even under heavy formation pull
	assert_lt(friendly_overlap_events, 10,
		"Formation weight 0.7 caused hull overlaps (%d events) — separation too weak"
		% friendly_overlap_events)
	assert_gt(min_friendly_distance, FIGHTER_COMBINED_RADII * 0.5,
		"Ships collapsed under formation pull (min_dist=%.1f)" % min_friendly_distance)
	# Ships must still be moving (not frozen by opposing forces)
	var max_fighter_speed: float = TestFactories.SHIP_CLASS_STATS["fighter"]["max_speed"]
	assert_gt(mean_speed_second_half, max_fighter_speed * 0.05,
		"Ships froze — separation and formation cancelling entirely (mean_speed=%.1f)"
		% mean_speed_second_half)


## Scenario 2 — Focus-convergence (knife range)
## 4 same-team fighters all pursuing ONE enemy at very short preferred_range (200).
## All four ships converge on the same point in front of the enemy; separation
## must prevent them from interpenetrating while all chasing the same target.
func test_focus_convergence_knife_range():
	# Single enemy ship dead ahead
	var enemy := TestFactories.make_fighter("kf_enemy", Vector2(400.0, 0.0), 1)
	enemy["collision_radius"] = 15.0

	# 4 team-0 fighters starting in a loose horizontal band behind the enemy
	var ships: Array = [enemy]
	var offsets := [Vector2(-200.0, -60.0), Vector2(-200.0, -20.0),
					Vector2(-200.0,  20.0), Vector2(-200.0,  60.0)]
	for i in range(4):
		var ship := TestFactories.make_fighter("kf%d" % i, offsets[i], 0)
		ship["collision_radius"] = 15.0
		ship["orders"] = {
			"current_order": "tactical",
			"engagement_target": "kf_enemy",
			"target_id": "kf_enemy",
			"goal_weights": KNIFE_FIGHT_WEIGHTS,
			"preferred_range": KNIFE_FIGHT_RANGE,
			"formation_slot": Vector2.ZERO,
			"anchor_position": Vector2.ZERO,
			"facing_mode": "auto",
		}
		ships.append(ship)

	var friendly_overlap_events := 0
	var min_friendly_distance   := INF
	var speed_sum_second_half   := 0.0
	var speed_frames_second_half := 0
	var game_time := 0.0

	for frame in range(CONV_SIM_FRAMES):
		ships = MovementSystem.update_all_ships(ships, DELTA, game_time, [])
		var phys := CollisionSystem.process_physical_collisions(ships, [])
		ships = phys.ships
		game_time += DELTA
		friendly_overlap_events += _count_friendly_overlaps(ships)
		var d := _min_friendly_dist(ships)
		if d < min_friendly_distance:
			min_friendly_distance = d
		if frame >= CONV_SIM_FRAMES / 2:
			speed_sum_second_half += _mean_speed(ships)
			speed_frames_second_half += 1

	var mean_speed_second_half := speed_sum_second_half / speed_frames_second_half if speed_frames_second_half > 0 else 0.0

	gut.p("=== FOCUS-CONVERGENCE (KNIFE RANGE) RESULTS ===")
	gut.p("friendly_overlap_events : %d" % friendly_overlap_events)
	gut.p("min_friendly_distance   : %.1f" % min_friendly_distance)
	gut.p("mean_speed_second_half  : %.1f" % mean_speed_second_half)

	# Pursuit toward a shared point must not cause sustained clipping
	assert_lt(friendly_overlap_events, 15,
		"Shared knife-range target caused hull overlaps (%d events)" % friendly_overlap_events)
	assert_gt(min_friendly_distance, FIGHTER_COMBINED_RADII * 0.4,
		"Ships collapsed at knife range (min_dist=%.1f)" % min_friendly_distance)
	# Ships must still be moving (they're in a knife fight, not frozen)
	var max_fighter_speed: float = TestFactories.SHIP_CLASS_STATS["fighter"]["max_speed"]
	assert_gt(mean_speed_second_half, max_fighter_speed * 0.05,
		"Ships froze entirely at knife range (mean_speed=%.1f)" % mean_speed_second_half)


## Scenario 3 — High-speed head-on
## Two same-team fighters launched at each other at near-max closing velocity.
## Separation must deflect them within a few frames; sustained interpenetration
## (many overlap frames) is a failure.  A brief deflection lag of a few frames
## is acceptable.
func test_high_speed_head_on_deflection():
	# One distant enemy to give ships a non-null target
	var enemy := TestFactories.make_fighter("ho_enemy", Vector2(0.0, 3000.0), 1)
	enemy["collision_radius"] = 15.0

	var max_speed: float = TestFactories.SHIP_CLASS_STATS["fighter"]["max_speed"]

	# Ship A flying right at full speed; Ship B flying left at full speed
	# They start 300 units apart — will close in ~1 second at max_speed each
	var ship_a := TestFactories.make_fighter("ho_a", Vector2(-150.0, 0.0), 0)
	ship_a["collision_radius"] = 15.0
	ship_a["velocity"]         = Vector2(max_speed, 0.0)
	ship_a["orders"] = {
		"current_order": "tactical",
		"engagement_target": "ho_enemy",
		"target_id": "ho_enemy",
		"goal_weights": ENGAGE_WEIGHTS,
		"preferred_range": PREFERRED_RANGE,
		"formation_slot": Vector2.ZERO,
		"anchor_position": Vector2.ZERO,
		"facing_mode": "auto",
	}

	var ship_b := TestFactories.make_fighter("ho_b", Vector2(150.0, 0.0), 0)
	ship_b["collision_radius"] = 15.0
	ship_b["velocity"]         = Vector2(-max_speed, 0.0)
	ship_b["orders"] = {
		"current_order": "tactical",
		"engagement_target": "ho_enemy",
		"target_id": "ho_enemy",
		"goal_weights": ENGAGE_WEIGHTS,
		"preferred_range": PREFERRED_RANGE,
		"formation_slot": Vector2.ZERO,
		"anchor_position": Vector2.ZERO,
		"facing_mode": "auto",
	}

	var ships: Array = [enemy, ship_a, ship_b]
	var friendly_overlap_events := 0
	var min_friendly_distance   := INF
	var game_time := 0.0

	for frame in range(CONV_SIM_FRAMES):
		ships = MovementSystem.update_all_ships(ships, DELTA, game_time, [])
		var phys := CollisionSystem.process_physical_collisions(ships, [])
		ships = phys.ships
		game_time += DELTA
		friendly_overlap_events += _count_friendly_overlaps(ships)
		var d := _min_friendly_dist(ships)
		if d < min_friendly_distance:
			min_friendly_distance = d

	gut.p("=== HIGH-SPEED HEAD-ON RESULTS ===")
	gut.p("friendly_overlap_events : %d" % friendly_overlap_events)
	gut.p("min_friendly_distance   : %.1f" % min_friendly_distance)

	# A few frames of deflection lag is acceptable; sustained clipping is not.
	# Threshold: <20 overlap frames out of 300 (~7% of the run).
	assert_lt(friendly_overlap_events, 20,
		"High-speed head-on caused sustained hull overlap (%d frames)" % friendly_overlap_events)
	# Min distance must not stay at zero (ships must have been pushed apart)
	assert_gt(min_friendly_distance, 0.0,
		"Ships passed completely through each other (min_dist=0)")


## Large-ship separation check
## Two same-team corvettes started within hull-touch distance on tactical orders
## must be pushed apart by separation + collision resolution, not left clumped.
## Corvette collision_radius = 30 (size), so combined_radii = 60.
func test_large_ship_tactical_separation():
	# Distant enemy gives corvettes a target
	var enemy := TestFactories.make_corvette("ls_enemy", Vector2(4000.0, 0.0), 1)
	enemy["collision_radius"] = 30.0

	# Two team-0 corvettes spawned just at hull-touch distance (62 ≈ combined_radii=60)
	var corv_a := TestFactories.make_corvette("ls_a", Vector2(0.0, -31.0), 0)
	corv_a["collision_radius"] = 30.0
	corv_a["orders"] = {
		"current_order": "tactical",
		"engagement_target": "ls_enemy",
		"target_id": "ls_enemy",
		"goal_weights": ENGAGE_WEIGHTS,
		"preferred_range": 1800.0,
		"formation_slot": Vector2.ZERO,
		"anchor_position": Vector2.ZERO,
		"facing_mode": "auto",
	}

	var corv_b := TestFactories.make_corvette("ls_b", Vector2(0.0, 31.0), 0)
	corv_b["collision_radius"] = 30.0
	corv_b["orders"] = {
		"current_order": "tactical",
		"engagement_target": "ls_enemy",
		"target_id": "ls_enemy",
		"goal_weights": ENGAGE_WEIGHTS,
		"preferred_range": 1800.0,
		"formation_slot": Vector2.ZERO,
		"anchor_position": Vector2.ZERO,
		"facing_mode": "auto",
	}

	var ships: Array = [enemy, corv_a, corv_b]
	var friendly_overlap_events := 0
	var min_friendly_distance   := INF
	var game_time := 0.0

	for frame in range(CONV_SIM_FRAMES):
		ships = MovementSystem.update_all_ships(ships, DELTA, game_time, [])
		var phys := CollisionSystem.process_physical_collisions(ships, [])
		ships = phys.ships
		game_time += DELTA
		friendly_overlap_events += _count_friendly_overlaps(ships)
		var d := _min_friendly_dist(ships)
		if d < min_friendly_distance:
			min_friendly_distance = d

	var corvette_combined_radii: float = 60.0  # 30 + 30
	gut.p("=== LARGE-SHIP SEPARATION RESULTS ===")
	gut.p("friendly_overlap_events : %d" % friendly_overlap_events)
	gut.p("min_friendly_distance   : %.1f" % min_friendly_distance)

	assert_lt(friendly_overlap_events, 10,
		"Two corvettes on tactical orders sustained hull overlap (%d events)"
		% friendly_overlap_events)
	assert_gt(min_friendly_distance, corvette_combined_radii * 0.5,
		"Corvettes collapsed (min_dist=%.1f, threshold=%.1f)"
		% [min_friendly_distance, corvette_combined_radii * 0.5])
