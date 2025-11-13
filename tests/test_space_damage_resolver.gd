extends GutTest

## Tests for DamageResolver system

var ship_data: Dictionary

func before_each():
	# Create a test ship
	ship_data = ShipData.create_ship_instance("fighter", 0, Vector2(500, 500))

func test_resolve_hit_damages_armor():
	var initial_armor = ship_data.armor_sections[0].current_armor
	var hit_position = ship_data.position + Vector2(0, -10)  # Hit front

	var result = DamageResolver.resolve_hit(ship_data, hit_position, 10, 0.0)

	assert_eq(result.type, "armor_hit")
	assert_lt(ship_data.armor_sections[0].current_armor, initial_armor)

func test_find_armor_section_at_angle():
	# Front section should be at 0 degrees
	var section = DamageResolver.find_armor_section_at_angle(ship_data, 0.0)
	assert_not_null(section)

func test_armor_penetration_damages_internals():
	# Get a section and destroy its armor
	var section = ship_data.armor_sections[0]
	var initial_armor = section.max_armor
	section.current_armor = 0  # Armor destroyed

	# Hit should now damage internals
	var hit_position = ship_data.position + Vector2(0, -10)
	var result = DamageResolver.resolve_hit(ship_data, hit_position, 20, 0.0)

	assert_true(result.penetrated)
	assert_has(result, "internal_hit")

func test_component_damage_applies_effects():
	# Find engine component
	var engine = null
	for internal in ship_data.internals:
		if internal.type == "engine":
			engine = internal
			break

	assert_not_null(engine)

	var initial_speed = ship_data.stats.max_speed

	# Damage the engine
	engine.current_health = engine.max_health / 2  # 50% health
	engine.status = "operational"  # Reset status

	# Apply damage effects
	engine.status = "damaged"
	DamageResolver.apply_component_damage_effects(ship_data, engine)

	# Speed should be reduced
	assert_lt(ship_data.stats.max_speed, initial_speed)

func test_component_destruction_disables_ship():
	# Find power core
	var power_core = null
	for internal in ship_data.internals:
		if internal.type == "power":
			power_core = internal
			break

	if power_core:  # Fighter might not have power core
		power_core.current_health = 0
		power_core.status = "destroyed"

		DamageResolver.apply_component_destruction_effects(ship_data, power_core)

		# Check if ship is disabled
		assert_eq(ship_data.status, "disabled")

func test_calculate_total_armor():
	var total = DamageResolver.calculate_total_armor(ship_data)
	assert_gt(total, 0)

	# Damage some armor
	ship_data.armor_sections[0].current_armor = 0

	var new_total = DamageResolver.calculate_total_armor(ship_data)
	assert_lt(new_total, total)

func test_calculate_total_internal_health():
	var total = DamageResolver.calculate_total_internal_health(ship_data)
	assert_gt(total, 0)

func test_is_ship_destroyed():
	# Ship should not be destroyed initially
	assert_false(DamageResolver.is_ship_destroyed(ship_data))

	# Destroy all internals
	for internal in ship_data.internals:
		internal.status = "destroyed"

	# Now ship should be destroyed
	assert_true(DamageResolver.is_ship_destroyed(ship_data))

func test_get_destroyed_components():
	# Initially no destroyed components
	var destroyed = DamageResolver.get_destroyed_components(ship_data)
	assert_eq(destroyed.size(), 0)

	# Destroy one component
	ship_data.internals[0].status = "destroyed"

	destroyed = DamageResolver.get_destroyed_components(ship_data)
	assert_eq(destroyed.size(), 1)

func test_get_damaged_components():
	# Initially no damaged components
	var damaged = DamageResolver.get_damaged_components(ship_data)
	assert_eq(damaged.size(), 0)

	# Damage one component
	ship_data.internals[0].status = "damaged"

	damaged = DamageResolver.get_damaged_components(ship_data)
	assert_eq(damaged.size(), 1)

func test_massive_damage_penetrates_armor_and_hits_internals():
	# Massive hit should penetrate armor and damage internals
	var initial_internal_health = ship_data.internals[0].current_health
	var hit_position = ship_data.position + Vector2(0, -10)

	# Hit with massive damage (more than armor can absorb)
	var result = DamageResolver.resolve_hit(ship_data, hit_position, 1000, 0.0)

	assert_true(result.penetrated)
	assert_has(result, "internal_hit")

func test_armor_section_wrap_around():
	# Test wrap-around arc (e.g., rear section that goes from 300 to 420 degrees)
	var ship = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)

	# Test angle that should hit wrap-around section
	var section = DamageResolver.find_armor_section_at_angle(ship, 350.0)
	assert_not_null(section, "Should find section in wrap-around arc")
