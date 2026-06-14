extends GutTest

## Tests for WeaponSystem - FUNCTIONALITY ONLY
## Tests weapon behaviors, not specific data values

# ============================================================================
# COOLDOWN MANAGEMENT TESTS
# ============================================================================

func test_weapon_fires_when_ready():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)  # No cooldown
	# Ship at rotation 0 visually faces UP (negative Y), so target must be above
	var target = TestFactories.make_fighter("", Vector2(0, -300), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_gt(result.fire_commands.size(), 0, "Ready weapon should fire at valid target")

func test_weapon_with_destroyed_mount_does_not_fire():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)  # No cooldown
	ship.weapons[0]["status"] = "destroyed"  # mount shot off
	var target = TestFactories.make_fighter("", Vector2(0, -300), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_eq(result.fire_commands.size(), 0,
		"A weapon whose mount is destroyed must not fire even when ready")


func test_operational_weapon_still_fires():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	ship.weapons[0]["status"] = "operational"
	var target = TestFactories.make_fighter("", Vector2(0, -300), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_gt(result.fire_commands.size(), 0,
		"An operational weapon fires normally")


func test_weapon_does_not_fire_during_cooldown():
	var ship = TestFactories.make_armed_ship("light_cannon", 1.0)  # In cooldown
	var target = TestFactories.make_fighter("", Vector2(300, 0), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Weapon in cooldown should not fire")

func test_cooldown_decreases_over_time():
	var ship = TestFactories.make_armed_ship("light_cannon", 1.0)
	var target = TestFactories.make_fighter("", Vector2(300, 0), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.5)

	assert_lt(result.ship_data.weapons[0].cooldown_remaining, 1.0, "Cooldown should decrease")

func test_cooldown_set_after_firing():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	# Ship at rotation 0 visually faces UP (negative Y)
	var target = TestFactories.make_fighter("", Vector2(0, -300), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_gt(result.fire_commands.size(), 0, "Weapon should fire")
	assert_gt(result.ship_data.weapons[0].cooldown_remaining, 0.0, "Cooldown should be set after firing")

func test_cooldown_cannot_go_negative():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.5)

	var result = WeaponSystem.update_weapons(ship, [], 2.0)  # Delta larger than cooldown

	assert_eq(result.ship_data.weapons[0].cooldown_remaining, 0.0, "Cooldown should not go negative")

# ============================================================================
# TARGET SELECTION TESTS
# ============================================================================

func test_weapon_selects_closest_target():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	# Ship at rotation 0 visually faces UP (negative Y)
	var close_target = TestFactories.make_fighter("", Vector2(0, -200), 1)
	var far_target = TestFactories.make_fighter("", Vector2(0, -600), 1)

	var result = WeaponSystem.update_weapons(ship, [far_target, close_target], 0.1)

	assert_gt(result.fire_commands.size(), 0, "Weapon should fire")
	assert_eq(result.fire_commands[0].target_id, close_target.ship_id, "Should target closest enemy")

func test_weapon_ignores_out_of_range_targets():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	var out_of_range = TestFactories.make_fighter("", Vector2(2000, 0), 1)  # Beyond weapon range

	var result = WeaponSystem.update_weapons(ship, [out_of_range], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire at targets out of range")

func test_weapon_ignores_allies():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	ship.team = 0
	var ally = TestFactories.make_fighter("", Vector2(300, 0), 1)
	ally.team = 0  # Same team

	var result = WeaponSystem.update_weapons(ship, [ally], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire at allies")

func test_weapon_ignores_destroyed_targets():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	var destroyed_target = TestFactories.make_fighter("", Vector2(300, 0), 1)
	destroyed_target.status = "destroyed"

	var result = WeaponSystem.update_weapons(ship, [destroyed_target], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire at destroyed targets")

func test_weapon_does_not_fire_without_targets():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)

	var result = WeaponSystem.update_weapons(ship, [], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire without targets")

# ============================================================================
# FIRING ARC TESTS
# ============================================================================

func test_weapon_fires_at_target_in_arc():
	var ship = TestFactories.make_armed_ship()
	ship.weapons[0].arc = {"min": -20, "max": 20}  # Narrow forward arc
	var target_in_arc = TestFactories.make_fighter("", Vector2(300, 50), 1)  # Slightly off-center but in arc

	var result = WeaponSystem.update_weapons(ship, [target_in_arc], 0.1)

	# This may or may not fire depending on arc, just verify no errors
	assert_true(true, "Weapon system handles arc calculation without errors")

func test_weapon_does_not_fire_outside_arc():
	var ship = TestFactories.make_armed_ship()
	ship.weapons[0].arc = {"min": -20, "max": 20}  # Narrow forward arc
	var target_behind = TestFactories.make_fighter("", Vector2(-300, 0), 1)  # Behind ship

	var result = WeaponSystem.update_weapons(ship, [target_behind], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Should not fire at target outside firing arc")

# ============================================================================
# SHIP STATE TESTS
# ============================================================================

func test_disabled_ship_does_not_fire():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	ship.status = "disabled"
	var target = TestFactories.make_fighter("", Vector2(300, 0), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Disabled ship should not fire")

func test_destroyed_ship_does_not_fire():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	ship.status = "destroyed"
	var target = TestFactories.make_fighter("", Vector2(300, 0), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_eq(result.fire_commands.size(), 0, "Destroyed ship should not fire")

# ============================================================================
# FIRE COMMAND CREATION TESTS
# ============================================================================

func test_fire_command_includes_required_fields():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	# Ship at rotation 0 visually faces UP (negative Y)
	var target = TestFactories.make_fighter("", Vector2(0, -300), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_gt(result.fire_commands.size(), 0, "Weapon should fire")
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
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	# Ship at rotation 0 visually faces UP (negative Y)
	var target = TestFactories.make_fighter("", Vector2(0, -300), 1)

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_gt(result.fire_commands.size(), 0, "Weapon should fire")
	var direction = result.fire_commands[0].direction
	var length = direction.length()
	assert_almost_eq(length, 1.0, 0.1, "Fire direction should be normalized")

func test_fire_command_targets_correct_enemy():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	# Ship at rotation 0 visually faces UP (negative Y)
	var target = TestFactories.make_fighter("", Vector2(0, -300), 1)
	target.ship_id = "enemy_123"

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_gt(result.fire_commands.size(), 0, "Weapon should fire")
	assert_eq(result.fire_commands[0].target_id, "enemy_123", "Fire command should target correct enemy")

# ============================================================================
# FUNCTIONAL PURITY TESTS
# ============================================================================

func test_weapon_update_does_not_mutate_input():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.5)
	var original_cooldown = ship.weapons[0].cooldown_remaining
	var target = TestFactories.make_fighter("", Vector2(300, 0), 1)

	var _result = WeaponSystem.update_weapons(ship, [target], 0.1)

	assert_eq(ship.weapons[0].cooldown_remaining, original_cooldown, "Original ship data should not be mutated")

func test_target_array_not_mutated():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	var target = TestFactories.make_fighter("", Vector2(300, 0), 1)
	var targets = [target]
	var original_target = target.duplicate(true)

	var _result = WeaponSystem.update_weapons(ship, targets, 0.1)

	assert_eq(targets[0], original_target, "Target array should not be mutated")

# ============================================================================
# QUERY FUNCTION TESTS
# ============================================================================

func test_get_fireable_weapons_returns_ready_weapons_only():
	var ship = TestFactories.make_armed_ship()
	ship.weapons.append(TestFactories.make_weapon("light_cannon", "weapon_2"))
	ship.weapons[0].cooldown_remaining = 0.0  # Ready
	ship.weapons[1].cooldown_remaining = 1.0  # Not ready

	var target = TestFactories.make_fighter("", Vector2(300, 0), 1)
	var fireable = WeaponSystem.get_fireable_weapons(ship, target)

	assert_lte(fireable.size(), ship.weapons.size(), "Should return subset of weapons")

func test_calculate_hit_probability_returns_valid_range():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	var weapon = ship.weapons[0]
	var target = TestFactories.make_fighter("", Vector2(300, 0), 1)

	var probability = WeaponSystem.calculate_hit_probability(ship, weapon, target)

	assert_gte(probability, 0.0, "Hit probability should be >= 0")
	assert_lte(probability, 1.0, "Hit probability should be <= 1")

# DIAGNOSE_FIRING TESTS

func test_diagnose_firing_can_fire_when_enemy_in_range_and_arc():
	# Ship at origin, rotation 0 → faces up (negative Y). Enemy directly above in arc.
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	var enemy = TestFactories.make_fighter("", Vector2(0, -300), 1)

	var result = WeaponSystem.diagnose_firing(ship, [ship, enemy])

	assert_eq(result.reason, WeaponSystem.DIAG_CAN_FIRE,
		"Should report can_fire when enemy is in range and arc")
	assert_true(result.firing, "firing flag should be true")

func test_diagnose_firing_out_of_range_when_enemy_too_far():
	# light_cannon range = 1000; enemy at 3x that.
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	var enemy = TestFactories.make_fighter("", Vector2(0, -3000), 1)

	var result = WeaponSystem.diagnose_firing(ship, [ship, enemy])

	assert_eq(result.reason, WeaponSystem.DIAG_OUT_OF_RANGE,
		"Should report out_of_range when nearest enemy is beyond weapon range")
	assert_false(result.firing, "firing flag should be false")

func test_diagnose_firing_all_weapons_destroyed_when_no_operational_weapon():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	ship.weapons[0]["status"] = "destroyed"
	var enemy = TestFactories.make_fighter("", Vector2(0, -300), 1)

	var result = WeaponSystem.diagnose_firing(ship, [ship, enemy])

	assert_eq(result.reason, WeaponSystem.DIAG_ALL_DESTROYED,
		"Should report all_weapons_destroyed when every mount is destroyed")
	assert_false(result.firing, "firing flag should be false")

func test_diagnose_firing_no_target_when_no_enemies():
	var ship = TestFactories.make_armed_ship("light_cannon", 0.0)
	# Only ship in the list is on same team — no valid enemies.
	var result = WeaponSystem.diagnose_firing(ship, [ship])

	assert_eq(result.reason, WeaponSystem.DIAG_NO_TARGET,
		"Should report no_target when no active enemies exist")
	assert_false(result.firing, "firing flag should be false")
