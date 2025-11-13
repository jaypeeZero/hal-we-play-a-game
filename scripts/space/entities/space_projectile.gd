class_name SpaceProjectile
extends IRenderable

## Space combat projectile
## Simple ballistic projectile with lifetime

signal hit_target(target_id: String)
signal projectile_expired()

var damage: int = 0
var velocity: Vector2 = Vector2.ZERO
var source_id: String = ""
var target_id: String = ""
var team: int = 0

var _entity_id: String = ""
var _lifetime: float = 0.0
var _max_lifetime: float = 10.0

static var _next_projectile_id: int = 0

## Initialize projectile
func initialize(fire_command: Dictionary) -> void:
	_entity_id = "projectile_" + str(_next_projectile_id)
	_next_projectile_id += 1

	global_position = fire_command.spawn_position
	velocity = fire_command.velocity
	damage = fire_command.damage
	source_id = fire_command.get("ship_id", "unknown")
	target_id = fire_command.get("target_id", "")

	# Determine team from source
	# TODO: Pass team through fire_command
	team = 0  # Default to player team for now

	# Setup collision
	_setup_collision()

	# Register with visual bridge
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.register_entity(self)

	# Emit initial state
	_emit_state_changed()

## Setup collision detection
func _setup_collision() -> void:
	var area = Area2D.new()
	area.name = "ProjectileArea"
	add_child(area)

	var shape = CircleShape2D.new()
	shape.radius = 3.0  # Small collision radius
	var collision_shape = CollisionShape2D.new()
	collision_shape.shape = shape
	area.add_child(collision_shape)

	# Projectiles only collide with ships of opposite team
	if team == 0:
		area.collision_layer = 32  # Player projectile layer
		area.collision_mask = 8  # Hit enemy ships
	else:
		area.collision_layer = 16  # Enemy projectile layer
		area.collision_mask = 4  # Hit player ships

	# Note: Collision is handled by the ship, not the projectile

## Update projectile position
func _process(delta: float) -> void:
	# Move projectile
	global_position += velocity * delta

	# Update lifetime
	_lifetime += delta
	if _lifetime >= _max_lifetime:
		projectile_expired.emit()
		queue_free()
		return

	# Emit state
	_emit_state_changed()

## Emit state for renderer
func _emit_state_changed() -> void:
	var state = EntityState.new()
	state.velocity = velocity
	state.facing_direction = velocity.normalized()
	state.health_percent = 1.0
	state_changed.emit(state)

## IRenderable implementation
func get_entity_id() -> String:
	return _entity_id

func get_visual_type() -> String:
	return "space_projectile"

## Clean up when freed
func _exit_tree() -> void:
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.unregister_entity(_entity_id)
