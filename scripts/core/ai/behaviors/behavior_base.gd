class_name BehaviorBase
extends RefCounted

## Base class for all creature behaviors
## Each behavior is a modular, reusable component that reads from TacticalMap

var owner: Node2D
var personality: AIPersonality
var sensory_system: SensorySystem
var emotional_state: EmotionalState

func initialize(p_owner: Node2D, p_personality: AIPersonality, p_sensory: SensorySystem, p_emotional: EmotionalState) -> void:
	owner = p_owner
	personality = p_personality
	sensory_system = p_sensory
	emotional_state = p_emotional

## Check if this behavior can execute in current context
func can_execute() -> bool:
	return false  # Override in subclass

## Execute behavior and return steering force
func execute() -> Vector2:
	return Vector2.ZERO  # Override in subclass

## Get speed from owner (helper)
func get_speed() -> float:
	return owner.speed if "speed" in owner else 100.0
