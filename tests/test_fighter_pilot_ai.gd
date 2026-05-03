extends GutTest

## Tests for FighterPilotAI - Simple, straightforward fighter pilot behavior
##
## Tests verify FUNCTIONALITY (behaviors), not specific data values
## Following test-driven approach: test behaviors and capabilities

var game_time: float = 0.0

# ============================================================================
# HELPER FUNCTIONS - Create test data
# ============================================================================

func create_fighter_ship(id: String, position: Vector2, team: int = 0) -> Dictionary:
	return {
		"ship_id": id,
		"type": "fighter",
		"team": team,
		"position": position,
		"rotation": 0.0,
		"velocity": Vector2.ZERO,
		"status": "operational",
		"collision_radius": 15.0,
		"stats": {
			"max_speed": 300.0,
			"acceleration": 100.0,
			"turn_rate": 3.0,
			"mass": 50.0,
			"size": 15.0
		},
		"orders": {
			"current_order": "",
			"target_id": ""
		}
	}

func create_corvette_ship(id: String, position: Vector2, team: int = 0) -> Dictionary:
	var ship = create_fighter_ship(id, position, team)
	ship.type = "corvette"
	ship.stats.max_speed = 200.0
	ship.stats.size = 30.0
	ship.collision_radius = 30.0
	return ship

func create_capital_ship(id: String, position: Vector2, team: int = 0) -> Dictionary:
	var ship = create_fighter_ship(id, position, team)
	ship.type = "capital"
	ship.stats.max_speed = 100.0
	ship.stats.size = 60.0
	ship.collision_radius = 60.0
	return ship

func create_pilot_crew(id: String, ship_id: String) -> Dictionary:
	return {
		"crew_id": id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"stats": {
			"skill": 0.8,
			"reaction_time": 0.1,
			"stress": 0.0,
			"fatigue": 0.0
		},
		"awareness": {
			"threats": [],
			"opportunities": [],
			"known_entities": []
		}
	}

# ============================================================================
# BEHAVIOR TESTS - Distance-based speed control
# ============================================================================

func test_full_speed_pursuit_when_far_away():
	# BEHAVIOR: When target is far away (beyond FAR_RANGE), fighter pursues at full speed
	var far_distance = FighterPilotAI.FAR_RANGE * 1.5  # Well beyond far range
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var target = create_fighter_ship("enemy1", Vector2(far_distance, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, target], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	assert_string_contains(decision.subtype, "pursue", "Should pursue when far away")

func test_slows_approach_at_mid_range():
	# BEHAVIOR: When target is at mid range, use tactical approach maneuvers (not close-range combat)
	var mid_distance = (FighterPilotAI.MID_RANGE + FighterPilotAI.FAR_RANGE) / 2.0  # Middle of mid range
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var target = create_fighter_ship("enemy1", Vector2(mid_distance, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, target], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	# When target is at mid range, should use pursuit-type maneuvers, not close-range ones
	var is_not_close_combat = decision.subtype not in ["fight_tight_pursuit", "fight_dogfight_maneuver"]
	assert_true(is_not_close_combat, "Should use approach maneuvers when target is at mid range")

func test_tight_maneuvering_at_close_range():
	# BEHAVIOR: At very close range (inside MIN_COMBAT_RANGE), fighter uses tight maneuvers
	var close_distance = FighterPilotAI.MIN_COMBAT_RANGE * 0.8  # Inside minimum combat range
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var target = create_fighter_ship("enemy1", Vector2(close_distance, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, target], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	var is_close_combat = decision.subtype in ["fight_tight_pursuit", "fight_dogfight_maneuver", "fight_flank_behind"]
	assert_true(is_close_combat, "Should use tight maneuvering at close range")

# ============================================================================
# BEHAVIOR TESTS - Fighter vs Fighter combat
# ============================================================================

func test_tries_to_get_behind_enemy_fighter():
	# BEHAVIOR: When fighting fighters at close range, try to get behind enemy
	var close_distance = FighterPilotAI.CLOSE_RANGE * 0.5  # Well inside close range
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var enemy = create_fighter_ship("enemy1", Vector2(close_distance, 0), 1)
	enemy.rotation = 0.0  # Facing right
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, enemy], [crew], game_time)

	# Should attempt flanking or pursuit maneuvers
	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	assert_true(decision.has("behind_position") or "flank" in decision.subtype.to_lower() or "pursuit" in decision.subtype.to_lower(),
		"Should consider getting behind enemy")

func test_formation_flying_with_wingmates():
	# BEHAVIOR: When fighting with wingmates, maintain formation
	var formation_spacing = FighterPilotAI.FORMATION_SPACING
	var combat_distance = FighterPilotAI.CLOSE_RANGE * 0.8
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var wingmate = create_fighter_ship("fighter2", Vector2(formation_spacing, formation_spacing), 0)  # Nearby friendly
	var enemy = create_fighter_ship("enemy1", Vector2(combat_distance, 0), 1)
	var crew1 = create_pilot_crew("pilot1", "fighter1")
	var crew2 = create_pilot_crew("pilot2", "fighter2")
	crew1.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew1, my_ship, [my_ship, wingmate, enemy], [crew1, crew2], game_time)

	# Should include formation offset when wingmates present
	assert_true(decision.has("formation_offset"), "Should calculate formation offset with wingmates")

# ============================================================================
# BEHAVIOR TESTS - Fighter vs Capital/Corvette combat
# ============================================================================

func test_stays_at_distance_vs_capital_ships():
	# BEHAVIOR: When fighting capitals/corvettes too close, use defensive maneuvers
	var too_close_distance = FighterPilotAI.SAFE_DISTANCE_VS_CAPITAL * 0.5  # Too close to capital
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var capital = create_capital_ship("capital1", Vector2(too_close_distance, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["capital1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, capital], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	var is_defensive = decision.subtype in ["fight_dodge_and_weave", "fight_cautious_approach", "fight_evasive_retreat"]
	assert_true(is_defensive, "Should use defensive maneuvers vs capital ships")

func test_dodge_and_weave_vs_corvettes():
	# BEHAVIOR: When fighting corvettes solo at safe distance, dodge and weave
	var safe_distance = FighterPilotAI.SAFE_DISTANCE_VS_CAPITAL  # At safe harass distance
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var corvette = create_corvette_ship("corvette1", Vector2(safe_distance, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["corvette1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, corvette], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	# Should use evasive tactics when solo vs larger ship
	assert_ne(decision.subtype, "fight_pursue_full_speed", "Should not charge capital ships alone")

func test_group_runs_with_multiple_fighters():
	# BEHAVIOR: With many fighters, coordinate group runs vs capitals
	var formation_spacing = FighterPilotAI.FORMATION_SPACING
	var attack_distance = FighterPilotAI.SAFE_DISTANCE_VS_CAPITAL * 0.8  # Close enough for attack run
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var fighters = [my_ship]
	var crew_list = [create_pilot_crew("pilot1", "fighter1")]

	# Add enough friendly fighters nearby to meet GROUP_RUN_THRESHOLD
	for i in range(2, FighterPilotAI.GROUP_RUN_THRESHOLD + 2):
		var fighter = create_fighter_ship("fighter" + str(i), Vector2(i * formation_spacing, 0), 0)
		fighters.append(fighter)
		crew_list.append(create_pilot_crew("pilot" + str(i), "fighter" + str(i)))

	var capital = create_capital_ship("capital1", Vector2(attack_distance, 0), 1)
	fighters.append(capital)
	var crew = crew_list[0]
	crew.awareness.threats = ["capital1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, fighters, crew_list, game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	# With enough fighters, should coordinate group runs
	var is_group_run = "group_run" in decision.subtype
	assert_true(is_group_run, "Should coordinate group runs with multiple fighters")
	assert_true(decision.has("nearby_fighters"), "Should track nearby fighters count")

# ============================================================================
# BEHAVIOR TESTS - Edge cases
# ============================================================================

func test_handles_no_targets_gracefully():
	# BEHAVIOR: When no targets available, idle
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = []
	crew.awareness.opportunities = []

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	assert_eq(decision.subtype, "idle", "Should idle when no targets")

func test_decision_includes_required_fields():
	# BEHAVIOR: All decisions include required fields for integration
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var enemy = create_fighter_ship("enemy1", Vector2(500, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, enemy], [crew], game_time)

	# Verify required fields for CrewAISystem integration
	assert_true(decision.has("type"), "Decision should have type")
	assert_true(decision.has("subtype"), "Decision should have subtype")
	assert_true(decision.has("crew_id"), "Decision should have crew_id")
	assert_true(decision.has("entity_id"), "Decision should have entity_id")
	assert_true(decision.has("skill_factor"), "Decision should have skill_factor")
	assert_true(decision.has("delay"), "Decision should have delay")
	assert_true(decision.has("timestamp"), "Decision should have timestamp")

func test_movement_system_handles_fighter_engage():
	# BEHAVIOR: MovementSystem can process FighterPilotAI maneuvers
	var ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var target = create_fighter_ship("enemy1", Vector2(300, 0), 1)

	# Set up fighter_engage order with various subtypes
	var subtypes = ["fight_pursue_full_speed", "fight_dogfight_maneuver", "fight_dodge_and_weave", "fight_group_run_attack"]

	for subtype in subtypes:
		ship.orders.current_order = "fighter_engage"
		ship.orders.target_id = "enemy1"
		ship.orders.maneuver_subtype = subtype

		var updated = MovementSystem.update_ship_movement(ship, [ship, target], 0.016, [])

		assert_not_null(updated, "MovementSystem should handle " + subtype)
		assert_true(updated.has("position"), "Should update position for " + subtype)
		assert_true(updated.has("velocity"), "Should update velocity for " + subtype)

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

func test_full_integration_fighter_vs_fighter():
	# BEHAVIOR: Full integration from AI decision to movement
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	my_ship.velocity = Vector2(100, 0)  # Moving right
	var enemy = create_fighter_ship("enemy1", Vector2(300, 0), 1)
	enemy.velocity = Vector2(-50, 0)  # Moving left (toward us)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["enemy1"]

	# 1. AI makes decision
	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, enemy], [crew], game_time)

	# 2. Apply decision to ship via CrewIntegrationSystem
	var updated_ship = CrewIntegrationSystem.apply_decision_to_ship(my_ship, decision, crew)

	# 3. Verify ship orders were updated
	assert_eq(updated_ship.orders.current_order, "fighter_engage", "Should set fighter_engage order")
	assert_eq(updated_ship.orders.target_id, "enemy1", "Should target enemy")

	# 4. MovementSystem processes the ship
	var final_ship = MovementSystem.update_ship_movement(updated_ship, [updated_ship, enemy], 0.016, [])

	# 5. Verify ship moved
	assert_ne(final_ship.position, my_ship.position, "Ship should move based on AI decision")
	assert_true(final_ship.has("_pilot_state"), "Should have pilot state from movement calculation")

func test_full_integration_group_run():
	# BEHAVIOR: Multiple fighters coordinate group run on capital
	var formation_spacing = FighterPilotAI.FORMATION_SPACING
	var attack_distance = FighterPilotAI.SAFE_DISTANCE_VS_CAPITAL * 0.8
	var fighters = []
	var crew_list = []

	# Create enough fighters to meet GROUP_RUN_THRESHOLD
	var num_fighters = FighterPilotAI.GROUP_RUN_THRESHOLD + 1
	for i in range(num_fighters):
		var fighter = create_fighter_ship("fighter" + str(i), Vector2(i * formation_spacing, 0), 0)
		fighters.append(fighter)
		var crew = create_pilot_crew("pilot" + str(i), "fighter" + str(i))
		crew.awareness.threats = ["capital1"]
		crew_list.append(crew)

	var capital = create_capital_ship("capital1", Vector2(attack_distance, 0), 1)
	fighters.append(capital)

	# All fighters make decisions
	var decisions = []
	for i in range(num_fighters):
		var decision = FighterPilotAI.make_decision(crew_list[i], fighters[i], fighters, crew_list, game_time)
		decisions.append(decision)

	# Verify group coordination
	var group_run_count = 0
	for decision in decisions:
		if "group_run" in decision.subtype:
			group_run_count += 1

	assert_gt(group_run_count, 0, "At least some fighters should coordinate group runs")

# ============================================================================
# COLLISION DETECTION AND LATERAL THRUST TESTS
# ============================================================================

func test_collision_detection_head_on_approach():
	# BEHAVIOR: Two ships flying toward each other should detect collision course
	var collision_range = FighterPilotAI.COLLISION_DETECTION_RANGE * 0.8  # Within detection range
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	my_ship.velocity = Vector2(200, 0)  # Flying right
	my_ship.rotation = 0.0

	var enemy = create_fighter_ship("enemy1", Vector2(collision_range, 0), 1)
	enemy.velocity = Vector2(-200, 0)  # Flying left (toward us)
	enemy.rotation = PI

	# Use the collision detection function directly
	var is_collision = FighterPilotAI._is_on_collision_course(my_ship, enemy)

	assert_true(is_collision, "Should detect head-on collision course when both ships approaching")

func test_collision_detection_not_triggered_when_diverging():
	# BEHAVIOR: Ships moving apart should NOT trigger collision detection
	var collision_range = FighterPilotAI.COLLISION_DETECTION_RANGE * 0.8
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	my_ship.velocity = Vector2(-200, 0)  # Flying left (away from enemy)

	var enemy = create_fighter_ship("enemy1", Vector2(collision_range, 0), 1)
	enemy.velocity = Vector2(200, 0)  # Flying right (away from us)

	var is_collision = FighterPilotAI._is_on_collision_course(my_ship, enemy)

	assert_false(is_collision, "Should NOT detect collision when ships diverging")

func test_skilled_pilot_chooses_lateral_break_on_collision():
	# BEHAVIOR: Skilled pilot facing head-on collision should choose lateral_break
	var collision_range = FighterPilotAI.COLLISION_DETECTION_RANGE * 0.8
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	my_ship.velocity = Vector2(200, 0)
	my_ship.rotation = 0.0

	var enemy = create_fighter_ship("enemy1", Vector2(collision_range, 0), 1)
	enemy.velocity = Vector2(-200, 0)
	enemy.rotation = PI

	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.stats.skill = 0.8  # Skilled pilot
	crew.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, enemy], [crew], game_time)

	assert_eq(decision.subtype, "fight_lateral_break", "Skilled pilot should choose lateral_break on head-on collision")

func test_lateral_break_returns_lateral_thrust():
	# BEHAVIOR: lateral_break maneuver should return lateral_thrust in pilot_control
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	my_ship.velocity = Vector2(200, 0)
	my_ship.orders = {"evasion_direction": 1}  # Evade right

	var enemy = create_fighter_ship("enemy1", Vector2(1000, 0), 1)

	var pilot_control = MovementSystem.calculate_lateral_break(my_ship, enemy, [], [])

	assert_has(pilot_control, "lateral_thrust", "lateral_break should return lateral_thrust")
	assert_ne(pilot_control.lateral_thrust, 0, "lateral_thrust should be non-zero")

func test_lateral_thrust_physics_applies_perpendicular_acceleration():
	# BEHAVIOR: lateral_thrust should apply acceleration perpendicular to facing
	var ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	ship.velocity = Vector2(0, -100)  # Moving up (same as facing)
	ship.rotation = 0.0  # Facing up: get_visual_forward(0) = Vector2(0, -1)
	ship.stats.acceleration = 100.0
	ship.stats.lateral_acceleration = 0.3  # 30% of main engine

	var pilot_control = {
		"desired_heading": 0.0,
		"thrust_active": false,  # No main thrust
		"lateral_thrust": 1  # Thrust right (perpendicular to facing)
	}

	var result = MovementSystem.apply_space_physics(ship, pilot_control, 1.0)

	# Ship faces (0, -1) "up", perpendicular right is (1, 0)
	# Lateral thrust right should add positive X velocity
	# Expected: lateral_accel = 100 * 0.3 = 30, so velocity.x should increase by ~30
	assert_gt(result.velocity.x, 0, "Lateral thrust right should add positive X velocity")
	assert_almost_eq(result.velocity.x, 30.0, 1.0, "Lateral thrust should apply correct acceleration")

# ============================================================================
# INERTIAL DAMPENING - Flight assist makes fighters feel tight, not boats on ice
# ============================================================================

func test_inertial_dampening_kills_perpendicular_drift():
	# BEHAVIOR: A ship facing forward but drifting sideways should have its
	# sideways drift reduced by the flight computer (inertial dampening).
	var ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	ship.rotation = 0.0  # Facing up: get_visual_forward(0) = Vector2(0, -1)
	ship.velocity = Vector2(100, 0)  # Drifting purely sideways
	ship.stats.inertial_dampening = 4.0

	var pilot_control = {
		"desired_heading": 0.0,
		"thrust_active": false,
		"throttle": 0.0
	}

	var result = MovementSystem.apply_space_physics(ship, pilot_control, 0.1)

	# Sideways component must shrink (the flight computer is killing the drift)
	assert_lt(abs(result.velocity.x), 100.0, "Inertial dampening should reduce perpendicular velocity")
	# 4.0 dampening * 0.1 delta = 40% removed
	assert_almost_eq(result.velocity.x, 60.0, 1.0, "Should remove ~40% of perpendicular drift in 0.1s at rate 4.0")

func test_inertial_dampening_preserves_forward_velocity():
	# BEHAVIOR: Forward-aligned velocity should NOT be affected by dampening
	# (only perpendicular drift gets killed).
	var ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	ship.rotation = 0.0  # Facing up
	ship.velocity = Vector2(0, -200)  # Moving forward (aligned with facing)
	ship.stats.inertial_dampening = 4.0

	var pilot_control = {
		"desired_heading": 0.0,
		"thrust_active": false,
		"throttle": 0.0
	}

	var result = MovementSystem.apply_space_physics(ship, pilot_control, 0.1)

	# Forward velocity preserved
	assert_almost_eq(result.velocity.y, -200.0, 0.1, "Forward velocity should be preserved")
	assert_almost_eq(result.velocity.x, 0.0, 0.1, "No sideways component should appear")

func test_inertial_dampening_disabled_during_lateral_thrust():
	# BEHAVIOR: When pilot is actively strafing, dampening must NOT cancel the
	# strafe — the manual lateral thruster takes priority. This preserves the
	# lateral_break / weave maneuvers.
	var ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	ship.rotation = 0.0  # Facing up
	ship.velocity = Vector2(50, 0)  # Existing perpendicular drift
	ship.stats.acceleration = 100.0
	ship.stats.lateral_acceleration = 0.5
	ship.stats.inertial_dampening = 4.0

	var pilot_control = {
		"desired_heading": 0.0,
		"thrust_active": false,
		"throttle": 0.0,
		"lateral_thrust": 1  # Pilot actively strafing right
	}

	var result = MovementSystem.apply_space_physics(ship, pilot_control, 0.1)

	# Strafe pushes right (+X). Dampening would pull it back. Result should
	# be net positive change (strafe wins; no dampening applied).
	# Without dampening: x = 50 + 100 * 0.5 * 0.1 = 55
	# With dampening: would shrink toward 30
	assert_gt(result.velocity.x, 50.0, "Lateral thrust should overpower (no) dampening — strafe wins")

func test_inertial_dampening_zero_means_pure_newtonian():
	# BEHAVIOR: Setting inertial_dampening = 0 (or absent) gives pure Newtonian
	# drift — the old "boats on ice" behavior, used by capital ships.
	var ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	ship.rotation = 0.0
	ship.velocity = Vector2(100, 0)
	ship.stats.inertial_dampening = 0.0

	var pilot_control = {
		"desired_heading": 0.0,
		"thrust_active": false,
		"throttle": 0.0
	}

	var result = MovementSystem.apply_space_physics(ship, pilot_control, 0.1)

	# Velocity should be completely unchanged
	assert_almost_eq(result.velocity.x, 100.0, 0.01, "Zero dampening must preserve drift")

func test_inertial_dampening_disabled_when_braking():
	# BEHAVIOR: The brake system handles its own deceleration; dampening must
	# step aside when brake_thrust is engaged so we don't double-decelerate.
	var ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	ship.rotation = 0.0
	ship.velocity = Vector2(100, 0)  # Sideways drift
	ship.stats.inertial_dampening = 4.0

	var pilot_control = {
		"desired_heading": 0.0,
		"thrust_active": false,
		"throttle": 0.0,
		"is_braking": true
	}

	var result = MovementSystem.apply_space_physics(ship, pilot_control, 0.1)

	# Without dampening interference: x decays only via brake_thrust (which is
	# 0 here), so should be unchanged.
	assert_almost_eq(result.velocity.x, 100.0, 0.01, "Dampening should yield to the brake system")

func test_inertial_dampening_does_not_reverse_velocity():
	# BEHAVIOR: Dampening must never overshoot and reverse the perpendicular
	# component — this would feel jittery and unphysical.
	var ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	ship.rotation = 0.0
	ship.velocity = Vector2(10, 0)  # Tiny sideways drift
	ship.stats.inertial_dampening = 100.0  # Absurdly high rate

	var pilot_control = {
		"desired_heading": 0.0,
		"thrust_active": false,
		"throttle": 0.0
	}

	var result = MovementSystem.apply_space_physics(ship, pilot_control, 1.0)  # Huge delta

	# At this rate the drift would mathematically reverse — but it must clamp to 0
	assert_almost_eq(result.velocity.x, 0.0, 0.01, "Dampening should clamp to 0, never reverse")

# ============================================================================
# SPEED-DEPENDENT TURN RATE — turn radius widens with airspeed (WW2 dogfight)
# ============================================================================

func test_turn_rate_falloff_slows_rotation_at_high_speed():
	# BEHAVIOR: A fighter at top speed must turn slower than the same fighter
	# at low speed. This creates turn radius and prevents instant aim snapping.
	var fast_ship = create_fighter_ship("ship_fast", Vector2(0, 0), 0)
	fast_ship.rotation = 0.0  # facing up
	fast_ship.stats.turn_rate = 4.0
	fast_ship.stats.turn_rate_falloff = 0.75
	fast_ship.stats.max_speed = 300.0
	fast_ship.velocity = Vector2(300, 0)  # at top speed

	var slow_ship = create_fighter_ship("ship_slow", Vector2(0, 0), 0)
	slow_ship.rotation = 0.0
	slow_ship.stats.turn_rate = 4.0
	slow_ship.stats.turn_rate_falloff = 0.75
	slow_ship.stats.max_speed = 300.0
	slow_ship.velocity = Vector2(0, 0)  # stopped

	# Both want to turn 90° to the right (target heading = PI/2)
	var pilot_control = {"desired_heading": PI / 2.0, "throttle": 0.0}

	var fast_result = MovementSystem.apply_space_physics(fast_ship, pilot_control, 0.1)
	var slow_result = MovementSystem.apply_space_physics(slow_ship, pilot_control, 0.1)

	var fast_turn = abs(fast_result.rotation - 0.0)
	var slow_turn = abs(slow_result.rotation - 0.0)

	assert_lt(fast_turn, slow_turn, "Fast ship must turn less than slow ship per frame")
	# Slow at full 4.0 rad/s for 0.1s → 0.4 rad. Fast at 1.0 rad/s for 0.1s → 0.1 rad.
	assert_almost_eq(slow_turn, 0.4, 0.01, "At zero speed, full turn rate should apply")
	assert_almost_eq(fast_turn, 0.1, 0.01, "At top speed, falloff should reduce turn rate to 25%")

func test_turn_rate_falloff_zero_means_constant_turn_rate():
	# BEHAVIOR: Ships without turn_rate_falloff (capital, default) keep
	# constant turn rate at all speeds. Backward compatibility.
	var ship = create_fighter_ship("ship", Vector2(0, 0), 0)
	ship.rotation = 0.0
	ship.stats.turn_rate = 2.0
	ship.stats.max_speed = 100.0
	ship.velocity = Vector2(100, 0)  # at max speed

	var pilot_control = {"desired_heading": PI, "throttle": 0.0}
	var result = MovementSystem.apply_space_physics(ship, pilot_control, 0.1)

	# Without falloff stat, turn at full rate: 2.0 * 0.1 = 0.2 rad
	assert_almost_eq(abs(result.rotation - 0.0), 0.2, 0.01, "No falloff stat -> constant turn rate")

# ============================================================================
# PASS-BY OFFSET — fighters never fly straight into a head-on collision
# ============================================================================

func test_pass_by_offset_deflects_head_on_approach():
	# BEHAVIOR: A fighter closing fast head-on must aim slightly off-center,
	# not at the target's nose. Otherwise both AIs converge into a collision.
	var ship = create_fighter_ship("ship1", Vector2(0, 0), 0)
	ship.rotation = 0.0  # facing up (Y-)
	ship.velocity = Vector2(0, -300)  # closing fast on target above? wait, target below
	ship.stats.max_speed = 300.0

	var target = create_fighter_ship("ship2", Vector2(0, -800), 1)
	target.velocity = Vector2(0, 300)  # target rushing at us

	# Direct heading would point straight at target
	var direct_heading = MovementSystem.direction_to_heading(target.position - ship.position)
	var offset_heading = MovementSystem.apply_pass_by_offset(ship, target, direct_heading)

	assert_ne(offset_heading, direct_heading, "Head-on closing should produce a deflected heading")

func test_pass_by_offset_no_deflection_when_far_away():
	# BEHAVIOR: At long range, no deflection — ship aims for target normally.
	# Only kicks in within PASS_BY_RANGE.
	var ship = create_fighter_ship("ship1", Vector2(0, 0), 0)
	ship.velocity = Vector2(0, -300)
	ship.stats.max_speed = 300.0

	var target = create_fighter_ship("ship2", Vector2(0, -5000), 1)
	target.velocity = Vector2(0, 300)

	var direct_heading = MovementSystem.direction_to_heading(target.position - ship.position)
	var offset_heading = MovementSystem.apply_pass_by_offset(ship, target, direct_heading)

	assert_eq(offset_heading, direct_heading, "Outside pass-by range, no deflection")

func test_pass_by_offset_no_deflection_when_not_closing():
	# BEHAVIOR: If the ship isn't closing fast (e.g. orbiting at combat range),
	# don't deflect — only the high-speed merge case needs it.
	var ship = create_fighter_ship("ship1", Vector2(0, 0), 0)
	ship.velocity = Vector2(50, 0)  # moving sideways, not closing
	ship.stats.max_speed = 300.0

	var target = create_fighter_ship("ship2", Vector2(0, -800), 1)
	target.velocity = Vector2(0, 0)

	var direct_heading = MovementSystem.direction_to_heading(target.position - ship.position)
	var offset_heading = MovementSystem.apply_pass_by_offset(ship, target, direct_heading)

	assert_eq(offset_heading, direct_heading, "Not closing fast -> no deflection")

func test_pass_by_offset_pair_picks_consistent_side():
	# BEHAVIOR: Both ships in a merge must pick the SAME world-space side so
	# they pass each other instead of converging. Symmetric hash key over the
	# ship-id pair guarantees agreement.
	var ship_a = create_fighter_ship("alpha", Vector2(0, 0), 0)
	ship_a.velocity = Vector2(0, -300)
	ship_a.stats.max_speed = 300.0

	var ship_b = create_fighter_ship("beta", Vector2(0, -800), 1)
	ship_b.velocity = Vector2(0, 300)
	ship_b.stats.max_speed = 300.0

	# A's direct heading toward B
	var a_direct = MovementSystem.direction_to_heading(ship_b.position - ship_a.position)
	var a_offset = MovementSystem.apply_pass_by_offset(ship_a, ship_b, a_direct)
	var a_deflection = a_offset - a_direct  # signed angle

	# B's direct heading toward A
	var b_direct = MovementSystem.direction_to_heading(ship_a.position - ship_b.position)
	var b_offset = MovementSystem.apply_pass_by_offset(ship_b, ship_a, b_direct)
	var b_deflection = b_offset - b_direct

	# Symmetric pair-key hash means both ships compute the same `side` and
	# apply the same LOS-frame deflection. Because they face opposite
	# directions, equal LOS deflections produce opposite world-space
	# motions — the pair diverges and passes cleanly instead of colliding.
	assert_almost_eq(a_deflection, b_deflection, 0.001,
		"Both ships in a pair must pick the same LOS-frame side via symmetric hash")

# ============================================================================
# TARGET DECONFLICTION — pairs split onto distinct enemies (no swarm)
# ============================================================================

func _make_lead_crew(crew_id: String, ship_id: String, skill: float = 0.7) -> Dictionary:
	var crew = create_pilot_crew(crew_id, ship_id)
	crew.stats.skill = skill
	return crew

func _set_engaging(crew: Dictionary, target_id: String) -> Dictionary:
	crew["orders"] = {"current": {"target_id": target_id}}
	return crew

func test_count_friendlies_engaging_excludes_self():
	# BEHAVIOR: When a lead re-evaluates targets, they shouldn't count
	# themselves as a friendly engager — that would bias every score.
	var me = _make_lead_crew("me", "ship_me")
	me = _set_engaging(me, "enemy1")
	var other = _make_lead_crew("other", "ship_other")
	other = _set_engaging(other, "enemy1")

	# Without self-exclude: counts 2. With self-exclude: counts 1 (just `other`).
	var count = FighterPilotAI._count_friendlies_engaging("enemy1", [me, other], "me")
	assert_eq(count, 1, "Self-exclusion should leave only other engagers in count")

func test_target_deconfliction_splits_wings_onto_distinct_fighters():
	# BEHAVIOR: Two wing leads scoring the same set of enemies must NOT both
	# pick the same target when one is already engaged. The deconfliction
	# penalty should steer the second lead onto a different enemy.
	var enemy_a = create_fighter_ship("enemy_a", Vector2(900, 0), 1)  # closer
	var enemy_b = create_fighter_ship("enemy_b", Vector2(1100, 0), 1)  # further

	# Lead 1: already locked onto enemy_a (pretend they decided first)
	var lead1 = _make_lead_crew("lead1", "ship1", 0.7)
	lead1.assigned_to = "ship1"
	lead1 = _set_engaging(lead1, "enemy_a")

	# Lead 2: scoring NOW. Without deconfliction, distance favors enemy_a.
	var lead2 = _make_lead_crew("lead2", "ship2", 0.7)
	lead2.assigned_to = "ship2"
	var ship2 = create_fighter_ship("ship2", Vector2(0, 0), 0)

	var score_a = FighterPilotAI._calculate_target_score(lead2, enemy_a, [ship2, enemy_a, enemy_b], [lead1, lead2])
	var score_b = FighterPilotAI._calculate_target_score(lead2, enemy_b, [ship2, enemy_a, enemy_b], [lead1, lead2])

	# enemy_a is closer (would normally score higher) but enemy_a has 1 engager
	# already. Penalty (4.0) > distance advantage (200u / 500 = 0.4). Deconfliction wins.
	assert_lt(score_a, score_b, "Engaged enemy must score lower than free enemy of similar distance")

func test_concentrate_fire_still_applies_to_capital_targets():
	# BEHAVIOR: Deconfliction is only for fighter-vs-fighter. Vs. a capital
	# ship, mass attack is correct doctrine — bonus per friendly engager.
	var capital = create_capital_ship("cap1", Vector2(1000, 0), 1)
	var other_capital = create_capital_ship("cap2", Vector2(1500, 0), 1)

	# Lead with skill above the coordinate-fire threshold
	var lead1 = _make_lead_crew("lead1", "ship1", 0.7)
	lead1 = _set_engaging(lead1, "cap1")

	var lead2 = _make_lead_crew("lead2", "ship2", 0.7)
	lead2.assigned_to = "ship2"
	var ship2 = create_fighter_ship("ship2", Vector2(0, 0), 0)

	var score_cap1 = FighterPilotAI._calculate_target_score(lead2, capital, [ship2, capital, other_capital], [lead1, lead2])
	var score_cap2 = FighterPilotAI._calculate_target_score(lead2, other_capital, [ship2, capital, other_capital], [lead1, lead2])

	# Capital with friendly already engaging should score higher (concentrate fire),
	# even though it'd otherwise tie/lose on distance.
	assert_gt(score_cap1, score_cap2, "Vs capital ships, friendly engagers should INCREASE score (concentrate fire)")

func test_rookie_leads_still_fixate_no_deconfliction():
	# BEHAVIOR: Below LEAD_DECONFLICT_SKILL, leads don't think tactically —
	# they pick the closest enemy regardless of who else is on it. This
	# preserves "rookies fixate" personality.
	var enemy_a = create_fighter_ship("enemy_a", Vector2(900, 0), 1)
	var enemy_b = create_fighter_ship("enemy_b", Vector2(1100, 0), 1)

	var lead1 = _make_lead_crew("lead1", "ship1", 0.7)
	lead1 = _set_engaging(lead1, "enemy_a")

	# Rookie lead — skill below deconflict threshold
	var rookie = _make_lead_crew("rookie", "ship2", 0.2)
	rookie.assigned_to = "ship2"
	var ship2 = create_fighter_ship("ship2", Vector2(0, 0), 0)

	var score_a = FighterPilotAI._calculate_target_score(rookie, enemy_a, [ship2, enemy_a, enemy_b], [lead1, rookie])
	var score_b = FighterPilotAI._calculate_target_score(rookie, enemy_b, [ship2, enemy_a, enemy_b], [lead1, rookie])

	# Rookie ignores deconfliction — closer target wins on raw distance
	assert_gt(score_a, score_b, "Rookie should pick closer enemy regardless of friendly engagement")

# ============================================================================
# WING SIZE — wings can now hold a full squadron (1 lead + 5 wingmen)
# ============================================================================

func _make_wing_crew_with_skill(crew_id: String, ship_id: String, skill: float) -> Dictionary:
	var crew = create_pilot_crew(crew_id, ship_id)
	crew.stats.skill = skill
	crew.assigned_to = ship_id
	return crew

func test_wing_can_grow_to_six_ships():
	# BEHAVIOR: A six-pack squadron spawned together must be able to form
	# under a single lead, not get split into pair + pair + pair.
	var ships = []
	var crew = []
	for i in range(6):
		var s = create_fighter_ship("ship_%d" % i, Vector2(i * 50.0, 0), 0)
		ships.append(s)
		# Vary skill so the highest becomes lead
		crew.append(_make_wing_crew_with_skill("c_%d" % i, "ship_%d" % i, 0.9 - i * 0.1))

	var wings = WingFormationSystem.form_wings(ships, crew, [])
	assert_eq(wings.size(), 1, "Six fighters in proximity should form one wing, not multiple")
	assert_eq(wings[0].wingmen.size(), 5, "Wing should have 5 wingmen under one lead")
	assert_eq(wings[0].wing_type, "six", "Wing type should be 'six' for a 6-ship wing")

func test_wingmen_get_distinct_slot_ranks():
	# BEHAVIOR: Multiple wingmen on the same side need distinct slot_ranks
	# so calculate_wing_position fans them out instead of stacking.
	var ships = []
	var crew = []
	for i in range(6):
		ships.append(create_fighter_ship("s_%d" % i, Vector2(i * 50.0, 0), 0))
		crew.append(_make_wing_crew_with_skill("c_%d" % i, "s_%d" % i, 0.9 - i * 0.1))

	var wings = WingFormationSystem.form_wings(ships, crew, [])
	var wingmen = wings[0].wingmen
	# All slot_ranks within a side should be distinct so wingmen fan out.
	var ranks_right := {}
	var ranks_left := {}
	var right_count := 0
	var left_count := 0
	for w in wingmen:
		if w.position_side == 1:
			ranks_right[w.slot_rank] = true
			right_count += 1
		else:
			ranks_left[w.slot_rank] = true
			left_count += 1
	assert_eq(ranks_right.size(), right_count, "All right-side slot_ranks must be unique")
	assert_eq(ranks_left.size(), left_count, "All left-side slot_ranks must be unique")

# ============================================================================
# SURVIVAL OVERLAY — "stay alive" overrides everything when desperate
# ============================================================================

func _set_armor(ship: Dictionary, ratio: float) -> Dictionary:
	# Replace armor sections with a single section at the given health ratio
	ship["armor_sections"] = [{
		"section_id": "front",
		"current_armor": 100.0 * ratio,
		"max_armor": 100.0,
		"arc": {"start": -90, "end": 90}
	}]
	return ship

func _set_aggression(crew: Dictionary, value: float) -> Dictionary:
	crew.stats["skills"] = crew.stats.get("skills", {})
	crew.stats.skills["aggression"] = value
	return crew

func test_critical_hull_triggers_retreat():
	# BEHAVIOR: A heavily damaged fighter should bug out instead of engaging,
	# regardless of who else is around.
	var ship = create_fighter_ship("me", Vector2(0, 0), 0)
	ship = _set_armor(ship, 0.10)  # 10% armor — clearly critical
	var crew = create_pilot_crew("pilot_me", "me")
	crew = _set_aggression(crew, 0.3)  # cautious

	var enemy = create_fighter_ship("enemy", Vector2(800, 0), 1)

	var mode = FighterPilotAI._assess_survival_state(crew, ship, [ship, enemy])
	assert_eq(mode, "retreat", "Critically damaged fighter should retreat")

func test_aggressive_pilot_tolerates_more_damage_than_timid():
	# BEHAVIOR: Aggression dial — heroic pilots fight on through hits that
	# make a timid pilot break off.
	var ship = create_fighter_ship("me", Vector2(0, 0), 0)
	ship = _set_armor(ship, 0.20)  # mid-band: depends on aggression
	var enemy = create_fighter_ship("enemy", Vector2(800, 0), 1)

	var aggressive = create_pilot_crew("hero", "me")
	aggressive = _set_aggression(aggressive, 1.0)
	var timid = create_pilot_crew("rabbit", "me")
	timid = _set_aggression(timid, 0.0)

	var hero_mode = FighterPilotAI._assess_survival_state(aggressive, ship, [ship, enemy])
	var rabbit_mode = FighterPilotAI._assess_survival_state(timid, ship, [ship, enemy])

	assert_eq(hero_mode, "", "Aggressive pilot should still fight at 20% armor")
	assert_eq(rabbit_mode, "retreat", "Timid pilot should retreat at 20% armor")

func test_outnumbered_isolated_pilot_evades():
	# BEHAVIOR: Three enemies in range and zero friendly support → evade.
	var me = create_fighter_ship("me", Vector2(0, 0), 0)
	var crew = create_pilot_crew("p", "me")
	crew = _set_aggression(crew, 0.4)
	var enemies = [
		create_fighter_ship("e1", Vector2(800, 0), 1),
		create_fighter_ship("e2", Vector2(0, 800), 1),
		create_fighter_ship("e3", Vector2(-800, 0), 1)
	]

	var ships = [me] + enemies
	var mode = FighterPilotAI._assess_survival_state(crew, me, ships)
	assert_eq(mode, "evade", "Pilot facing 3 enemies with no support should evade")

func test_engaged_with_support_does_not_evade():
	# BEHAVIOR: 2 friends + 2 enemies in mutual range — solid odds, hold the line.
	var me = create_fighter_ship("me", Vector2(0, 0), 0)
	var crew = create_pilot_crew("p", "me")
	crew = _set_aggression(crew, 0.5)
	var ships = [
		me,
		create_fighter_ship("f1", Vector2(500, 0), 0),  # friendly
		create_fighter_ship("f2", Vector2(0, 500), 0),  # friendly
		create_fighter_ship("e1", Vector2(800, 0), 1),
		create_fighter_ship("e2", Vector2(0, 800), 1)
	]

	var mode = FighterPilotAI._assess_survival_state(crew, me, ships)
	assert_eq(mode, "", "Even odds with support — engage normally")

# ============================================================================
# DOCTRINE DIVERSITY — same skill, different aggression → different approach
# ============================================================================

func test_aggressive_lead_rushes_head_on():
	# BEHAVIOR: A skilled lead with high aggression should pick DIRECT
	# (commit head-on), even when a less aggressive same-skill lead would
	# pick a tactical curve.
	var style_aggressive = FighterPilotAI._select_approach_style(0.7, "neutral", 0.9)
	var style_balanced = FighterPilotAI._select_approach_style(0.7, "neutral", 0.5)
	assert_eq(style_aggressive, FighterPilotAI.ApproachStyle.DIRECT,
		"High aggression at high skill should commit to direct attack")
	assert_ne(style_balanced, FighterPilotAI.ApproachStyle.DIRECT,
		"Balanced aggression at the same skill should NOT pick DIRECT")

func test_cautious_lead_flanks_instead_of_charging():
	# BEHAVIOR: Low aggression at the same skill picks ANGLED — flanks
	# rather than charging head-on. This is what gives 6v6 a mix of charging
	# and flanking wings.
	var style_cautious = FighterPilotAI._select_approach_style(0.5, "neutral", 0.1)
	assert_eq(style_cautious, FighterPilotAI.ApproachStyle.ANGLED,
		"Cautious lead should approach from an angle, not directly")

# ============================================================================
# SQUADRON COMMAND BIAS — squadron leader's focus pulls wings toward it
# ============================================================================

func test_squadron_focus_target_gets_score_bonus():
	# BEHAVIOR: When my squadron's leader has a designated target, that
	# target should score higher than an equivalent alternative — but the
	# bonus should NOT override deconfliction (a target with several engagers
	# already on it still gets dropped).
	var enemy_focus = create_fighter_ship("focus", Vector2(1000, 0), 1)
	var enemy_other = create_fighter_ship("other", Vector2(1000, 100), 1)

	# Squadron leader (commander), targeting "focus"
	var commander = _make_wing_crew_with_skill("cmdr", "ship_cmdr", 0.8)
	commander["command_chain"] = {"superior": ""}  # no superior — top of chain
	commander = _set_engaging(commander, "focus")

	# A wing lead in the same squadron, scoring targets
	var wing_lead = _make_wing_crew_with_skill("wlead", "ship_wlead", 0.7)
	wing_lead["command_chain"] = {"superior": "cmdr"}

	var ship_wlead = create_fighter_ship("ship_wlead", Vector2(0, 0), 0)

	var ships = [ship_wlead, enemy_focus, enemy_other]
	var crews = [commander, wing_lead]
	var score_focus = FighterPilotAI._calculate_target_score(wing_lead, enemy_focus, ships, crews)
	var score_other = FighterPilotAI._calculate_target_score(wing_lead, enemy_other, ships, crews)

	# Without command bias, the two enemies are basically tied (same distance).
	# WITH command bias, focus should win (commander has tagged it).
	# But commander is also engaging focus so deconfliction subtracts; the
	# squadron bonus must be larger than that single-engager penalty so the
	# overall effect is "follow the commander's call."
	assert_gt(score_focus, score_other, "Squadron commander's target should win on equal alternatives")

# ============================================================================
# AREA LEASH — ships rotate back toward their assigned operating area
# ============================================================================

func _ship_with_area(id: String, pos: Vector2, area_center: Vector2, radius: float) -> Dictionary:
	var ship = create_fighter_ship(id, pos, 0)
	ship["assigned_area"] = {"center": area_center, "radius": radius}
	# Sit at low speed so turn rate is sharp and the leash effect is visible per-frame
	ship.velocity = Vector2.ZERO
	return ship

func test_inside_zone_leash_does_not_modify_heading():
	# BEHAVIOR: A ship comfortably inside its zone is unaffected — pilot's
	# desired heading is preserved exactly.
	var ship = _ship_with_area("me", Vector2(0, 0), Vector2(0, 0), 500.0)
	var east_heading: float = MovementSystem.direction_to_heading(Vector2(1, 0))
	var leashed = MovementSystem.apply_area_leash(ship, east_heading)
	assert_eq(leashed, east_heading, "Inside the zone, no leash bias should be applied")

func test_outside_zone_at_full_pull_overrides_heading_to_home():
	# BEHAVIOR: At 2x leash radius, pull = 1.0 — heading is fully replaced
	# by the direction back to home, ignoring whatever the pilot wanted.
	var ship = _ship_with_area("me", Vector2(2000, 0), Vector2(0, 0), 500.0)
	var east_heading: float = MovementSystem.direction_to_heading(Vector2(1, 0))
	var leashed = MovementSystem.apply_area_leash(ship, east_heading)
	var west_heading: float = MovementSystem.direction_to_heading(Vector2(-1, 0))
	# Compare angles modulo 2π via angle_difference (lerp_angle may return ± equivalent)
	var diff_to_west = abs(MovementSystem.angle_difference(leashed, west_heading))
	assert_lt(diff_to_west, 0.001,
		"At full pull (>=2x radius outside), heading must point toward area center")

func test_no_assigned_area_means_no_leash():
	# BEHAVIOR: Ships without an assigned area behave exactly as before
	# (backwards compatibility for anything not yet assigned).
	var ship = create_fighter_ship("me", Vector2(2000, 0), 0)
	var east_heading: float = MovementSystem.direction_to_heading(Vector2(1, 0))
	var leashed = MovementSystem.apply_area_leash(ship, east_heading)
	assert_eq(leashed, east_heading, "With no assigned_area, leash must have no effect")

func test_far_outside_area_triggers_hard_return_override():
	# BEHAVIOR: At >1.5x leash radius, the AI override fires — pilot drops
	# the current target and chooses fight_return_to_area instead.
	var center = Vector2(960, 540)
	var ship = create_fighter_ship("me", Vector2(960 + 600, 540), 0)  # 600u east of center
	ship["assigned_area"] = {"center": center, "radius": 335.0}  # threshold ≈ 502u
	assert_true(FighterPilotAI._is_far_outside_area(ship),
		"600u from center > 1.5*335 = 502u; should trigger return")

func test_inside_area_does_not_trigger_hard_return():
	var center = Vector2(960, 540)
	var ship = create_fighter_ship("me", Vector2(960 + 200, 540), 0)
	ship["assigned_area"] = {"center": center, "radius": 335.0}
	assert_false(FighterPilotAI._is_far_outside_area(ship),
		"200u from center is well inside the leash; no override")

func test_no_assigned_area_never_triggers_return():
	var ship = create_fighter_ship("me", Vector2(99999, 99999), 0)
	# No assigned_area set
	assert_false(FighterPilotAI._is_far_outside_area(ship),
		"With no assigned area there is no leash to violate")

func test_return_to_area_aims_inside_zone_not_at_center():
	# BEHAVIOR: A ship returning to its zone should aim for a point INSIDE
	# the zone, not the dead center. Otherwise N ships all converge on the
	# same point and pile up there.
	var ship = create_fighter_ship("me", Vector2(2000, 0), 0)
	ship["assigned_area"] = {"center": Vector2(0, 0), "radius": 500.0}
	var control = MovementSystem.calculate_return_to_area(ship)
	# desired_heading should point toward a target between origin and ship,
	# not the dead origin. Angle from ship (2000, 0) to origin is "west",
	# heading = direction_to_heading((-1, 0)) = PI. Target inside zone at
	# (~300, 0) gives heading also approximately PI but toward (300-2000, 0)
	# which is also "west". The KEY check: distance returned should be the
	# distance to the entry point, NOT to the center.
	assert_lt(control.current_distance, 2000.0,
		"Return distance should be to the entry point, not all the way to center")

func test_return_to_area_spreads_ships_to_distinct_entry_points():
	# BEHAVIOR: Two ships at the same external position with different
	# ship_ids should pick different entry points (per-ship tangential
	# spread). Without this, N ships pile up on one entry point.
	var area = {"center": Vector2(0, 0), "radius": 500.0}
	var ship_a = create_fighter_ship("alpha_lots_of_text_to_change_hash", Vector2(1500, 0), 0)
	ship_a["assigned_area"] = area
	var ship_b = create_fighter_ship("beta", Vector2(1500, 0), 0)
	ship_b["assigned_area"] = area

	var ctrl_a = MovementSystem.calculate_return_to_area(ship_a)
	var ctrl_b = MovementSystem.calculate_return_to_area(ship_b)

	# At the very least, their headings should differ (we add per-ship tangent)
	assert_ne(ctrl_a.desired_heading, ctrl_b.desired_heading,
		"Two ships with different ids returning from the same point should pick different entry headings")

func test_leash_pull_ramps_with_distance():
	# BEHAVIOR: Pull is 0 at the edge of the leash and 1 at 2x radius. A
	# ship further out should have its heading pulled more strongly home.
	var center = Vector2(0, 0)
	var radius = 500.0
	var east_heading: float = MovementSystem.direction_to_heading(Vector2(1, 0))
	var west_heading: float = MovementSystem.direction_to_heading(Vector2(-1, 0))

	var ship_near = _ship_with_area("a", Vector2(750, 0), center, radius)   # 1.5x → pull 0.5
	var ship_far = _ship_with_area("b", Vector2(950, 0), center, radius)    # 1.9x → pull 0.9

	var heading_near = MovementSystem.apply_area_leash(ship_near, east_heading)
	var heading_far = MovementSystem.apply_area_leash(ship_far, east_heading)

	# Distance-from-east measures how much the heading has been pulled toward west
	var pull_near = abs(MovementSystem.angle_difference(heading_near, east_heading))
	var pull_far = abs(MovementSystem.angle_difference(heading_far, east_heading))
	assert_gt(pull_far, pull_near,
		"Ship further outside the zone should be pulled more strongly back home")
