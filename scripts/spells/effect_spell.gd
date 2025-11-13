extends Spell
class_name EffectSpell

# Spell that creates effect objects or terrain
# Uses entity_class from enriched data (provided by CombatSystem)

func resolve(caster: Node2D, target_pos: Vector2, data: Dictionary, scene_root: Node2D) -> Node2D:
	var effect_type: String = data.get("effect_type", "")
	var effect_class: Variant = data.get("entity_class")

	if not effect_class:
		push_error("EffectSpell: No entity_class provided in data")
		return null

	@warning_ignore("unsafe_method_access")
	var effect: Node2D = effect_class.new()
	scene_root.add_child(effect)

	# Position: terrain at target, other effects at caster
	if effect_type == "terrain":
		effect.global_position = target_pos
	else:
		effect.global_position = caster.global_position

	@warning_ignore("unsafe_method_access")
	effect.initialize(data, target_pos)

	# Register with VisualBridge (must be in scene tree first)
	if effect is IRenderable:
		VisualBridgeAutoload.register_entity(effect as IRenderable)

	return effect
