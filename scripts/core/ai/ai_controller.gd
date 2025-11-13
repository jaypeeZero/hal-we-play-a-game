class_name AIController
extends RefCounted

## Central AI orchestrator for creatures
## Replaces hardcoded _calculate_steering_force() overrides

const AIPersonality = preload("res://scripts/core/ai/ai_personality.gd")
const EmotionalState = preload("res://scripts/core/ai/emotional_state.gd")
const SensorySystem = preload("res://scripts/core/ai/sensory_system.gd")
const SteeringBehaviors = preload("res://scripts/core/ai/steering_behaviors.gd")
const BehaviorBase = preload("res://scripts/core/ai/behaviors/behavior_base.gd")

# Signals for visual feedback
signal behavior_changed(behavior_name: String)
signal emotional_state_changed(emotion: String)
signal tactical_action(action_name: String, position: Vector2)
signal stealth_mode_changed(is_stealthy: bool)
signal charge_initiated(direction: Vector2)
signal ambush_triggered(target: Node2D)

# Core components
var personality: AIPersonality
var emotional_state: EmotionalState
var sensory_system: SensorySystem

# Behavior library (composed by creature classes)
var active_behaviors: Array[BehaviorBase] = []

# Current behavior state
var current_behavior: String = "idle"
var current_target: Node2D = null

# Reference to owning creature
var owner: Node2D

# Decision update timing
var decision_interval: float = 0.5  # Make decisions every 0.5s
var time_since_decision: float = 0.0

func _init(p_owner: Node2D, p_personality: AIPersonality) -> void:
	owner = p_owner
	personality = p_personality
	emotional_state = EmotionalState.new(personality)
	sensory_system = SensorySystem.new(owner, personality)

	# Connect emotional state signals
	emotional_state.state_changed.connect(_on_emotional_state_changed)

	# Debug logging - AIController is RefCounted so use print directly
	print("[AIController] Created for creature with boldness=%.2f, aggression=%.2f" % [personality.boldness, personality.aggression])

	# Make initial decision immediately (don't wait for first update)
	time_since_decision = decision_interval  # Force immediate decision on first update

## Add a behavior to the active behavior list
## Creature classes call this to compose their behavior
func add_behavior(behavior: BehaviorBase) -> void:
	behavior.initialize(owner, personality, sensory_system, emotional_state)
	active_behaviors.append(behavior)
	print("[AIController] Added behavior: %s" % behavior.get_script().get_global_name())

## Main update loop - called by creature each frame
func update(delta: float) -> void:
	# Update perception
	sensory_system.update(delta)

	# Update emotional state
	var context: Dictionary = sensory_system.get_emotional_context()
	emotional_state.update(context)

	# Make decisions periodically
	time_since_decision += delta
	if time_since_decision >= decision_interval:
		time_since_decision = 0.0
		_make_decision()

## Get steering force for movement
## Replaces creature's _calculate_steering_force()
func get_steering_force() -> Vector2:
	# If creature has composed behaviors, use them
	if not active_behaviors.is_empty():
		for behavior in active_behaviors:
			if behavior.can_execute():
				var behavior_name = behavior.get_script().get_global_name()
				_switch_behavior(behavior_name)
				return behavior.execute()

		# No behavior could execute - idle
		return _behavior_idle()

	# Fallback to simple behaviors for creatures without composition
	match current_behavior:
		"idle":
			return _behavior_idle()
		"seek":
			return _behavior_seek()
		"flee":
			return _behavior_flee()
		"attack":
			return _behavior_attack()
		_:
			return Vector2.ZERO

func _make_decision() -> void:
	"""Decide which behavior to execute based on emotional state and perception"""

	# Debug logging
	print("[AIController] Decision: enemies=%d, allies=%d, confidence=%.2f, fear=%.2f" % [
		sensory_system.visible_enemies.size(),
		sensory_system.visible_allies.size(),
		emotional_state.confidence,
		emotional_state.fear
	])

	# Emergency flee if panicked
	if emotional_state.should_flee():
		_switch_behavior("flee")
		return

	# No enemies visible - idle/wander
	if sensory_system.visible_enemies.is_empty():
		current_target = null
		_switch_behavior("idle")
		return

	# Has confidence to attack
	if emotional_state.should_attack():
		current_target = sensory_system.get_nearest_enemy()
		_switch_behavior("attack")
		return

	# Default: cautious seeking
	current_target = sensory_system.get_nearest_enemy()
	_switch_behavior("seek")

func _switch_behavior(new_behavior: String) -> void:
	if new_behavior != current_behavior:
		var old_behavior: String = current_behavior
		current_behavior = new_behavior
		print("[AIController] Behavior: %s -> %s (target=%s)" % [old_behavior, new_behavior, current_target])
		behavior_changed.emit(new_behavior)

		# Emit tactical signals for visual feedback
		match new_behavior:
			"StealthBehavior":
				stealth_mode_changed.emit(true)
				tactical_action.emit("stealth_activated", owner.global_position)
			"PackBehavior":
				tactical_action.emit("pack_coordinating", owner.global_position)
			"SwarmBehavior":
				tactical_action.emit("swarm_attacking", owner.global_position)
			"AmbushBehavior":
				var target = sensory_system.get_nearest_enemy()
				if target:
					ambush_triggered.emit(target)
					tactical_action.emit("ambush_triggered", owner.global_position)
			"ChargeBehavior":
				charge_initiated.emit(owner.global_position)
				tactical_action.emit("charge_initiated", owner.global_position)
			"FleeBehavior":
				tactical_action.emit("fleeing", owner.global_position)

		# Emit stealth_mode_changed when leaving stealth
		if old_behavior == "StealthBehavior" and new_behavior != "StealthBehavior":
			stealth_mode_changed.emit(false)

func _on_emotional_state_changed(emotion: String) -> void:
	emotional_state_changed.emit(emotion)

## Behavior implementations (simple versions, will be replaced by behavior library)

func _behavior_idle() -> Vector2:
	# Check for dynamic target first (takes precedence over static target)
	if "dynamic_target" in owner and owner.dynamic_target and is_instance_valid(owner.dynamic_target):
		var speed: float = owner.speed if "speed" in owner else 100.0
		return SteeringBehaviors.seek(owner.global_position, owner.dynamic_target.global_position, speed)

	# Fall back to static target_position if available (for tests and simple cases)
	if "target_position" in owner:
		var target_pos: Vector2 = owner.target_position
		if owner.global_position.distance_to(target_pos) > 10.0:  # UNIT_ARRIVAL_THRESHOLD
			var speed: float = owner.speed if "speed" in owner else 100.0
			return SteeringBehaviors.seek(owner.global_position, target_pos, speed)
	return Vector2.ZERO

func _behavior_seek() -> Vector2:
	if not current_target or not is_instance_valid(current_target):
		return Vector2.ZERO

	var speed: float = owner.speed if "speed" in owner else 100.0
	return SteeringBehaviors.seek(owner.global_position, current_target.global_position, speed)

func _behavior_flee() -> Vector2:
	var threat: Dictionary = sensory_system.get_highest_threat()
	if threat.is_empty():
		return Vector2.ZERO

	# Check validity before assignment to avoid "trying to assign invalid previously freed instance" error
	if not is_instance_valid(threat.entity):
		return Vector2.ZERO

	var threat_entity: Node2D = threat.entity
	var speed: float = owner.speed if "speed" in owner else 100.0
	return SteeringBehaviors.flee(owner.global_position, threat_entity.global_position, speed)

func _behavior_attack() -> Vector2:
	if not current_target or not is_instance_valid(current_target):
		return Vector2.ZERO

	var speed: float = owner.speed if "speed" in owner else 100.0
	return SteeringBehaviors.seek(owner.global_position, current_target.global_position, speed)

## Get debug information for visualization (development only)
func get_debug_info() -> Dictionary:
	if not OS.is_debug_build():
		return {}

	var debug_data: Dictionary = {
		"behavior": current_behavior,
		"target": current_target,
		"awareness_radius": personality.awareness_radius,
		"confidence": emotional_state.confidence,
		"fear": emotional_state.fear,
		"aggression": personality.aggression,
		"visible_enemies": sensory_system.visible_enemies.size(),
		"visible_allies": sensory_system.visible_allies.size(),
		"active_behavior_count": active_behaviors.size()
	}

	return debug_data
