class_name ProjectileEntity
extends Node2D

## Minimal projectile entity for ECS architecture
## Only handles Godot physics/rendering integration
## All logic lives in Systems, all data in projectile_data Dictionary

var entity_id: String = ""
var team: int = 0

var _area: Area2D

## Initialize entity with ID and team for collision layers
func initialize(id: String, projectile_team: int) -> void:
	entity_id = id
	team = projectile_team
	_setup_collision()

	# Register with visual bridge for rendering
	if VisualBridgeAutoload.bridge:
		var renderable = _create_renderable()
		VisualBridgeAutoload.bridge.register_entity(renderable)

## Setup collision area
func _setup_collision() -> void:
	_area = Area2D.new()
	_area.name = "CollisionArea"
	add_child(_area)

	var shape = CircleShape2D.new()
	shape.radius = 3.0  # Small collision radius
	var collision_shape = CollisionShape2D.new()
	collision_shape.shape = shape
	_area.add_child(collision_shape)

	# Set collision layers based on team
	if team == 0:
		_area.collision_layer = 32  # Player projectile layer
		_area.collision_mask = 8  # Hit enemy ships
	else:
		_area.collision_layer = 16  # Enemy projectile layer
		_area.collision_mask = 4  # Hit player ships

## Sync transform from projectile_data (called by game loop)
func sync_transform(projectile_data: Dictionary) -> void:
	global_position = projectile_data.position

## Emit state for renderer (called by game loop)
func emit_state(projectile_data: Dictionary) -> void:
	if VisualBridgeAutoload.bridge:
		var state = _create_entity_state(projectile_data)
		var renderable = _create_renderable()
		renderable.state_changed.emit(state)

## Create renderable wrapper for visual bridge
func _create_renderable() -> IRenderable:
	var renderable = ProjectileRenderable.new()
	renderable.entity_id = entity_id
	renderable.node_position = global_position
	return renderable

## Create entity state for renderer
func _create_entity_state(projectile_data: Dictionary) -> EntityState:
	var state = EntityState.new()
	state.velocity = projectile_data.velocity
	state.facing_direction = projectile_data.velocity.normalized()
	state.health_percent = 1.0
	return state

## Clean up
func _exit_tree() -> void:
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.unregister_entity(entity_id)

# ============================================================================
# Minimal IRenderable Implementation
# ============================================================================

class ProjectileRenderable extends IRenderable:
	var entity_id: String
	var node_position: Vector2

	func get_entity_id() -> String:
		return entity_id

	func get_visual_type() -> String:
		return "space_projectile"

	func _process(_delta: float) -> void:
		global_position = node_position
