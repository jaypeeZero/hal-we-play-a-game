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
			"size": 15.0
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
