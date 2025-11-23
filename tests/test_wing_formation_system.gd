extends GutTest

## Tests for WingFormationSystem - Dynamic wing formation for fighters


# =============================================================================
# TEST HELPERS
# =============================================================================

func create_test_fighter(ship_id: String, team: int, position: Vector2) -> Dictionary:
	return {
		"ship_id": ship_id,
		"type": "fighter",
		"team": team,
		"status": "operational",
		"position": position,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"stats": {"max_speed": 300.0, "acceleration": 150.0}
	}

func create_test_crew(crew_id: String, ship_id: String, skill: float = 0.5) -> Dictionary:
	return {
		"crew_id": crew_id,
		"assigned_ship_id": ship_id,
		"role": CrewData.Role.PILOT,
		"stats": {
			"skill": skill,
			"skills": {
				"situational_awareness": skill,
				"aggression": skill,
				"composure": skill,
				"anticipation": skill,
				"marksmanship": skill
			}
		},
		"orders": {"current": {}},
		"awareness": {"threats": [], "opportunities": []}
	}


# =============================================================================
# WING FORMATION TESTS
# =============================================================================

func test_form_wings_creates_pair_from_two_nearby_fighters():
	# Two nearby fighters on same team should form a wing pair
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0))  # Within 500 units
	]
	var crew = [
		create_test_crew("crew_1", "ship_1", 0.7),  # Higher skill = lead
		create_test_crew("crew_2", "ship_2", 0.5)   # Lower skill = wingman
	]

	var wings = WingFormationSystem.form_wings(ships, crew)

	assert_eq(wings.size(), 1, "Should form one wing")
	assert_eq(wings[0].wing_type, "pair", "Should be a pair")
	assert_eq(wings[0].lead_crew_id, "crew_1", "Higher skill pilot should be lead")
	assert_eq(wings[0].wingmen.size(), 1, "Should have one wingman")
	assert_eq(wings[0].wingmen[0].crew_id, "crew_2", "Lower skill pilot should be wingman")


func test_form_wings_creates_three_from_three_nearby_fighters():
	# Three nearby fighters should form a wing-three
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0)),
		create_test_fighter("ship_3", 0, Vector2(50, 100))
	]
	var crew = [
		create_test_crew("crew_1", "ship_1", 0.8),  # Highest skill = lead
		create_test_crew("crew_2", "ship_2", 0.6),
		create_test_crew("crew_3", "ship_3", 0.4)
	]

	var wings = WingFormationSystem.form_wings(ships, crew)

	assert_eq(wings.size(), 1, "Should form one wing")
	assert_eq(wings[0].wing_type, "three", "Should be a wing-three")
	assert_eq(wings[0].lead_crew_id, "crew_1", "Highest skill should be lead")
	assert_eq(wings[0].wingmen.size(), 2, "Should have two wingmen")


func test_form_wings_ignores_distant_fighters():
	# Fighters too far apart should not form a wing
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(2000, 0))  # Beyond 1000 units
	]
	var crew = [
		create_test_crew("crew_1", "ship_1"),
		create_test_crew("crew_2", "ship_2")
	]

	var wings = WingFormationSystem.form_wings(ships, crew)

	assert_eq(wings.size(), 0, "Distant fighters should not form wings")


func test_form_wings_ignores_different_teams():
	# Fighters on different teams should not form a wing
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 1, Vector2(100, 0))  # Different team
	]
	var crew = [
		create_test_crew("crew_1", "ship_1"),
		create_test_crew("crew_2", "ship_2")
	]

	var wings = WingFormationSystem.form_wings(ships, crew)

	assert_eq(wings.size(), 0, "Different teams should not form wings")


func test_form_wings_ignores_destroyed_fighters():
	# Destroyed fighters should not be included in wings
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0))
	]
	ships[1]["status"] = "destroyed"

	var crew = [
		create_test_crew("crew_1", "ship_1"),
		create_test_crew("crew_2", "ship_2")
	]

	var wings = WingFormationSystem.form_wings(ships, crew)

	assert_eq(wings.size(), 0, "Should not form wing with destroyed ship")


func test_form_wings_multiple_pairs():
	# Four fighters should form two pairs
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0)),
		create_test_fighter("ship_3", 0, Vector2(2000, 0)),  # Far from first pair
		create_test_fighter("ship_4", 0, Vector2(2100, 0))   # Near ship_3
	]
	var crew = [
		create_test_crew("crew_1", "ship_1", 0.7),
		create_test_crew("crew_2", "ship_2", 0.5),
		create_test_crew("crew_3", "ship_3", 0.8),
		create_test_crew("crew_4", "ship_4", 0.6)
	]

	var wings = WingFormationSystem.form_wings(ships, crew)

	assert_eq(wings.size(), 2, "Should form two wings")


func test_form_wings_teams_separated():
	# Each team forms its own wings
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0)),
		create_test_fighter("ship_3", 1, Vector2(200, 0)),  # Different team but nearby
		create_test_fighter("ship_4", 1, Vector2(300, 0))
	]
	var crew = [
		create_test_crew("crew_1", "ship_1"),
		create_test_crew("crew_2", "ship_2"),
		create_test_crew("crew_3", "ship_3"),
		create_test_crew("crew_4", "ship_4")
	]

	var wings = WingFormationSystem.form_wings(ships, crew)

	assert_eq(wings.size(), 2, "Should form two wings, one per team")

	# Verify each wing is same team
	for wing in wings:
		var team = wing.team
		for wingman in wing.wingmen:
			# Find the ship for this wingman
			var found_same_team = false
			for ship in ships:
				if ship.ship_id == wingman.ship_id:
					if ship.team == team:
						found_same_team = true
					break
			assert_true(found_same_team, "Wingmen should be same team as lead")


# =============================================================================
# WING INFO LOOKUP TESTS
# =============================================================================

func test_get_wing_info_for_lead():
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0))
	]
	var crew = [
		create_test_crew("crew_1", "ship_1", 0.8),
		create_test_crew("crew_2", "ship_2", 0.5)
	]

	var wings = WingFormationSystem.form_wings(ships, crew)
	var info = WingFormationSystem.get_wing_info("crew_1", wings)

	assert_false(info.is_empty(), "Should find wing info for lead")
	assert_eq(info.role, "lead", "Should be identified as lead")


func test_get_wing_info_for_wingman():
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0))
	]
	var crew = [
		create_test_crew("crew_1", "ship_1", 0.8),
		create_test_crew("crew_2", "ship_2", 0.5)
	]

	var wings = WingFormationSystem.form_wings(ships, crew)
	var info = WingFormationSystem.get_wing_info("crew_2", wings)

	assert_false(info.is_empty(), "Should find wing info for wingman")
	assert_eq(info.role, "wingman", "Should be identified as wingman")
	assert_true(info.position_side != 0, "Should have position side assigned")


func test_get_wing_info_not_in_wing():
	var wings = []  # No wings
	var info = WingFormationSystem.get_wing_info("crew_1", wings)

	assert_true(info.is_empty(), "Should return empty for crew not in a wing")


# =============================================================================
# WING POSITION CALCULATION TESTS
# =============================================================================

func test_calculate_wing_position_reasonable_distance():
	var lead_ship = {
		"position": Vector2(100, 100),
		"velocity": Vector2(100, 0),  # Moving right
		"rotation": 0.0
	}

	var position = WingFormationSystem.calculate_wing_position(lead_ship, 1, 0.5)

	# Wingman should be at a reasonable distance from lead (not on top, not too far)
	# Base distance is ~200 units, with skill modifier and prediction
	var distance = lead_ship.position.distance_to(position)
	assert_true(distance > 100, "Wingman should not be on top of lead")
	assert_true(distance < 500, "Wingman should not be too far from lead")


func test_calculate_wing_position_skill_affects_distance():
	var lead_ship = {
		"position": Vector2(100, 100),
		"velocity": Vector2(100, 0),
		"rotation": 0.0
	}

	var pos_low_skill = WingFormationSystem.calculate_wing_position(lead_ship, 1, 0.0)
	var pos_high_skill = WingFormationSystem.calculate_wing_position(lead_ship, 1, 1.0)

	var dist_low = lead_ship.position.distance_to(pos_low_skill)
	var dist_high = lead_ship.position.distance_to(pos_high_skill)

	# High skill wingman should stay closer (tighter formation)
	# Note: There's randomness in the calculation, so we use approximate comparison
	# The skill_distance_modifier is lerp(1.3, 0.8, skill) so low skill = farther
	assert_true(dist_high < dist_low + 50, "High skill wingman should be closer to lead")


func test_calculate_wing_position_opposite_sides():
	var lead_ship = {
		"position": Vector2(100, 100),
		"velocity": Vector2(100, 0),
		"rotation": 0.0
	}

	var pos_right = WingFormationSystem.calculate_wing_position(lead_ship, 1, 0.5)  # Right side
	var pos_left = WingFormationSystem.calculate_wing_position(lead_ship, -1, 0.5)  # Left side

	# Positions should be on opposite sides
	# The Y coordinate difference should show they're on opposite sides
	assert_true(abs(pos_right.y - pos_left.y) > 50, "Right and left wingmen should be on opposite sides")


# =============================================================================
# FORMATION STATUS TESTS
# =============================================================================

func test_is_in_formation_close():
	var lead_ship = {
		"position": Vector2(100, 100),
		"velocity": Vector2(0, 0),
		"rotation": 0.0
	}
	var wingman_ship = {
		"position": Vector2(150, 150),  # Close to lead
		"velocity": Vector2(0, 0),
		"rotation": 0.0
	}

	var in_formation = WingFormationSystem.is_in_formation(wingman_ship, lead_ship, 0.5)

	assert_true(in_formation, "Wingman close to lead should be in formation")


func test_is_in_formation_far():
	var lead_ship = {
		"position": Vector2(100, 100),
		"velocity": Vector2(0, 0),
		"rotation": 0.0
	}
	var wingman_ship = {
		"position": Vector2(500, 500),  # Far from lead
		"velocity": Vector2(0, 0),
		"rotation": 0.0
	}

	var in_formation = WingFormationSystem.is_in_formation(wingman_ship, lead_ship, 0.5)

	assert_false(in_formation, "Wingman far from lead should not be in formation")


# =============================================================================
# WING BREAK TESTS
# =============================================================================

func test_should_wing_break_lead_destroyed():
	var wing = {
		"lead_ship_id": "ship_1",
		"wingmen": [{"ship_id": "ship_2"}]
	}
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0))
	]
	ships[0]["status"] = "destroyed"

	var should_break = WingFormationSystem.should_wing_break(wing, ships)

	assert_true(should_break, "Wing should break when lead is destroyed")


func test_should_wing_break_too_far():
	var wing = {
		"lead_ship_id": "ship_1",
		"wingmen": [{"ship_id": "ship_2"}]
	}
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(4000, 0))  # Beyond WING_BREAK_RANGE (3600)
	]

	var should_break = WingFormationSystem.should_wing_break(wing, ships)

	assert_true(should_break, "Wing should break when wingman is too far")


func test_should_wing_not_break_normal():
	var wing = {
		"lead_ship_id": "ship_1",
		"wingmen": [{"ship_id": "ship_2"}]
	}
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0))  # Within range
	]

	var should_break = WingFormationSystem.should_wing_break(wing, ships)

	assert_false(should_break, "Wing should not break under normal conditions")


# =============================================================================
# LEAD TARGET/MANEUVER RETRIEVAL TESTS
# =============================================================================

func test_get_lead_target():
	var wing = {
		"lead_crew_id": "crew_1",
		"wingmen": []
	}
	var crew = [
		{
			"crew_id": "crew_1",
			"orders": {
				"current": {"target_id": "enemy_1"}
			}
		}
	]

	var target_id = WingFormationSystem.get_lead_target(wing, crew)

	assert_eq(target_id, "enemy_1", "Should retrieve lead's target")


func test_get_lead_maneuver():
	var wing = {
		"lead_crew_id": "crew_1",
		"wingmen": []
	}
	var crew = [
		{
			"crew_id": "crew_1",
			"orders": {
				"current": {"subtype": "flank_behind"}
			}
		}
	]

	var maneuver = WingFormationSystem.get_lead_maneuver(wing, crew)

	assert_eq(maneuver, "flank_behind", "Should retrieve lead's maneuver")


# =============================================================================
# WING LOYALTY TESTS - Preserve memberships across frames
# =============================================================================

func test_wing_loyalty_maintains_pair_when_drifting_apart():
	# Initial formation
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0))
	]
	var crew = [
		create_test_crew("crew_1", "ship_1", 0.7),
		create_test_crew("crew_2", "ship_2", 0.5)
	]

	# Frame 1: Form initial wing pair
	var wings_frame1 = WingFormationSystem.form_wings(ships, crew)
	assert_eq(wings_frame1.size(), 1, "Should form one wing pair")
	var initial_lead_id = wings_frame1[0].lead_ship_id
	var initial_wingman_id = wings_frame1[0].wingmen[0].ship_id

	# Frame 2: Ships drift apart (but within BREAK_RANGE)
	ships[1]["position"] = Vector2(800, 800)  # 1131 units away, beyond FORMATION_RANGE but within BREAK_RANGE

	# Form wings with previous wings passed in
	var wings_frame2 = WingFormationSystem.form_wings(ships, crew, wings_frame1)

	# They should still be together
	assert_eq(wings_frame2.size(), 1, "Wing pair should be maintained")
	assert_eq(wings_frame2[0].lead_ship_id, initial_lead_id, "Lead should stay the same")
	assert_eq(wings_frame2[0].wingmen[0].ship_id, initial_wingman_id, "Wingman should stay loyal to lead")


func test_wing_loyalty_breaks_when_beyond_break_range():
	# Initial formation
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0))
	]
	var crew = [
		create_test_crew("crew_1", "ship_1", 0.7),
		create_test_crew("crew_2", "ship_2", 0.5)
	]

	var wings_frame1 = WingFormationSystem.form_wings(ships, crew)

	# Ships separate beyond BREAK_RANGE
	ships[1]["position"] = Vector2(4000, 0)

	var wings_frame2 = WingFormationSystem.form_wings(ships, crew, wings_frame1)

	# Wing should break
	assert_eq(wings_frame2.size(), 0, "Wing should break when beyond break range")


func test_solo_fighter_finds_new_wing():
	# Three fighters: pair + solo
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(100, 0)),
		create_test_fighter("ship_3", 0, Vector2(1000, 1000))  # Solo, far away
	]
	var crew = [
		create_test_crew("crew_1", "ship_1", 0.8),
		create_test_crew("crew_2", "ship_2", 0.5),
		create_test_crew("crew_3", "ship_3", 0.6)
	]

	# Frame 1: Form initial wings
	var wings_frame1 = WingFormationSystem.form_wings(ships, crew)
	assert_eq(wings_frame1.size(), 1, "Should form one pair (solo too far)")

	# Frame 2: Solo fighter moves closer to the pair
	ships[2]["position"] = Vector2(150, 50)  # Close to the pair now

	var wings_frame2 = WingFormationSystem.form_wings(ships, crew, wings_frame1)

	# Now should form a wing-three (existing pair plus solo)
	assert_eq(wings_frame2.size(), 1, "Should still be one wing")
	assert_eq(wings_frame2[0].wing_type, "three", "Should form a wing-three when solo joins")
	assert_eq(wings_frame2[0].wingmen.size(), 2, "Should have two wingmen")


func test_solo_fighter_stays_solo_when_no_nearby_wings():
	# Multiple isolated fighters that can't form wings
	var ships = [
		create_test_fighter("ship_1", 0, Vector2(0, 0)),
		create_test_fighter("ship_2", 0, Vector2(2000, 0))  # Too far
	]
	var crew = [
		create_test_crew("crew_1", "ship_1", 0.5),
		create_test_crew("crew_2", "ship_2", 0.5)
	]

	var wings = WingFormationSystem.form_wings(ships, crew)

	assert_eq(wings.size(), 0, "Isolated fighters should not form wings")
