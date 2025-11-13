class_name EmotionalState
extends RefCounted

## Tracks creature's emotional state and morale
## Determines confidence levels that drive behavior decisions

signal state_changed(emotion: String)

var personality: AIPersonality

# Current emotional values (0.0 to 1.0)
var confidence: float = 0.5
var fear: float = 0.0
var morale: float = 0.5

# Last known context
var last_context: Dictionary = {}

func _init(p_personality: AIPersonality) -> void:
	personality = p_personality

## Update emotional state based on sensory context
func update(context: Dictionary) -> void:
	last_context = context

	var ally_count: int = context.get("ally_count", 0)
	var enemy_count: int = context.get("enemy_count", 0)
	var health_percent: float = context.get("health_percent", 1.0)
	var threat_level: float = context.get("threat_level", 0.0)

	# Calculate morale from allies vs enemies
	morale = personality.boldness
	morale += ally_count * personality.morale_bonus_per_ally
	morale -= enemy_count * 0.1
	morale = clamp(morale, 0.0, 1.0)

	# Calculate fear from health and threat
	fear = 0.0
	if health_percent < personality.panic_threshold:
		fear += (personality.panic_threshold - health_percent) / personality.panic_threshold
	fear += threat_level * 0.5
	fear = clamp(fear, 0.0, 1.0)

	# Calculate confidence (morale - fear)
	confidence = clamp(morale - fear, 0.0, 1.0)

	# Emit state changes
	if fear > 0.7:
		state_changed.emit("panicked")
	elif confidence > 0.7:
		state_changed.emit("confident")
	elif confidence < 0.3:
		state_changed.emit("cautious")

## Should creature flee from combat?
func should_flee() -> bool:
	return fear > 0.6 or confidence < 0.2

## Should creature attack aggressively?
func should_attack() -> bool:
	return confidence >= personality.min_confidence_to_attack and fear < 0.3

## Is creature in panic state?
func is_panicked() -> bool:
	return fear > 0.7

## Is creature confident?
func is_confident() -> bool:
	return confidence > 0.7
