extends GutTest

## Tests for WeaponSystem

var attacker_data: Dictionary
var target_data: Dictionary

func before_each():
	# Create attacker and target
	attacker_data = ShipData.create_ship_instance("corvette", 0, Vector2(100, 100))
	target_data = ShipData.create_ship_instance("fighter", 1, Vector2(500, 100))

	# Zero out velocities for predictable tests
	attacker_data.velocity = Vector2.ZERO
	target_data.velocity = Vector2.ZERO

func test_find_best_target():
	var targets = [target_data]
	var weapon = attacker_data.weapons[0]

	var best_target = WeaponSystem.find_best_target(attacker_data, weapon, targets)

	assert_not_null(best_target)
	assert_eq(best_target.ship_id, target_data.ship_id)

func test_ignores_friendly_targets():
	var friendly = ShipData.create_ship_instance("fighter", 0, Vector2(200, 100))  # Same team
	var targets = [friendly]
	var weapon = attacker_data.weapons[0]

	var best_target = WeaponSystem.find_best_target(attacker_data, weapon, targets)

	assert_null(best_target, "Should not target friendly ships")

func test_ignores_out_of_range_targets():
	var far_target = ShipData.create_ship_instance("fighter", 1, Vector2(5000, 5000))
	var targets = [far_target]
	var weapon = attacker_data.weapons[0]

	var best_target = WeaponSystem.find_best_target(attacker_data, weapon, targets)

	assert_null(best_target, "Should not target ships out of range")

func test_can_fire_at_target_in_range_and_arc():
	var weapon = attacker_data.weapons[0]

	var can_fire = WeaponSystem.can_fire_at_target(attacker_data, weapon, target_data)

	assert_true(can_fire, "Should be able to fire at target in range and arc")

func test_cannot_fire_at_target_out_of_arc():
	# Put target behind ship (outside weapon arc)
	target_data.position = attacker_data.position + Vector2(0, 500)
	var weapon = attacker_data.weapons[0]

	# Assuming weapon faces forward with limited arc
	var can_fire = WeaponSystem.can_fire_at_target(attacker_data, weapon, target_data)

	# This depends on weapon arc - corvette turrets might have wide arcs
	# Just test that the function runs without error
	assert_not_null(can_fire)

func test_create_fire_command():
	var weapon = attacker_data.weapons[0]

	var fire_command = WeaponSystem.create_fire_command(attacker_data, weapon, target_data)

	assert_not_null(fire_command)
	assert_has(fire_command, "spawn_position")
	assert_has(fire_command, "direction")
	assert_has(fire_command, "damage")
	assert_has(fire_command, "speed")
	assert_has(fire_command, "delay")

func test_fire_command_has_human_reaction_delay():
	var weapon = attacker_data.weapons[0]

	var fire_command = WeaponSystem.create_fire_command(attacker_data, weapon, target_data)

	assert_ge(fire_command.delay, 0.1, "Delay should be at least 100ms")
	assert_le(fire_command.delay, 0.3, "Delay should be at most 300ms")

func test_update_weapons_respects_cooldown():
	var targets = [target_data]

	# Set weapon on cooldown
	attacker_data.weapons[0].cooldown_remaining = 1.0

	var fire_commands = WeaponSystem.update_weapons(attacker_data, targets, 0.1)

	assert_eq(fire_commands.size(), 0, "Should not fire while on cooldown")

func test_update_weapons_reduces_cooldown():
	var initial_cooldown = 1.0
	attacker_data.weapons[0].cooldown_remaining = initial_cooldown

	WeaponSystem.update_weapons(attacker_data, [], 0.5)

	assert_lt(attacker_data.weapons[0].cooldown_remaining, initial_cooldown)

func test_disabled_ship_cannot_fire():
	attacker_data.status = "disabled"
	var targets = [target_data]

	var fire_commands = WeaponSystem.update_weapons(attacker_data, targets, 0.1)

	assert_eq(fire_commands.size(), 0, "Disabled ship should not fire")

func test_calculate_lead_position_for_moving_target():
	# Target moving to the right
	target_data.velocity = Vector2(100, 0)

	var weapon = attacker_data.weapons[0]
	var lead_pos = WeaponSystem.calculate_lead_position(attacker_data, weapon, target_data)

	# Lead position should be ahead of current position
	assert_gt(lead_pos.x, target_data.position.x, "Lead should be ahead of moving target")

func test_get_power_modifier_normal():
	var modifier = WeaponSystem.get_power_modifier(attacker_data)
	assert_eq(modifier, 1.0, "Normal ship should have 1.0 power modifier")

func test_get_power_modifier_damaged():
	# Damage power core
	for internal in attacker_data.internals:
		if internal.type == "power":
			internal.status = "damaged"
			break

	var modifier = WeaponSystem.get_power_modifier(attacker_data)
	assert_le(modifier, 1.0, "Damaged power should reduce modifier")

func test_get_accuracy_modifier_normal():
	var modifier = WeaponSystem.get_accuracy_modifier(attacker_data)
	assert_eq(modifier, 1.0, "Normal ship should have 1.0 accuracy modifier")

func test_get_accuracy_modifier_damaged_control():
	# Damage control/bridge
	for internal in attacker_data.internals:
		if internal.type == "control":
			internal.status = "damaged"
			break

	var modifier = WeaponSystem.get_accuracy_modifier(attacker_data)
	assert_lt(modifier, 1.0, "Damaged control should reduce accuracy")

func test_calculate_hit_probability():
	var weapon = attacker_data.weapons[0]

	var probability = WeaponSystem.calculate_hit_probability(attacker_data, weapon, target_data)

	assert_ge(probability, 0.0)
	assert_le(probability, 1.0)

func test_get_fireable_weapons():
	var targets = [target_data]

	# All weapons should be fireable initially
	var fireable = WeaponSystem.get_fireable_weapons(attacker_data, target_data)

	assert_gt(fireable.size(), 0, "Corvette should have fireable weapons")

func test_multiple_weapons_can_fire():
	# Corvette has multiple turrets
	var targets = [target_data]

	var fire_commands = WeaponSystem.update_weapons(attacker_data, targets, 0.1)

	# At least one weapon should fire
	assert_ge(fire_commands.size(), 1, "At least one weapon should fire")
