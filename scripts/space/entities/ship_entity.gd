class_name ShipEntity
extends IRenderable

## Minimal ship entity for ECS architecture
## Only handles Godot physics/rendering integration
## All logic lives in Systems, all data in ship_data Dictionary

var entity_id: String = ""
var team: int = 0

var _area: Area2D

## Initialize entity with ID and team for collision layers
func initialize(id: String, ship_team: int, size: float) -> void:
	entity_id = id
	team = ship_team
	_setup_collision(size)

	# Register with visual bridge for rendering
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.register_entity(self)

## Setup collision area
func _setup_collision(size: float) -> void:
	_area = Area2D.new()
	_area.name = "CollisionArea"
	add_child(_area)

	var shape = CircleShape2D.new()
	shape.radius = size
	var collision_shape = CollisionShape2D.new()
	collision_shape.shape = shape
	_area.add_child(collision_shape)

	# Set collision layers based on team
	if team == 0:
		_area.collision_layer = 4  # Player ships
		_area.collision_mask = 8 | 16  # Hit by enemy projectiles and ships
	else:
		_area.collision_layer = 8  # Enemy ships
		_area.collision_mask = 4 | 32  # Hit by player projectiles and ships

## Sync transform from ship_data (called by game loop)
func sync_transform(ship_data: Dictionary) -> void:
	global_position = ship_data.position
	rotation = ship_data.rotation

## Emit state for renderer (called by game loop)
func emit_state(ship_data: Dictionary) -> void:
	var state = _create_entity_state(ship_data)
	state_changed.emit(state)

## Create entity state for renderer
func _create_entity_state(ship_data: Dictionary) -> EntityState:
	var state = EntityState.new()
	state.velocity = ship_data.velocity
	state.facing_direction = Vector2.from_angle(ship_data.rotation)

	# Calculate health percent
	var total_health = 0.0
	var max_health = 0.0
	for internal in ship_data.internals:
		total_health += internal.current_health
		max_health += internal.max_health

	state.health_percent = total_health / max_health if max_health > 0 else 0.0

	# Add status flags
	match ship_data.status:
		"operational":
			if ship_data.velocity.length() > 10:
				state.add_flag("moving")
		"damaged":
			state.add_flag("damaged")
		"disabled":
			state.add_flag("disabled")
		"destroyed":
			state.add_flag("destroyed")

	# Add component status effects
	for internal in ship_data.internals:
		if internal.status == "damaged":
			state.status_effects.append(internal.component_id + "_damaged")
		elif internal.status == "destroyed":
			state.status_effects.append(internal.component_id + "_destroyed")

	return state

## IRenderable implementation
func get_entity_id() -> String:
	return entity_id

func get_visual_type() -> String:
	return "ship"

## Clean up
func _exit_tree() -> void:
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.unregister_entity(self)
