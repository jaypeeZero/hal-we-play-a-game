extends GutTest

## Tests for obstacle system - BEHAVIOR-FOCUSED
## Tests obstacle behaviors and relationships, NOT specific data values

# ============================================================================
# OBSTACLE CREATION BEHAVIOR TESTS
# ============================================================================

func test_obstacles_have_unique_ids():
	# BEHAVIOR: Each obstacle instance should have a unique identifier
	var obstacle1 = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))
	var obstacle2 = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))

	assert_ne(obstacle1.obstacle_id, obstacle2.obstacle_id, "Each obstacle should have unique ID")

func test_obstacles_have_required_properties():
	# BEHAVIOR: All obstacles should have essential properties for collision/rendering
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))

	assert_gt(obstacle.radius, 0, "Obstacle should have positive radius")
	assert_gt(obstacle.max_health, 0, "Obstacle should have positive max health")
	assert_eq(obstacle.current_health, obstacle.max_health, "New obstacle should be at full health")
	assert_true(obstacle.has("destructible"), "Obstacle should specify if destructible")
	assert_true(obstacle.has("blocks_movement"), "Obstacle should specify if it blocks movement")
	assert_true(obstacle.has("blocks_projectiles"), "Obstacle should specify if it blocks projectiles")

func test_obstacle_validates_correctly():
	# BEHAVIOR: Validation should pass for properly created obstacles
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))

	assert_true(ObstacleData.validate_obstacle_data(obstacle), "Valid obstacle should pass validation")

func test_invalid_obstacle_fails_validation():
	# BEHAVIOR: Incomplete obstacle data should fail validation
	var invalid = {"obstacle_id": "test"}

	assert_false(ObstacleData.validate_obstacle_data(invalid), "Incomplete obstacle should fail validation")

# ============================================================================
# SIZE/HEALTH/MASS RELATIONSHIP TESTS - Test design intent, not values
# ============================================================================

func test_larger_asteroids_have_more_health():
	# BEHAVIOR: Larger asteroids should be tougher (more health)
	var small = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))
	var medium = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(0, 0))
	var large = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(0, 0))

	assert_gt(medium.max_health, small.max_health, "Medium asteroid should have more health than small")
	assert_gt(large.max_health, medium.max_health, "Large asteroid should have more health than medium")

func test_larger_asteroids_have_bigger_collision_radius():
	# BEHAVIOR: Larger asteroids should have bigger collision areas
	var small = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))
	var medium = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(0, 0))
	var large = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(0, 0))

	assert_gt(medium.radius, small.radius, "Medium asteroid should have bigger radius than small")
	assert_gt(large.radius, medium.radius, "Large asteroid should have bigger radius than medium")

func test_larger_asteroids_have_more_mass():
	# BEHAVIOR: Larger asteroids should be heavier (more inertia in collisions)
	var small = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))
	var medium = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(0, 0))
	var large = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(0, 0))

	assert_gt(medium.mass, small.mass, "Medium asteroid should be heavier than small")
	assert_gt(large.mass, medium.mass, "Large asteroid should be heavier than medium")

func test_platforms_tougher_than_asteroids():
	# BEHAVIOR: Platforms should be more durable than asteroids (structures vs rocks)
	var large_asteroid = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(0, 0))
	var platform = ObstacleData.create_obstacle_instance("platform", Vector2(0, 0))

	assert_gt(platform.max_health, large_asteroid.max_health, "Platform should have more health than large asteroid")

func test_debris_smallest_and_weakest():
	# BEHAVIOR: Debris should be smaller and weaker than small asteroids
	var debris = ObstacleData.create_obstacle_instance("debris", Vector2(0, 0))
	var small_asteroid = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))

	assert_lt(debris.radius, small_asteroid.radius, "Debris should be smaller than small asteroid")
	assert_lt(debris.max_health, small_asteroid.max_health, "Debris should have less health than small asteroid")

# ============================================================================
# DESTRUCTIBILITY BEHAVIOR TESTS
# ============================================================================

func test_platforms_are_indestructible():
	# BEHAVIOR: Platforms should be indestructible structures
	var platform = ObstacleData.create_obstacle_instance("platform", Vector2(0, 0))

	assert_false(platform.destructible, "Platforms should be indestructible")

func test_asteroids_are_destructible():
	# BEHAVIOR: All asteroids should be destructible
	var small = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))
	var medium = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(0, 0))
	var large = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(0, 0))

	assert_true(small.destructible, "Small asteroid should be destructible")
	assert_true(medium.destructible, "Medium asteroid should be destructible")
	assert_true(large.destructible, "Large asteroid should be destructible")

# ============================================================================
# BLOCKING BEHAVIOR TESTS
# ============================================================================

func test_solid_obstacles_block_movement():
	# BEHAVIOR: Solid structures should block ship movement
	var asteroid = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(0, 0))
	var platform = ObstacleData.create_obstacle_instance("platform", Vector2(0, 0))

	assert_true(asteroid.blocks_movement, "Asteroids should block movement")
	assert_true(platform.blocks_movement, "Platforms should block movement")

func test_solid_obstacles_block_projectiles():
	# BEHAVIOR: Solid structures should block projectile fire
	var asteroid_small = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))
	var asteroid_medium = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(0, 0))
	var platform = ObstacleData.create_obstacle_instance("platform", Vector2(0, 0))

	assert_true(asteroid_small.blocks_projectiles, "Small asteroids should block projectiles")
	assert_true(asteroid_medium.blocks_projectiles, "Medium asteroids should block projectiles")
	assert_true(platform.blocks_projectiles, "Platforms should block projectiles")

func test_open_structures_dont_block_projectiles():
	# BEHAVIOR: Open structures like scaffolding shouldn't block shots
	var scaffolding = ObstacleData.create_obstacle_instance("dock_scaffolding", Vector2(0, 0))
	var debris = ObstacleData.create_obstacle_instance("debris", Vector2(0, 0))

	assert_false(scaffolding.blocks_projectiles, "Scaffolding should not block projectiles (open structure)")
	assert_false(debris.blocks_projectiles, "Debris should not block projectiles")

func test_large_obstacles_block_line_of_sight():
	# BEHAVIOR: Large obstacles should block visual line of sight
	var medium = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(0, 0))
	var large = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(0, 0))
	var platform = ObstacleData.create_obstacle_instance("platform", Vector2(0, 0))

	assert_true(medium.blocks_line_of_sight, "Medium asteroids should block line of sight")
	assert_true(large.blocks_line_of_sight, "Large asteroids should block line of sight")
	assert_true(platform.blocks_line_of_sight, "Platforms should block line of sight")

func test_small_obstacles_dont_block_line_of_sight():
	# BEHAVIOR: Small obstacles shouldn't obstruct vision
	var small_asteroid = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))
	var debris = ObstacleData.create_obstacle_instance("debris", Vector2(0, 0))
	var scaffolding = ObstacleData.create_obstacle_instance("dock_scaffolding", Vector2(0, 0))

	assert_false(small_asteroid.blocks_line_of_sight, "Small asteroids should not block line of sight")
	assert_false(debris.blocks_line_of_sight, "Debris should not block line of sight")
	assert_false(scaffolding.blocks_line_of_sight, "Scaffolding should not block line of sight")

# ============================================================================
# COLLISION DETECTION BEHAVIOR TESTS
# ============================================================================

func test_projectile_hits_obstacle_when_overlapping():
	# BEHAVIOR: Projectile should hit obstacle when positions overlap
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = create_test_projectile(Vector2(100, 100), 0)  # At obstacle center

	var hit = CollisionSystem.find_obstacle_hit_for_projectile(projectile, [obstacle])

	assert_false(hit.is_empty(), "Projectile should hit obstacle when overlapping")
	assert_eq(hit.obstacle_id, obstacle.obstacle_id, "Hit should reference correct obstacle")

func test_projectile_misses_distant_obstacle():
	# BEHAVIOR: Projectile should miss obstacle when far away
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = create_test_projectile(Vector2(500, 500), 0)  # Far away

	var hit = CollisionSystem.find_obstacle_hit_for_projectile(projectile, [obstacle])

	assert_true(hit.is_empty(), "Projectile should miss distant obstacle")

func test_projectile_ignores_non_blocking_obstacle():
	# BEHAVIOR: Projectiles should pass through open structures
	var obstacle = ObstacleData.create_obstacle_instance("debris", Vector2(100, 100))
	var projectile = create_test_projectile(Vector2(100, 100), 0)

	var blocks = CollisionSystem.is_projectile_colliding_with_obstacle(projectile, obstacle)

	assert_false(blocks, "Debris should not block projectiles")

func test_ship_detects_obstacle_collision():
	# BEHAVIOR: Ship should detect collision when overlapping obstacle
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(100, 100))
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)

	var collision = CollisionSystem.find_obstacle_collision_for_ship(ship, [obstacle])

	assert_false(collision.is_empty(), "Ship should detect obstacle collision when overlapping")

func test_ship_avoids_far_obstacle():
	# BEHAVIOR: Ship shouldn't collide with distant obstacles
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(500, 500))
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)

	var collision = CollisionSystem.find_obstacle_collision_for_ship(ship, [obstacle])

	assert_true(collision.is_empty(), "Ship should not collide with far obstacle")

# ============================================================================
# OBSTACLE DAMAGE BEHAVIOR TESTS
# ============================================================================

func test_obstacle_takes_damage_from_projectile():
	# BEHAVIOR: Destructible obstacles should take damage from hits
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var initial_health = obstacle.current_health
	var projectile = create_test_projectile(Vector2(100, 100), 0)
	projectile.damage = initial_health / 2  # Half damage

	var result = CollisionSystem.apply_projectile_hits_to_obstacles([obstacle], [projectile], [projectile.projectile_id])
	var updated_obstacle = result.obstacles[0]

	assert_lt(updated_obstacle.current_health, initial_health, "Obstacle should take damage")
	assert_eq(updated_obstacle.status, "damaged", "Damaged obstacle should have damaged status")

func test_obstacle_destroyed_when_health_depleted():
	# BEHAVIOR: Obstacle should be destroyed when health reaches zero
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(100, 100))
	var projectile = create_test_projectile(Vector2(100, 100), 0)
	projectile.damage = obstacle.max_health * 2  # Overkill

	var result = CollisionSystem.apply_projectile_hits_to_obstacles([obstacle], [projectile], [projectile.projectile_id])
	var updated_obstacle = result.obstacles[0]

	assert_true(updated_obstacle.current_health <= 0, "Obstacle health should be depleted")
	assert_eq(updated_obstacle.status, "destroyed", "Depleted obstacle should be destroyed")

func test_indestructible_obstacle_takes_no_damage():
	# BEHAVIOR: Indestructible obstacles should not take damage
	var obstacle = ObstacleData.create_obstacle_instance("platform", Vector2(100, 100))
	var initial_health = obstacle.current_health
	var projectile = create_test_projectile(Vector2(100, 100), 0)
	projectile.damage = 100.0

	var result = CollisionSystem.apply_projectile_hits_to_obstacles([obstacle], [projectile], [projectile.projectile_id])
	var updated_obstacle = result.obstacles[0]

	assert_eq(updated_obstacle.current_health, initial_health, "Indestructible obstacle should not take damage")
	assert_ne(updated_obstacle.status, "destroyed", "Indestructible obstacle should not be destroyed")

# ============================================================================
# OBSTACLE AVOIDANCE BEHAVIOR TESTS
# ============================================================================

func test_ship_generates_avoidance_force_for_nearby_obstacle():
	# BEHAVIOR: Ship should generate avoidance force when obstacle ahead
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)  # Moving right

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(200, 100))  # Ahead

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_gt(avoidance_force.length(), 0, "Should generate avoidance force for nearby obstacle")

func test_ship_ignores_distant_obstacle():
	# BEHAVIOR: Ship shouldn't react to obstacles far away
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(1000, 100))  # Far away

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_eq(avoidance_force.length(), 0, "Should ignore distant obstacles")

func test_ship_ignores_destroyed_obstacles():
	# BEHAVIOR: Ship shouldn't avoid destroyed obstacles
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.velocity = Vector2(50, 0)

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(200, 100))
	obstacle.status = "destroyed"

	var avoidance_force = MovementSystem.calculate_obstacle_avoidance(ship, [obstacle])

	assert_eq(avoidance_force.length(), 0, "Should ignore destroyed obstacles")

# ============================================================================
# PHYSICAL COLLISION BEHAVIOR TESTS
# ============================================================================

func test_collision_damage_scales_with_speed():
	# BEHAVIOR: Faster collisions should cause more damage
	var ship_slow = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship_slow.stats.size = 15.0
	ship_slow.stats.mass = 50.0

	var ship_fast = create_test_ship("ship_2", Vector2(100, 100), 0)
	ship_fast.stats.size = 15.0
	ship_fast.stats.mass = 50.0

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_medium", Vector2(0, 0))

	var damage_slow = CollisionSystem.calculate_collision_damage(ship_slow, obstacle, 30.0)  # Slow
	var damage_fast = CollisionSystem.calculate_collision_damage(ship_fast, obstacle, 150.0)  # Fast

	assert_gt(damage_fast, damage_slow, "Faster collision should deal more damage")

func test_larger_obstacles_deal_more_collision_damage():
	# BEHAVIOR: Colliding with larger obstacles should hurt more
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.stats.size = 15.0
	ship.stats.mass = 50.0

	var small_asteroid = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))
	var large_asteroid = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(0, 0))

	var damage_small = CollisionSystem.calculate_collision_damage(ship, small_asteroid, 100.0)
	var damage_large = CollisionSystem.calculate_collision_damage(ship, large_asteroid, 100.0)

	assert_gt(damage_large, damage_small, "Larger obstacle should deal more damage at same impact speed")

func test_slow_collision_deals_no_damage():
	# BEHAVIOR: Very slow collisions shouldn't cause damage (gentle bump)
	var ship = create_test_ship("ship_1", Vector2(100, 100), 0)
	ship.stats.size = 15.0

	var obstacle = ObstacleData.create_obstacle_instance("asteroid_small", Vector2(0, 0))

	var damage = CollisionSystem.calculate_collision_damage(ship, obstacle, 10.0)  # Very slow

	assert_eq(damage, 0.0, "Very slow collisions should not deal damage")

# ============================================================================
# INTEGRATION BEHAVIOR TESTS
# ============================================================================

func test_movement_with_obstacle_avoidance():
	# BEHAVIOR: Ship should change course to avoid obstacle in path
	var ship = create_test_ship("ship_1", Vector2(0, 0), 0)
	var target = create_test_ship("ship_2", Vector2(2000, 0), 1)  # Far target
	var obstacle = ObstacleData.create_obstacle_instance("asteroid_large", Vector2(500, 0))  # In path

	var direct_heading = atan2(target.position.y - ship.position.y, target.position.x - ship.position.x)
	var updated_ship = MovementSystem.update_ship_movement(ship, [ship, target], 0.1, [obstacle])

	# Pilot should detect obstacle and change heading
	assert_true(updated_ship.has("_pilot_state"), "Should have pilot state")
	var pilot_state = updated_ship._pilot_state
	var heading_changed = abs(pilot_state.desired_heading - direct_heading) > 0.1
	assert_true(heading_changed, "Pilot should change heading to avoid obstacle")

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
