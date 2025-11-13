class_name AIPersonality
extends Resource

## Defines creature personality traits and behavior thresholds
## Loaded from creature type ai_config data

# Core traits (0.0 to 1.0)
@export_range(0.0, 1.0) var boldness: float = 0.5
@export_range(0.0, 1.0) var aggression: float = 0.5
@export_range(0.0, 1.0) var intelligence: float = 0.5
@export_range(0.0, 1.0) var pack_instinct: float = 0.5
@export_range(0.0, 1.0) var stealth_preference: float = 0.5

# Behavior thresholds
@export_range(0.0, 1.0) var panic_threshold: float = 0.3
@export_range(0.0, 1.0) var min_confidence_to_attack: float = 0.4
@export_range(0.0, 1.0) var morale_bonus_per_ally: float = 0.15

# Sensory config
@export var awareness_radius: float = 200.0
@export var ambush_distance: float = 80.0

## Create default personality
static func create_default() -> AIPersonality:
	return AIPersonality.new()

## Load from creature type data
static func from_data(ai_config: Dictionary) -> AIPersonality:
	var personality: AIPersonality = AIPersonality.new()
	var traits: Dictionary = ai_config.get("personality", {})

	personality.boldness = traits.get("boldness", 0.5)
	personality.aggression = traits.get("aggression", 0.5)
	personality.intelligence = traits.get("intelligence", 0.5)
	personality.pack_instinct = traits.get("pack_instinct", 0.5)
	personality.stealth_preference = traits.get("stealth_preference", 0.5)
	personality.panic_threshold = traits.get("panic_threshold", 0.3)
	personality.min_confidence_to_attack = traits.get("min_confidence_to_attack", 0.4)
	personality.morale_bonus_per_ally = traits.get("morale_bonus_per_ally", 0.15)
	personality.awareness_radius = ai_config.get("awareness_radius", 200.0)
	personality.ambush_distance = ai_config.get("ambush_distance", 80.0)

	return personality
