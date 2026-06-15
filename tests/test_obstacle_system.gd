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
	assert_gt(obstacle.radius, 0.0, "Obstacle radius should be positive")
	assert_gt(obstacle.max_health, 0.0, "Destructible obstacle should have positive health")
	assert_eq(obstacle.current_health, obstacle.max_health, "Obstacle should spawn at full health")
	assert_true(obstacle.destructible)
	assert_true(obstacle.blocks_movement)
	assert_true(obstacle.blocks_projectiles)

func test_asteroid_size_classes_scale_radius_and_health():
	# BEHAVIOR: bigger asteroid classes are physically larger and tougher
	var small = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var medium = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(100, 100))
	var large = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(100, 100))

	assert_gt(medium.radius, small.radius, "Medium asteroid should be larger than small")
	assert_gt(medium.max_health, small.max_health, "Medium asteroid should be tougher than small")
	assert_gt(large.radius, medium.radius, "Large asteroid should be larger than medium")
	assert_gt(large.max_health, medium.max_health, "Large asteroid should be tougher than medium")

func test_create_medium_asteroid():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(100, 100))

	assert_eq(obstacle.type, "asteroid_medium")
	assert_true(obstacle.blocks_line_of_sight)

func test_create_large_asteroid():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(100, 100))

	assert_eq(obstacle.type, "asteroid_large")
	assert_true(obstacle.blocks_line_of_sight)

func test_create_platform():
	var obstacle = ObstacleData.create_obstacle_instance("platform", Vector2(100, 100))

	assert_eq(obstacle.type, "platform")
	assert_gt(obstacle.radius, 0.0, "Platform radius should be positive")
	assert_false(obstacle.destructible, "Platforms should be indestructible")
	assert_true(obstacle.blocks_movement)

func test_create_dock_scaffolding():
	var obstacle = ObstacleData.create_obstacle_instance("dock_scaffolding", Vector2(100, 100))

	assert_eq(obstacle.type, "dock_scaffolding")
	assert_gt(obstacle.radius, 0.0, "Scaffolding radius should be positive")
	assert_false(obstacle.blocks_projectiles, "Scaffolding is open structure")
	assert_false(obstacle.blocks_line_of_sight)

func test_create_debris():
	var small = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var obstacle = ObstacleData.create_obstacle_instance("debris", Vector2(100, 100))

	assert_eq(obstacle.type, "debris")
	assert_gt(obstacle.radius, 0.0, "Debris radius should be positive")
	assert_lt(obstacle.radius, small.radius, "Debris should be smaller than the smallest asteroid")
	assert_gt(obstacle.max_health, 0.0, "Debris should have positive health")
	assert_lt(obstacle.max_health, small.max_health, "Debris should be flimsier than the smallest asteroid")
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
	var projectile = TestFactories.make_projectile(Vector2(100, 100), 0)  # At obstacle center

	var hit = CollisionSystem.find_obstacle_hit_for_projectile(projectile, [obstacle])

	assert_false(hit.is_empty(), "Projectile should hit obstacle")
	assert_eq(hit.obstacle_id, obstacle.obstacle_id)
	assert_eq(hit.projectile_id, projectile.projectile_id)

func test_projectile_misses_obstacle():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = TestFactories.make_projectile(Vector2(500, 500), 0)  # Far away

	var hit = CollisionSystem.find_obstacle_hit_for_projectile(projectile, [obstacle])

	assert_true(hit.is_empty(), "Projectile should miss obstacle")

func test_projectile_ignores_non_blocking_obstacle():
	var obstacle = ObstacleData.create_obstacle_instance("debris", Vector2(100, 100))
	var projectile = TestFactories.make_projectile(Vector2(100, 100), 0)

	# Debris doesn't block projectiles
	var blocks = CollisionSystem.is_projectile_colliding_with_obstacle(projectile, obstacle)
	assert_false(blocks, "Debris should not block projectiles")

func test_ship_detects_obstacle_collision():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(100, 100))
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)

	var collision = CollisionSystem.find_obstacle_collision_for_ship(ship, [obstacle])

	assert_false(collision.is_empty(), "Ship should detect obstacle collision")
	assert_eq(collision.obstacle_id, obstacle.obstacle_id)

func test_ship_avoids_far_obstacle():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(500, 500))
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)

	var collision = CollisionSystem.find_obstacle_collision_for_ship(ship, [obstacle])

	assert_true(collision.is_empty(), "Ship should not collide with far obstacle")

# ============================================================================
# OBSTACLE DAMAGE TESTS
# ============================================================================

func test_obstacle_takes_damage():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = TestFactories.make_projectile(Vector2(100, 100), 0)
	projectile.damage = obstacle.max_health / 2.0  # Damaging but not destroying

	var result = CollisionSystem.apply_projectile_hits_to_obstacles([obstacle], [projectile], [projectile.projectile_id])
	var updated_obstacle = result.obstacles[0]

	assert_eq(updated_obstacle.current_health, obstacle.current_health - projectile.damage,
		"Obstacle health should drop by projectile damage")
	assert_eq(updated_obstacle.status, "damaged")

func test_obstacle_destroyed_by_damage():
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = TestFactories.make_projectile(Vector2(100, 100), 0)
	projectile.damage = obstacle.max_health * 2.0  # More than obstacle health

	var result = CollisionSystem.apply_projectile_hits_to_obstacles([obstacle], [projectile], [projectile.projectile_id])
	var updated_obstacle = result.obstacles[0]

	assert_true(updated_obstacle.current_health <= 0.0)
	assert_eq(updated_obstacle.status, "destroyed")

func test_indestructible_obstacle_takes_no_damage():
	var obstacle = ObstacleData.create_obstacle_instance("platform", Vector2(100, 100))
	var initial_health = obstacle.current_health
	var projectile = TestFactories.make_projectile(Vector2(100, 100), 0)
	projectile.damage = 100.0

	var result = CollisionSystem.apply_projectile_hits_to_obstacles([obstacle], [projectile], [projectile.projectile_id])
	var updated_obstacle = result.obstacles[0]

	assert_eq(updated_obstacle.current_health, initial_health, "Indestructible obstacle should not take damage")
	assert_ne(updated_obstacle.status, "destroyed")

# ============================================================================
# OBSTACLE AVOIDANCE TESTS
# ============================================================================

func test_ship_avoids_nearby_obstacle():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)  # Moving right

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(200, 100))  # Ahead

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_gt(avoidance_force.length(), 0.0, "Should generate avoidance force")
	assert_lt(avoidance_force.x, 0.0, "Should push away from obstacle (negative x)")

func test_ship_ignores_distant_obstacle():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(1000, 100))  # Far away

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_eq(avoidance_force.length(), 0.0, "Should ignore distant obstacles")

func test_ship_ignores_obstacle_behind():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)  # Moving right

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(50, 100))  # Behind

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	# Should have minimal avoidance for obstacles behind
	assert_lt(avoidance_force.length(), 50.0, "Should mostly ignore obstacles behind")

func test_ship_emergency_push_when_colliding():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship.stats.size = 20.0
	ship.collision_radius = 20.0

	# Obstacle overlapping ship
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(100, 100))

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_gt(avoidance_force.length(), 0.0, "Should generate emergency push")

func test_ship_avoids_destroyed_obstacles():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(200, 100))
	obstacle.status = "destroyed"

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_eq(avoidance_force.length(), 0.0, "Should ignore destroyed obstacles")

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

func test_process_collisions_with_obstacles():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	var projectile = TestFactories.make_projectile(Vector2(200, 100), 1)
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(200, 100))

	var result = CollisionSystem.process_collisions([ship], [projectile], [obstacle])

	assert_eq(result.projectiles.size(), 0, "Projectile should be destroyed by obstacle")
	assert_eq(result.obstacles.size(), 1, "Obstacle should still exist")
	assert_has(result, "visual_effects")

func test_movement_with_obstacle_avoidance():
	# BEHAVIOR: When an obstacle is in the path to target, pilot detects it and changes course to avoid
	var ship = TestFactories.make_fighter("ship_1", Vector2(0, 0), 0)
	ship.velocity = Vector2(100, 0)  # Moving toward obstacle for detection
	var target = TestFactories.make_fighter("ship_2", Vector2(2000, 0), 1)  # Far target

	# Detection range is collision_radius * 8.0, place obstacle within detection range
	var detection_range = ship.collision_radius * 8.0
	var obstacle_distance = detection_range * 0.5  # Well within detection range
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(obstacle_distance, 0))  # In direct path

	var direct_heading = atan2(target.position.y - ship.position.y, target.position.x - ship.position.x)
	var updated_ship = MovementSystem.update_ship_movement(ship, [ship, target], 0.1, 0.0, [obstacle])

	# Pilot state should contain obstacle avoidance information
	assert_true(updated_ship.has("_pilot_state"), "Should have pilot state")
	var pilot_state = updated_ship._pilot_state
	# When obstacle is detected, pilot changes heading away from direct approach
	# The heading should differ from the direct approach to the target
	var heading_changed = abs(pilot_state.desired_heading - direct_heading) > 0.1
	assert_true(heading_changed, "Pilot should change heading to avoid obstacle")

# ============================================================================
# PHYSICAL COLLISION TESTS
# ============================================================================

func test_ship_obstacle_collision_applies_momentum():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(100, 0)  # Moving right at 100 units/sec
	ship.stats.mass = 50.0
	ship.stats.size = 15.0
	ship.collision_radius = 15.0

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(115, 100))  # Overlapping
	obstacle.mass = 100.0
	obstacle.radius = 20.0

	var result = CollisionSystem.check_and_resolve_ship_obstacle_collision(ship, obstacle)

	assert_false(result.is_empty(), "Should detect collision")
	assert_lt(result.ship.velocity.x, ship.velocity.x, "Ship should slow down after collision")
	assert_gt(result.ship.velocity.x, 0.0, "Ship should still be moving forward")

func test_ship_obstacle_collision_moves_asteroid():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(100, 0)  # Moving right
	ship.stats.mass = 100.0
	ship.stats.size = 15.0
	ship.collision_radius = 15.0

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(115, 100))
	obstacle.velocity = Vector2.ZERO  # Stationary

	var result = CollisionSystem.check_and_resolve_ship_obstacle_collision(ship, obstacle)

	assert_false(result.is_empty(), "Should detect collision")
	assert_gt(result.obstacle.velocity.x, 0.0, "Asteroid should start moving after impact")

func test_ship_obstacle_collision_damage_scales_with_speed():
	var ship_slow = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship_slow.velocity = Vector2(30, 0)  # Slow speed
	ship_slow.stats.mass = 50.0
	ship_slow.stats.size = 15.0
	ship_slow.collision_radius = 15.0

	var obstacle1 = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(115, 100))

	var result_slow = CollisionSystem.check_and_resolve_ship_obstacle_collision(ship_slow, obstacle1)

	var ship_fast = TestFactories.make_fighter("ship_2", Vector2(100, 100), 0)
	ship_fast.velocity = Vector2(150, 0)  # Fast speed
	ship_fast.stats.mass = 50.0
	ship_fast.stats.size = 15.0
	ship_fast.collision_radius = 15.0

	var obstacle2 = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(115, 100))

	var result_fast = CollisionSystem.check_and_resolve_ship_obstacle_collision(ship_fast, obstacle2)

	# Faster collision should deal more damage
	if not result_slow.is_empty() and not result_fast.is_empty():
		assert_gt(result_fast.event.damage, result_slow.event.damage, "Faster collision should deal more damage")

func test_larger_asteroid_deals_more_damage():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(100, 0)
	ship.stats.mass = 50.0
	ship.stats.size = 15.0
	ship.collision_radius = 15.0

	var small_asteroid = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(115, 100))
	var large_asteroid = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(115, 100))

	var damage_small = CollisionSystem.calculate_collision_damage(ship, small_asteroid, 100.0)
	var damage_large = CollisionSystem.calculate_collision_damage(ship, large_asteroid, 100.0)

	assert_gt(damage_large, damage_small, "Larger asteroid should deal more damage at same impact speed")

func test_no_damage_from_slow_collision():
	var ship = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship.stats.size = 15.0
	ship.collision_radius = 15.0

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(115, 100))

	var damage = CollisionSystem.calculate_collision_damage(ship, obstacle, 10.0)  # Very slow impact

	assert_eq(damage, 0.0, "Very slow collisions should not deal damage")

func test_overlapping_ships_pass_through_each_other():
	# Ship-ship collisions are not physically resolved: ships keep their
	# velocity and position even when fully overlapping (the AI steers to
	# avoid each other instead).
	var ship1 = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship1.velocity = Vector2(100, 0)  # Moving right
	ship1.stats.mass = 50.0
	ship1.stats.size = 15.0
	ship1.collision_radius = 15.0

	var ship2 = TestFactories.make_fighter("ship_2", Vector2(110, 100), 1)  # Overlapping
	ship2.velocity = Vector2(-50, 0)  # Moving left (head-on)
	ship2.stats.mass = 50.0
	ship2.stats.size = 15.0
	ship2.collision_radius = 15.0

	var result = CollisionSystem.process_physical_collisions([ship1, ship2], [])

	assert_eq(result.ships[0].velocity, ship1.velocity, "Ship 1 velocity should be unchanged")
	assert_eq(result.ships[1].velocity, ship2.velocity, "Ship 2 velocity should be unchanged")
	assert_eq(result.ships[0].position, ship1.position, "Ship 1 position should be unchanged")
	assert_eq(result.ships[1].position, ship2.position, "Ship 2 position should be unchanged")
	assert_eq(result.collision_events.size(), 0, "No ship-ship collision events should be emitted")

func test_process_physical_collisions_handles_multiple_ships():
	var ship1 = TestFactories.make_fighter("ship_1", Vector2(100, 100), 0)
	ship1.velocity = Vector2(50, 0)
	ship1.stats.size = 15.0
	ship1.collision_radius = 15.0

	var ship2 = TestFactories.make_fighter("ship_2", Vector2(130, 100), 1)
	ship2.velocity = Vector2.ZERO
	ship2.stats.size = 15.0
	ship2.collision_radius = 15.0

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
