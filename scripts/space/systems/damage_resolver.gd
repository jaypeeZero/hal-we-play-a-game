class_name DamageResolver
extends RefCounted

## Pure functional damage resolution system
## Handles armor penetration, internal component damage, and component effects

## Resolve a projectile hit on a ship
## Returns Dictionary with hit result information
static func resolve_hit(ship_data: Dictionary, hit_position: Vector2, damage: int, projectile_angle: float) -> Dictionary:
	# Calculate angle from ship facing to hit position
	var ship_to_hit = (hit_position - ship_data.position).normalized()
	var local_angle = ship_to_hit.angle() - ship_data.rotation

	# Normalize angle to 0-360 degrees
	var hit_angle_deg = rad_to_deg(local_angle)
	while hit_angle_deg < 0:
		hit_angle_deg += 360
	while hit_angle_deg >= 360:
		hit_angle_deg -= 360

	# Find which armor section was hit
	var section = find_armor_section_at_angle(ship_data, hit_angle_deg)

	if section == null:
		return {"type": "miss", "reason": "no_section_found"}

	# Try to damage armor
	var remaining_damage = damage
	var armor_damaged = 0
	var armor_penetrated = false

	if section.current_armor > 0:
		armor_damaged = min(damage, section.current_armor)
		section.current_armor -= armor_damaged
		remaining_damage -= armor_damaged

		if remaining_damage > 0:
			armor_penetrated = true
	else:
		# Armor already destroyed, penetration automatic
		armor_penetrated = true

	var result = {
		"type": "armor_hit",
		"section_id": section.section_id,
		"damage": armor_damaged,
		"armor_remaining": section.current_armor,
		"penetrated": armor_penetrated,
		"position": hit_position
	}

	# If penetrated, hit internals
	if armor_penetrated and remaining_damage > 0:
		var internal_hit = damage_internal_component(ship_data, hit_position, remaining_damage)
		if internal_hit:
			result.internal_hit = internal_hit

	return result

## Find which armor section is hit based on angle
static func find_armor_section_at_angle(ship_data: Dictionary, angle_deg: float) -> Dictionary:
	for section in ship_data.armor_sections:
		var arc_start = section.arc.start
		var arc_end = section.arc.end

		# Handle wrap-around arcs (e.g., 300-420 degrees for rear)
		if arc_end > 360:
			# Arc wraps around 0
			if angle_deg >= arc_start or angle_deg <= (arc_end - 360):
				return section
		else:
			# Normal arc
			if angle_deg >= arc_start and angle_deg <= arc_end:
				return section

	return null

## Damage an internal component at a given position
static func damage_internal_component(ship_data: Dictionary, hit_position: Vector2, damage: int) -> Dictionary:
	# Find closest internal component to hit position
	var closest_internal = null
	var closest_distance = INF

	for internal in ship_data.internals:
		var world_pos = ship_data.position + internal.position_offset.rotated(ship_data.rotation)
		var distance = hit_position.distance_to(world_pos)

		if distance < closest_distance:
			closest_distance = distance
			closest_internal = internal

	if closest_internal == null:
		return {}

	# Apply damage
	var old_health = closest_internal.current_health
	var old_status = closest_internal.status
	closest_internal.current_health = max(0, closest_internal.current_health - damage)

	# Update status
	if closest_internal.current_health == 0:
		closest_internal.status = "destroyed"
		apply_component_destruction_effects(ship_data, closest_internal)
	elif closest_internal.current_health < closest_internal.max_health and old_status == "operational":
		closest_internal.status = "damaged"
		apply_component_damage_effects(ship_data, closest_internal)

	return {
		"component_id": closest_internal.component_id,
		"type": closest_internal.type,
		"damage": damage,
		"health_remaining": closest_internal.current_health,
		"old_status": old_status,
		"new_status": closest_internal.status,
		"position": ship_data.position + closest_internal.position_offset.rotated(ship_data.rotation)
	}

## Apply effects when a component is damaged
static func apply_component_damage_effects(ship_data: Dictionary, component: Dictionary) -> void:
	if not component.effect_on_ship.has("on_damaged"):
		return

	var effects = component.effect_on_ship.on_damaged

	for effect_key in effects:
		var multiplier = effects[effect_key]

		match effect_key:
			"max_speed":
				ship_data.stats.max_speed *= multiplier
				# Clamp current velocity
				if ship_data.velocity.length() > ship_data.stats.max_speed:
					ship_data.velocity = ship_data.velocity.normalized() * ship_data.stats.max_speed

			"acceleration":
				ship_data.stats.acceleration *= multiplier

			"turn_rate":
				ship_data.stats.turn_rate *= multiplier

			"weapon_power":
				for weapon in ship_data.weapons:
					weapon.stats.damage = int(weapon.stats.damage * multiplier)

			"accuracy":
				for weapon in ship_data.weapons:
					weapon.stats.accuracy *= multiplier

## Apply effects when a component is destroyed
static func apply_component_destruction_effects(ship_data: Dictionary, component: Dictionary) -> void:
	if not component.effect_on_ship.has("on_destroyed"):
		return

	var effects = component.effect_on_ship.on_destroyed

	for effect_key in effects:
		var value = effects[effect_key]

		match effect_key:
			"disabled":
				if value:
					ship_data.status = "disabled"
					ship_data.velocity = Vector2.ZERO
					ship_data.angular_velocity = 0.0

			"ai_disabled":
				if value:
					ship_data.orders.current_order = "drift"

			"explode":
				if value:
					ship_data.status = "exploding"

			"max_speed":
				ship_data.stats.max_speed *= value

			"acceleration":
				ship_data.stats.acceleration *= value

## Calculate total remaining armor for a ship
static func calculate_total_armor(ship_data: Dictionary) -> int:
	var total = 0
	for section in ship_data.armor_sections:
		total += section.current_armor
	return total

## Calculate total health of all internal components
static func calculate_total_internal_health(ship_data: Dictionary) -> int:
	var total = 0
	for internal in ship_data.internals:
		total += internal.current_health
	return total

## Check if ship is destroyed (all internals destroyed)
static func is_ship_destroyed(ship_data: Dictionary) -> bool:
	if ship_data.status == "destroyed" or ship_data.status == "exploding":
		return true

	for internal in ship_data.internals:
		if internal.status != "destroyed":
			return false

	return true

## Get list of destroyed components
static func get_destroyed_components(ship_data: Dictionary) -> Array:
	var destroyed = []
	for internal in ship_data.internals:
		if internal.status == "destroyed":
			destroyed.append(internal.component_id)
	return destroyed

## Get list of damaged components
static func get_damaged_components(ship_data: Dictionary) -> Array:
	var damaged = []
	for internal in ship_data.internals:
		if internal.status == "damaged":
			damaged.append(internal.component_id)
	return damaged
