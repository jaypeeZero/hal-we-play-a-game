extends GutTest

## Tests for ShipData class

func test_get_fighter_template():
	var template = ShipData.get_ship_template("fighter")

	assert_not_null(template)
	assert_eq(template.type, "fighter")
	assert_has(template, "stats")
	assert_has(template, "armor_sections")
	assert_has(template, "internals")
	assert_has(template, "weapons")

func test_get_corvette_template():
	var template = ShipData.get_ship_template("corvette")

	assert_not_null(template)
	assert_eq(template.type, "corvette")
	assert_gt(template.stats.size, 15.0)  # Larger than fighter

func test_get_capital_template():
	var template = ShipData.get_ship_template("capital")

	assert_not_null(template)
	assert_eq(template.type, "capital")
	assert_gt(template.stats.size, 30.0)  # Largest ship

func test_create_ship_instance():
	var instance = ShipData.create_ship_instance("fighter", 0, Vector2(100, 200))

	assert_not_null(instance)
	assert_has(instance, "ship_id")
	assert_eq(instance.team, 0)
	assert_eq(instance.position, Vector2(100, 200))
	assert_eq(instance.type, "fighter")

func test_ship_instance_has_unique_id():
	var ship1 = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var ship2 = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)

	assert_ne(ship1.ship_id, ship2.ship_id)

func test_validate_ship_data():
	var valid_data = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	assert_true(ShipData.validate_ship_data(valid_data))

	var invalid_data = {"some": "data"}
	assert_false(ShipData.validate_ship_data(invalid_data))

func test_fighter_has_correct_stats():
	var fighter = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)

	assert_gt(fighter.stats.max_speed, 200.0)  # Fast
	assert_lt(fighter.stats.size, 20.0)  # Small

func test_corvette_has_more_armor_than_fighter():
	var fighter = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var corvette = ShipData.create_ship_instance("corvette", 0, Vector2.ZERO)

	var fighter_armor = 0
	for section in fighter.armor_sections:
		fighter_armor += section.max_armor

	var corvette_armor = 0
	for section in corvette.armor_sections:
		corvette_armor += section.max_armor

	assert_gt(corvette_armor, fighter_armor)

func test_capital_has_most_weapons():
	var fighter = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	var corvette = ShipData.create_ship_instance("corvette", 0, Vector2.ZERO)
	var capital = ShipData.create_ship_instance("capital", 0, Vector2.ZERO)

	assert_lt(fighter.weapons.size(), corvette.weapons.size())
	assert_lt(corvette.weapons.size(), capital.weapons.size())

func test_ship_armor_sections_have_arcs():
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)

	for section in ship.armor_sections:
		assert_has(section, "arc")
		assert_has(section.arc, "start")
		assert_has(section.arc, "end")

func test_ship_internals_have_effects():
	var ship = ShipData.create_ship_instance("corvette", 0, Vector2.ZERO)

	var found_power = false
	var found_engine = false
	var found_control = false

	for internal in ship.internals:
		match internal.type:
			"power":
				found_power = true
			"engine":
				found_engine = true
			"control":
				found_control = true

	assert_true(found_power, "Should have power component")
	assert_true(found_engine, "Should have engine component")
	assert_true(found_control, "Should have control component")

func test_ship_weapons_have_stats():
	var ship = ShipData.create_ship_instance("corvette", 0, Vector2.ZERO)

	for weapon in ship.weapons:
		assert_has(weapon.stats, "damage")
		assert_has(weapon.stats, "rate_of_fire")
		assert_has(weapon.stats, "projectile_speed")
		assert_has(weapon.stats, "range")
		assert_has(weapon.stats, "accuracy")
