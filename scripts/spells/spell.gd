extends RefCounted
class_name Spell

# Base class for spell resolution
# Subclasses: ProjectileSpell, SummonCreatureSpell, EffectSpell
#
# A spell defines what happens when a medallion is cast.
# It creates and returns a Node2D object based on the medallion data.

func resolve(caster: Node2D, target_pos: Vector2, data: Dictionary, scene_root: Node2D) -> Node2D:
	# Subclasses override this to create the appropriate object
	push_error("Spell.resolve() not implemented in subclass")
	return null
