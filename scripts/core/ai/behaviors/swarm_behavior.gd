class_name SwarmBehavior
extends BehaviorBase

## Overwhelm targets with numbers, minimal coordination
## Used by rats and other small swarming creatures
## Reads from TacticalMap for panic/morale information

const SteeringBehaviors = preload("res://scripts/core/ai/steering_behaviors.gd")

const SEPARATION_WEIGHT = 0.3  # Light collision avoidance
const COHESION_WEIGHT = 0.0    # No cohesion - let them scatter
const SEEK_WEIGHT = 1.0        # Full speed toward target

# Swarm parameters
const SEPARATION_RADIUS = 20.0  # Minimal personal space
const MAX_SEPARATION_FORCE = 100.0

# Panic thresholds
const PANIC_THRESHOLD = 0.5
const FLEE_SPEED_MULTIPLIER = 1.5

func can_execute() -> bool:
	# Use swarm when confident (has allies nearby)
	return sensory_system.visible_allies.size() >= 2 \
		and emotional_state.should_attack()

func execute() -> Vector2:
	var force: Vector2 = Vector2.ZERO
	var neighbors: Array = sensory_system.visible_allies
	var current_speed: float = get_speed()

	# READ from TacticalMap for panic signals (event-driven swarm behavior)
	if TacticalMap and owner.is_inside_tree():
		var current_cell = TacticalMap.get_cell_at(owner.global_position)

		# React to panic: flee to safety as a swarm
		if current_cell.panic > PANIC_THRESHOLD:
			var safe_pos = TacticalMap.find_safest_position_near(
				owner.global_position,
				120.0,
				owner.owner_id
			)
			return SteeringBehaviors.seek(owner.global_position, safe_pos, current_speed * FLEE_SPEED_MULTIPLIER)

	# Normal swarm behavior
	var target = sensory_system.get_nearest_enemy()
	if not target or not is_instance_valid(target):
		return Vector2.ZERO

	# Minimal separation (let them cluster)
	force += SteeringBehaviors.separate(
		owner.global_position,
		neighbors,
		SEPARATION_RADIUS,
		MAX_SEPARATION_FORCE
	) * SEPARATION_WEIGHT

	# Cohesion (optional, currently disabled for chaotic swarm)
	force += SteeringBehaviors.cohesion(
		owner.global_position,
		neighbors,
		current_speed
	) * COHESION_WEIGHT

	# Direct seek - rush the target
	force += SteeringBehaviors.seek(
		owner.global_position,
		target.global_position,
		current_speed
	) * SEEK_WEIGHT

	return force
