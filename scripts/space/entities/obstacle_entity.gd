class_name ObstacleEntity
extends IRenderable

## Minimal obstacle entity for ECS architecture
## Only handles Godot physics/rendering integration
## All logic lives in Systems, all data in obstacle_data Dictionary

var entity_id: String = ""
var obstacle_type: String = ""

var _area: Area2D

## Initialize entity with ID and type for collision
func initialize(id: String, obs_type: String, radius: float) -> void:
	entity_id = id
	obstacle_type = obs_type
	_setup_collision(radius)

	# Register with visual bridge for rendering
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.register_entity(self)

## Setup collision area (neutral - hits all teams)
func _setup_collision(radius: float) -> void:
	_area = Area2D.new()
	_area.name = "CollisionArea"
	add_child(_area)

	var shape = CircleShape2D.new()
	shape.radius = radius
	var collision_shape = CollisionShape2D.new()
	collision_shape.shape = shape
	_area.add_child(collision_shape)

	# Obstacles use layer 64 and collide with all ships and projectiles
	_area.collision_layer = 64  # Obstacle layer
	_area.collision_mask = 4 | 8 | 16 | 32  # All ships and projectiles

## Sync transform from obstacle_data (called by game loop)
func sync_transform(obstacle_data: Dictionary) -> void:
	global_position = obstacle_data.position
	rotation = obstacle_data.rotation

## Emit state for renderer (called by game loop)
func emit_state(obstacle_data: Dictionary) -> void:
	var state = _create_entity_state(obstacle_data)
	state_changed.emit(state)

## Create entity state for renderer
func _create_entity_state(obstacle_data: Dictionary) -> EntityState:
	var state = EntityState.new()
	state.velocity = obstacle_data.get("velocity", Vector2.ZERO)
	state.facing_direction = Vector2.from_angle(obstacle_data.rotation)

	# Calculate health percent
	var max_health = obstacle_data.get("max_health", 100.0)
	var current_health = obstacle_data.get("current_health", 100.0)
	state.health_percent = current_health / max_health if max_health > 0 else 0.0

	# Add status flags based on health
	if state.health_percent <= 0.0:
		state.add_flag("destroyed")
	elif state.health_percent < 0.5:
		state.add_flag("damaged")
	else:
		state.add_flag("operational")

	# Add type-specific flags
	if obstacle_data.get("destructible", true) == false:
		state.add_flag("indestructible")

	return state

## IRenderable implementation
func get_entity_id() -> String:
	return entity_id

func get_visual_type() -> String:
	return "obstacle_" + obstacle_type

## Clean up
func _exit_tree() -> void:
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.unregister_entity(self)
