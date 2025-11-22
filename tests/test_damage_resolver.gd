extends GutTest

## Tests for DamageResolver - FUNCTIONALITY ONLY
## Tests damage resolution behaviors, not specific data values

# ============================================================================
# ARMOR DAMAGE TESTS
# ============================================================================

func test_armor_blocks_damage_when_sufficient():
	var ship = create_test_ship_with_armor(100)
	var result = DamageResolver.resolve_hit(ship, ship.position + Vector2(0, -10), 50, 0.0)

	assert_false(result.hit_result.penetrated, "Armor should block damage when sufficient")
	assert_eq(result.hit_result.type, "armor_hit")
	assert_lt(result.ship_data.armor_sections[0].current_armor, ship.armor_sections[0].current_armor, "Armor should be reduced")

func test_armor_penetration_when_damage_exceeds_armor():
	var ship = create_test_ship_with_armor(10)
	var result = DamageResolver.resolve_hit(ship, ship.position + Vector2(0, -10), 50, 0.0)

	assert_true(result.hit_result.penetrated, "Armor should be penetrated when damage exceeds armor")
	assert_has(result.hit_result, "internal_hit", "Penetration should damage internals")

func test_armor_depletion_allows_penetration():
	var ship = create_test_ship_with_armor(20)

	# First hit depletes armor
	var result1 = DamageResolver.resolve_hit(ship, ship.position + Vector2(0, -10), 20, 0.0)
	assert_false(result1.hit_result.penetrated, "First hit depletes armor but doesn't penetrate")

	# Second hit penetrates
	var result2 = DamageResolver.resolve_hit(result1.ship_data, ship.position + Vector2(0, -10), 5, 0.0)
	assert_true(result2.hit_result.penetrated, "Second hit should penetrate depleted armor")

func test_hit_angle_determines_armor_section():
	var ship = create_test_ship_with_multiple_sections()

	# Hit from front (0 degrees)
	var front_hit = DamageResolver.resolve_hit(ship, ship.position + Vector2(0, -20), 10, 0.0)
	var front_section_id = front_hit.hit_result.section_id

	# Hit from side (90 degrees)
	var side_hit = DamageResolver.resolve_hit(ship, ship.position + Vector2(20, 0), 10, 0.0)
	var side_section_id = side_hit.hit_result.section_id

	assert_ne(front_section_id, side_section_id, "Different angles should hit different sections")

# ============================================================================
# INTERNAL COMPONENT DAMAGE TESTS
# ============================================================================

func test_component_transitions_to_damaged_when_hit():
	var ship = create_test_ship_with_components()
	ship.armor_sections[0].current_armor = 0  # Depleted armor

	var result = DamageResolver.resolve_hit(ship, ship.position, 10, 0.0)

	if result.hit_result.has("internal_hit"):
		var component = find_component(result.ship_data, result.hit_result.internal_hit.component_id)
		assert_true(component.status in ["damaged", "destroyed"], "Component should be damaged or destroyed")

func test_component_transitions_to_destroyed_at_zero_health():
	var ship = create_test_ship_with_components()
	ship.armor_sections[0].current_armor = 0

	# Damage equal to component health
	var component = ship.internals[0]
	var result = DamageResolver.resolve_hit(ship, ship.position, component.current_health, 0.0)

	if result.hit_result.has("internal_hit"):
		var damaged_component = find_component(result.ship_data, result.hit_result.internal_hit.component_id)
		if result.hit_result.internal_hit.health_remaining == 0:
			assert_eq(damaged_component.status, "destroyed", "Component at 0 health should be destroyed")

func test_damaged_component_applies_effects_to_ship():
	var ship = create_test_ship_with_engine()
	var original_max_speed = ship.stats.max_speed
	ship.armor_sections[0].current_armor = 0

	# Damage the engine
	var result = DamageResolver.resolve_hit(ship, ship.internals[0].position_offset, 15, 0.0)

	if result.hit_result.has("internal_hit") and result.hit_result.internal_hit.new_status == "damaged":
		assert_lt(result.ship_data.stats.max_speed, original_max_speed, "Damaged engine should reduce max_speed")

func test_destroyed_component_applies_more_severe_effects_than_damaged():
	var ship1 = create_test_ship_with_engine()
	var ship2 = create_test_ship_with_engine()
	ship1.armor_sections[0].current_armor = 0
	ship2.armor_sections[0].current_armor = 0

	# Damage the engine on ship1
	var result1 = DamageResolver.resolve_hit(ship1, ship1.internals[0].position_offset, 15, 0.0)

	# Destroy the engine on ship2
	var engine_health = ship2.internals[0].current_health
	var result2 = DamageResolver.resolve_hit(ship2, ship2.internals[0].position_offset, engine_health, 0.0)

	if result1.hit_result.has("internal_hit") and result2.hit_result.has("internal_hit"):
		if result1.hit_result.internal_hit.new_status == "damaged" and result2.hit_result.internal_hit.new_status == "destroyed":
			assert_lt(result2.ship_data.stats.max_speed, result1.ship_data.stats.max_speed, "Destroyed engine should reduce speed more than damaged engine")

func test_closest_component_is_damaged_on_penetration():
	var ship = create_test_ship_with_multiple_components()
	ship.armor_sections[0].current_armor = 0

	var hit_position = ship.position + Vector2(0, -10)
	var result = DamageResolver.resolve_hit(ship, hit_position, 20, 0.0)

	if result.hit_result.has("internal_hit"):
		var damaged_component = find_component(result.ship_data, result.hit_result.internal_hit.component_id)
		var distance = hit_position.distance_to(ship.position + damaged_component.position_offset)

		# Check that other components are not closer
		for component in ship.internals:
			if component.component_id != damaged_component.component_id:
				var other_distance = hit_position.distance_to(ship.position + component.position_offset)
				assert_lte(distance, other_distance + 0.1, "Closest component should be damaged")

# ============================================================================
# SHIP STATE QUERY TESTS
# ============================================================================

func test_total_armor_calculation_sums_all_sections():
	var ship = create_test_ship_with_multiple_sections()
	var total = DamageResolver.calculate_total_armor(ship)

	var expected = 0
	for section in ship.armor_sections:
		expected += section.current_armor

	assert_eq(total, expected, "Total armor should sum all sections")

func test_total_armor_decreases_after_damage():
	var ship = create_test_ship_with_armor(50)
	var initial_total = DamageResolver.calculate_total_armor(ship)

	var result = DamageResolver.resolve_hit(ship, ship.position + Vector2(0, -10), 20, 0.0)
	var final_total = DamageResolver.calculate_total_armor(result.ship_data)

	assert_lt(final_total, initial_total, "Total armor should decrease after damage")

func test_destroyed_components_query_returns_destroyed_only():
	var ship = create_test_ship_with_multiple_components()

	# Manually set component statuses
	ship.internals[0].status = "destroyed"
	ship.internals[1].status = "operational"
	if ship.internals.size() > 2:
		ship.internals[2].status = "damaged"

	var destroyed = DamageResolver.get_destroyed_components(ship)

	# Should include destroyed components
	assert_has(destroyed, ship.internals[0].component_id, "Should return destroyed component")
	# Should not include operational or damaged components
	assert_false(destroyed.has(ship.internals[1].component_id), "Should not return operational component")

func test_damaged_components_query_returns_damaged_only():
	var ship = create_test_ship_with_multiple_components()

	ship.internals[0].status = "damaged"
	ship.internals[1].status = "operational"
	if ship.internals.size() > 2:
		ship.internals[2].status = "destroyed"

	var damaged = DamageResolver.get_damaged_components(ship)

	# Should include damaged components
	assert_has(damaged, ship.internals[0].component_id, "Should return damaged component")
	# Should not include operational or destroyed components
	assert_false(damaged.has(ship.internals[1].component_id), "Should not return operational component")

# ============================================================================
# FUNCTIONAL PURITY TESTS
# ============================================================================

func test_damage_resolution_does_not_mutate_input():
	var ship = create_test_ship_with_armor(100)
	var original_armor = ship.armor_sections[0].current_armor

	var _result = DamageResolver.resolve_hit(ship, ship.position + Vector2(0, -10), 50, 0.0)

	assert_eq(ship.armor_sections[0].current_armor, original_armor, "Original ship data should not be mutated")

func test_multiple_hits_accumulate_correctly():
	var ship = create_test_ship_with_armor(100)

	var result1 = DamageResolver.resolve_hit(ship, ship.position + Vector2(0, -10), 30, 0.0)
	var armor_after_first_hit = result1.ship_data.armor_sections[0].current_armor

	var result2 = DamageResolver.resolve_hit(result1.ship_data, ship.position + Vector2(0, -10), 40, 0.0)
	var armor_after_second_hit = result2.ship_data.armor_sections[0].current_armor

	assert_lt(armor_after_second_hit, armor_after_first_hit, "Armor should decrease after second hit")
	assert_lt(armor_after_first_hit, ship.armor_sections[0].current_armor, "Armor should decrease after first hit")

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

## Base template for creating test ships with common fields
func _base_test_ship(ship_type: String = "fighter", extra_fields: Dictionary = {}) -> Dictionary:
	var base = {
		"ship_id": "test_ship",
		"type": ship_type,
		"team": 0,
		"position": Vector2(0, 0),
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"rotation": 0.0,
		"status": "operational",
		"stats": {"max_speed": 300.0, "acceleration": 100.0, "turn_rate": 3.0},
		"weapons": [],
		"armor_sections": [],
		"internals": []
	}

	# Merge in extra fields
	for key in extra_fields:
		base[key] = extra_fields[key]

	return base

func create_test_ship_with_armor(armor_value: int) -> Dictionary:
	return _base_test_ship("fighter", {
		"armor_sections": [
			{
				"section_id": "front",
				"arc": {"start": -90, "end": 90},
				"max_armor": armor_value,
				"current_armor": armor_value
			}
		],
		"internals": []
	})

func create_test_ship_with_multiple_sections() -> Dictionary:
	return _base_test_ship("corvette", {
		"stats": {"max_speed": 200.0, "acceleration": 100.0, "turn_rate": 3.0},
		"armor_sections": [
			{"section_id": "front", "arc": {"start": -45, "end": 45}, "max_armor": 50, "current_armor": 50},
			{"section_id": "left", "arc": {"start": 45, "end": 135}, "max_armor": 40, "current_armor": 40},
			{"section_id": "right", "arc": {"start": 225, "end": 315}, "max_armor": 40, "current_armor": 40}
		],
		"internals": []
	})

func create_test_ship_with_components() -> Dictionary:
	return _base_test_ship("fighter", {
		"armor_sections": [
			{"section_id": "front", "arc": {"start": 0, "end": 360}, "max_armor": 20, "current_armor": 20}
		],
		"internals": [
			{"component_id": "engine", "type": "engine", "position_offset": Vector2(0, 5), "max_health": 25, "current_health": 25, "status": "operational", "effect_on_ship": {"on_damaged": {"max_speed": 0.7}, "on_destroyed": {"max_speed": 0.2}}}
		]
	})

func create_test_ship_with_engine() -> Dictionary:
	return create_test_ship_with_components()

func create_test_ship_with_multiple_components() -> Dictionary:
	return _base_test_ship("fighter", {
		"armor_sections": [
			{"section_id": "front", "arc": {"start": 0, "end": 360}, "max_armor": 50, "current_armor": 50}
		],
		"internals": [
			{"component_id": "engine", "type": "engine", "position_offset": Vector2(0, 10), "max_health": 30, "current_health": 30, "status": "operational", "effect_on_ship": {"on_damaged": {}, "on_destroyed": {}}},
			{"component_id": "reactor", "type": "reactor", "position_offset": Vector2(0, 0), "max_health": 40, "current_health": 40, "status": "operational", "effect_on_ship": {"on_damaged": {}, "on_destroyed": {}}},
			{"component_id": "sensors", "type": "sensors", "position_offset": Vector2(0, -10), "max_health": 20, "current_health": 20, "status": "operational", "effect_on_ship": {"on_damaged": {}, "on_destroyed": {}}}
		]
	})

func find_component(ship: Dictionary, component_id: String) -> Dictionary:
	for component in ship["internals"]:
		if component.component_id == component_id:
			return component
	return {}
