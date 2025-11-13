class_name VisualEffectSystem
extends RefCounted

## Pure functional visual effect system - IMMUTABLE DATA
## Manages temporary visual effects like damage impacts, explosions
## Following functional programming principles

# ============================================================================
# MAIN API - Process visual effects
# ============================================================================

static var _next_effect_id: int = 0

## Create a damage effect at the hit location
static func create_damage_effect(hit_result: Dictionary, hit_position: Vector2) -> Dictionary:
	var effect_type = "effect_armor_hit" if not hit_result.get("penetrated", false) else "effect_armor_penetration"

	if hit_result.has("internal_hit"):
		effect_type = "effect_internal_damage"

	return create_effect(effect_type, hit_position, 0.5)

## Create a projectile impact effect
static func create_projectile_impact(position: Vector2) -> Dictionary:
	return create_effect("effect_projectile_impact", position, 0.3)

## Create a generic effect
static func create_effect(effect_type: String, position: Vector2, duration: float = 1.0) -> Dictionary:
	var effect_id = "effect_" + str(_next_effect_id)
	_next_effect_id += 1

	return {
		effect_id = effect_id,
		type = effect_type,
		position = position,
		lifetime = 0.0,
		max_lifetime = duration
	}

## Update single effect - returns {effect: Dictionary, expired: bool}
static func update_effect(effect_data: Dictionary, delta: float) -> Dictionary:
	var new_lifetime = effect_data.lifetime + delta

	if new_lifetime >= effect_data.max_lifetime:
		return {effect = effect_data, expired = true}

	return {
		effect = merge_dict(effect_data, {lifetime = new_lifetime}),
		expired = false
	}

## Update all effects - returns {effects: Array, expired_ids: Array}
static func update_all_effects(effects: Array, delta: float) -> Dictionary:
	var results = effects.map(func(e): return update_effect(e, delta))

	return {
		effects = results.filter(func(r): return not r.expired).map(func(r): return r.effect),
		expired_ids = results.filter(func(r): return r.expired).map(func(r): return r.effect.effect_id)
	}

# ============================================================================
# UTILITY
# ============================================================================

static func merge_dict(base: Dictionary, override: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	for key in override:
		result[key] = override[key]
	return result
