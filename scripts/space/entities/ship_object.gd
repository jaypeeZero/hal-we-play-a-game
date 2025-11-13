class_name ShipObject
extends IRenderable

## Ship entity in space combat
## Maintains ship state and emits signals for rendering and game events

# Signals
signal ship_hit(damage_info: Dictionary)
signal component_damaged(component_id: String)
signal component_destroyed(component_id: String)
signal weapon_fired(weapon_id: String, fire_command: Dictionary)
signal ship_destroyed()

# Ship data (Dictionary matching ShipData structure)
var ship_data: Dictionary = {}

# Entity tracking
var _entity_id: String = ""
var _visual_type: String = ""

# Update timers
var _weapon_update_timer: float = 0.0
const WEAPON_UPDATE_INTERVAL: float = 0.1  # Update weapons 10 times per second

# Target tracking for AI
var _potential_targets: Array = []

## Initialize ship from data dictionary
func initialize(data: Dictionary) -> void:
	ship_data = data
	_entity_id = data.ship_id
	_visual_type = "ship_" + data.type

	# Set initial position
	global_position = data.position
	rotation = data.rotation

	# Setup collision
	_setup_collision()

	# Register with visual bridge
	if VisualBridgeAutoload.bridge:
		VisualBridgeAutoload.bridge.register_entity(self)

	# Emit initial state
	_emit_state_changed()

## Setup collision areas for the ship
func _setup_collision() -> void:
	# Create main ship collision area
	var area = Area2D.new()
	area.name = "ShipCollisionArea"
	add_child(area)

	var shape = CircleShape2D.new()
	shape.radius = ship_data.stats.size
	var collision_shape = CollisionShape2D.new()
	collision_shape.shape = shape
	area.add_child(collision_shape)

	# Connect collision signal
	area.area_entered.connect(_on_area_entered)

	# Set collision layers (team-based)
	if ship_data.team == 0:
		area.collision_layer = 4  # Player ships
		area.collision_mask = 8 | 16  # Hit by enemy projectiles and ships
	else:
		area.collision_layer = 8  # Enemy ships
		area.collision_mask = 4 | 32  # Hit by player projectiles and ships

## Process ship movement and weapons
func _process(delta: float) -> void:
	if ship_data.is_empty():
		return

	# Update position from ship data
	global_position = ship_data.position
	rotation = ship_data.rotation

	# Update weapons
	_weapon_update_timer += delta
	if _weapon_update_timer >= WEAPON_UPDATE_INTERVAL:
		_weapon_update_timer = 0.0
		_update_weapons(delta)

	# Update movement (basic AI for now)
	_update_movement(delta)

	# Emit state for renderer
	_emit_state_changed()

## Update weapons and fire if possible
func _update_weapons(delta: float) -> void:
	if _potential_targets.is_empty():
		return

	# Use WeaponSystem to get fire commands
	var fire_commands = WeaponSystem.update_weapons(ship_data, _potential_targets, delta)

	for fire_command in fire_commands:
		# Emit signal so orchestrator can spawn projectile
		weapon_fired.emit(fire_command.weapon_id, fire_command)

## Basic movement AI (will be improved later)
func _update_movement(delta: float) -> void:
	if ship_data.status == "disabled" or ship_data.status == "destroyed":
		ship_data.velocity = ship_data.velocity * 0.95  # Drift to stop
		ship_data.position += ship_data.velocity * delta
		return

	# Find nearest enemy
	var target = _find_nearest_enemy()
	if target == null:
		return

	# Simple seek behavior
	var to_target = (target.position - ship_data.position).normalized()
	var desired_velocity = to_target * ship_data.stats.max_speed

	# Steer toward target
	var steering = desired_velocity - ship_data.velocity
	var max_force = ship_data.stats.acceleration * delta
	if steering.length() > max_force:
		steering = steering.normalized() * max_force

	ship_data.velocity += steering

	# Clamp to max speed
	if ship_data.velocity.length() > ship_data.stats.max_speed:
		ship_data.velocity = ship_data.velocity.normalized() * ship_data.stats.max_speed

	# Update position
	ship_data.position += ship_data.velocity * delta

	# Rotate toward movement direction
	var target_rotation = ship_data.velocity.angle()
	ship_data.rotation = lerp_angle(ship_data.rotation, target_rotation, ship_data.stats.turn_rate * delta)

## Find nearest enemy ship
func _find_nearest_enemy() -> Dictionary:
	var nearest = null
	var nearest_distance = INF

	for target in _potential_targets:
		if target.team == ship_data.team:
			continue
		if target.status == "destroyed":
			continue

		var distance = ship_data.position.distance_to(target.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = target

	return nearest if nearest != null else {}

## Set potential targets for weapon systems
func set_targets(targets: Array) -> void:
	_potential_targets = targets

## Handle projectile collision
func _on_area_entered(area: Area2D) -> void:
	# Get the projectile
	var projectile = area.get_parent()
	if not projectile is SpaceProjectile:
		return

	# Get projectile data
	var damage = projectile.damage
	var hit_position = area.global_position

	# Resolve damage using DamageResolver
	var hit_result = DamageResolver.resolve_hit(
		ship_data,
		hit_position,
		damage,
		projectile.global_position.angle_to_point(hit_position)
	)

	# Emit signals based on hit result
	ship_hit.emit(hit_result)

	if hit_result.has("internal_hit"):
		var internal = hit_result.internal_hit
		if internal.old_status == "operational" and internal.new_status == "damaged":
			component_damaged.emit(internal.component_id)
		if internal.new_status == "destroyed":
			component_destroyed.emit(internal.component_id)

	# Check if ship is destroyed
	if DamageResolver.is_ship_destroyed(ship_data):
		ship_data.status = "destroyed"
		ship_destroyed.emit()
		_handle_destruction()

	# Destroy projectile
	projectile.queue_free()

	# Log event
	if BattleEventLoggerAutoload.logger:
		BattleEventLoggerAutoload.logger.log_damage_dealt(
			projectile.source_id if projectile.has("source_id") else "unknown",
			_entity_id,
			damage
		)

## Handle ship destruction
func _handle_destruction() -> void:
	# Emit final state
	_emit_state_changed()

	# TODO: Spawn explosion effect

	# Remove from scene after delay
	await get_tree().create_timer(2.0).timeout
	queue_free()

## Emit state changed signal for renderer
func _emit_state_changed() -> void:
	var state = EntityState.new()

	state.velocity = ship_data.velocity
	state.facing_direction = Vector2.from_angle(ship_data.rotation)

	# Calculate health percent (average of all internal components)
	var total_health = 0.0
	var max_health = 0.0
	for internal in ship_data.internals:
		total_health += internal.current_health
		max_health += internal.max_health

	state.health_percent = total_health / max_health if max_health > 0 else 0.0

	# Add state flags
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

	# Add damage states
	for internal in ship_data.internals:
		if internal.status == "damaged":
			state.status_effects.append(internal.component_id + "_damaged")
		elif internal.status == "destroyed":
			state.status_effects.append(internal.component_id + "_destroyed")

	state_changed.emit(state)

## IRenderable implementation
func get_entity_id() -> String:
	return _entity_id

func get_visual_type() -> String:
	return _visual_type

## Get ship data for external systems
func get_ship_data() -> Dictionary:
	return ship_data

## Take direct damage (for testing or special cases)
func take_damage(amount: int, hit_position: Vector2) -> void:
	var hit_result = DamageResolver.resolve_hit(
		ship_data,
		hit_position,
		amount,
		0.0
	)

	ship_hit.emit(hit_result)

	if DamageResolver.is_ship_destroyed(ship_data):
		ship_data.status = "destroyed"
		ship_destroyed.emit()
		_handle_destruction()
