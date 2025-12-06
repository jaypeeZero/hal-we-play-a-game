class_name ObstacleData
extends RefCounted

## Pure data container and factory for obstacle instances
## Provides templates for Asteroids, Platforms, and Dock Scaffolding

# ============================================================================
# OBSTACLE TYPE CONSTANTS - Size/Health/Mass relationships
# ============================================================================

## Asteroid size progression (small -> medium -> large)
const ASTEROID_SMALL_RADIUS = 20.0
const ASTEROID_MEDIUM_RADIUS = 40.0
const ASTEROID_LARGE_RADIUS = 80.0

## Asteroid health scales with size
const ASTEROID_SMALL_HEALTH = 50.0
const ASTEROID_MEDIUM_HEALTH = 150.0
const ASTEROID_LARGE_HEALTH = 500.0

## Asteroid mass scales with size
const ASTEROID_SMALL_MASS = 100.0
const ASTEROID_MEDIUM_MASS = 500.0
const ASTEROID_LARGE_MASS = 2000.0

## Structure sizes
const PLATFORM_RADIUS = 60.0
const PLATFORM_HEALTH = 1000.0
const PLATFORM_MASS = 5000.0

const DOCK_SCAFFOLDING_RADIUS = 50.0
const DOCK_SCAFFOLDING_HEALTH = 200.0
const DOCK_SCAFFOLDING_MASS = 300.0

const DEBRIS_RADIUS = 15.0
const DEBRIS_HEALTH = 20.0
const DEBRIS_MASS = 50.0

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
	if not data.has("current_health"): return false
	return true

## Small Asteroid - low radius, low health
static func _create_asteroid_small_template() -> Dictionary:
	return {
		"type": "asteroid_small",
		"name": "Small Asteroid",
		"radius": ASTEROID_SMALL_RADIUS,
		"max_health": ASTEROID_SMALL_HEALTH,
		"current_health": ASTEROID_SMALL_HEALTH,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": true,
		"blocks_line_of_sight": false,  # Small asteroids don't block visibility
		"velocity": Vector2.ZERO,  # Stationary for now
		"angular_velocity": 0.0,
		"mass": ASTEROID_SMALL_MASS
	}

## Medium Asteroid - medium radius, medium health
static func _create_asteroid_medium_template() -> Dictionary:
	return {
		"type": "asteroid_medium",
		"name": "Medium Asteroid",
		"radius": ASTEROID_MEDIUM_RADIUS,
		"max_health": ASTEROID_MEDIUM_HEALTH,
		"current_health": ASTEROID_MEDIUM_HEALTH,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": true,
		"blocks_line_of_sight": true,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": ASTEROID_MEDIUM_MASS
	}

## Large Asteroid - large radius, high health
static func _create_asteroid_large_template() -> Dictionary:
	return {
		"type": "asteroid_large",
		"name": "Large Asteroid",
		"radius": ASTEROID_LARGE_RADIUS,
		"max_health": ASTEROID_LARGE_HEALTH,
		"current_health": ASTEROID_LARGE_HEALTH,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": true,
		"blocks_line_of_sight": true,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": ASTEROID_LARGE_MASS
	}

## Platform - indestructible structure
static func _create_platform_template() -> Dictionary:
	return {
		"type": "platform",
		"name": "Space Platform",
		"radius": PLATFORM_RADIUS,
		"max_health": PLATFORM_HEALTH,
		"current_health": PLATFORM_HEALTH,
		"destructible": false,  # Platforms are indestructible
		"blocks_movement": true,
		"blocks_projectiles": true,
		"blocks_line_of_sight": true,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": PLATFORM_MASS
	}

## Dock Scaffolding - open structure
static func _create_dock_scaffolding_template() -> Dictionary:
	return {
		"type": "dock_scaffolding",
		"name": "Dock Scaffolding",
		"radius": DOCK_SCAFFOLDING_RADIUS,
		"max_health": DOCK_SCAFFOLDING_HEALTH,
		"current_health": DOCK_SCAFFOLDING_HEALTH,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": false,  # Scaffolding is open structure
		"blocks_line_of_sight": false,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": DOCK_SCAFFOLDING_MASS
	}

## Debris - small fragments
static func _create_debris_template() -> Dictionary:
	return {
		"type": "debris",
		"name": "Space Debris",
		"radius": DEBRIS_RADIUS,
		"max_health": DEBRIS_HEALTH,
		"current_health": DEBRIS_HEALTH,
		"destructible": true,
		"blocks_movement": true,
		"blocks_projectiles": false,
		"blocks_line_of_sight": false,
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0,
		"mass": DEBRIS_MASS
	}
