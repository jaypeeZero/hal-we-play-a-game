class_name ObstacleData
extends RefCounted

## Pure data container and factory for obstacle instances
## Provides templates for Asteroids, Platforms, and Dock Scaffolding

static var _next_obstacle_id: int = 0

## Get obstacle template by type
static func get_obstacle_template(obstacle_type: String) -> Dictionary:
	match obstacle_type:
		"asteroid_small":
			return _create_asteroid_small_template()
		"asteroid_medium":
			return _create_asteroid_medium_template()
		"asteroid_large":
			return _create_asteroid_large_template()
		"platform":
			return _create_platform_template()
		"dock_scaffolding":
			return _create_dock_scaffolding_template()
		"debris":
			return _create_debris_template()
		_:
			push_error("Unknown obstacle type: " + obstacle_type)
			return {}

## Create an obstacle instance from template
static func create_obstacle_instance(obstacle_type: String, position: Vector2, rotation: float = 0.0) -> Dictionary:
	var template = get_obstacle_template(obstacle_type)
	if template.is_empty():
		return {}

	var instance = template.duplicate(true)
	instance.obstacle_id = "obstacle_" + str(_next_obstacle_id)
	_next_obstacle_id += 1
	instance.position = position
	instance.rotation = rotation
	instance.status = "operational"

	return instance

## Validate obstacle data structure
static func validate_obstacle_data(data: Dictionary) -> bool:
	if not data.has("obstacle_id"): return false
	if not data.has("type"): return false
	if not data.has("position"): return false
	if not data.has("radius"): return false
	if not data.has("health"): return false
	return true

## Small Asteroid - 20 radius, low health
static func _create_asteroid_small_template() -> Dictionary:
	return {
		"type": "asteroid_small",
		"name": "Small Asteroid",
		"radius": 20.0,
		"max_health": 50.0,
		"current_health": 50.0,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": true,
		"blocks_line_of_sight": false,  # Small asteroids don't block visibility
		"velocity": Vector2.ZERO,  # Stationary for now
		"angular_velocity": 0.0,
		"mass": 100.0
	}

## Medium Asteroid - 40 radius, medium health
static func _create_asteroid_medium_template() -> Dictionary:
	return {
		"type": "asteroid_medium",
		"name": "Medium Asteroid",
		"radius": 40.0,
		"max_health": 150.0,
		"current_health": 150.0,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": true,
		"blocks_line_of_sight": true,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": 500.0
	}

## Large Asteroid - 80 radius, high health
static func _create_asteroid_large_template() -> Dictionary:
	return {
		"type": "asteroid_large",
		"name": "Large Asteroid",
		"radius": 80.0,
		"max_health": 500.0,
		"current_health": 500.0,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": true,
		"blocks_line_of_sight": true,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": 2000.0
	}

## Platform - 60 radius, indestructible
static func _create_platform_template() -> Dictionary:
	return {
		"type": "platform",
		"name": "Space Platform",
		"radius": 60.0,
		"max_health": 1000.0,
		"current_health": 1000.0,
		"destructible": false,  # Platforms are indestructible
		"blocks_movement": true,
		"blocks_projectiles": true,
		"blocks_line_of_sight": true,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": 5000.0
	}

## Dock Scaffolding - 50 radius, medium health
static func _create_dock_scaffolding_template() -> Dictionary:
	return {
		"type": "dock_scaffolding",
		"name": "Dock Scaffolding",
		"radius": 50.0,
		"max_health": 200.0,
		"current_health": 200.0,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": false,  # Scaffolding is open structure
		"blocks_line_of_sight": false,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": 300.0
	}

## Debris - 15 radius, very low health
static func _create_debris_template() -> Dictionary:
	return {
		"type": "debris",
		"name": "Space Debris",
		"radius": 15.0,
		"max_health": 20.0,
		"current_health": 20.0,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": false,
		"blocks_line_of_sight": false,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": 50.0
	}
