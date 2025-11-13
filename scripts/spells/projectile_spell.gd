extends Spell
class_name ProjectileSpell

# Spell that creates a projectile object
# Expects entity_class to be provided in the data dict

func resolve(caster: Node2D, target_pos: Vector2, data: Dictionary, scene_root: Node2D) -> Node2D:
	var entity_class: Variant = data.get("entity_class")
	if not entity_class:
		push_error("ProjectileSpell: No entity_class in data")
		return null

	@warning_ignore("unsafe_method_access")
	var projectile: Node2D = entity_class.new()
	scene_root.add_child(projectile)
	projectile.global_position = caster.global_position
	@warning_ignore("unsafe_method_access")
	projectile.initialize(data, target_pos, caster)

	# Register with VisualBridge (must be in scene tree first)
	if projectile is IRenderable:
		VisualBridgeAutoload.register_entity(projectile as IRenderable)

	return projectile
