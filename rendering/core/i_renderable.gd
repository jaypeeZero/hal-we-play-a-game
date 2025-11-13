## Interface: Any game entity that needs visual representation
## Implementations: Player, Creature, Projectile, Terrain
class_name IRenderable extends Node2D

## Emitted when entity's visual state changes (position, health, movement)
signal state_changed(state: EntityState)

## Emitted when entity requests animation (attack, damage, death)
signal animation_requested(request: AnimationRequest)

## Unique identifier for this entity instance
func get_entity_id() -> String:
	assert(false, "IRenderable.get_entity_id() must be implemented")
	return ""

## Visual type identifier (maps to theme JSON key)
## Examples: "wizard_player", "olophant", "fireball"
func get_visual_type() -> String:
	assert(false, "IRenderable.get_visual_type() must be implemented")
	return ""
