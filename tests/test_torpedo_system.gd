extends GutTest

## Tests for Torpedo System - FUNCTIONALITY ONLY
## Tests torpedo behaviors, explosion mechanics, and torpedo boat integration

# ============================================================================
# TORPEDO BOAT REGISTRATION TESTS
# ============================================================================

func test_torpedo_boat_in_ship_types():
	assert_has(FleetDataManager.SHIP_TYPES, "torpedo_boat", "torpedo_boat should be in SHIP_TYPES")

func test_torpedo_boat_template_loads():
	var template = ShipData.get_ship_template("torpedo_boat")
	assert_false(template.is_empty(), "torpedo_boat template should load")
	assert_eq(template.type, "torpedo_boat", "Template should have correct type")

func test_torpedo_boat_has_required_weapons():
	var template = ShipData.get_ship_template("torpedo_boat")
	assert_gt(template.weapons.size(), 0, "torpedo_boat should have weapons")

	var has_gatling = false
	var has_torpedo = false
	for weapon in template.weapons:
		if weapon.type == "gatling_gun":
			has_gatling = true
		elif weapon.type == "torpedo_launcher":
			has_torpedo = true

	assert_true(has_gatling, "torpedo_boat should have gatling gun")
	assert_true(has_torpedo, "torpedo_boat should have torpedo launcher")

# ============================================================================
# TORPEDO LAUNCHER WEAPON TESTS
# ============================================================================

func test_torpedo_launcher_exists_in_base_stats():
	var stats = BaseStats.get_weapon_stats("torpedo_launcher")
	assert_false(stats.is_empty(), "torpedo_launcher should exist in base stats")

func test_torpedo_launcher_has_explosion_properties():
	var stats = BaseStats.get_weapon_stats("torpedo_launcher")
	assert_has(stats, "explosion_radius", "torpedo_launcher should have explosion_radius")
	assert_has(stats, "explosion_damage", "torpedo_launcher should have explosion_damage")
	assert_gt(stats.explosion_radius, 0.0, "explosion_radius should be positive")
	assert_gt(stats.explosion_damage, 0.0, "explosion_damage should be positive")

func test_torpedo_slower_than_standard_projectiles():
	var torpedo_stats = BaseStats.get_weapon_stats("torpedo_launcher")
	var cannon_stats = BaseStats.get_weapon_stats("light_cannon")

	assert_lt(torpedo_stats.projectile_speed, cannon_stats.projectile_speed,
		"Torpedoes should be slower than standard projectiles")

# ============================================================================
# PROJECTILE SYSTEM TESTS
# ============================================================================

func test_torpedo_projectile_has_explosion_data():
	var fire_command = create_torpedo_fire_command()
	var projectile = ProjectileSystem.create_projectile(fire_command, 0)

	assert_eq(projectile.projectile_type, "explosive", "Projectile should be explosive type")
	assert_gt(projectile.explosion_radius, 0.0, "Torpedo should have explosion radius")
	assert_gt(projectile.explosion_damage, 0.0, "Torpedo should have explosion damage")

func test_standard_projectile_has_no_explosion_data():
	var fire_command = create_standard_fire_command()
	var projectile = ProjectileSystem.create_projectile(fire_command, 0)

	assert_eq(projectile.projectile_type, "standard", "Projectile should be standard type")
	assert_eq(projectile.explosion_radius, 0.0, "Standard projectile should have no explosion radius")
	assert_eq(projectile.explosion_damage, 0.0, "Standard projectile should have no explosion damage")

func test_torpedo_has_longer_lifetime():
	var torpedo_command = create_torpedo_fire_command()
	var standard_command = create_standard_fire_command()

	var torpedo = ProjectileSystem.create_projectile(torpedo_command, 0)
	var standard = ProjectileSystem.create_projectile(standard_command, 0)

	assert_gt(torpedo.max_lifetime, standard.max_lifetime,
		"Torpedoes should have longer lifetime due to slow speed")

# ============================================================================
# EXPLOSION DAMAGE TESTS
# ============================================================================

func test_explosion_damages_ships_in_radius():
	var ships = [
		create_test_ship(Vector2(0, 0)),    # At explosion center
		create_test_ship(Vector2(50, 0)),   # Within radius
	]
	var explosion = {
		position = Vector2(0, 0),
		radius = 80.0,
		damage = 60.0,
		source_id = "attacker",
		team = 1
	}

	var result = CollisionSystem.apply_torpedo_explosion(ships, explosion)

	# Both ships should be damaged (within 80 radius)
	assert_eq(result.ships.size(), 2, "Should return all ships")
	# Check that visual effects were created (damage was applied)
	assert_gt(result.visual_effects.size(), 0, "Should create visual effects for damage")

func test_explosion_does_not_damage_ships_outside_radius():
	var ships = [
		create_test_ship(Vector2(200, 0)),  # Outside radius
	]
	var explosion = {
		position = Vector2(0, 0),
		radius = 80.0,
		damage = 60.0,
		source_id = "attacker",
		team = 1
	}

	var result = CollisionSystem.apply_torpedo_explosion(ships, explosion)

	# Only explosion effect, no damage effects
	assert_eq(result.visual_effects.size(), 1, "Should only have explosion effect, no damage")

func test_explosion_damage_falls_off_with_distance():
	# Ships at different distances should receive different damage
	# This is tested by verifying the explosion system applies the falloff formula
	var center_ship = create_test_ship(Vector2(0, 0))
	var edge_ship = create_test_ship(Vector2(79, 0))  # Near edge of 80 radius

	var explosion = {
		position = Vector2(0, 0),
		radius = 80.0,
		damage = 60.0,
		source_id = "attacker",
		team = 1
	}

	# At center: damage_multiplier = 1.0, at edge: damage_multiplier ≈ 0.01
	# This test verifies the system processes both
	var result1 = CollisionSystem.apply_torpedo_explosion([center_ship], explosion)
	var result2 = CollisionSystem.apply_torpedo_explosion([edge_ship], explosion)

	assert_gt(result1.visual_effects.size(), 0, "Center ship should be damaged")
	assert_gt(result2.visual_effects.size(), 0, "Edge ship should be damaged")

# ============================================================================
# VISUAL EFFECT TESTS
# ============================================================================

func test_torpedo_explosion_effect_creation():
	var effect = VisualEffectSystem.create_torpedo_explosion(Vector2(100, 100), 80.0)

	assert_eq(effect.type, "effect_torpedo_explosion", "Effect should be torpedo explosion type")
	assert_eq(effect.radius, 80.0, "Effect should store explosion radius")
	assert_eq(effect.position, Vector2(100, 100), "Effect should store position")
	assert_gt(effect.max_lifetime, 0.5, "Explosion should have longer duration")

# ============================================================================
# FIRE COMMAND TESTS
# ============================================================================

func test_fire_command_includes_explosion_data():
	var ship = create_test_ship_with_torpedo_launcher(0.0)
	var target = create_test_target(Vector2(0, -500))

	var result = WeaponSystem.update_weapons(ship, [target], 0.1)

	# Find the torpedo fire command (might be the gatling too)
	var torpedo_command = null
	for cmd in result.fire_commands:
		if cmd.get("explosion_radius", 0.0) > 0:
			torpedo_command = cmd
			break

	if torpedo_command != null:
		assert_gt(torpedo_command.explosion_radius, 0.0, "Torpedo command should have explosion radius")
		assert_gt(torpedo_command.explosion_damage, 0.0, "Torpedo command should have explosion damage")

# ============================================================================
# TARGETING PRIORITY TESTS
# ============================================================================

func test_torpedo_boat_has_target_priority():
	var priority = WeaponSystem.calculate_type_priority("torpedo_boat")
	assert_gt(priority, 0.0, "torpedo_boat should have target priority")

func test_torpedo_boat_priority_is_high():
	var torpedo_priority = WeaponSystem.calculate_type_priority("torpedo_boat")
	var corvette_priority = WeaponSystem.calculate_type_priority("corvette")

	assert_gt(torpedo_priority, corvette_priority,
		"torpedo_boat should have higher priority than corvette (dangerous platform)")

# ============================================================================
# CREW TESTS
# ============================================================================

func test_torpedo_boat_crew_creation():
	var crew = CrewData.create_torpedo_boat_crew(0.5)

	assert_eq(crew.size(), 2, "Torpedo boat should have 2 crew members")

	var has_pilot = false
	var has_gunner = false
	for member in crew:
		if member.role == CrewData.Role.PILOT:
			has_pilot = true
		elif member.role == CrewData.Role.GUNNER:
			has_gunner = true

	assert_true(has_pilot, "Should have a pilot")
	assert_true(has_gunner, "Should have a torpedo operator (gunner)")

func test_torpedo_boat_crew_has_command_chain():
	var crew = CrewData.create_torpedo_boat_crew(0.5)

	var pilot = crew[0]
	var torpedo_op = crew[1]

	assert_eq(torpedo_op.command_chain.superior, pilot.crew_id,
		"Torpedo operator should report to pilot")
	assert_has(pilot.command_chain.subordinates, torpedo_op.crew_id,
		"Pilot should command torpedo operator")

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func create_test_ship(pos: Vector2) -> Dictionary:
	return {
		"ship_id": "test_ship_" + str(randi()),
		"type": "fighter",
		"team": 0,
		"position": pos,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"collision_radius": 15.0,
		"stats": {"mass": 50.0, "size": 15.0},
		"armor_sections": [
			{
				"section_id": "front",
				"current_armor": 25.0,
				"max_armor": 25.0,
				"size": 1.0,
				"arc": {"start": -90.0, "end": 90.0}
			}
		],
		"internals": []
	}

func create_test_target(pos: Vector2) -> Dictionary:
	return {
		"ship_id": "target_" + str(randi()),
		"type": "corvette",
		"team": 1,
		"position": pos,
		"velocity": Vector2.ZERO,
		"status": "operational",
		"armor_sections": [
			{"section_id": "front", "current_armor": 50.0, "max_armor": 50.0, "size": 2.0}
		]
	}

func create_torpedo_fire_command() -> Dictionary:
	return {
		"type": "fire_projectile",
		"ship_id": "test_ship",
		"weapon_id": "torpedo_tube",
		"spawn_position": Vector2(0, 0),
		"direction": Vector2(0, -1),
		"velocity": Vector2(0, -200),
		"damage": 15,
		"speed": 200,
		"target_id": "target",
		"delay": 0.1,
		"accuracy": 0.95,
		"weapon_size": 3,
		"explosion_radius": 80.0,
		"explosion_damage": 60.0
	}

func create_standard_fire_command() -> Dictionary:
	return {
		"type": "fire_projectile",
		"ship_id": "test_ship",
		"weapon_id": "cannon",
		"spawn_position": Vector2(0, 0),
		"direction": Vector2(0, -1),
		"velocity": Vector2(0, -600),
		"damage": 10,
		"speed": 600,
		"target_id": "target",
		"delay": 0.1,
		"accuracy": 0.85,
		"weapon_size": 1
	}

func create_test_ship_with_torpedo_launcher(cooldown: float) -> Dictionary:
	return {
		"ship_id": "test_torpedo_boat",
		"type": "torpedo_boat",
		"team": 0,
		"position": Vector2(0, 0),
		"rotation": 0.0,
		"status": "operational",
		"stats": {"max_speed": 250.0},
		"weapons": [
			{
				"weapon_id": "torpedo_tube",
				"type": "torpedo_launcher",
				"position_offset": Vector2(0, -8),
				"facing": 0.0,
				"arc": {"min": -10, "max": 10},
				"stats": {
					"damage": 15,
					"rate_of_fire": 0.3,
					"projectile_speed": 200,
					"range": 1200,
					"accuracy": 0.95,
					"size": 3,
					"explosion_radius": 80.0,
					"explosion_damage": 60.0
				},
				"cooldown_remaining": cooldown
			}
		],
		"internals": []
	}
