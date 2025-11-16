extends GutTest

## Tests for obstacle system
## Tests obstacle creation, collision detection, avoidance, and damage

# ============================================================================
# OBSTACLE DATA CREATION TESTS
# ============================================================================

func test_create_small_asteroid():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))

	assert_not_null(obstacle.obstacle_id)
	assert_eq(obstacle.type, "asteroid_small")
	assert_eq(obstacle.radius, 20.0)
	assert_eq(obstacle.max_health, 50.0)
	assert_eq(obstacle.current_health, 50.0)
	assert_true(obstacle.destructible)
	assert_true(obstacle.blocks_movement)
	assert_true(obstacle.blocks_projectiles)

func test_create_medium_asteroid():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(100, 100))

	assert_eq(obstacle.type, "asteroid_medium")
	assert_eq(obstacle.radius, 40.0)
	assert_eq(obstacle.max_health, 150.0)
	assert_true(obstacle.blocks_line_of_sight)

func test_create_large_asteroid():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(100, 100))

	assert_eq(obstacle.type, "asteroid_large")
	assert_eq(obstacle.radius, 80.0)
	assert_eq(obstacle.max_health, 500.0)
	assert_true(obstacle.blocks_line_of_sight)

func test_create_platform():
	var obstacle = ObstacleData.create_obstacle_instance("platform", Vector2(100, 100))

	assert_eq(obstacle.type, "platform")
	assert_eq(obstacle.radius, 60.0)
	assert_false(obstacle.destructible, "Platforms should be indestructible")
	assert_true(obstacle.blocks_movement)

func test_create_dock_scaffolding():
	var obstacle = ObstacleData.create_obstacle_instance("dock_scaffolding", Vector2(100, 100))

	assert_eq(obstacle.type, "dock_scaffolding")
	assert_eq(obstacle.radius, 50.0)
	assert_false(obstacle.blocks_projectiles, "Scaffolding is open structure")
	assert_false(obstacle.blocks_line_of_sight)

func test_create_debris():
	var obstacle = ObstacleData.create_obstacle_instance("debris", Vector2(100, 100))

	assert_eq(obstacle.type, "debris")
	assert_eq(obstacle.radius, 15.0)
	assert_eq(obstacle.max_health, 20.0)
	assert_false(obstacle.blocks_projectiles)

func test_obstacle_unique_ids():
	var obstacle1 = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))
	var obstacle2 = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))

	assert_ne(obstacle1.obstacle_id, obstacle2.obstacle_id, "Each obstacle should have unique ID")

func test_validate_obstacle_data():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))

	assert_true(ObstacleData.validate_obstacle_data(obstacle))

	# Test invalid data
	var invalid = {"obstacle_id": "test"}
	assert_false(ObstacleData.validate_obstacle_data(invalid))

# ============================================================================
# COLLISION DETECTION TESTS
# ============================================================================

func test_projectile_hits_obstacle():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = create_test_projectile(Vector2(100, 100), 0)  # At obstacle center

	var hit = CollisionSystem.find_obstacle_hit_for_projectile(projectile, [obstacle])

	assert_false(hit.is_empty(), "Projectile should hit obstacle")
	assert_eq(hit.obstacle_id, obstacle.obstacle_id)
	assert_eq(hit.projectile_id, projectile.projectile_id)

func test_projectile_misses_obstacle():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = create_test_projectile(Vector2(500, 500), 0)  # Far away

	var hit = CollisionSystem.find_obstacle_hit_for_projectile(projectile, [obstacle])

	assert_true(hit.is_empty(), "Projectile should miss obstacle")

func test_projectile_ignores_non_blocking_obstacle():
	var obstacle = ObstacleData.create_obstacle_instance("debris", Vector2(100, 100))
	var projectile = create_test_projectile(Vector2(100, 100), 0)

	# Debris doesn't block projectiles
	var blocks = CollisionSystem.is_projectile_colliding_with_obstacle(projectile, obstacle)
	assert_false(blocks, "Debris should not block projectiles")

func test_ship_detects_obstacle_collision():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(100, 100))
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)

	var collision = CollisionSystem.find_obstacle_collision_for_ship(ship, [obstacle])

	assert_false(collision.is_empty(), "Ship should detect obstacle collision")
	assert_eq(collision.obstacle_id, obstacle.obstacle_id)

func test_ship_avoids_far_obstacle():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(500, 500))
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)

	var collision = CollisionSystem.find_obstacle_collision_for_ship(ship, [obstacle])

	assert_true(collision.is_empty(), "Ship should not collide with far obstacle")

# ============================================================================
# OBSTACLE DAMAGE TESTS
# ============================================================================

func test_obstacle_takes_damage():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = create_test_projectile(Vector2(100, 100), 0)
	projectile.damage = 25.0

	var result = CollisionSystem.apply_projectile_hits_to_obstacles([obstacle], [projectile], [projectile.projectile_id])
	var updated_obstacle = result.obstacles[0]

	assert_eq(updated_obstacle.current_health, 25.0, "Obstacle should take 25 damage")
	assert_eq(updated_obstacle.status, "damaged")

func test_obstacle_destroyed_by_damage():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = create_test_projectile(Vector2(100, 100), 0)
	projectile.damage = 100.0  # More than obstacle health

	var result = CollisionSystem.apply_projectile_hits_to_obstacles([obstacle], [projectile], [projectile.projectile_id])
	var updated_obstacle = result.obstacles[0]

	assert_true(updated_obstacle.current_health <= 0)
	assert_eq(updated_obstacle.status, "destroyed")

func test_indestructible_obstacle_takes_no_damage():
	var obstacle = ObstacleData.create_obstacle_instance("platform", Vector2(100, 100))
	var initial_health = obstacle.current_health
	var projectile = create_test_projectile(Vector2(100, 100), 0)
	projectile.damage = 100.0

	var result = CollisionSystem.apply_projectile_hits_to_obstacles([obstacle], [projectile], [projectile.projectile_id])
	var updated_obstacle = result.obstacles[0]

	assert_eq(updated_obstacle.current_health, initial_health, "Indestructible obstacle should not take damage")
	assert_ne(updated_obstacle.status, "destroyed")

# ============================================================================
# OBSTACLE AVOIDANCE TESTS
# ============================================================================

func test_ship_avoids_nearby_obstacle():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)  # Moving right

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(200, 100))  # Ahead

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_gt(avoidance_force.length(), 0, "Should generate avoidance force")
	assert_lt(avoidance_force.x, 0, "Should push away from obstacle (negative x)")

func test_ship_ignores_distant_obstacle():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(1000, 100))  # Far away

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_eq(avoidance_force.length(), 0, "Should ignore distant obstacles")

func test_ship_ignores_obstacle_behind():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)  # Moving right

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(50, 100))  # Behind

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	# Should have minimal avoidance for obstacles behind
	assert_lt(avoidance_force.length(), 50, "Should mostly ignore obstacles behind")

func test_ship_emergency_push_when_colliding():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.stats.size = 20.0

	# Obstacle overlapping ship
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(100, 100))

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_gt(avoidance_force.length(), 0, "Should generate emergency push")

func test_ship_avoids_destroyed_obstacles():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(200, 100))
	obstacle.status = "destroyed"

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_eq(avoidance_force.length(), 0, "Should ignore destroyed obstacles")

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

func test_process_collisions_with_obstacles():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	var projectile = create_test_projectile(Vector2(200, 100), 1)
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(200, 100))

	var result = CollisionSystem.process_collisions([ship], [projectile], [obstacle])

	assert_eq(result.projectiles.size(), 0, "Projectile should be destroyed by obstacle")
	assert_eq(result.obstacles.size(), 1, "Obstacle should still exist")
	assert_has(result, "visual_effects")

func test_movement_with_obstacle_avoidance():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	var target = create_test_ship("ship_2", Vector2(300, 100), 1)
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(200, 100))

	var initial_pos = ship.position
	var updated_ship = MovementSystem.update_ship_movement(ship, [ship, target], 0.1, [obstacle])

	# Ship should move but be influenced by obstacle
	assert_ne(updated_ship.position, initial_pos, "Ship should move")
	# The Y position should change as ship tries to go around obstacle
	assert_ne(updated_ship.position.y, initial_pos.y, "Ship should steer around obstacle")

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
			"turn_rate": 3.0,
			"size": 15.0,
			"mass": 50.0
		},
		"armor_sections": [],
		"internals": [
			{
				"component_id": "cockpit",
				"current_health": 20,
				"max_health": 20,
				"status": "operational"
			}
		],
		"weapons": []
	}

func create_test_projectile(pos: Vector2, team: int) -> Dictionary:
	return {
		"projectile_id": "proj_" + str(randi()),
		"position": pos,
		"velocity": Vector2(100, 0),
		"team": team,
		"damage": 10.0,
		"source_id": "ship_test",
		"lifetime": 5.0
	}

# ============================================================================
# PHYSICAL COLLISION TESTS
# ============================================================================

func test_ship_obstacle_collision_applies_momentum():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(100, 0)  # Moving right at 100 units/sec
	ship.stats.mass = 50.0
	ship.stats.size = 15.0

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(115, 100))  # Overlapping
	obstacle.mass = 100.0
	obstacle.radius = 20.0

	var result = CollisionSystem.check_and_resolve_ship_obstacle_collision(ship, obstacle)

	assert_false(result.is_empty(), "Should detect collision")
	assert_lt(result.ship.velocity.x, ship.velocity.x, "Ship should slow down after collision")
	assert_gt(result.ship.velocity.x, 0, "Ship should still be moving forward")

func test_ship_obstacle_collision_moves_asteroid():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(100, 0)  # Moving right
	ship.stats.mass = 100.0
	ship.stats.size = 15.0

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(115, 100))
	obstacle.velocity = Vector2.ZERO  # Stationary

	var result = CollisionSystem.check_and_resolve_ship_obstacle_collision(ship, obstacle)

	assert_false(result.is_empty(), "Should detect collision")
	assert_gt(result.obstacle.velocity.x, 0, "Asteroid should start moving after impact")

func test_ship_obstacle_collision_damage_scales_with_speed():
	var ship_slow = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship_slow.velocity = Vector2(30, 0)  # Slow speed
	ship_slow.stats.mass = 50.0
	ship_slow.stats.size = 15.0

	var obstacle1 = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(115, 100))

	var result_slow = CollisionSystem.check_and_resolve_ship_obstacle_collision(ship_slow, obstacle1)

	var ship_fast = create_test_ship("ship_2", Vector2(100, 100), 0)
	ship_fast.velocity = Vector2(150, 0)  # Fast speed
	ship_fast.stats.mass = 50.0
	ship_fast.stats.size = 15.0

	var obstacle2 = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(115, 100))

	var result_fast = CollisionSystem.check_and_resolve_ship_obstacle_collision(ship_fast, obstacle2)

	# Faster collision should deal more damage
	if not result_slow.is_empty() and not result_fast.is_empty():
		assert_gt(result_fast.event.damage, result_slow.event.damage, "Faster collision should deal more damage")

func test_larger_asteroid_deals_more_damage():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(100, 0)
	ship.stats.mass = 50.0
	ship.stats.size = 15.0

	var small_asteroid = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(115, 100))
	var large_asteroid = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(115, 100))

	var damage_small = CollisionSystem.calculate_collision_damage(ship, small_asteroid, 100.0)
	var damage_large = CollisionSystem.calculate_collision_damage(ship, large_asteroid, 100.0)

	assert_gt(damage_large, damage_small, "Larger asteroid should deal more damage at same impact speed")

func test_no_damage_from_slow_collision():
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.stats.size = 15.0

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(115, 100))

	var damage = CollisionSystem.calculate_collision_damage(ship, obstacle, 10.0)  # Very slow impact

	assert_eq(damage, 0.0, "Very slow collisions should not deal damage")

func test_ship_ship_collision_applies_momentum_to_both():
	var ship1 = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship1.velocity = Vector2(100, 0)  # Moving right
	ship1.stats.mass = 50.0
	ship1.stats.size = 15.0

	var ship2 = create_test_ship("ship_2", Vector2(130, 100), 1)
	ship2.velocity = Vector2(-50, 0)  # Moving left (head-on)
	ship2.stats.mass = 50.0
	ship2.stats.size = 15.0

	var result = CollisionSystem.check_and_resolve_ship_ship_collision(ship1, ship2)

	assert_false(result.is_empty(), "Should detect collision")
	# Both ships should have their velocities changed
	assert_ne(result.ship1.velocity, ship1.velocity, "Ship 1 velocity should change")
	assert_ne(result.ship2.velocity, ship2.velocity, "Ship 2 velocity should change")

func test_heavier_ship_affected_less_by_collision():
	var light_ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	light_ship.velocity = Vector2(100, 0)
	light_ship.stats.mass = 50.0
	light_ship.stats.size = 15.0

	var heavy_ship = create_test_ship("ship_2", Vector2(130, 100), 1)
	heavy_ship.velocity = Vector2.ZERO  # Stationary
	heavy_ship.stats.mass = 200.0  # 4x heavier
	heavy_ship.stats.size = 30.0

	var result = CollisionSystem.check_and_resolve_ship_ship_collision(light_ship, heavy_ship)

	if not result.is_empty():
		var light_velocity_change = (result.ship1.velocity - light_ship.velocity).length()
		var heavy_velocity_change = (result.ship2.velocity - heavy_ship.velocity).length()

		# Lighter ship should experience more velocity change (conservation of momentum)
		assert_gt(light_velocity_change, heavy_velocity_change, "Lighter ship should be affected more")

func test_collision_separates_overlapping_ships():
	var ship1 = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship1.velocity = Vector2(50, 0)
	ship1.stats.size = 15.0

	var ship2 = create_test_ship("ship_2", Vector2(110, 100), 1)  # Overlapping
	ship2.velocity = Vector2.ZERO
	ship2.stats.size = 15.0

	var initial_distance = ship1.position.distance_to(ship2.position)

	var result = CollisionSystem.check_and_resolve_ship_ship_collision(ship1, ship2)

	if not result.is_empty():
		var final_distance = result.ship1.position.distance_to(result.ship2.position)
		var min_distance = ship1.stats.size + ship2.stats.size

		assert_true(final_distance >= min_distance, "Ships should be separated after collision")

func test_moving_apart_ships_not_colliding():
	var ship1 = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship1.velocity = Vector2(-100, 0)  # Moving left
	ship1.stats.size = 15.0

	var ship2 = create_test_ship("ship_2", Vector2(115, 100), 1)
	ship2.velocity = Vector2(100, 0)  # Moving right (away)
	ship2.stats.size = 15.0

	var result = CollisionSystem.check_and_resolve_ship_ship_collision(ship1, ship2)

	assert_true(result.is_empty(), "Ships moving apart should not trigger collision response")

func test_process_physical_collisions_handles_multiple_ships():
	var ship1 = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship1.velocity = Vector2(50, 0)
	ship1.stats.size = 15.0

	var ship2 = create_test_ship("ship_2", Vector2(130, 100), 1)
	ship2.velocity = Vector2.ZERO
	ship2.stats.size = 15.0

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(500, 500))

	var result = CollisionSystem.process_physical_collisions([ship1, ship2], [obstacle])

	assert_eq(result.ships.size(), 2, "Should return all ships")
	assert_eq(result.obstacles.size(), 1, "Should return all obstacles")
	assert_has(result, "collision_events", "Should include collision events")

func test_obstacle_movement_updates_position():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	obstacle.velocity = Vector2(50, 0)  # Moving right

	var updated = MovementSystem.update_obstacle_movement(obstacle, 1.0)  # 1 second

	assert_eq(updated.position.x, 150.0, "Obstacle should move based on velocity")
	assert_eq(updated.position.y, 100.0, "Y position should not change")

func test_stationary_obstacle_doesnt_move():
	var obstacle = ObstacleData.create_obstacle_instance("platform", Vector2(100, 100))
	obstacle.velocity = Vector2.ZERO

	var updated = MovementSystem.update_obstacle_movement(obstacle, 1.0)

	assert_eq(updated.position, Vector2(100, 100), "Stationary obstacle should not move")

func test_destroyed_obstacle_doesnt_update():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	obstacle.velocity = Vector2(50, 0)
	obstacle.status = "destroyed"

	var updated = MovementSystem.update_obstacle_movement(obstacle, 1.0)

	assert_eq(updated.position, Vector2(100, 100), "Destroyed obstacle should not move")
