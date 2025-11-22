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
	return ship

func create_capital_ship(id: String, position: Vector2, team: int = 0) -> Dictionary:
	var ship = create_fighter_ship(id, position, team)
	ship.type = "capital"
	ship.stats.max_speed = 100.0
	ship.stats.size = 60.0
	return ship

func create_pilot_crew(id: String, ship_id: String) -> Dictionary:
	return {
		"crew_id": id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"assigned_ship_id": ship_id,
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
	# BEHAVIOR: When target is far away, fighter pursues at full speed
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var target = create_fighter_ship("enemy1", Vector2(1000, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, target], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	assert_string_contains(decision.subtype, "pursue", "Should pursue when far away")

func test_slows_approach_at_mid_range():
	# BEHAVIOR: When target is NOT directly behind us and reasonably far away, use approach maneuvers
	# (not close-range combat maneuvers like tight_pursuit or dogfight)
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var target = create_fighter_ship("enemy1", Vector2(3000, 0), 1)  # Far enough to be outside close range
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, target], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	# When target is far and not behind us, should use pursuit-type maneuvers, not close-range ones
	var is_not_close_combat = decision.subtype not in ["tight_pursuit", "dogfight_maneuver"]
	assert_true(is_not_close_combat, "Should use approach maneuvers when target is far")

func test_tight_maneuvering_at_close_range():
	# BEHAVIOR: At close range, fighter uses tight maneuvers
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var target = create_fighter_ship("enemy1", Vector2(100, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["enemy1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, target], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	var is_close_combat = decision.subtype in ["tight_pursuit", "dogfight_maneuver", "flank_behind"]
	assert_true(is_close_combat, "Should use tight maneuvering at close range")

# ============================================================================
# BEHAVIOR TESTS - Fighter vs Fighter combat
# ============================================================================

func test_tries_to_get_behind_enemy_fighter():
	# BEHAVIOR: When fighting fighters, try to get behind enemy
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var enemy = create_fighter_ship("enemy1", Vector2(200, 0), 1)
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
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var wingmate = create_fighter_ship("fighter2", Vector2(50, 50), 0)  # Nearby friendly
	var enemy = create_fighter_ship("enemy1", Vector2(500, 0), 1)
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
	# BEHAVIOR: When fighting capitals/corvettes, stay at distance
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var capital = create_capital_ship("capital1", Vector2(300, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["capital1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, capital], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	var is_defensive = decision.subtype in ["dodge_and_weave", "cautious_approach", "evasive_retreat"]
	assert_true(is_defensive, "Should use defensive maneuvers vs capital ships")

func test_dodge_and_weave_vs_corvettes():
	# BEHAVIOR: When fighting corvettes solo, dodge and weave
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var corvette = create_corvette_ship("corvette1", Vector2(400, 0), 1)
	var crew = create_pilot_crew("pilot1", "fighter1")
	crew.awareness.threats = ["corvette1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, [my_ship, corvette], [crew], game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	# Should use evasive tactics when solo vs larger ship
	assert_ne(decision.subtype, "pursue_full_speed", "Should not charge capital ships alone")

func test_group_runs_with_multiple_fighters():
	# BEHAVIOR: With many fighters, coordinate group runs vs capitals
	var my_ship = create_fighter_ship("fighter1", Vector2(0, 0), 0)
	var fighters = [my_ship]
	var crew_list = [create_pilot_crew("pilot1", "fighter1")]

	# Add 4 more friendly fighters nearby
	for i in range(2, 6):
		var fighter = create_fighter_ship("fighter" + str(i), Vector2(i * 50, 0), 0)
		fighters.append(fighter)
		crew_list.append(create_pilot_crew("pilot" + str(i), "fighter" + str(i)))

	var capital = create_capital_ship("capital1", Vector2(800, 0), 1)
	fighters.append(capital)
	var crew = crew_list[0]
	crew.awareness.threats = ["capital1"]

	var decision = FighterPilotAI.make_decision(crew, my_ship, fighters, crew_list, game_time)

	assert_eq(decision.type, "maneuver", "Should make maneuver decision")
	# With 5 fighters, should coordinate group runs
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
	var subtypes = ["pursue_full_speed", "dogfight_maneuver", "dodge_and_weave", "group_run_attack"]

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
	var fighters = []
	var crew_list = []

	# Create 5 fighters
	for i in range(5):
		var fighter = create_fighter_ship("fighter" + str(i), Vector2(i * 100, 0), 0)
		fighters.append(fighter)
		var crew = create_pilot_crew("pilot" + str(i), "fighter" + str(i))
		crew.awareness.threats = ["capital1"]
		crew_list.append(crew)

	var capital = create_capital_ship("capital1", Vector2(1000, 0), 1)
	fighters.append(capital)

	# All fighters make decisions
	var decisions = []
	for i in range(5):
		var decision = FighterPilotAI.make_decision(crew_list[i], fighters[i], fighters, crew_list, game_time)
		decisions.append(decision)

	# Verify group coordination
	var group_run_count = 0
	for decision in decisions:
		if "group_run" in decision.subtype:
			group_run_count += 1

	assert_gt(group_run_count, 0, "At least some fighters should coordinate group runs")
