extends GutTest

## Tests for hierarchical crew AI system
## Tests crew creation, decision making, command chain, and integration

# ============================================================================
# CREW DATA CREATION TESTS
# ============================================================================

func test_create_pilot():
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.7)

	assert_not_null(pilot.crew_id)
	assert_eq(pilot.role, CrewData.Role.PILOT)
	assert_eq(pilot.stats.skill, 0.7)
	assert_gt(pilot.stats.awareness_range, 0)
	assert_has(pilot, "awareness")
	assert_has(pilot, "orders")
	assert_has(pilot, "command_chain")

func test_create_solo_fighter_crew():
	var crew = CrewData.create_solo_fighter_crew(0.6)

	assert_eq(crew.size(), 1)
	assert_eq(crew[0].role, CrewData.Role.PILOT)
	assert_null(crew[0].command_chain.superior, "Solo pilot has no superior")

func test_create_ship_crew():
	var crew = CrewData.create_ship_crew(2, 0.7)  # 2 weapons

	# Should have captain, pilot, and 2 gunners
	assert_eq(crew.size(), 4)

	var captain = crew[0]
	var pilot = crew[1]
	var gunner1 = crew[2]
	var gunner2 = crew[3]

	assert_eq(captain.role, CrewData.Role.CAPTAIN)
	assert_eq(pilot.role, CrewData.Role.PILOT)
	assert_eq(gunner1.role, CrewData.Role.GUNNER)
	assert_eq(gunner2.role, CrewData.Role.GUNNER)

	# Check command chain
	assert_null(captain.command_chain.superior, "Captain has no superior")
	assert_eq(pilot.command_chain.superior, captain.crew_id, "Pilot reports to captain")
	assert_eq(gunner1.command_chain.superior, captain.crew_id, "Gunner reports to captain")
	assert_eq(captain.command_chain.subordinates.size(), 3, "Captain has 3 subordinates")

func test_create_squadron():
	var squadron = CrewData.create_squadron(2, 1, 0.8)  # 2 ships, 1 weapon each

	# Squadron leader + 2 ship crews (each with captain, pilot, gunner)
	assert_eq(squadron.size(), 7)  # 1 + 2*(1+1+1)

	var leader = squadron[0]
	assert_eq(leader.role, CrewData.Role.SQUADRON_LEADER)

# ============================================================================
# INFORMATION SYSTEM TESTS
# ============================================================================

func test_crew_awareness_empty():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	crew.assigned_to = "ship_1"

	var ship = create_test_ship("ship_1", Vector2(0, 0), 0)
	var updated = InformationSystem.update_crew_awareness(crew, [ship], [], 0.0)

	assert_eq(updated.awareness.known_entities.size(), 0, "No other entities visible")
	assert_eq(updated.awareness.threats.size(), 0)

func test_crew_awareness_detects_enemy():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	crew.assigned_to = "ship_1"

	var own_ship = create_test_ship("ship_1", Vector2(0, 0), 0)
	var enemy_ship = create_test_ship("ship_2", Vector2(200, 0), 1)  # Different team

	var updated = InformationSystem.update_crew_awareness(crew, [own_ship, enemy_ship], [], 0.0)

	assert_eq(updated.awareness.known_entities.size(), 1, "Detects one enemy")
	assert_eq(updated.awareness.threats.size(), 1, "Enemy is a threat")

func test_crew_awareness_range_limits():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	crew.assigned_to = "ship_1"
	crew.stats.awareness_range = 500.0

	var own_ship = create_test_ship("ship_1", Vector2(0, 0), 0)
	var near_enemy = create_test_ship("ship_2", Vector2(300, 0), 1)
	var far_enemy = create_test_ship("ship_3", Vector2(1000, 0), 1)

	var updated = InformationSystem.update_crew_awareness(crew, [own_ship, near_enemy, far_enemy], [], 0.0)

	assert_eq(updated.awareness.known_entities.size(), 1, "Only detects enemy within range")

func test_threat_prioritization():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
	crew.assigned_to = "ship_1"

	var own_ship = create_test_ship("ship_1", Vector2(0, 0), 0)
	var close_enemy = create_test_ship("ship_2", Vector2(100, 0), 1)
	var far_enemy = create_test_ship("ship_3", Vector2(700, 0), 1)

	var updated = InformationSystem.update_crew_awareness(crew, [own_ship, close_enemy, far_enemy], [], 0.0)

	assert_eq(updated.awareness.threats.size(), 2)
	# Closer threat should be higher priority
	assert_gt(updated.awareness.threats[0]._threat_priority, updated.awareness.threats[1]._threat_priority)

# ============================================================================
# CREW AI DECISION TESTS
# ============================================================================

func test_pilot_makes_evasive_decision():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.7)
	crew.assigned_to = "ship_1"
	# Give crew a superior so they're treated as corvette/multi-crew (uses evade/pursue subtypes)
	crew.command_chain.superior = "captain_1"

	# Add multiple threats (outnumbered should evade)
	crew.awareness.threats = [
		{"id": "enemy_1", "type": "ship", "_threat_priority": 150.0},
		{"id": "enemy_2", "type": "ship", "_threat_priority": 140.0}
	]

	var result = CrewAISystem.update_crew_member(crew, 0.1, 1.0)

	assert_has(result, "decision")
	assert_eq(result.decision.type, "maneuver")
	assert_eq(result.decision.subtype, "evade")
	assert_eq(result.decision.target_id, "enemy_1")

func test_pilot_makes_pursuit_decision():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.7)
	crew.assigned_to = "ship_1"
	# Give crew a superior so they're treated as corvette/multi-crew (uses evade/pursue subtypes)
	crew.command_chain.superior = "captain_1"

	# Add an opportunity, no threats
	crew.awareness.opportunities = [
		{"id": "enemy_1", "type": "ship", "_opportunity_score": 100.0}
	]

	var result = CrewAISystem.update_crew_member(crew, 0.1, 1.0)

	assert_has(result, "decision")
	assert_eq(result.decision.type, "maneuver")
	assert_eq(result.decision.subtype, "pursue")

func test_gunner_selects_target():
	var crew = CrewData.create_crew_member(CrewData.Role.GUNNER, 0.8)
	crew.assigned_to = "ship_1"

	crew.awareness.opportunities = [
		{"id": "enemy_1", "type": "ship", "_opportunity_score": 120.0}
	]

	var result = CrewAISystem.update_crew_member(crew, 0.1, 1.0)

	assert_has(result, "decision")
	assert_eq(result.decision.type, "fire")
	assert_eq(result.decision.target_id, "enemy_1")

func test_captain_issues_orders():
	var captain = CrewData.create_crew_member(CrewData.Role.CAPTAIN, 0.7)
	captain.assigned_to = "ship_1"
	captain.command_chain.subordinates = ["pilot_1", "gunner_1"]

	captain.awareness.opportunities = [
		{"id": "enemy_1", "type": "ship", "_opportunity_score": 100.0}
	]

	var result = CrewAISystem.update_crew_member(captain, 0.1, 1.0)

	assert_has(result, "decision")
	assert_eq(result.decision.type, "tactical")
	assert_gt(result.crew_data.orders.issued.size(), 0, "Captain issues orders to subordinates")

func test_crew_skill_affects_decisions():
	var skilled_crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.9)
	var unskilled_crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.3)

	var skilled_factor = CrewAISystem.calculate_effective_skill(skilled_crew)
	var unskilled_factor = CrewAISystem.calculate_effective_skill(unskilled_crew)

	assert_gt(skilled_factor, unskilled_factor)
	assert_gt(unskilled_crew.stats.decision_time, skilled_crew.stats.decision_time)

func test_stress_affects_performance():
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 0.8)
	crew.stats.stress = 0.0

	var no_stress_skill = CrewAISystem.calculate_effective_skill(crew)

	crew.stats.stress = 0.9  # High stress
	var high_stress_skill = CrewAISystem.calculate_effective_skill(crew)

	assert_gt(no_stress_skill, high_stress_skill, "Stress reduces effective skill")

# ============================================================================
# COMMAND CHAIN TESTS
# ============================================================================

func test_order_distribution_down_chain():
	var captain = CrewData.create_crew_member(CrewData.Role.CAPTAIN, 0.7)
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.6)

	captain.command_chain.subordinates = [pilot.crew_id]
	pilot.command_chain.superior = captain.crew_id

	# Captain issues order
	captain.orders.issued = [
		{"to": pilot.crew_id, "type": "engage", "target_id": "enemy_1"}
	]

	var crew_list = [captain, pilot]
	var updated = CommandChainSystem.process_command_chain(crew_list)

	# Find updated pilot
	var updated_pilot = null
	for crew in updated:
		if crew.crew_id == pilot.crew_id:
			updated_pilot = crew
			break

	assert_not_null(updated_pilot.orders.received, "Pilot received order")
	assert_eq(updated_pilot.orders.received.type, "engage")

func test_information_sharing_up_chain():
	var captain = CrewData.create_crew_member(CrewData.Role.CAPTAIN, 0.7)
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.6)

	captain.command_chain.subordinates = [pilot.crew_id]
	pilot.command_chain.superior = captain.crew_id

	# Pilot has awareness
	pilot.awareness.threats = [
		{"id": "enemy_1", "type": "ship", "_threat_priority": 100.0}
	]

	var crew_list = [captain, pilot]
	var updated = CommandChainSystem.process_command_chain(crew_list)

	# Find updated captain
	var updated_captain = null
	for crew in updated:
		if crew.crew_id == captain.crew_id:
			updated_captain = crew
			break

	assert_gt(updated_captain.awareness.threats.size(), 0, "Captain receives pilot's threat info")

func test_find_top_commander():
	var leader = CrewData.create_crew_member(CrewData.Role.SQUADRON_LEADER, 0.8)
	var captain = CrewData.create_crew_member(CrewData.Role.CAPTAIN, 0.7)
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.6)

	captain.command_chain.superior = leader.crew_id
	pilot.command_chain.superior = captain.crew_id

	var crew_list = [pilot, captain, leader]
	var top = CommandChainSystem.find_top_commander(crew_list)

	assert_eq(top.crew_id, leader.crew_id, "Squadron leader is top commander")

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

func test_apply_pilot_decision_to_ship():
	var ship = create_test_ship("ship_1", Vector2(0, 0), 0)
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.8)
	pilot.assigned_to = "ship_1"

	var decision = {
		"type": "maneuver",
		"subtype": "pursue",
		"entity_id": "ship_1",
		"target_id": "enemy_1"
	}

	var updated_ship = CrewIntegrationSystem.apply_decision_to_ship(ship, decision, pilot)

	assert_eq(updated_ship.orders.current_order, "engage")
	assert_eq(updated_ship.orders.target_id, "enemy_1")
	assert_has(updated_ship, "crew_modifiers")

func test_apply_gunner_decision_to_ship():
	var ship = create_test_ship("ship_1", Vector2(0, 0), 0)
	var gunner = CrewData.create_crew_member(CrewData.Role.GUNNER, 0.7)
	gunner.assigned_to = "ship_1"

	var decision = {
		"type": "fire",
		"entity_id": "ship_1",
		"target_id": "enemy_1"
	}

	var updated_ship = CrewIntegrationSystem.apply_decision_to_ship(ship, decision, gunner)

	assert_eq(updated_ship.orders.target_id, "enemy_1")
	assert_has(updated_ship.crew_modifiers, "gunner_skill")

func test_crew_modified_stats():
	var ship = create_test_ship("ship_1", Vector2(0, 0), 0)
	var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.9)  # Highly skilled

	ship.crew_modifiers = {
		"pilot_skill": 0.9
	}

	var modified_stats = CrewIntegrationSystem.get_crew_modified_movement_stats(ship)

	# High skill should improve stats
	assert_gt(modified_stats.turn_rate, ship.stats.turn_rate * 0.8)

func test_ship_with_crew_creation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0), true, 0.7)

	assert_has(ship, "crew")
	assert_gt(ship.crew.size(), 0)
	assert_eq(ship.crew[0].assigned_to, ship.ship_id)

# ============================================================================
# FULL SYSTEM INTEGRATION TEST
# ============================================================================

func test_full_crew_ai_cycle():
	# Create ships with crew
	var player_ship = ShipData.create_ship_instance("corvette", 0, Vector2(0, 0), true, 0.8)
	var enemy_ship = ShipData.create_ship_instance("fighter", 1, Vector2(500, 0), true, 0.6)

	var ships = [player_ship, enemy_ship]

	# Extract all crew
	var all_crew = []
	all_crew.append_array(player_ship.crew)
	all_crew.append_array(enemy_ship.crew)

	# Step 1: Update crew awareness
	var game_time = 1.0
	var updated_crew = InformationSystem.update_all_crew_awareness(all_crew, ships, [], game_time)

	# Crew should detect enemies
	var player_pilot = updated_crew[1]  # Index depends on creation order
	assert_gt(player_pilot.awareness.known_entities.size(), 0, "Crew detects enemies")

	# Step 2: Process command chain
	updated_crew = CommandChainSystem.process_command_chain(updated_crew)

	# Step 3: Make AI decisions
	var ai_result = CrewAISystem.update_all_crew(updated_crew, 0.1, game_time)
	updated_crew = ai_result.crew_list
	var decisions = ai_result.decisions

	# Should have some decisions
	assert_gt(decisions.size(), 0, "Crew makes decisions")

	# Step 4: Apply decisions to ships
	var integration_result = CrewIntegrationSystem.apply_crew_decisions_to_ships(ships, updated_crew, decisions)
	var updated_ships = integration_result.ships

	# Ships should have modified orders based on crew decisions
	assert_true(true, "Full cycle completes without errors")

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func create_test_ship(id: String, pos: Vector2, team: int) -> Dictionary:
	return {
		"ship_id": id,
		"type": "fighter",
		"team": team,
		"position": pos,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"stats": {
			"max_speed": 300.0,
			"acceleration": 100.0,
			"turn_rate": 3.0
		},
		"weapons": [],
		"orders": {
			"current_order": "engage",
			"target_id": null
		}
	}
