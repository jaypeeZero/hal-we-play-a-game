class_name WeaponSystem
extends RefCounted

## Pure functional weapon system
## Handles weapon firing, cooldowns, targeting, and accuracy calculations

## Human reaction time range (in seconds)
const MIN_REACTION_TIME = 0.1  # 100ms - very fast
const MAX_REACTION_TIME = 0.3  # 300ms - average

## Update all weapons on a ship and return firing commands
## Returns Array of fire command Dictionaries
static func update_weapons(ship_data: Dictionary, targets: Array, delta: float) -> Array:
	if ship_data.status == "disabled" or ship_data.status == "destroyed":
		return []

	var fire_commands = []

	# Update cooldowns
	for weapon in ship_data.weapons:
		weapon.cooldown_remaining = max(0.0, weapon.cooldown_remaining - delta)

	# Try to fire at targets
	for weapon in ship_data.weapons:
		if weapon.cooldown_remaining > 0.0:
			continue

		# Find best target for this weapon
		var target = find_best_target(ship_data, weapon, targets)
		if target == null:
			continue

		# Check if can fire at target
		if not can_fire_at_target(ship_data, weapon, target):
			continue

		# Calculate firing solution
		var fire_command = create_fire_command(ship_data, weapon, target)
		if fire_command:
			fire_commands.append(fire_command)

			# Set weapon cooldown
			weapon.cooldown_remaining = 1.0 / weapon.stats.rate_of_fire

	return fire_commands

## Find the best target for a weapon
static func find_best_target(ship_data: Dictionary, weapon: Dictionary, targets: Array) -> Dictionary:
	var best_target = null
	var best_priority = -INF

	for target in targets:
		# Skip allies
		if target.team == ship_data.team:
			continue

		# Skip destroyed targets
		if target.status == "destroyed":
			continue

		# Calculate priority (closer = higher priority)
		var distance = ship_data.position.distance_to(target.position)

		# Out of range
		if distance > weapon.stats.range:
			continue

		# Calculate priority based on distance and target type
		var priority = 1000.0 - distance

		# Prioritize smaller ships (easier to destroy)
		match target.type:
			"fighter":
				priority += 100
			"corvette":
				priority += 50
			"capital":
				priority += 25

		if priority > best_priority:
			best_priority = priority
			best_target = target

	return best_target

## Check if a weapon can fire at a target (range and arc checks)
static func can_fire_at_target(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> bool:
	# Distance check
	var distance = ship_data.position.distance_to(target.position)
	if distance > weapon.stats.range:
		return false

	# Angle check (is target in weapon's firing arc?)
	var to_target = (target.position - ship_data.position).normalized()
	var target_angle = to_target.angle()

	# Weapon's world angle
	var weapon_world_angle = ship_data.rotation + weapon.facing

	# Relative angle to weapon facing
	var relative_angle = target_angle - weapon_world_angle

	# Normalize to -PI to PI
	while relative_angle > PI:
		relative_angle -= TAU
	while relative_angle < -PI:
		relative_angle += TAU

	# Convert to degrees
	var relative_angle_deg = rad_to_deg(relative_angle)

	# Check if in arc
	if relative_angle_deg < weapon.arc.min or relative_angle_deg > weapon.arc.max:
		return false

	return true

## Create a fire command for a weapon
static func create_fire_command(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> Dictionary:
	# Calculate lead position (predict where target will be)
	var lead_position = calculate_lead_position(ship_data, weapon, target)

	# Apply modifiers from ship damage
	var power_modifier = get_power_modifier(ship_data)
	var accuracy_modifier = get_accuracy_modifier(ship_data)

	# Calculate final accuracy
	var final_accuracy = weapon.stats.accuracy * accuracy_modifier

	# Add human reaction time delay
	var reaction_delay = randf_range(MIN_REACTION_TIME, MAX_REACTION_TIME)

	# Weapon world position
	var weapon_world_pos = ship_data.position + weapon.position_offset.rotated(ship_data.rotation)

	# Calculate direction with accuracy spread
	var perfect_direction = (lead_position - weapon_world_pos).normalized()
	var spread_angle = (1.0 - final_accuracy) * PI / 6.0  # Up to 30 degrees spread at 0 accuracy
	var spread = randf_range(-spread_angle, spread_angle)
	var actual_direction = perfect_direction.rotated(spread)

	return {
		"type": "fire_projectile",
		"ship_id": ship_data.ship_id,
		"weapon_id": weapon.weapon_id,
		"spawn_position": weapon_world_pos,
		"direction": actual_direction,
		"velocity": actual_direction * weapon.stats.projectile_speed,
		"damage": int(weapon.stats.damage * power_modifier),
		"speed": weapon.stats.projectile_speed,
		"target_id": target.ship_id,
		"delay": reaction_delay,
		"accuracy": final_accuracy
	}

## Calculate lead position for moving target
static func calculate_lead_position(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> Vector2:
	if not target.has("velocity"):
		return target.position

	var weapon_world_pos = ship_data.position + weapon.position_offset.rotated(ship_data.rotation)
	var distance = weapon_world_pos.distance_to(target.position)
	var time_to_impact = distance / weapon.stats.projectile_speed

	# Predict where target will be
	return target.position + (target.velocity * time_to_impact)

## Get power modifier from ship damage (power core status)
static func get_power_modifier(ship_data: Dictionary) -> float:
	for internal in ship_data.internals:
		if internal.type == "power":
			if internal.status == "destroyed":
				return 0.0  # No power, no weapons
			elif internal.status == "damaged":
				if internal.effect_on_ship.on_damaged.has("weapon_power"):
					return internal.effect_on_ship.on_damaged.weapon_power
	return 1.0

## Get accuracy modifier from ship damage (bridge/control status)
static func get_accuracy_modifier(ship_data: Dictionary) -> float:
	for internal in ship_data.internals:
		if internal.type == "control":
			if internal.status == "destroyed":
				return 0.3  # Heavily reduced accuracy
			elif internal.status == "damaged":
				if internal.effect_on_ship.on_damaged.has("accuracy"):
					return internal.effect_on_ship.on_damaged.accuracy
	return 1.0

## Calculate hit probability for debugging/UI
static func calculate_hit_probability(ship_data: Dictionary, weapon: Dictionary, target: Dictionary) -> float:
	var base_accuracy = weapon.stats.accuracy
	var accuracy_mod = get_accuracy_modifier(ship_data)

	# Distance penalty
	var distance = ship_data.position.distance_to(target.position)
	var range_factor = 1.0 - (distance / weapon.stats.range) * 0.3  # Up to 30% penalty at max range

	# Target velocity penalty (harder to hit fast targets)
	var velocity_factor = 1.0
	if target.has("velocity"):
		var target_speed = target.velocity.length()
		velocity_factor = 1.0 - min(target_speed / 300.0, 0.5)  # Up to 50% penalty

	return base_accuracy * accuracy_mod * range_factor * velocity_factor

## Get all weapons that can currently fire at a target
static func get_fireable_weapons(ship_data: Dictionary, target: Dictionary) -> Array:
	var fireable = []

	for weapon in ship_data.weapons:
		if weapon.cooldown_remaining <= 0.0 and can_fire_at_target(ship_data, weapon, target):
			fireable.append(weapon)

	return fireable
