extends GutTest

## Test Large Ship AI behavior
## Verifies that corvettes and capitals make proper movement decisions

var game_time := 1.0

# ============================================================================
# TEST DATA HELPERS
# ============================================================================

func create_corvette_ship(id: String, position: Vector2, team: int = 0) -> Dictionary:
	return {
		"ship_id": id,
		"type": "corvette",
		"team": team,
		"position": position,
		"rotation": 0.0,
		"velocity": Vector2.ZERO,
		"status": "operational",
		"stats": {
			"max_speed": 200.0,
			"size": 30.0,
			"turn_rate": 1.5,
			"acceleration": 100.0
		},
		"orders": {
			"current_order": "",
			"target_id": "",
			"maneuver_subtype": ""
		}
	}

func create_capital_ship(id: String, position: Vector2, team: int = 0) -> Dictionary:
	var ship = create_corvette_ship(id, position, team)
	ship.type = "capital"
	ship.stats.max_speed = 100.0
	ship.stats.size = 60.0
	return ship

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
			"max_speed": 400.0,
			"size": 10.0,
			"turn_rate": 3.0,
			"acceleration": 200.0
		},
		"orders": {}
	}

func create_corvette_pilot(id: String, ship_id: String, has_captain: bool = true) -> Dictionary:
	var pilot = {
		"crew_id": id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"stats": {
			"skill": 0.7,
			"reaction_time": 0.1,
			"stress": 0.0,
			"fatigue": 0.0,
			"decision_time": 0.3
		},
		"awareness": {
			"threats": [],
			"opportunities": [],
			"known_entities": []
		},
		"orders": {
			"received": null,
			"current": null
		},
		"command_chain": {
			"superior": "captain1" if has_captain else null,
			"subordinates": []
		},
		"current_action": "idle",
		"next_decision_time": 0.0
	}
	return pilot

# ============================================================================
# LARGE SHIP PILOT AI TESTS
# ============================================================================

func test_large_ship_finds_enemy_target():
	# BEHAVIOR: LargeShipPilotAI should find enemy ships to target
	var my_corvette = create_corvette_ship("corvette1", Vector2(0, 0), 0)
	var enemy_fighter = create_fighter_ship("enemy1", Vector2(1000, 0), 1)
	var crew = create_corvette_pilot("pilot1", "corvette1")

	var all_ships = [my_corvette, enemy_fighter]

	var result = LargeShipPilotAI.make_decision(crew, my_corvette, all_ships, game_time)

	# Should have a decision (not just crew_data update)
	assert_true(result.has("decision"), "Should make a decision when enemy present")
	if result.has("decision"):
		assert_eq(result.decision.type, "maneuver", "Should be a maneuver decision")
		assert_eq(result.decision.target_id, "enemy1", "Should target the enemy")
		assert_true(result.decision.subtype.begins_with("large_ship_"),
			"Maneuver should be a large ship maneuver: " + result.decision.get("subtype", ""))

func test_large_ship_approaches_at_far_range():
	# BEHAVIOR: When enemy is far away, corvette should approach
	var my_corvette = create_corvette_ship("corvette1", Vector2(0, 0), 0)
	var enemy = create_fighter_ship("enemy1", Vector2(5000, 0), 1)  # Far away
	var crew = create_corvette_pilot("pilot1", "corvette1")

	var result = LargeShipPilotAI.make_decision(crew, my_corvette, [my_corvette, enemy], game_time)

	assert_true(result.has("decision"), "Should make a decision")
	if result.has("decision"):
		assert_eq(result.decision.subtype, "large_ship_approach",
			"Should approach when far: " + result.decision.get("subtype", ""))

func test_large_ship_broadside_at_mid_range():
	# BEHAVIOR: At mid-range, corvette should present broadside
	var my_corvette = create_corvette_ship("corvette1", Vector2(0, 0), 0)
	var enemy = create_corvette_ship("enemy1", Vector2(2500, 0), 1)  # Mid range
	var crew = create_corvette_pilot("pilot1", "corvette1")

	var result = LargeShipPilotAI.make_decision(crew, my_corvette, [my_corvette, enemy], game_time)

	assert_true(result.has("decision"), "Should make a decision")
	if result.has("decision"):
		assert_eq(result.decision.subtype, "large_ship_broadside",
			"Should broadside at mid range: " + result.decision.get("subtype", ""))

func test_large_ship_kites_close_fighters():
	# BEHAVIOR: When fighters are too close, corvette should kite (back away)
	var my_corvette = create_corvette_ship("corvette1", Vector2(0, 0), 0)
	var enemy_fighter = create_fighter_ship("enemy1", Vector2(1000, 0), 1)  # Close
	var crew = create_corvette_pilot("pilot1", "corvette1")

	var result = LargeShipPilotAI.make_decision(crew, my_corvette, [my_corvette, enemy_fighter], game_time)

	assert_true(result.has("decision"), "Should make a decision")
	if result.has("decision"):
		assert_eq(result.decision.subtype, "large_ship_kite",
			"Should kite when fighters are close: " + result.decision.get("subtype", ""))

func test_no_decision_without_enemies():
	# BEHAVIOR: No enemies means idle
	var my_corvette = create_corvette_ship("corvette1", Vector2(0, 0), 0)
	var friendly = create_corvette_ship("friendly1", Vector2(500, 0), 0)  # Same team
	var crew = create_corvette_pilot("pilot1", "corvette1")

	var result = LargeShipPilotAI.make_decision(crew, my_corvette, [my_corvette, friendly], game_time)

	# Should NOT have a decision key when no targets
	assert_false(result.has("decision"), "Should not have decision without enemies")

# ============================================================================
# CREW AI SYSTEM ROUTING TESTS
# ============================================================================

func test_infer_ship_type_returns_corvette_for_multi_crew():
	# BEHAVIOR: Pilots with a captain superior should be identified as corvette pilots
	var crew = create_corvette_pilot("pilot1", "corvette1", true)  # has captain

	var ship_type = CrewAISystem.infer_ship_type(crew)

	assert_eq(ship_type, "corvette", "Pilot with captain should be corvette type")

func test_infer_ship_type_returns_fighter_for_solo():
	# BEHAVIOR: Solo pilots (no superior) should be identified as fighters
	var crew = create_corvette_pilot("pilot1", "fighter1", false)  # no captain

	var ship_type = CrewAISystem.infer_ship_type(crew)

	assert_eq(ship_type, "fighter", "Pilot without captain should be fighter type")

func test_corvette_pilot_decision_routes_to_large_ship_ai():
	# BEHAVIOR: make_corvette_pilot_decision should use LargeShipPilotAI
	var my_corvette = create_corvette_ship("corvette1", Vector2(0, 0), 0)
	var enemy = create_fighter_ship("enemy1", Vector2(1000, 0), 1)
	var crew = create_corvette_pilot("pilot1", "corvette1")

	var context = {
		"ship_data": my_corvette,
		"all_ships": [my_corvette, enemy],
		"is_outnumbered": false
	}

	var result = CrewAISystem.make_corvette_pilot_decision(crew, context, game_time)

	assert_true(result.has("decision"), "Should return a decision")
	if result.has("decision"):
		assert_true(result.decision.subtype.begins_with("large_ship_"),
			"Decision should be a large ship maneuver: " + result.decision.get("subtype", ""))

# ============================================================================
# INTEGRATION TESTS - Full decision-to-movement flow
# ============================================================================

func test_decision_applies_to_ship_orders():
	# BEHAVIOR: A large ship decision should set ship orders correctly
	var my_corvette = create_corvette_ship("corvette1", Vector2(0, 0), 0)
	var enemy = create_fighter_ship("enemy1", Vector2(1000, 0), 1)
	var crew = create_corvette_pilot("pilot1", "corvette1")

	var result = LargeShipPilotAI.make_decision(crew, my_corvette, [my_corvette, enemy], game_time)

	assert_true(result.has("decision"), "Should have decision")

	# Apply decision via CrewIntegrationSystem
	var applied = CrewIntegrationSystem.apply_decision_to_ship(my_corvette, result.decision, crew)

	# Verify orders are set
	assert_eq(applied.orders.current_order, "large_ship_engage",
		"Current order should be large_ship_engage: " + applied.orders.get("current_order", "EMPTY"))
	assert_eq(applied.orders.target_id, "enemy1", "Target should be set")
	assert_true(applied.orders.maneuver_subtype.begins_with("large_ship_"),
		"Maneuver subtype should be set: " + applied.orders.get("maneuver_subtype", "EMPTY"))

func test_movement_system_executes_large_ship_maneuver():
	# BEHAVIOR: MovementSystem should execute large_ship_engage orders and actually move the ship
	var my_corvette = create_corvette_ship("corvette1", Vector2(0, 0), 0)
	my_corvette.orders.current_order = "large_ship_engage"
	my_corvette.orders.target_id = "enemy1"
	my_corvette.orders.maneuver_subtype = "large_ship_approach"

	var enemy = create_fighter_ship("enemy1", Vector2(2000, 0), 1)
	var all_ships = [my_corvette, enemy]

	# Run multiple movement updates to give ship time to turn and accelerate
	var updated = my_corvette
	for i in range(10):
		updated = MovementSystem.update_ship_movement(updated, all_ships, 0.1, [])

	# Ship should have started moving toward enemy
	# After approach maneuver, velocity should have positive x component (toward enemy)
	assert_gt(updated.velocity.length(), 0.1, "Ship should be moving: velocity=" + str(updated.velocity))

	# Ship should be turning toward target (enemy is at x=2000, so positive x direction)
	# Visual heading uses a different convention, but velocity should be toward enemy
	assert_gt(updated.velocity.x, 0.0, "Ship should be moving toward enemy (positive x direction)")
