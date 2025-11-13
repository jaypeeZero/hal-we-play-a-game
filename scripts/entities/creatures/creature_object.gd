extends BattlefieldObject
class_name CreatureObject

const SteeringBehaviors = preload("res://scripts/core/ai/steering_behaviors.gd")
const CollisionUtils = preload("res://scripts/core/utilities/collision_utils.gd")
const MovementController = preload("res://scripts/core/movement/movement_controller.gd")
const AIController = preload("res://scripts/core/ai/ai_controller.gd")
const AIPersonalityScript = preload("res://scripts/core/ai/ai_personality.gd")

# Signals
signal damaged(amount: float)
signal died()
signal hit_target(target: Node2D)
signal spell_cast(target_position: Vector2)

# Health properties
@export var max_health: float = 100.0
var health_component: HealthComponent

# Unit-specific properties
var owner_id: int = -1  # Track which player cast this
var coordination_group_id: String = ""  # Tactical coordination group (for pack/swarm behavior)
var attack_target: Node2D = null

# Movement properties
var speed: float = 100.0
var direction: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO

# Lifetime management
const MAX_LIFETIME = 10.0
var lifetime: float = 0.0
const UNIT_ARRIVAL_THRESHOLD = 10.0

# Unit-specific properties
var hit_box: Area2D

# Creature type name for visual_type
var creature_type_name: String = "generic"

# Dynamic targeting
var dynamic_target: Node2D = null
var _enemy_player: PlayerCharacter = null
const TARGET_UPDATE_INTERVAL = 0.5
var _target_update_timer: float = 0.0

# Movement system
var movement_controller: MovementController = null

# AI system (optional, falls back to simple behavior if not configured)
var ai_controller: AIController = null

# Current AI behavior state flag (for visual system)
var _current_ai_state_flag: String = ""

# Tactical intelligence system (event-driven coordination)
var signal_cooldown: float = 0.0
const SIGNAL_INTERVAL: float = 0.5  # Emit tactical signals every 0.5 seconds

# Health threshold signaling (0 = disabled)
var near_death_threshold: float = 0.0
var _has_emitted_near_death: bool = false

func _ready() -> void:
	# Health component will be set up in initialize
	pass

func initialize(data: Dictionary, target_pos: Vector2, enemy_player: PlayerCharacter = null) -> void:
	super.initialize(data, target_pos)
	speed = data.get("speed", 100.0)
	_enemy_player = enemy_player

	# Set visual type based on creature data
	creature_type_name = data.get("creature_type", "generic")
	visual_type = "creature_%s" % creature_type_name
	entity_id = "creature_%s" % _generate_unique_id()

	# Initialize movement controller (moved from _ready to work in tests)
	if not movement_controller:
		movement_controller = MovementController.new()
		add_child(movement_controller)

	# Setup AI if configuration exists
	var ai_config: Variant = data.get("ai_config", null)
	if ai_config:
		var personality = AIPersonalityScript.from_data(ai_config)
		ai_controller = AIController.new(self, personality)
		_connect_ai_signals()

	_setup_collision(data)

	# Setup Health Component
	health_component = HealthComponent.new()
	health_component.max_health = data.get("max_health", 50.0)
	health_component.health = health_component.max_health  # Explicitly initialize health
	add_child(health_component)

	add_to_group("creatures")
	add_to_group("combatants")
	health_component.died.connect(_on_unit_died)
	health_component.health_changed.connect(_on_health_changed)
	_update_direction()
	_update_target_priority()
	spell_cast.emit(target_pos)

	# Emit initial state
	_emit_creature_state()

func _setup_collision(data: Dictionary) -> void:
	hit_box = Area2D.new()
	hit_box.name = "HitBox"
	add_child(hit_box)

	# Creature exists on CREATURE layer and detects both TERRAIN and CREATURE layers
	hit_box.collision_layer = CollisionLayers.CREATURE_COLLISION_LAYER
	hit_box.collision_mask = CollisionLayers.CREATURE_COLLISION_MASK

	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = get_collision_radius_for_visual_type()
	collision_shape.shape = shape
	hit_box.add_child(collision_shape)

	hit_box.area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	# Lifetime limit
	lifetime += delta
	if lifetime > MAX_LIFETIME:
		queue_free()
		return

	# Update AI controller if available
	if ai_controller:
		ai_controller.update(delta)

	# Emit tactical signals periodically (event-driven coordination)
	signal_cooldown -= delta
	if signal_cooldown <= 0.0:
		_emit_tactical_signals()
		signal_cooldown = SIGNAL_INTERVAL

	# Update targeting periodically (event-driven via _on_target_acquired)
	_target_update_timer += delta
	if _target_update_timer >= TARGET_UPDATE_INTERVAL:
		_target_update_timer = 0.0
		_update_target_priority()

	# Move toward target
	if direction != Vector2.ZERO and movement_controller:
		_move_with_movement_controller(delta)

func _move_with_movement_controller(delta: float) -> void:
	# Get steering force from AI (overridden by subclasses)
	var steering_force: Vector2 = _calculate_steering_force()

	# Feed steering to movement controller
	movement_controller.steering_system.set_steering_force(steering_force)
	movement_controller.steering_system.set_desired_speed(speed)

	# Get movement delta with physics constraints
	var motion: Vector2 = movement_controller.update(delta)

	# Check collision and move
	var desired_position: Vector2 = global_position + motion
	if not _would_collide(desired_position):
		global_position = desired_position
	else:
		# Try sliding along obstacle
		var normal: Vector2 = _get_collision_normal(desired_position)
		if normal != Vector2.ZERO:
			var slide_motion: Vector2 = motion.slide(normal)
			var slide_position: Vector2 = global_position + slide_motion
			if not _would_collide(slide_position):
				global_position = slide_position

	# Update velocity and direction for other systems
	velocity = movement_controller.velocity
	if velocity.length() > 0:
		direction = velocity.normalized()

	# Check if reached target
	if _has_reached_target():
		_on_reached_target()

	# Emit state update when moving
	_emit_creature_state()

func _emit_tactical_signals() -> void:
	"""
	Virtual method: Override in subclasses to emit creature-specific tactical signals.
	Default implementation emits basic PRESENCE signal.
	"""
	if TacticalMap and is_inside_tree():
		var sig = TacticalSignal.presence(global_position, owner_id, get_instance_id())
		sig.coordination_group_id = coordination_group_id
		TacticalMap.emit_signal_at(sig)


func _on_near_death() -> void:
	"""
	Virtual method: Called when health crosses near_death_threshold.
	Override in subclasses to respond to critical health (panic, berserk, call support, etc.).
	"""
	pass


func _on_target_acquired(target: Node2D) -> void:
	"""
	Virtual method: Called when a new target is acquired via scanning.
	Override in subclasses to emit tactical signals or coordinate attacks.
	"""
	pass


func _on_enemy_engaged(target: Node2D) -> void:
	"""
	Virtual method: Called when making physical contact with an enemy.
	Override in subclasses to emit tactical signals for engagement coordination.
	"""
	pass


func _calculate_steering_force() -> Vector2:
	# Use AI controller if available
	if ai_controller:
		return ai_controller.get_steering_force()

	# Fallback for creatures without AI: simple seek
	# (Subclasses like WolfUnit/RatUnit override this entirely for complex behavior)
	return SteeringBehaviors.seek(global_position, target_position, speed)

func _update_direction() -> void:
	# Calculate direction after entity position is finalized
	direction = (target_position - global_position).normalized()

func _has_reached_target() -> bool:
	var target_pos: Vector2 = dynamic_target.global_position if (dynamic_target and is_instance_valid(dynamic_target)) else target_position
	return global_position.distance_to(target_pos) < UNIT_ARRIVAL_THRESHOLD

func _on_reached_target() -> void:
	# Unit persists and emits signal
	direction = Vector2.ZERO  # Stop moving
	reached_target.emit()

func _on_area_entered(area: Area2D) -> void:
	# Check if we hit a player's or creature's hitbox
	if area.name == "HitBox":
		var allies: Array = _get_allies()
		var target: Node2D = CollisionUtils.get_valid_target(area, hit_box, allies)
		if target:
			attack_target = target
			_request_animation("attack", AnimationRequest.Priority.HIGH)
			if target.has_method("take_damage"):
				target.call("take_damage", damage)
			hit_target.emit(target)
			_on_enemy_engaged(target)  # Event: contact made with enemy

func _on_unit_died() -> void:
	# Event-driven: broadcast death to coordination group
	if TacticalMap and is_inside_tree():
		var sig = TacticalSignal.new()
		sig.signal_type = TacticalSignal.Type.KILL_CONFIRMED
		sig.position = global_position
		sig.owner_id = owner_id
		sig.coordination_group_id = coordination_group_id
		sig.emitter_id = get_instance_id()
		sig.strength = 1.0
		sig.radius = 150.0
		sig.duration = 2.0
		TacticalMap.emit_signal_at(sig)

	_request_animation("death", AnimationRequest.Priority.CRITICAL)
	died.emit()
	queue_free()

func _on_health_changed(_current: float, _maximum: float) -> void:
	_emit_creature_state()

	# Event-driven: emit NEAR_DEATH when crossing threshold
	if near_death_threshold > 0 and not _has_emitted_near_death:
		var health_percent = _current / _maximum
		if health_percent < near_death_threshold and TacticalMap and is_inside_tree():
			var sig = TacticalSignal.near_death(global_position, owner_id, get_instance_id())
			sig.coordination_group_id = coordination_group_id
			TacticalMap.emit_signal_at(sig)
			_has_emitted_near_death = true
			_on_near_death()  # Hook for subclasses

func _update_target_priority() -> void:
	var enemy_creatures: Array = _get_enemy_creatures()
	var new_target: Node2D = null

	if enemy_creatures.size() > 0:
		# Target nearest enemy creature
		new_target = _get_nearest_creature(enemy_creatures)
	elif _enemy_player and is_instance_valid(_enemy_player):
		# Target enemy player if no enemy creatures
		new_target = _enemy_player

	# Event-driven: notify when target changes
	if new_target != dynamic_target:
		dynamic_target = new_target
		if new_target:
			_on_target_acquired(new_target)

func _get_enemy_creatures() -> Array:
	var enemies: Array = []

	# Check if we're in the scene tree
	if not is_inside_tree():
		return enemies

	var all_creatures: Array = get_tree().get_nodes_in_group("creatures")

	for creature: Variant in all_creatures:
		if creature != self and "owner_id" in creature:
			if (creature as Object).get("owner_id") != owner_id:
				enemies.append(creature)

	return enemies

func _get_allies() -> Array:
	var allies: Array = []

	# Add owner player if available
	if _enemy_player and is_instance_valid(_enemy_player):
		var owner_player: PlayerCharacter = _get_owner_player()
		if owner_player:
			allies.append(owner_player)

	# Add same-team creatures
	if is_inside_tree():
		var all_creatures: Array = get_tree().get_nodes_in_group("creatures")
		for creature: Variant in all_creatures:
			if creature != self and "owner_id" in creature:
				if (creature as Object).get("owner_id") == owner_id:
					allies.append(creature)

	return allies

func _get_owner_player() -> PlayerCharacter:
	# Find the player that owns this unit
	if not is_inside_tree():
		return null

	var all_combatants: Array = get_tree().get_nodes_in_group("combatants")
	for combatant: Variant in all_combatants:
		if combatant is PlayerCharacter and (combatant as PlayerCharacter).player_id == owner_id:
			return combatant as PlayerCharacter

	return null

func _get_nearest_creature(creatures: Array) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = INF

	for creature: Variant in creatures:
		if creature is Node2D:
			var distance: float = global_position.distance_to((creature as Node2D).global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = creature as Node2D

	return nearest

func take_damage(amount: float, source: Node = null) -> void:
	health_component.take_damage(amount, source)
	_request_animation("damaged", AnimationRequest.Priority.HIGH)

## Connect AI controller signals to visual system
func _connect_ai_signals() -> void:
	if not ai_controller:
		return

	ai_controller.tactical_action.connect(_on_ai_tactical_action)
	ai_controller.stealth_mode_changed.connect(_on_ai_stealth_mode_changed)
	ai_controller.charge_initiated.connect(_on_ai_charge_initiated)
	ai_controller.ambush_triggered.connect(_on_ai_ambush_triggered)
	ai_controller.behavior_changed.connect(_on_ai_behavior_changed)

## Handle AI tactical action signals
func _on_ai_tactical_action(action_name: String, _position: Vector2) -> void:
	# Map tactical actions to visual state flags
	match action_name:
		"stealth_activated":
			_current_ai_state_flag = EntityStateFlags.STEALTH
		"pack_coordinating":
			_current_ai_state_flag = EntityStateFlags.PACK_COORDINATING
		"swarm_attacking":
			_current_ai_state_flag = EntityStateFlags.SWARM_ATTACKING
		"ambush_triggered":
			_current_ai_state_flag = EntityStateFlags.AMBUSHING
		"charge_initiated":
			_current_ai_state_flag = EntityStateFlags.CHARGING_ATTACK
		"fleeing":
			_current_ai_state_flag = EntityStateFlags.FLEEING

	_emit_creature_state()

## Handle stealth mode changes
func _on_ai_stealth_mode_changed(is_stealthy: bool) -> void:
	if is_stealthy:
		_current_ai_state_flag = EntityStateFlags.STEALTH
	else:
		# Clear stealth flag if it was set
		if _current_ai_state_flag == EntityStateFlags.STEALTH:
			_current_ai_state_flag = ""

	_emit_creature_state()

## Handle charge initiation
func _on_ai_charge_initiated(_direction: Vector2) -> void:
	_current_ai_state_flag = EntityStateFlags.CHARGING_ATTACK
	_emit_creature_state()

## Handle ambush trigger
func _on_ai_ambush_triggered(_target: Node2D) -> void:
	_current_ai_state_flag = EntityStateFlags.AMBUSHING
	_emit_creature_state()

## Handle behavior changes (clear state when behavior changes to idle)
func _on_ai_behavior_changed(behavior_name: String) -> void:
	# Clear AI state flag when returning to idle/basic behaviors
	if behavior_name in ["idle", "seek", "attack"]:
		_current_ai_state_flag = ""
		_emit_creature_state()

## Emit creature state with movement and health info
func _emit_creature_state() -> void:
	var state = EntityState.new()
	state.velocity = velocity
	state.health_percent = health_component.health / health_component.max_health if health_component else 1.0

	# Use flags for behavioral states
	if velocity.length() > 10.0:
		state.add_flag(EntityStateFlags.MOVING)
	else:
		state.add_flag(EntityStateFlags.IDLE)

	# Add current AI behavior state flag (if any)
	if _current_ai_state_flag != "":
		state.add_flag(_current_ai_state_flag)

	if direction.length() > 0:
		state.facing_direction = direction

	state_changed.emit(state)

func _would_collide(target_position: Vector2) -> bool:
	if not is_inside_tree():
		return false

	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state

	# Create a shape query (circle for creature hitbox)
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var shape: CircleShape2D = CircleShape2D.new()

	# Get collision radius from hit_box if available
	var collision_radius: float = 10.0  # Default
	if hit_box:
		for child: Variant in hit_box.get_children():
			if child is CollisionShape2D and (child as CollisionShape2D).shape is CircleShape2D:
				collision_radius = ((child as CollisionShape2D).shape as CircleShape2D).radius
				break

	shape.radius = collision_radius
	params.shape = shape
	params.transform = Transform2D(0, target_position)
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.collision_mask = CollisionLayers.PATHFINDING_MASK  # Only check TERRAIN layer

	var result: Array[Dictionary] = space_state.intersect_shape(params, 1)
	return result.size() > 0

func _get_collision_normal(target_position: Vector2) -> Vector2:
	if not is_inside_tree():
		return Vector2.ZERO

	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state

	# Create a shape query to get collision info
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var shape: CircleShape2D = CircleShape2D.new()

	# Get collision radius from hit_box if available
	var collision_radius: float = 10.0  # Default
	if hit_box:
		for child: Variant in hit_box.get_children():
			if child is CollisionShape2D and (child as CollisionShape2D).shape is CircleShape2D:
				collision_radius = ((child as CollisionShape2D).shape as CircleShape2D).radius
				break

	shape.radius = collision_radius
	params.shape = shape
	params.transform = Transform2D(0, target_position)
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.collision_mask = CollisionLayers.PATHFINDING_MASK  # Only check TERRAIN layer

	var results: Array[Dictionary] = space_state.intersect_shape(params, 1)
	if results.size() > 0:
		# Calculate normal from creature to obstacle
		var obstacle: Object = results[0].collider
		if obstacle and obstacle is Node2D:
			var normal: Vector2 = (global_position - (obstacle as Node2D).global_position).normalized()
			return normal

	return Vector2.ZERO

