class_name PackBehavior
extends BehaviorBase

## Coordinate with allies to surround and overwhelm targets
## Used by wolves and other pack hunters
## Reads from TacticalSignal for coordination information

const SteeringBehaviors = preload("res://scripts/core/ai/steering_behaviors.gd")

# Pack behavior states
enum State {
	SEEKING,      # No target, lope together
	SURROUNDING,  # Target found, spread out to surround
	ATTACKING     # Rush in to attack
}

# Behavior weights for different states
const COHESION_WEIGHT_SEEKING = 0.4
const SEPARATION_WEIGHT = 0.3
const SEEK_WEIGHT = 1.0
const MAX_SEPARATION_FORCE = 100.0

# Surrounding behavior
const SURROUND_RADIUS = 50.0
const ATTACK_DISTANCE = 80.0

# Speed constants
const LOPE_SPEED = 80.0
const STALK_SPEED = 60.0
const ATTACK_SPEED = 120.0

# State tracking
var current_state: State = State.SEEKING
var pack_target: Node2D = null
var assigned_angle: float = 0.0

func can_execute() -> bool:
	# Use pack tactics if high pack instinct and has allies nearby
	return personality.pack_instinct > 0.6 \
		and sensory_system.has_allies_nearby() \
		and emotional_state.should_attack()

func execute() -> Vector2:
	var force: Vector2 = Vector2.ZERO
	var neighbors: Array = sensory_system.visible_allies

	# READ from TacticalMap for pack coordination
	if TacticalMap and owner.is_inside_tree():
		# Priority 1: Respond to pack members needing support (filter by coordination group)
		var support_signals = TacticalMap.get_active_signals_near(
			owner.global_position,
			200.0,
			owner.owner_id,
			TacticalSignal.Type.NEED_SUPPORT,
			owner.coordination_group_id
		)
		if not support_signals.is_empty():
			# Go help pack member!
			var help_pos = support_signals[0].position
			return SteeringBehaviors.seek(owner.global_position, help_pos, ATTACK_SPEED) * 1.5

		# Priority 2: If we don't have a target, check for spotted targets (filter by coordination group)
		if not pack_target or not is_instance_valid(pack_target):
			var target_signals = TacticalMap.get_active_signals_near(
				owner.global_position,
				250.0,
				owner.owner_id,
				TacticalSignal.Type.TARGET_SPOTTED,
				owner.coordination_group_id
			)
			if not target_signals.is_empty() and target_signals[0].target_entity:
				pack_target = target_signals[0].target_entity

	# Update target from sensory system if we don't have one from TacticalMap
	if not pack_target or not is_instance_valid(pack_target):
		pack_target = sensory_system.get_nearest_enemy()

	# Update state based on target distance
	_update_state()

	# State-based pack behavior
	match current_state:
		State.SEEKING:
			# Move together, cohesive pack
			force += SteeringBehaviors.cohesion(owner.global_position, neighbors, LOPE_SPEED) * COHESION_WEIGHT_SEEKING
			force += SteeringBehaviors.separate(owner.global_position, neighbors, 30.0, MAX_SEPARATION_FORCE) * SEPARATION_WEIGHT

			# Seek toward target
			if pack_target and is_instance_valid(pack_target):
				force += SteeringBehaviors.seek(owner.global_position, pack_target.global_position, LOPE_SPEED) * SEEK_WEIGHT

		State.SURROUNDING:
			# Spread out to surround target
			if pack_target and is_instance_valid(pack_target):
				var surround_position: Vector2 = _calculate_surround_position()
				force += SteeringBehaviors.arrive(owner.global_position, surround_position, STALK_SPEED, 30.0) * SEEK_WEIGHT
				force += SteeringBehaviors.separate(owner.global_position, neighbors, 40.0, MAX_SEPARATION_FORCE) * SEPARATION_WEIGHT

		State.ATTACKING:
			# Rush directly at target
			if pack_target and is_instance_valid(pack_target):
				force += SteeringBehaviors.seek(owner.global_position, pack_target.global_position, ATTACK_SPEED) * SEEK_WEIGHT
				force += SteeringBehaviors.separate(owner.global_position, neighbors, 25.0, MAX_SEPARATION_FORCE) * SEPARATION_WEIGHT

	return force

func _update_state() -> void:
	var previous_state = current_state

	if not pack_target or not is_instance_valid(pack_target):
		current_state = State.SEEKING
		_set_owner_speed(LOPE_SPEED)
	else:
		var distance: float = owner.global_position.distance_to(pack_target.global_position)

		if distance < ATTACK_DISTANCE:
			current_state = State.ATTACKING
			_set_owner_speed(ATTACK_SPEED)
		else:
			current_state = State.SURROUNDING
			_set_owner_speed(STALK_SPEED)

	# EMIT to TacticalMap when entering ATTACKING state
	if current_state == State.ATTACKING and previous_state != State.ATTACKING:
		if pack_target and TacticalMap and owner.is_inside_tree():
			var sig = TacticalSignal.attacking(
				pack_target.global_position,
				pack_target,
				owner.owner_id,
				owner.get_instance_id()
			)
			sig.coordination_group_id = owner.coordination_group_id
			TacticalMap.emit_signal_at(sig)

func _calculate_surround_position() -> Vector2:
	if not pack_target or not is_instance_valid(pack_target):
		return owner.global_position

	# Calculate position at assigned angle around target
	# Use instance ID to generate unique angle for each pack member
	var angle_seed = owner.get_instance_id() % 360
	assigned_angle = deg_to_rad(angle_seed)

	var offset: Vector2 = Vector2(cos(assigned_angle), sin(assigned_angle)) * SURROUND_RADIUS
	return pack_target.global_position + offset

func _set_owner_speed(new_speed: float) -> void:
	if "speed" in owner:
		owner.speed = new_speed
