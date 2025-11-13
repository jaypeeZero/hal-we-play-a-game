extends GutTest

## Tests for ShipData - FUNCTIONALITY ONLY
## Tests ship creation and validation behaviors, not specific data values

# ============================================================================
# TEMPLATE RETRIEVAL TESTS
# ============================================================================

func test_can_retrieve_fighter_template():
	var template = ShipData.get_ship_template("fighter")

	assert_false(template.is_empty(), "Fighter template should be retrievable")
	assert_eq(template.type, "fighter")

func test_can_retrieve_corvette_template():
	var template = ShipData.get_ship_template("corvette")

	assert_false(template.is_empty(), "Corvette template should be retrievable")
	assert_eq(template.type, "corvette")

func test_can_retrieve_capital_template():
	var template = ShipData.get_ship_template("capital")

	assert_false(template.is_empty(), "Capital template should be retrievable")
	assert_eq(template.type, "capital")

func test_invalid_ship_type_returns_empty():
	var template = ShipData.get_ship_template("invalid_type")

	assert_true(template.is_empty(), "Invalid ship type should return empty dictionary")

func test_templates_have_required_components():
	var types = ["fighter", "corvette", "capital"]

	for ship_type in types:
		var template = ShipData.get_ship_template(ship_type)
		assert_has(template, "stats", ship_type + " should have stats")
		assert_has(template, "armor_sections", ship_type + " should have armor sections")
		assert_has(template, "internals", ship_type + " should have internals")
		assert_has(template, "weapons", ship_type + " should have weapons")

func test_templates_have_movement_stats():
	var types = ["fighter", "corvette", "capital"]

	for ship_type in types:
		var template = ShipData.get_ship_template(ship_type)
		assert_has(template.stats, "max_speed")
		assert_has(template.stats, "acceleration")
		assert_has(template.stats, "turn_rate")

# ============================================================================
# SHIP INSTANCE CREATION TESTS
# ============================================================================

func test_create_ship_instance_generates_unique_id():
	var ship1 = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	var ship2 = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))

	assert_ne(ship1.ship_id, ship2.ship_id, "Each ship should have unique ID")

func test_create_ship_instance_sets_team():
	var ship = ShipData.create_ship_instance("fighter", 5, Vector2(0, 0))

	assert_eq(ship.team, 5, "Ship should have specified team")

func test_create_ship_instance_sets_position():
	var position = Vector2(100, 200)
	var ship = ShipData.create_ship_instance("fighter", 0, position)

	assert_eq(ship.position, position, "Ship should have specified position")

func test_create_ship_instance_initializes_status():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))

	assert_eq(ship.status, "operational", "New ship should be operational")

func test_create_ship_instance_initializes_velocity():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))

	assert_eq(ship.velocity, Vector2.ZERO, "New ship should have zero velocity")

func test_opposing_teams_face_opposite_directions():
	var team0_ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	var team1_ship = ShipData.create_ship_instance("fighter", 1, Vector2(0, 0))

	var rotation_difference = abs(team0_ship.rotation - team1_ship.rotation)
	assert_almost_eq(rotation_difference, PI, 0.1, "Opposing teams should face opposite directions")

# ============================================================================
# CREW CREATION TESTS
# ============================================================================

func test_create_ship_without_crew():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0), false)

	assert_false(ship.has("crew") and ship.crew.size() > 0, "Ship created without crew should not have crew")

func test_create_ship_with_crew():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0), true)

	assert_has(ship, "crew", "Ship created with crew should have crew array")
	assert_gt(ship.crew.size(), 0, "Crew array should not be empty")

func test_fighter_gets_solo_pilot():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0), true)

	assert_eq(ship.crew.size(), 1, "Fighter should have solo pilot")
	assert_eq(ship.crew[0].role, CrewData.Role.PILOT)

func test_corvette_gets_full_crew():
	var ship = ShipData.create_ship_instance("corvette", 0, Vector2(0, 0), true)

	assert_gt(ship.crew.size(), 1, "Corvette should have multiple crew members")

func test_crew_assigned_to_ship():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0), true)

	for crew_member in ship.crew:
		assert_eq(crew_member.assigned_to, ship.ship_id, "Crew should be assigned to ship")

func test_crew_skill_level_applied():
	var high_skill_ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0), true, 0.9)
	var low_skill_ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0), true, 0.3)

	assert_gt(high_skill_ship.crew[0].stats.skill, low_skill_ship.crew[0].stats.skill, "Crew skill should match specified level")

# ============================================================================
# SHIP VALIDATION TESTS
# ============================================================================

func test_valid_ship_passes_validation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))

	assert_true(ShipData.validate_ship_data(ship), "Valid ship should pass validation")

func test_missing_ship_id_fails_validation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	ship.erase("ship_id")

	assert_false(ShipData.validate_ship_data(ship), "Ship without ship_id should fail validation")

func test_missing_type_fails_validation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	ship.erase("type")

	assert_false(ShipData.validate_ship_data(ship), "Ship without type should fail validation")

func test_missing_team_fails_validation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	ship.erase("team")

	assert_false(ShipData.validate_ship_data(ship), "Ship without team should fail validation")

func test_missing_position_fails_validation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	ship.erase("position")

	assert_false(ShipData.validate_ship_data(ship), "Ship without position should fail validation")

func test_missing_stats_fails_validation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	ship.erase("stats")

	assert_false(ShipData.validate_ship_data(ship), "Ship without stats should fail validation")

func test_missing_armor_fails_validation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	ship.erase("armor_sections")

	assert_false(ShipData.validate_ship_data(ship), "Ship without armor_sections should fail validation")

func test_missing_internals_fails_validation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	ship.erase("internals")

	assert_false(ShipData.validate_ship_data(ship), "Ship without internals should fail validation")

func test_missing_weapons_fails_validation():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	ship.erase("weapons")

	assert_false(ShipData.validate_ship_data(ship), "Ship without weapons should fail validation")

# ============================================================================
# TEMPLATE STRUCTURE TESTS
# ============================================================================

func test_all_templates_have_armor_sections():
	var types = ["fighter", "corvette", "capital"]

	for ship_type in types:
		var template = ShipData.get_ship_template(ship_type)
		assert_gt(template.armor_sections.size(), 0, ship_type + " should have armor sections")

func test_all_armor_sections_have_arcs():
	var types = ["fighter", "corvette", "capital"]

	for ship_type in types:
		var template = ShipData.get_ship_template(ship_type)
		for section in template.armor_sections:
			assert_has(section, "arc", "Armor section should have arc")
			assert_has(section.arc, "start", "Arc should have start")
			assert_has(section.arc, "end", "Arc should have end")

func test_all_templates_have_internal_components():
	var types = ["fighter", "corvette", "capital"]

	for ship_type in types:
		var template = ShipData.get_ship_template(ship_type)
		assert_gt(template.internals.size(), 0, ship_type + " should have internal components")

func test_all_internal_components_have_effects():
	var types = ["fighter", "corvette", "capital"]

	for ship_type in types:
		var template = ShipData.get_ship_template(ship_type)
		for component in template.internals:
			assert_has(component, "effect_on_ship", "Component should have effect_on_ship")

func test_all_templates_have_weapons():
	var types = ["fighter", "corvette", "capital"]

	for ship_type in types:
		var template = ShipData.get_ship_template(ship_type)
		assert_gt(template.weapons.size(), 0, ship_type + " should have weapons")

func test_all_weapons_have_stats():
	var types = ["fighter", "corvette", "capital"]

	for ship_type in types:
		var template = ShipData.get_ship_template(ship_type)
		for weapon in template.weapons:
			assert_has(weapon, "stats", "Weapon should have stats")
			assert_has(weapon.stats, "damage")
			assert_has(weapon.stats, "rate_of_fire")
			assert_has(weapon.stats, "range")

# ============================================================================
# SHIP TYPE CHARACTERISTICS TESTS
# ============================================================================

func test_fighter_faster_than_corvette():
	var fighter = ShipData.get_ship_template("fighter")
	var corvette = ShipData.get_ship_template("corvette")

	assert_gt(fighter.stats.max_speed, corvette.stats.max_speed, "Fighter should be faster than corvette")

func test_corvette_faster_than_capital():
	var corvette = ShipData.get_ship_template("corvette")
	var capital = ShipData.get_ship_template("capital")

	assert_gt(corvette.stats.max_speed, capital.stats.max_speed, "Corvette should be faster than capital")

func test_fighter_more_agile_than_corvette():
	var fighter = ShipData.get_ship_template("fighter")
	var corvette = ShipData.get_ship_template("corvette")

	assert_gt(fighter.stats.turn_rate, corvette.stats.turn_rate, "Fighter should turn faster than corvette")

func test_corvette_has_more_weapons_than_fighter():
	var fighter = ShipData.get_ship_template("fighter")
	var corvette = ShipData.get_ship_template("corvette")

	assert_gt(corvette.weapons.size(), fighter.weapons.size(), "Corvette should have more weapons than fighter")

func test_capital_has_most_weapons():
	var fighter = ShipData.get_ship_template("fighter")
	var corvette = ShipData.get_ship_template("corvette")
	var capital = ShipData.get_ship_template("capital")

	assert_gt(capital.weapons.size(), fighter.weapons.size(), "Capital should have more weapons than fighter")
	assert_ge(capital.weapons.size(), corvette.weapons.size(), "Capital should have at least as many weapons as corvette")

# ============================================================================
# TEMPLATE IMMUTABILITY TESTS
# ============================================================================

func test_creating_instance_does_not_affect_template():
	var template_before = ShipData.get_ship_template("fighter")
	var original_armor = template_before.armor_sections[0].current_armor

	var _instance = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))

	var template_after = ShipData.get_ship_template("fighter")
	assert_eq(template_after.armor_sections[0].current_armor, original_armor, "Template should not be affected by instance creation")

func test_modifying_instance_does_not_affect_template():
	var template_before = ShipData.get_ship_template("fighter")
	var original_armor = template_before.armor_sections[0].current_armor

	var instance = ShipData.create_ship_instance("fighter", 0, Vector2(0, 0))
	instance.armor_sections[0].current_armor = 0

	var template_after = ShipData.get_ship_template("fighter")
	assert_eq(template_after.armor_sections[0].current_armor, original_armor, "Modifying instance should not affect template")
