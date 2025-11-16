class_name WeaponSystem
extends RefCounted

## Pure functional weapon system - IMMUTABLE DATA
## Every function returns new data, never mutates input
## Following functional programming principles:
## - Functions are deterministic
## - No side effects
## - Data is immutable
## - Declarative composition

const MIN_REACTION_TIME = 0.1
const MAX_REACTION_TIME = 0.3

# ============================================================================
# MAIN API - Returns new ship_data with updated weapons
# ============================================================================

## Update weapons and return {ship_data: Dictionary, fire_commands: Array}
static func update_weapons(ship_data: Dictionary, targets: Array, delta: float) -> Dictionary:
	if is_ship_disabled(ship_data):
		return create_update_result(ship_data, [])

	var updated_weapons = update_all_weapon_cooldowns(ship_data.weapons, delta)
	var valid_targets = get_valid_targets(targets, ship_data.team)
	var firing_result = process_weapon_firing(ship_data, updated_weapons, valid_targets)

	return create_update_result(
		create_ship_with_weapons(ship_data, firing_result.weapons),
		firing_result.commands
	)

# ============================================================================
# COMPOSITION - High Level Logic
# ============================================================================

static func process_weapon_firing(ship_data: Dictionary, weapons: Array, targets: Array) -> Dictionary:
	var results = weapons.map(func(weapon): return try_fire_weapon(ship_data, weapon, targets))
	return combine_firing_results(results)

static func try_fire_weapon(ship_data: Dictionary, weapon: Dictionary, targets: Array) -> Dictionary:
	if not is_weapon_ready(weapon):
		return create_no_fire_result(weapon)

	if targets.is_empty():
		return create_no_fire_result(weapon)

	var best_target = find_best_target_for_weapon(ship_data, weapon, targets)

	if best_target.is_empty():
		return create_no_fire_result(weapon)

	if not can_fire_at_target(ship_data, weapon, best_target):
		return create_no_fire_result(weapon)

	return create_fire_result(
		set_weapon_cooldown(weapon, calculate_cooldown_time(weapon)),
		create_fire_command(ship_data, weapon, best_target)
	)

static func combine_firing_results(results: Array) -> Dictionary:
	var weapons = results.map(func(r): return r.weapon)
	var commands = results.filter(func(r): return r.has("command")).map(func(r): return r.command)
	return {weapons = weapons, commands = commands}

# ============================================================================
# RESULT CONSTRUCTORS
# ============================================================================

static func create_update_result(ship_data: Dictionary, commands: Array) -> Dictionary:
	return {ship_data = ship_data, fire_commands = commands}

static func create_no_fire_result(weapon: Dictionary) -> Dictionary:
	return {weapon = weapon}

static func create_fire_result(weapon: Dictionary, command: Dictionary) -> Dictionary:
	return {weapon = weapon, command = command}

static func create_ship_with_weapons(ship_data: Dictionary, weapons: Array) -> Dictionary:
	var new_ship = ship_data.duplicate(true)
	new_ship.weapons = weapons
	return new_ship

# ============================================================================
# SHIP STATE PREDICATES
# ============================================================================

static func is_ship_disabled(ship_data: Dictionary) -> bool:
	return ship_data.status in ["disabled", "destroyed"]

# ============================================================================
# WEAPON STATE - Immutable Updates
# ============================================================================

static func is_weapon_ready(weapon: Dictionary) -> bool:
	return weapon.cooldown_remaining <= 0.0

static func calculate_cooldown_time(weapon: Dictionary) -> float:
	return 1.0 / weapon.stats.rate_of_fire

static func set_weapon_cooldown(weapon: Dictionary, cooldown: float) -> Dictionary:
	return DictUtils.merge_dict(weapon, {cooldown_remaining = cooldown})

static func update_all_weapon_cooldowns(weapons: Array, delta: float) -> Array:
	return weapons.map(func(w): return update_weapon_cooldown(w, delta))

static func update_weapon_cooldown(weapon: Dictionary, delta: float) -> Dictionary:
	return set_weapon_cooldown(weapon, max(0.0, weapon.cooldown_remaining - delta))

# ============================================================================
# TARGET FILTERING - Declarative Composition
# ============================================================================

static func get_valid_targets(targets: Array, own_team: int) -> Array:
	return targets \
		.filter(func(t): return not is_ally(t, own_team)) \
		.filter(func(t): return not is_destroyed(t))

static func is_ally(target: Dictionary, own_team: int) -> bool:
	return target.team == own_team

static func is_destroyed(target: Dictionary) -> bool:
	return target.status == "destroyed"

static func filter_targets_in_range(targets: Array, position: Vector2, range: float) -> Array:
	return targets.filter(func(t): return is_in_range(position, t.position, range))

static func is_in_range(from: Vector2, to: Vector2, range: float) -> bool:
	return calculate_distance(from, to) <= range

static func calculate_distance(from: Vector2, to: Vector2) -> float:
	return from.distance_to(to)

# ============================================================================
# TARGET SELECTION - Pure Priority Calculation
# ============================================================================

static func find_best_target_for_weapon(ship_data: Dictionary, weapon: Dictionary, targets: Array) -> Dictionary:
	# Filter by range, then prioritize good targets over poor ones
	var in_range_targets = filter_targets_in_range(targets, ship_data.position, weapon.stats.range)

	# Try to find a good target (effective damage)
	var good_targets = in_range_targets \
		.filter(func(t): return can_weapon_damage_target(weapon, t)) \
		.map(func(t): return add_priority(t, ship_data.position)) \
		.reduce(select_higher_priority, {})

	# If we found a good target, use it
	if not good_targets.is_empty():
		return good_targets

	# Otherwise, target anything in range (reduced effectiveness is better than nothing)
	return in_range_targets \
		.map(func(t): return add_priority(t, ship_data.position)) \
		.reduce(select_higher_priority, {})

static func add_priority(target: Dictionary, ship_pos: Vector2) -> Dictionary:
	return DictUtils.merge_dict(target, {_priority = calculate_priority(target, ship_pos)})

static func calculate_priority(target: Dictionary, ship_pos: Vector2) -> float:
	return calculate_distance_priority(ship_pos, target.position) + \
	       calculate_type_priority(target.type)

static func calculate_distance_priority(from: Vector2, to: Vector2) -> float:
	return 1000.0 - calculate_distance(from, to)

static func calculate_type_priority(ship_type: String) -> float:
	var priorities = {
		"fighter": 100.0,
		"corvette": 50.0,
		"capital": 25.0
	}
	return priorities.get(ship_type, 0.0)

static func select_higher_priority(best: Dictionary, current: Dictionary) -> Dictionary:
	if best.is_empty():
		return current
	return current if get_priority(current) > get_priority(best) else best

static func get_priority(target: Dictionary) -> float:
	return target.get("_priority", -INF)

# ============================================================================
# SIZE-BASED TARGETING - AC3 Implementation
# ============================================================================

## Check if weapon can effectively damage target
## All weapons can damage all targets, but effectiveness varies by size
## Prefer targets within effective range or heavily damaged targets
static func can_weapon_damage_target(weapon: Dictionary, target: Dictionary) -> bool:
	# All weapons can damage all targets (just at reduced effectiveness for size mismatch)
	# This function now checks if target is a GOOD choice (effective damage)
	var weapon_size = weapon.stats.get("size", 1)

	# Target is good if heavily damaged (>50% armor gone = can hit internals easily)
	var armor_percentage = calculate_armor_percentage(target)
	if armor_percentage < 0.5:
		return true

	# Target is good if we have at least one armor section in effective range
	return can_damage_any_armor_section_effectively(weapon_size, target)

## Calculate percentage of armor remaining on target (0.0 to 1.0)
static func calculate_armor_percentage(target: Dictionary) -> float:
	var armor_sections = target.get("armor_sections", [])
	if armor_sections.is_empty():
		return 0.0  # No armor sections means 0% armored

	var total_max_armor = 0
	var total_current_armor = 0

	for section in armor_sections:
		total_max_armor += section.get("max_armor", 0)
		total_current_armor += section.get("current_armor", 0)

	if total_max_armor == 0:
		return 0.0

	return float(total_current_armor) / float(total_max_armor)

## Check if weapon can effectively damage any armor section on target
## "Effectively" means within the weapon's optimal range (weapon_size to weapon_size+1)
static func can_damage_any_armor_section_effectively(weapon_size: int, target: Dictionary) -> bool:
	var armor_sections = target.get("armor_sections", [])

	for section in armor_sections:
		var armor_size = section.get("size", 1)
		# Effective damage range: armor_size <= weapon_size + 1
		if armor_size <= weapon_size + 1:
			return true

	return false

## Check if ship has ANY weapon that can damage the target
## Used by AI to filter valid targets in awareness system
static func can_ship_damage_target(ship_data: Dictionary, target: Dictionary) -> bool:
	var weapons = ship_data.get("weapons", [])

	# If ship has no weapons defined, allow targeting (backward compatibility for tests)
	if weapons.is_empty():
		return true

	for weapon in weapons:
		if can_weapon_damage_target(weapon, target):
			return true

	return false

# ============================================================================
# FIRING ARC VALIDATION
# ============================================================================

static func can_fire_at_target(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> bool:
	return is_in_range(ship_data.position, target.position, weapon.stats.range) and \
	       is_in_firing_arc(ship_data, weapon, target)

static func is_in_firing_arc(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> bool:
	var relative_angle = calculate_relative_angle_to_target(ship_data, weapon, target)
	return is_angle_in_arc(relative_angle, weapon.arc.min, weapon.arc.max)

static func calculate_relative_angle_to_target(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> float:
	var to_target = calculate_direction_to_target(ship_data.position, target.position)
	var target_angle = calculate_angle_from_direction(to_target)
	var weapon_angle = calculate_weapon_world_angle(ship_data.rotation, weapon.facing)
	return normalize_angle_degrees(rad_to_deg(target_angle - weapon_angle))

static func calculate_direction_to_target(from: Vector2, to: Vector2) -> Vector2:
	return (to - from).normalized()

static func calculate_angle_from_direction(direction: Vector2) -> float:
	return direction.angle()

static func calculate_weapon_world_angle(ship_rotation: float, weapon_facing: float) -> float:
	return ship_rotation + weapon_facing

static func normalize_angle_degrees(angle_deg: float) -> float:
	var normalized = fmod(angle_deg, 360.0)
	if normalized > 180.0:
		normalized -= 360.0
	if normalized < -180.0:
		normalized += 360.0
	return normalized

static func is_angle_in_arc(angle_deg: float, arc_min: float, arc_max: float) -> bool:
	return angle_deg >= arc_min and angle_deg <= arc_max

# ============================================================================
# FIRE COMMAND CREATION
# ============================================================================

static func create_fire_command(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> Dictionary:
	var lead_pos = calculate_lead_position(ship_data, weapon, target)
	var weapon_pos = calculate_weapon_world_position(ship_data, weapon)
	var direction = calculate_firing_direction(weapon_pos, lead_pos, ship_data, weapon)

	return {
		type = "fire_projectile",
		ship_id = ship_data.ship_id,
		weapon_id = weapon.weapon_id,
		spawn_position = weapon_pos,
		direction = direction,
		velocity = calculate_projectile_velocity(direction, weapon.stats.projectile_speed),
		damage = calculate_final_damage(weapon.stats.damage, ship_data),
		speed = weapon.stats.projectile_speed,
		target_id = target.ship_id,
		delay = generate_reaction_delay(),
		accuracy = calculate_final_accuracy(weapon.stats.accuracy, ship_data),
		weapon_size = weapon.stats.get("size", 1)
	}

static func calculate_weapon_world_position(ship_data: Dictionary, weapon: Dictionary) -> Vector2:
	return ship_data.position + weapon.position_offset.rotated(ship_data.rotation)

static func calculate_lead_position(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> Vector2:
	if not target.has("velocity"):
		return target.position

	var weapon_pos = calculate_weapon_world_position(ship_data, weapon)
	var time_to_impact = calculate_time_to_impact(weapon_pos, target.position, weapon.stats.projectile_speed)
	return predict_target_position(target.position, target.velocity, time_to_impact)

static func calculate_time_to_impact(from: Vector2, to: Vector2, projectile_speed: float) -> float:
	return calculate_distance(from, to) / projectile_speed

static func predict_target_position(current_pos: Vector2, velocity: Vector2, time: float) -> Vector2:
	return current_pos + (velocity * time)

static func calculate_firing_direction(weapon_pos: Vector2, target_pos: Vector2, ship_data: Dictionary, weapon: Dictionary) -> Vector2:
	var perfect_direction = calculate_direction_to_target(weapon_pos, target_pos)
	var accuracy = calculate_final_accuracy(weapon.stats.accuracy, ship_data)
	return apply_accuracy_spread(perfect_direction, accuracy)

static func apply_accuracy_spread(direction: Vector2, accuracy: float) -> Vector2:
	var spread_angle = calculate_spread_angle(accuracy)
	var random_spread = generate_random_spread(spread_angle)
	return direction.rotated(random_spread)

static func calculate_spread_angle(accuracy: float) -> float:
	return (1.0 - accuracy) * PI / 6.0  # Up to 30 degrees at 0 accuracy

static func generate_random_spread(max_spread: float) -> float:
	return randf_range(-max_spread, max_spread)

static func generate_reaction_delay() -> float:
	return randf_range(MIN_REACTION_TIME, MAX_REACTION_TIME)

static func calculate_projectile_velocity(direction: Vector2, speed: float) -> Vector2:
	return direction * speed

# ============================================================================
# DAMAGE MODIFIERS - Find, don't mutate
# ============================================================================

static func calculate_final_damage(base_damage: int, ship_data: Dictionary) -> int:
	return base_damage

static func calculate_final_accuracy(base_accuracy: float, ship_data: Dictionary) -> float:
	return base_accuracy

# ============================================================================
# PUBLIC QUERY FUNCTIONS
# ============================================================================

static func get_fireable_weapons(ship_data: Dictionary, target: Dictionary) -> Array:
	return ship_data.weapons.filter(
		func(w): return is_weapon_ready(w) and can_fire_at_target(ship_data, w, target)
	)

static func calculate_hit_probability(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> float:
	var base = weapon.stats.accuracy
	var range_factor = calculate_range_factor(ship_data.position, target.position, weapon.stats.range)
	var velocity_factor = calculate_velocity_factor(target)
	return base * range_factor * velocity_factor

static func calculate_range_factor(from: Vector2, to: Vector2, max_range: float) -> float:
	var distance = calculate_distance(from, to)
	return 1.0 - (distance / max_range) * 0.3  # Up to 30% penalty

static func calculate_velocity_factor(target: Dictionary) -> float:
	if not target.has("velocity"):
		return 1.0
	var speed = target.velocity.length()
	return 1.0 - min(speed / 300.0, 0.5)  # Up to 50% penalty
