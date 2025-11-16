class_name DamageResolver
extends RefCounted

## Pure functional damage resolution system - IMMUTABLE DATA
## Every function returns new data, never mutates input
## Following functional programming principles

# ============================================================================
# MAIN API - Returns new ship_data with damage applied
# ============================================================================

## Resolve a projectile hit - returns {ship_data: Dictionary, hit_result: Dictionary}
static func resolve_hit(ship_data: Dictionary, hit_position: Vector2, damage: int, projectile_angle: float) -> Dictionary:
	var hit_angle = calculate_hit_angle(ship_data, hit_position)
	var section = find_armor_section_at_angle(ship_data, hit_angle)

	if section.is_empty():
		return create_miss_result(ship_data)

	return apply_damage_to_ship(ship_data, section, hit_position, damage, hit_angle)

# ============================================================================
# HIT RESOLUTION
# ============================================================================

static func apply_damage_to_ship(ship_data: Dictionary, section: Dictionary, hit_pos: Vector2, damage: int, hit_angle: float) -> Dictionary:
	var armor_result = apply_damage_to_armor(section, damage)
	var updated_ship = replace_armor_section(ship_data, armor_result.get("section", {}))

	if not armor_result.get("penetrated", false):
		return create_armor_hit_result(updated_ship, armor_result, hit_pos)

	# Armor penetrated - damage internals
	var internal_result = apply_damage_to_internals(updated_ship, hit_pos, armor_result.get("remaining_damage", 0))
	return create_penetration_result(internal_result.get("ship_data", {}), armor_result, internal_result.get("hit_result", {}), hit_pos)

# ============================================================================
# ARMOR DAMAGE - Pure Functions
# ============================================================================

static func apply_damage_to_armor(section: Dictionary, damage: int) -> Dictionary:
	if has_armor_remaining(section):
		return damage_armor_section(section, damage)
	else:
		return create_armor_penetrated_result(section, damage)

static func has_armor_remaining(section: Dictionary) -> bool:
	return section.get("current_armor", 0) > 0

static func damage_armor_section(section: Dictionary, damage: int) -> Dictionary:
	var armor_damaged = min(damage, section.get("current_armor", 0))
	var remaining_damage = damage - armor_damaged
	var new_section = set_section_armor(section, section.get("current_armor", 0) - armor_damaged)

	return {
		section = new_section,
		armor_damaged = armor_damaged,
		remaining_damage = remaining_damage,
		penetrated = remaining_damage > 0
	}

static func create_armor_penetrated_result(section: Dictionary, damage: int) -> Dictionary:
	return {
		section = section,
		armor_damaged = 0,
		remaining_damage = damage,
		penetrated = true
	}

static func set_section_armor(section: Dictionary, new_armor: int) -> Dictionary:
	return DictUtils.merge_dict(section, {current_armor = new_armor})

static func replace_armor_section(ship_data: Dictionary, new_section: Dictionary) -> Dictionary:
	var new_sections = ship_data.get("armor_sections", []).map(
		func(s): return new_section if s.get("section_id") == new_section.get("section_id") else s
	)
	return DictUtils.merge_dict(ship_data, {armor_sections = new_sections})

# ============================================================================
# INTERNAL DAMAGE - Pure Functions
# ============================================================================

static func apply_damage_to_internals(ship_data: Dictionary, hit_pos: Vector2, damage: int) -> Dictionary:
	var closest = find_closest_internal(ship_data, hit_pos)

	if closest.is_empty():
		return {ship_data = ship_data, hit_result = {}}

	var damaged_component = apply_damage_to_component(closest, damage)
	var updated_ship = replace_internal_component(ship_data, damaged_component.get("component", {}))
	var final_ship = apply_component_effects(updated_ship, damaged_component.get("component", {}), damaged_component.get("status_changed", false))

	return {
		ship_data = final_ship,
		hit_result = create_internal_hit_info(damaged_component, hit_pos)
	}

static func find_closest_internal(ship_data: Dictionary, hit_pos: Vector2) -> Dictionary:
	if ship_data.get("internals", []).is_empty():
		return {}

	return ship_data.get("internals", []) \
		.map(func(i): return add_distance_to_component(i, ship_data, hit_pos)) \
		.reduce(select_closest_component, {})

static func add_distance_to_component(component: Dictionary, ship_data: Dictionary, hit_pos: Vector2) -> Dictionary:
	var world_pos = calculate_component_world_position(component, ship_data)
	var distance = calculate_distance(hit_pos, world_pos)
	return DictUtils.merge_dict(component, {_distance = distance})

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
	var old_status = component.get("status", "operational")
	var new_health = max(0, component.get("current_health", 0) - damage)
	var new_status = calculate_component_status(new_health, component.get("max_health", 100), old_status)

	return {
		component = set_component_health_and_status(component, new_health, new_status),
		old_status = old_status,
		new_status = new_status,
		status_changed = old_status != new_status,
		damage = damage
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
		current_health = health,
		status = status
	})

static func replace_internal_component(ship_data: Dictionary, new_component: Dictionary) -> Dictionary:
	var new_internals = ship_data.get("internals", []).map(
		func(c): return new_component if c.get("component_id") == new_component.get("component_id") else c
	)
	return DictUtils.merge_dict(ship_data, {internals = new_internals})

# ============================================================================
# COMPONENT EFFECTS - Apply status effects to ship
# ============================================================================

static func apply_component_effects(ship_data: Dictionary, component: Dictionary, status_changed: bool) -> Dictionary:
	if not status_changed:
		return ship_data

	match component.get("status", "operational"):
		"damaged":
			return apply_damaged_effects(ship_data, component)
		"destroyed":
			return apply_destroyed_effects(ship_data, component)
		_:
			return ship_data

static func apply_damaged_effects(ship_data: Dictionary, component: Dictionary) -> Dictionary:
	if not component.get("effect_on_ship", {}).has("on_damaged"):
		return ship_data

	var effects = component.get("effect_on_ship", {}).get("on_damaged", {})
	return apply_effects_to_ship(ship_data, effects)

static func apply_destroyed_effects(ship_data: Dictionary, component: Dictionary) -> Dictionary:
	if not component.get("effect_on_ship", {}).has("on_destroyed"):
		return ship_data

	var effects = component.get("effect_on_ship", {}).get("on_destroyed", {})
	var ship_with_effects = apply_effects_to_ship(ship_data, effects)

	# Check for special destruction effects
	if effects.has("disabled") and effects.get("disabled", false):
		return set_ship_disabled(ship_with_effects)

	if effects.has("explode") and effects.get("explode", false):
		return set_ship_exploding(ship_with_effects)

	return ship_with_effects

static func apply_effects_to_ship(ship_data: Dictionary, effects: Dictionary) -> Dictionary:
	var updated = ship_data

	for effect_key in effects:
		var multiplier = effects[effect_key]

		match effect_key:
			"max_speed":
				updated = multiply_ship_stat(updated, "max_speed", multiplier)
				updated = clamp_velocity_to_max_speed(updated)
			"acceleration":
				updated = multiply_ship_stat(updated, "acceleration", multiplier)
			"turn_rate":
				updated = multiply_ship_stat(updated, "turn_rate", multiplier)
			"weapon_power":
				updated = multiply_all_weapon_damage(updated, multiplier)
			"accuracy":
				updated = multiply_all_weapon_accuracy(updated, multiplier)

	return updated

static func multiply_ship_stat(ship_data: Dictionary, stat_name: String, multiplier: float) -> Dictionary:
	var new_stats = ship_data.get("stats", {}).duplicate(true)
	new_stats[stat_name] = ship_data.get("stats", {}).get(stat_name, 0.0) * multiplier
	return DictUtils.merge_dict(ship_data, {stats = new_stats})

static func clamp_velocity_to_max_speed(ship_data: Dictionary) -> Dictionary:
	if ship_data.get("velocity", Vector2.ZERO).length() <= ship_data.get("stats", {}).get("max_speed", 0.0):
		return ship_data

	var clamped_velocity = ship_data.get("velocity", Vector2.ZERO).normalized() * ship_data.get("stats", {}).get("max_speed", 0.0)
	return DictUtils.merge_dict(ship_data, {velocity = clamped_velocity})

static func multiply_all_weapon_damage(ship_data: Dictionary, multiplier: float) -> Dictionary:
	var new_weapons = ship_data.get("weapons", []).map(
		func(w): return multiply_weapon_damage(w, multiplier)
	)
	return DictUtils.merge_dict(ship_data, {weapons = new_weapons})

static func multiply_weapon_damage(weapon: Dictionary, multiplier: float) -> Dictionary:
	var new_stats = weapon.get("stats", {}).duplicate(true)
	new_stats["damage"] = int(weapon.get("stats", {}).get("damage", 0) * multiplier)
	return DictUtils.merge_dict(weapon, {stats = new_stats})

static func multiply_all_weapon_accuracy(ship_data: Dictionary, multiplier: float) -> Dictionary:
	var new_weapons = ship_data.get("weapons", []).map(
		func(w): return multiply_weapon_accuracy(w, multiplier)
	)
	return DictUtils.merge_dict(ship_data, {weapons = new_weapons})

static func multiply_weapon_accuracy(weapon: Dictionary, multiplier: float) -> Dictionary:
	var new_stats = weapon.get("stats", {}).duplicate(true)
	new_stats["accuracy"] = weapon.get("stats", {}).get("accuracy", 1.0) * multiplier
	return DictUtils.merge_dict(weapon, {stats = new_stats})

static func set_ship_disabled(ship_data: Dictionary) -> Dictionary:
	return DictUtils.merge_dict(ship_data, {
		status = "disabled",
		velocity = Vector2.ZERO,
		angular_velocity = 0.0
	})

static func set_ship_exploding(ship_data: Dictionary) -> Dictionary:
	return DictUtils.merge_dict(ship_data, {status = "exploding"})

# ============================================================================
# HIT ANGLE CALCULATION
# ============================================================================

static func calculate_hit_angle(ship_data: Dictionary, hit_position: Vector2) -> float:
	var ship_to_hit = calculate_direction_to_hit(ship_data.get("position", Vector2.ZERO), hit_position)
	var local_angle = calculate_local_angle(ship_to_hit, ship_data.get("rotation", 0.0))
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
	var sections = ship_data.get("armor_sections", []).filter(
		func(section): return is_angle_in_section_arc(angle_deg, section)
	)
	if sections.is_empty():
		return {}
	return sections[0]

static func is_angle_in_section_arc(angle_deg: float, section: Dictionary) -> bool:
	var arc_start = section.get("arc", {}).get("start", 0.0)
	var arc_end = section.get("arc", {}).get("end", 0.0)

	if is_wrapping_arc(arc_end):
		return is_in_wrapping_arc(angle_deg, arc_start, arc_end)
	else:
		return is_in_normal_arc(angle_deg, arc_start, arc_end)

static func is_wrapping_arc(arc_end: float) -> bool:
	return arc_end > 360

static func is_in_wrapping_arc(angle: float, arc_start: float, arc_end: float) -> bool:
	return angle >= arc_start or angle <= (arc_end - 360)

static func is_in_normal_arc(angle: float, arc_start: float, arc_end: float) -> bool:
	return angle >= arc_start and angle <= arc_end

# ============================================================================
# RESULT CONSTRUCTORS
# ============================================================================

static func create_miss_result(ship_data: Dictionary) -> Dictionary:
	return {
		ship_data = ship_data,
		hit_result = {type = "miss", reason = "no_section_found"}
	}

static func create_armor_hit_result(ship_data: Dictionary, armor_result: Dictionary, hit_pos: Vector2) -> Dictionary:
	return {
		ship_data = ship_data,
		hit_result = {
			type = "armor_hit",
			section_id = armor_result.get("section", {}).get("section_id", ""),
			damage = armor_result.get("armor_damaged", 0),
			armor_remaining = armor_result.get("section", {}).get("current_armor", 0),
			penetrated = false,
			position = hit_pos
		}
	}

static func create_penetration_result(ship_data: Dictionary, armor_result: Dictionary, internal_hit: Dictionary, hit_pos: Vector2) -> Dictionary:
	return {
		ship_data = ship_data,
		hit_result = {
			type = "armor_hit",
			section_id = armor_result.get("section", {}).get("section_id", ""),
			damage = armor_result.get("armor_damaged", 0),
			armor_remaining = armor_result.get("section", {}).get("current_armor", 0),
			penetrated = true,
			position = hit_pos,
			internal_hit = internal_hit
		}
	}

static func create_internal_hit_info(damage_result: Dictionary, hit_pos: Vector2) -> Dictionary:
	var component = damage_result.get("component", {})
	return {
		component_id = component.get("component_id", ""),
		type = component.get("type", ""),
		damage = damage_result.get("damage", 0),
		health_remaining = component.get("current_health", 0),
		old_status = damage_result.get("old_status", "operational"),
		new_status = damage_result.get("new_status", "operational"),
		position = hit_pos
	}

# ============================================================================
# QUERY FUNCTIONS - Ship State
# ============================================================================

static func calculate_total_armor(ship_data: Dictionary) -> int:
	return ship_data.get("armor_sections", []).reduce(
		func(total, section): return total + section.get("current_armor", 0),
		0
	)

static func calculate_total_internal_health(ship_data: Dictionary) -> int:
	return ship_data.get("internals", []).reduce(
		func(total, internal): return total + internal.get("current_health", 0),
		0
	)

static func is_ship_destroyed(ship_data: Dictionary) -> bool:
	if ship_data.get("status", "active") in ["destroyed", "exploding"]:
		return true

	return ship_data.get("internals", []).all(
		func(internal): return internal.get("status", "operational") == "destroyed"
	)

static func get_destroyed_components(ship_data: Dictionary) -> Array:
	return ship_data.get("internals", []) \
		.filter(func(i): return i.get("status", "operational") == "destroyed") \
		.map(func(i): return i.get("component_id", ""))

static func get_damaged_components(ship_data: Dictionary) -> Array:
	return ship_data.get("internals", []) \
		.filter(func(i): return i.get("status", "operational") == "damaged") \
		.map(func(i): return i.get("component_id", ""))

