class_name DamageResolver
extends RefCounted

## Pure functional damage resolution system - IMMUTABLE DATA
## Every function returns new data, never mutates input
## Following functional programming principles

# ============================================================================
# MAIN API - Returns new ship_data with damage applied
# ============================================================================

## Resolve a projectile hit - returns {ship_data: Dictionary, hit_result: Dictionary}
## `intended_subsystem` (component_id or "") biases internal damage routing for
## elite SUBSYSTEM-style fire — see apply_damage_to_internals.
static func resolve_hit(ship_data: Dictionary, hit_position: Vector2, damage: int, projectile_angle: float, weapon_size: int = 999, intended_subsystem: String = "") -> Dictionary:
	var hit_angle = calculate_hit_angle(ship_data, hit_position)
	var section = find_armor_section_at_angle(ship_data, hit_angle)

	if section.is_empty():
		return create_miss_result(ship_data)

	return apply_damage_to_ship(ship_data, section, hit_position, damage, hit_angle, weapon_size, intended_subsystem)

# ============================================================================
# HIT RESOLUTION
# ============================================================================

static func apply_damage_to_ship(ship_data: Dictionary, section: Dictionary, hit_pos: Vector2, damage: int, hit_angle: float, weapon_size: int, intended_subsystem: String = "") -> Dictionary:
	var armor_result = apply_damage_to_armor(section, damage, weapon_size)
	var updated_ship = replace_armor_section(ship_data, armor_result.get("section"))

	if not armor_result.get("penetrated"):
		return create_armor_hit_result(updated_ship, armor_result, hit_pos)

	# Armor penetrated - damage internals
	var internal_result = apply_damage_to_internals(updated_ship, hit_pos, armor_result.get("remaining_damage"), intended_subsystem)
	return create_penetration_result(internal_result.get("ship_data"), armor_result, internal_result.get("hit_result"), hit_pos)

# ============================================================================
# ARMOR DAMAGE - Pure Functions
# ============================================================================

static func apply_damage_to_armor(section: Dictionary, damage: int, weapon_size: int) -> Dictionary:
	# Apply size-based damage reduction
	# Weapons are fully effective against armor sizes: weapon_size to weapon_size + 1
	# Beyond that range, damage is reduced based on size mismatch
	var armor_size = section.get("size", 1)
	var effective_damage = calculate_size_adjusted_damage(damage, weapon_size, armor_size)

	if has_armor_remaining(section):
		return damage_armor_section(section, effective_damage)
	else:
		return create_armor_penetrated_result(section, effective_damage)

## Calculate damage after applying size-based reduction
## Size 1 weapon vs Size 3 armor = ~10% damage
## Size 2 weapon vs Size 4 armor = ~15% damage
## Size 3 weapon vs Size 5 armor = ~18% damage
## Formula: Higher size weapons are more effective against oversized armor
static func calculate_size_adjusted_damage(base_damage: int, weapon_size: int, armor_size: int) -> int:
	# Full damage if armor is within weapon's effective range
	if armor_size <= weapon_size + 1:
		return base_damage

	# Reduced damage based on size mismatch
	# Formula: weapon_size / armor_size * 0.3
	# This gives higher size weapons better scaling against tough armor
	var damage_multiplier = float(weapon_size) / float(armor_size) * 0.3
	var adjusted_damage = int(base_damage * damage_multiplier)

	# Ensure at least 1 damage gets through
	return max(1, adjusted_damage)

static func has_armor_remaining(section: Dictionary) -> bool:
	return section.get("current_armor", 0) > 0

static func damage_armor_section(section: Dictionary, damage: int) -> Dictionary:
	var armor_damaged = min(damage, section.get("current_armor", 0))
	var remaining_damage = damage - armor_damaged
	var new_section = set_section_armor(section, section.get("current_armor", 0) - armor_damaged)

	return {
		"section": new_section,
		"armor_damaged": armor_damaged,
		"remaining_damage": remaining_damage,
		"penetrated": remaining_damage > 0
	}

static func create_armor_penetrated_result(section: Dictionary, damage: int) -> Dictionary:
	return {
		"section": section,
		"armor_damaged": 0,
		"remaining_damage": damage,
		"penetrated": true
	}

static func set_section_armor(section: Dictionary, new_armor: int) -> Dictionary:
	return DictUtils.merge_dict(section, {"current_armor": new_armor})

static func replace_armor_section(ship_data: Dictionary, new_section: Dictionary) -> Dictionary:
	var armor_sections = ship_data.get("armor_sections", [])
	if armor_sections is Array:
		var new_sections = []
		for s in armor_sections:
			if s.get("section_id") == new_section.get("section_id"):
				new_sections.append(new_section)
			else:
				new_sections.append(s.duplicate(true))
		return DictUtils.merge_dict(ship_data, {"armor_sections": new_sections})
	return ship_data

# ============================================================================
# INTERNAL DAMAGE - Pure Functions
# ============================================================================

static func apply_damage_to_internals(ship_data: Dictionary, hit_pos: Vector2, damage: int, intended_subsystem: String = "") -> Dictionary:
	# Elite gunners aim at a specific subsystem; bias damage routing toward
	# that intended target. Falls back to closest-component when there is no
	# intent or the intended subsystem is already destroyed.
	var target_component = pick_internal_to_damage(ship_data, hit_pos, intended_subsystem)

	if target_component.is_empty():
		return {"ship_data": ship_data, "hit_result": {}}

	var damaged_component = apply_damage_to_component(target_component, damage)
	var updated_ship = replace_internal_component(ship_data, damaged_component.get("component"))
	var final_ship = apply_component_effects(updated_ship, damaged_component.get("component"), damaged_component.get("status_changed"))

	return {
		"ship_data": final_ship,
		"hit_result": create_internal_hit_info(damaged_component, hit_pos)
	}

## Choose which internal component absorbs the damage. With an intent set,
## roll SUBSYSTEM_INTENDED_HIT_BIAS to route to it; otherwise fall back to
## closest-component. The intent only applies when the component is still
## functional.
static func pick_internal_to_damage(ship_data: Dictionary, hit_pos: Vector2, intended_subsystem: String) -> Dictionary:
	if intended_subsystem != "":
		var intended := find_internal_by_id(ship_data, intended_subsystem)
		if not intended.is_empty() and intended.get("status", "") != "destroyed":
			if randf() < WingConstants.SUBSYSTEM_INTENDED_HIT_BIAS:
				return intended
	return find_closest_internal(ship_data, hit_pos)

static func find_internal_by_id(ship_data: Dictionary, component_id: String) -> Dictionary:
	var internals = ship_data.get("internals", [])
	if not (internals is Array):
		return {}
	for component in internals:
		if component.get("component_id") == component_id:
			return component
	return {}

static func find_closest_internal(ship_data: Dictionary, hit_pos: Vector2) -> Dictionary:
	var internals = ship_data.get("internals", [])
	if not (internals is Array) or internals.is_empty():
		return {}

	return internals \
		.map(func(i): return add_distance_to_component(i, ship_data, hit_pos)) \
		.reduce(select_closest_component, {})

static func add_distance_to_component(component: Dictionary, ship_data: Dictionary, hit_pos: Vector2) -> Dictionary:
	var world_pos = calculate_component_world_position(component, ship_data)
	var distance = calculate_distance(hit_pos, world_pos)
	return DictUtils.merge_dict(component, {"_distance": distance})

static func calculate_component_world_position(component: Dictionary, ship_data: Dictionary) -> Vector2:
	return ship_data.get("position", Vector2.ZERO) + component.get("position_offset", Vector2.ZERO).rotated(ship_data.get("rotation", 0.0))

static func calculate_distance(from: Vector2, to: Vector2) -> float:
	return from.distance_to(to)

static func select_closest_component(closest: Dictionary, current: Dictionary) -> Dictionary:
	if closest.is_empty():
		return current
	return current if get_distance(current) < get_distance(closest) else closest

static func get_distance(component: Dictionary) -> float:
	return component.get("_distance", INF)

static func apply_damage_to_component(component: Dictionary, damage: int) -> Dictionary:
	var old_status = component.get("status")
	var new_health = max(0, component.get("current_health") - damage)
	var new_status = calculate_component_status(new_health, component.get("max_health"), old_status)

	return {
		"component": set_component_health_and_status(component, new_health, new_status),
		"old_status": old_status,
		"new_status": new_status,
		"status_changed": old_status != new_status,
		"damage": damage
	}

static func calculate_component_status(current_health: int, max_health: int, old_status: String) -> String:
	if current_health == 0:
		return "destroyed"
	elif current_health < max_health and old_status == "operational":
		return "damaged"
	else:
		return old_status

static func set_component_health_and_status(component: Dictionary, health: int, status: String) -> Dictionary:
	return DictUtils.merge_dict(component, {
		"current_health": health,
		"status": status
	})

static func replace_internal_component(ship_data: Dictionary, new_component: Dictionary) -> Dictionary:
	var internals = ship_data.get("internals", [])
	if internals is Array:
		var new_internals = []
		for c in internals:
			if c.get("component_id") == new_component.get("component_id"):
				new_internals.append(new_component)
			else:
				new_internals.append(c.duplicate(true))
		return DictUtils.merge_dict(ship_data, {"internals": new_internals})
	return ship_data

# ============================================================================
# COMPONENT EFFECTS - Derive effective stats from component statuses
# ============================================================================

static func apply_component_effects(ship_data: Dictionary, component: Dictionary, status_changed: bool) -> Dictionary:
	if not status_changed:
		return ship_data

	var updated = recompute_stats_from_components(ship_data)

	# disabled/explode are one-way transition effects, not stat multipliers.
	if component.get("status") == "destroyed":
		var effects = component.get("effect_on_ship", {}).get("on_destroyed", {})
		if effects.get("disabled", false):
			updated = set_ship_disabled(updated)
		if effects.get("explode", false):
			updated = set_ship_exploding(updated)

	return updated

## Derive effective ship and weapon stats from the pristine `base_stats`
## snapshot (taken at ship creation) and the current status of every
## internal component. Damage and repair both route through here, so
## effect multipliers never compound across status transitions.
static func recompute_stats_from_components(ship_data: Dictionary) -> Dictionary:
	var multipliers := {
		"max_speed": 1.0,
		"acceleration": 1.0,
		"turn_rate": 1.0,
		"weapon_power": 1.0,
		"accuracy": 1.0,
	}
	for component in ship_data.get("internals", []):
		var effects = get_effects_for_status(component)
		for effect_key in effects:
			if multipliers.has(effect_key):
				multipliers[effect_key] = multipliers[effect_key] * effects[effect_key]

	var base_stats: Dictionary = ship_data.base_stats
	var new_stats: Dictionary = ship_data.get("stats", {}).duplicate(true)
	for stat_name in ["max_speed", "acceleration", "turn_rate"]:
		if base_stats.has(stat_name):
			new_stats[stat_name] = base_stats[stat_name] * multipliers[stat_name]

	var updated = DictUtils.merge_dict(ship_data, {"stats": new_stats})
	updated = recompute_weapon_stats(updated, multipliers["weapon_power"], multipliers["accuracy"])
	return clamp_velocity_to_max_speed(updated)

## The effect set a component currently exerts on its ship.
static func get_effects_for_status(component: Dictionary) -> Dictionary:
	var effects_dict = component.get("effect_on_ship", {})
	match component.get("status", ""):
		"damaged":
			return effects_dict.get("on_damaged", {})
		"destroyed":
			return effects_dict.get("on_destroyed", {})
		_:
			return {}

static func recompute_weapon_stats(ship_data: Dictionary, damage_multiplier: float, accuracy_multiplier: float) -> Dictionary:
	var weapons = ship_data.get("weapons", [])
	if not (weapons is Array) or weapons.is_empty():
		return ship_data
	var new_weapons = weapons.map(
		func(w): return recompute_one_weapon(w, damage_multiplier, accuracy_multiplier)
	)
	return DictUtils.merge_dict(ship_data, {"weapons": new_weapons})

static func recompute_one_weapon(weapon: Dictionary, damage_multiplier: float, accuracy_multiplier: float) -> Dictionary:
	var base_stats: Dictionary = weapon.base_stats
	var new_stats: Dictionary = weapon.get("stats", {}).duplicate(true)
	new_stats["damage"] = int(base_stats.get("damage", 0) * damage_multiplier)
	new_stats["accuracy"] = base_stats.get("accuracy", 0.0) * accuracy_multiplier
	return DictUtils.merge_dict(weapon, {"stats": new_stats})

static func clamp_velocity_to_max_speed(ship_data: Dictionary) -> Dictionary:
	var velocity = ship_data.get("velocity", Vector2.ZERO)
	var max_speed = ship_data.get("stats", {}).get("max_speed", 0.0)
	if velocity.length() <= max_speed:
		return ship_data

	var clamped_velocity = velocity.normalized() * max_speed
	return DictUtils.merge_dict(ship_data, {"velocity": clamped_velocity})

static func set_ship_disabled(ship_data: Dictionary) -> Dictionary:
	return DictUtils.merge_dict(ship_data, {
		"status": "disabled",
		"velocity": Vector2.ZERO,
		"angular_velocity": 0.0
	})

static func set_ship_exploding(ship_data: Dictionary) -> Dictionary:
	return DictUtils.merge_dict(ship_data, {"status": "exploding"})

# ============================================================================
# HIT ANGLE CALCULATION
# ============================================================================

static func calculate_hit_angle(ship_data: Dictionary, hit_position: Vector2) -> float:
	var ship_to_hit = calculate_direction_to_hit(ship_data.get("position"), hit_position)
	var local_angle = calculate_local_angle(ship_to_hit, ship_data.get("rotation"))
	return normalize_angle_to_degrees(local_angle)

static func calculate_direction_to_hit(ship_pos: Vector2, hit_pos: Vector2) -> Vector2:
	return (hit_pos - ship_pos).normalized()

static func calculate_local_angle(direction: Vector2, ship_rotation: float) -> float:
	return direction.angle() - ship_rotation

static func normalize_angle_to_degrees(angle_rad: float) -> float:
	var degrees = rad_to_deg(angle_rad)
	while degrees < 0:
		degrees += 360
	while degrees >= 360:
		degrees -= 360
	return degrees

## Find which armor section is hit based on angle (0-360 degrees)
static func find_armor_section_at_angle(ship_data: Dictionary, angle_deg: float) -> Dictionary:
	var armor_sections = ship_data.get("armor_sections", [])
	if not (armor_sections is Array):
		return {}
	var sections = armor_sections.filter(
		func(section): return is_angle_in_section_arc(angle_deg, section)
	)
	if sections.is_empty():
		return {}  # Return empty dict which will be caught by is_empty() check
	return sections[0]

static func is_angle_in_section_arc(angle_deg: float, section: Dictionary) -> bool:
	var arc = section.get("arc", {})
	var arc_start = arc.get("start", 0)
	var arc_end = arc.get("end", 360)

	# Normalize arc_start and arc_end to 0-360 range
	while arc_start < 0:
		arc_start += 360
	while arc_start >= 360:
		arc_start -= 360
	while arc_end < 0:
		arc_end += 360
	while arc_end > 360:
		arc_end -= 360

	# Check if arc wraps around 0 (e.g., 270 to 90 means 270-360 and 0-90)
	if arc_start > arc_end:
		return is_in_wrapping_arc(angle_deg, arc_start, arc_end)
	else:
		return is_in_normal_arc(angle_deg, arc_start, arc_end)

static func is_in_wrapping_arc(angle: float, arc_start: float, arc_end: float) -> bool:
	# For wrapping arc (e.g., 270 to 90), angle is in arc if >= start OR <= end
	const EPSILON = 0.01
	return angle >= (arc_start - EPSILON) or angle <= (arc_end + EPSILON)

static func is_in_normal_arc(angle: float, arc_start: float, arc_end: float) -> bool:
	const EPSILON = 0.01
	return angle >= (arc_start - EPSILON) and angle <= (arc_end + EPSILON)

# ============================================================================
# RESULT CONSTRUCTORS
# ============================================================================

static func create_miss_result(ship_data: Dictionary) -> Dictionary:
	return {
		"ship_data": ship_data,
		"hit_result": {"type": "miss", "reason": "no_section_found"}
	}

static func create_armor_hit_result(ship_data: Dictionary, armor_result: Dictionary, hit_pos: Vector2) -> Dictionary:
	var section = armor_result.get("section", {})
	return {
		"ship_data": ship_data,
		"hit_result": {
			"type": "armor_hit",
			"section_id": section.get("section_id"),
			"damage": armor_result.get("armor_damaged"),
			"armor_remaining": section.get("current_armor"),
			"penetrated": false,
			"position": hit_pos
		}
	}

static func create_penetration_result(ship_data: Dictionary, armor_result: Dictionary, internal_hit: Dictionary, hit_pos: Vector2) -> Dictionary:
	var section = armor_result.get("section", {})
	return {
		"ship_data": ship_data,
		"hit_result": {
			"type": "armor_hit",
			"section_id": section.get("section_id"),
			"damage": armor_result.get("armor_damaged"),
			"armor_remaining": section.get("current_armor"),
			"penetrated": true,
			"position": hit_pos,
			"internal_hit": internal_hit
		}
	}

static func create_internal_hit_info(damage_result: Dictionary, hit_pos: Vector2) -> Dictionary:
	var component = damage_result.get("component")
	return {
		"component_id": component.get("component_id"),
		"type": component.get("type"),
		"damage": damage_result.get("damage"),
		"health_remaining": component.get("current_health"),
		"old_status": damage_result.get("old_status"),
		"new_status": damage_result.get("new_status"),
		"position": hit_pos
	}

# ============================================================================
# QUERY FUNCTIONS - Ship State
# ============================================================================

static func calculate_total_armor(ship_data: Dictionary) -> int:
	var armor_sections = ship_data.get("armor_sections", [])
	if not (armor_sections is Array):
		return 0
	return armor_sections.reduce(
		func(total, section): return total + section.get("current_armor", 0),
		0
	)

static func calculate_total_internal_health(ship_data: Dictionary) -> int:
	var internals = ship_data.get("internals", [])
	if not (internals is Array):
		return 0
	return internals.reduce(
		func(total, internal): return total + internal.get("current_health", 0),
		0
	)

static func is_ship_destroyed(ship_data: Dictionary) -> bool:
	if ship_data.get("status") in ["destroyed", "exploding"]:
		return true

	var internals = ship_data.get("internals", [])
	if not (internals is Array):
		return false
	return internals.all(
		func(internal): return internal.get("status") == "destroyed"
	)

static func get_destroyed_components(ship_data: Dictionary) -> Array:
	var internals = ship_data.get("internals", [])
	if not (internals is Array):
		return []
	return internals \
		.filter(func(i): return i.get("status") == "destroyed") \
		.map(func(i): return i.get("component_id"))

static func get_damaged_components(ship_data: Dictionary) -> Array:
	var internals = ship_data.get("internals", [])
	if not (internals is Array):
		return []
	return internals \
		.filter(func(i): return i.get("status") == "damaged") \
		.map(func(i): return i.get("component_id"))

