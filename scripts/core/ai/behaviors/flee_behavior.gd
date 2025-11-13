class_name FleeBehavior
extends BehaviorBase

## Escape from overwhelming threats
## Universal behavior for all creatures when panicked

const SteeringBehaviors = preload("res://scripts/core/ai/steering_behaviors.gd")

const FLEE_SPEED_MULTIPLIER = 1.5

func can_execute() -> bool:
	# Always execute when creature should flee
	return emotional_state.should_flee()

func execute() -> Vector2:
	var threat: Dictionary = sensory_system.get_highest_threat()
	if threat.is_empty() or not is_instance_valid(threat.entity):
		return Vector2.ZERO

	var threat_entity: Node2D = threat.entity
	var current_speed: float = get_speed()

	# Flee away from threat at increased speed
	return SteeringBehaviors.flee(
		owner.global_position,
		threat_entity.global_position,
		current_speed * FLEE_SPEED_MULTIPLIER
	)
