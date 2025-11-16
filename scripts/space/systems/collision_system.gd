class_name CollisionSystem
extends RefCounted

## Pure functional collision system - IMMUTABLE DATA
## Detects hits between projectiles and ships
## Following functional programming principles

# ============================================================================
# MAIN API - Detect collisions and apply damage
# ============================================================================

## Check all collisions - returns {ships: Array, projectiles: Array, obstacles: Array, hits: Array, visual_effects: Array}
static func process_collisions(ships: Array, projectiles: Array, obstacles: Array = []) -> Dictionary:
	var hits = []
	var destroyed_projectile_ids = []
	var visual_effects = []

	# Filter out null values
	var valid_ships = ships.filter(func(s): return s != null)
	var valid_projectiles = projectiles.filter(func(p): return p != null)
	var valid_obstacles = obstacles.filter(func(o): return o != null and o.get("status", "operational") != "destroyed")

	# Check each projectile against all ships
	for projectile in valid_projectiles:
		var hit = find_hit_for_projectile(projectile, valid_ships)
		if not hit.is_empty():
			hits.append(hit)
			destroyed_projectile_ids.append(projectile.projectile_id)
			continue  # Projectile can only hit one target

		# Check projectile against obstacles
		var obstacle_hit = find_obstacle_hit_for_projectile(projectile, valid_obstacles)
		if not obstacle_hit.is_empty():
			destroyed_projectile_ids.append(projectile.projectile_id)
			# Create visual effect for projectile hitting obstacle
			var effect = VisualEffectSystem.create_effect("effect_projectile_impact", obstacle_hit.hit_position, 0.3)
			visual_effects.append(effect)

	# Apply damage to ships and generate visual effects
	var result = apply_hits_to_ships_with_effects(valid_ships, hits)
	var updated_ships = result.ships
	visual_effects.append_array(result.visual_effects)

	# Apply damage to obstacles from projectiles
	var obstacle_result = apply_projectile_hits_to_obstacles(valid_obstacles, valid_projectiles, destroyed_projectile_ids)
	var updated_obstacles = obstacle_result.obstacles

	# Remove destroyed projectiles
	var remaining_projectiles = valid_projectiles.filter(
		func(p): return not destroyed_projectile_ids.has(p.projectile_id)
	)

	return {
		ships = updated_ships,
		projectiles = remaining_projectiles,
		obstacles = updated_obstacles,
		hits = hits,
		visual_effects = visual_effects
	}

# ============================================================================
# HIT DETECTION
# ============================================================================

## Find if projectile hits any ship
static func find_hit_for_projectile(projectile: Dictionary, ships: Array) -> Dictionary:
	for ship in ships:
		if ship == null:
			continue
		if can_projectile_hit_ship(projectile, ship):
			if is_projectile_colliding_with_ship(projectile, ship):
				return create_hit(projectile, ship)
	return {}

static func can_projectile_hit_ship(projectile: Dictionary, ship: Dictionary) -> bool:
	# Projectile can't hit same team
	if projectile.team == ship.team:
		return false

	# Can't hit destroyed ships
	if ship.status == "destroyed":
		return false

	return true

static func is_projectile_colliding_with_ship(projectile: Dictionary, ship: Dictionary) -> bool:
	var distance = projectile.position.distance_to(ship.position)
	var collision_radius = ship.stats.size + 3.0  # ship size + projectile size
	return distance <= collision_radius

static func create_hit(projectile: Dictionary, ship: Dictionary) -> Dictionary:
	return {
		projectile_id = projectile.projectile_id,
		ship_id = ship.ship_id,
		hit_position = projectile.position,
		damage = projectile.damage,
		projectile_angle = projectile.velocity.angle(),
		source_id = projectile.source_id
	}

# ============================================================================
# OBSTACLE HIT DETECTION
# ============================================================================

## Find if projectile hits any obstacle
static func find_obstacle_hit_for_projectile(projectile: Dictionary, obstacles: Array) -> Dictionary:
	for obstacle in obstacles:
		if obstacle == null:
			continue
		if is_projectile_colliding_with_obstacle(projectile, obstacle):
			return create_obstacle_hit(projectile, obstacle)
	return {}

static func is_projectile_colliding_with_obstacle(projectile: Dictionary, obstacle: Dictionary) -> bool:
	# Only check if obstacle blocks projectiles
	if not obstacle.get("blocks_projectiles", true):
		return false

	var distance = projectile.position.distance_to(obstacle.position)
	var collision_radius = obstacle.radius + 3.0  # obstacle radius + projectile size
	return distance <= collision_radius

static func create_obstacle_hit(projectile: Dictionary, obstacle: Dictionary) -> Dictionary:
	return {
		projectile_id = projectile.projectile_id,
		obstacle_id = obstacle.obstacle_id,
		hit_position = projectile.position,
		damage = projectile.damage
	}

## Check if ship is colliding with any obstacle - returns closest obstacle or empty dict
static func find_obstacle_collision_for_ship(ship: Dictionary, obstacles: Array) -> Dictionary:
	var closest_obstacle = {}
	var min_distance = INF

	for obstacle in obstacles:
		if obstacle == null:
			continue
		if not obstacle.get("blocks_movement", true):
			continue

		var distance = ship.position.distance_to(obstacle.position)
		var collision_radius = ship.stats.size + obstacle.radius

		if distance <= collision_radius and distance < min_distance:
			min_distance = distance
			closest_obstacle = obstacle

	return closest_obstacle

# ============================================================================
# DAMAGE APPLICATION
# ============================================================================

## Apply all hits to ships with visual effects - returns {ships: Array, visual_effects: Array}
static func apply_hits_to_ships_with_effects(ships: Array, hits: Array) -> Dictionary:
	# Group hits by ship_id
	var hits_by_ship = {}
	for hit in hits:
		if not hits_by_ship.has(hit.ship_id):
			hits_by_ship[hit.ship_id] = []
		hits_by_ship[hit.ship_id].append(hit)

	var updated_ships = []
	var all_visual_effects = []

	# Apply hits to each ship
	for ship in ships:
		var ship_hits = hits_by_ship.get(ship.ship_id, [])
		var result = apply_hits_to_ship_with_effects(ship, ship_hits)
		updated_ships.append(result.ship)
		all_visual_effects.append_array(result.visual_effects)

	return {
		ships = updated_ships,
		visual_effects = all_visual_effects
	}

## Apply hits to ship with visual effects - returns {ship: Dictionary, visual_effects: Array}
static func apply_hits_to_ship_with_effects(ship: Dictionary, hits: Array) -> Dictionary:
	if hits.is_empty():
		return {ship = ship, visual_effects = []}

	var updated_ship = ship
	var visual_effects = []

	# Apply each hit sequentially (immutable)
	for hit in hits:
		var damage_result = DamageResolver.resolve_hit(
			updated_ship,
			hit.hit_position,
			hit.damage,
			hit.projectile_angle
		)
		updated_ship = damage_result.ship_data

		# Create visual effect based on damage result
		var effect = VisualEffectSystem.create_damage_effect(damage_result.hit_result, hit.hit_position)
		visual_effects.append(effect)

		# Log damage event
		if BattleEventLoggerAutoload.service:
			BattleEventLoggerAutoload.log_damage_dealt(
				ship.ship_id,      # victim_id
				hit.source_id,     # attacker_id
				hit.damage         # amount
			)

	return {ship = updated_ship, visual_effects = visual_effects}

# ============================================================================
# OBSTACLE DAMAGE APPLICATION
# ============================================================================

## Apply projectile damage to obstacles - returns {obstacles: Array}
static func apply_projectile_hits_to_obstacles(obstacles: Array, projectiles: Array, hit_projectile_ids: Array) -> Dictionary:
	var updated_obstacles = []

	for obstacle in obstacles:
		var updated_obstacle = obstacle.duplicate(true)
		var took_damage = false

		# Only destructible obstacles can take damage
		if not obstacle.get("destructible", true):
			updated_obstacles.append(updated_obstacle)
			continue

		# Check each projectile that hit this obstacle
		for projectile in projectiles:
			if not hit_projectile_ids.has(projectile.projectile_id):
				continue

			# Check if this projectile hit this obstacle
			if is_projectile_colliding_with_obstacle(projectile, obstacle):
				updated_obstacle.current_health -= projectile.damage
				took_damage = true

		# Update status based on health
		if updated_obstacle.current_health <= 0:
			updated_obstacle.status = "destroyed"
		elif took_damage and updated_obstacle.current_health <= updated_obstacle.max_health * 0.5:
			updated_obstacle.status = "damaged"

		updated_obstacles.append(updated_obstacle)

	return {obstacles = updated_obstacles}

# ============================================================================
# PHYSICAL COLLISION RESOLUTION (Ship-Ship & Ship-Obstacle)
# ============================================================================

## Process all physical collisions between ships and obstacles
## Returns {ships: Array, obstacles: Array, collision_events: Array}
static func process_physical_collisions(ships: Array, obstacles: Array) -> Dictionary:
	var collision_events = []
	var updated_ships = ships.duplicate()
	var updated_obstacles = obstacles.duplicate()

	# Process ship-obstacle collisions
	for i in range(updated_ships.size()):
		var ship = updated_ships[i]
		if ship == null or ship.status == "destroyed":
			continue

		for j in range(updated_obstacles.size()):
			var obstacle = updated_obstacles[j]
			if obstacle == null or obstacle.get("status", "operational") == "destroyed":
				continue
			if not obstacle.get("blocks_movement", true):
				continue

			var collision_result = check_and_resolve_ship_obstacle_collision(ship, obstacle)
			if not collision_result.is_empty():
				updated_ships[i] = collision_result.ship
				updated_obstacles[j] = collision_result.obstacle
				collision_events.append(collision_result.event)

	# Process ship-ship collisions
	for i in range(updated_ships.size()):
		for j in range(i + 1, updated_ships.size()):
			var ship1 = updated_ships[i]
			var ship2 = updated_ships[j]

			if ship1 == null or ship2 == null:
				continue
			if ship1.status == "destroyed" or ship2.status == "destroyed":
				continue

			var collision_result = check_and_resolve_ship_ship_collision(ship1, ship2)
			if not collision_result.is_empty():
				updated_ships[i] = collision_result.ship1
				updated_ships[j] = collision_result.ship2
				collision_events.append(collision_result.event)

	return {
		ships = updated_ships,
		obstacles = updated_obstacles,
		collision_events = collision_events
	}

## Check and resolve collision between ship and obstacle
## Returns {ship: Dictionary, obstacle: Dictionary, event: Dictionary} or empty dict
static func check_and_resolve_ship_obstacle_collision(ship: Dictionary, obstacle: Dictionary) -> Dictionary:
	var distance = ship.position.distance_to(obstacle.position)
	var collision_radius = ship.stats.size + obstacle.radius

	# Not colliding
	if distance > collision_radius:
		return {}

	# Calculate collision normal (from obstacle to ship)
	var collision_normal = (ship.position - obstacle.position)
	if collision_normal.length() < 0.1:
		# Objects are exactly on top of each other - use random direction
		collision_normal = Vector2(randf() * 2 - 1, randf() * 2 - 1)
	collision_normal = collision_normal.normalized()

	# Calculate relative velocity
	var obstacle_velocity = obstacle.get("velocity", Vector2.ZERO)
	var relative_velocity = ship.velocity - obstacle_velocity
	var velocity_along_normal = relative_velocity.dot(collision_normal)

	# Objects are moving apart - no collision response needed
	if velocity_along_normal > 0:
		return {}

	# Calculate impact velocity (for damage)
	var impact_speed = abs(velocity_along_normal)

	# Apply elastic collision physics
	var ship_mass = ship.stats.mass
	var obstacle_mass = obstacle.mass
	var restitution = 0.4  # Coefficient of restitution (0 = perfectly inelastic, 1 = perfectly elastic)

	# Calculate impulse scalar: j = -(1 + e) * v_rel • n / (1/m1 + 1/m2)
	var impulse_scalar = -(1.0 + restitution) * velocity_along_normal / (1.0 / ship_mass + 1.0 / obstacle_mass)
	var impulse = collision_normal * impulse_scalar

	# Apply impulse to ship and obstacle
	var updated_ship = ship.duplicate(true)
	var updated_obstacle = obstacle.duplicate(true)

	updated_ship.velocity += impulse / ship_mass

	# Only move obstacle if it's moveable (not platforms/stations)
	if obstacle.get("destructible", true):
		var new_obstacle_velocity = obstacle_velocity - impulse / obstacle_mass
		updated_obstacle.velocity = new_obstacle_velocity

	# Separate the objects to prevent overlap
	var separation = (collision_radius - distance) * 1.01
	var separation_ratio = ship_mass / (ship_mass + obstacle_mass)
	updated_ship.position += collision_normal * separation * (1.0 - separation_ratio)

	# Only move obstacle if it's moveable
	if obstacle.get("destructible", true):
		updated_obstacle.position -= collision_normal * separation * separation_ratio

	# Calculate damage based on impact speed and size discrepancy
	var damage = calculate_collision_damage(ship, obstacle, impact_speed)
	if damage > 0:
		# Apply damage to ship using DamageResolver
		var damage_result = DamageResolver.resolve_hit(
			updated_ship,
			ship.position,  # Hit position
			damage,
			collision_normal.angle()  # Impact angle
		)
		updated_ship = damage_result.ship_data

	# Create collision event
	var event = {
		type = "ship_obstacle_collision",
		ship_id = ship.ship_id,
		obstacle_id = obstacle.obstacle_id,
		impact_speed = impact_speed,
		damage = damage,
		position = ship.position
	}

	return {
		ship = updated_ship,
		obstacle = updated_obstacle,
		event = event
	}

## Check and resolve collision between two ships
## Returns {ship1: Dictionary, ship2: Dictionary, event: Dictionary} or empty dict
static func check_and_resolve_ship_ship_collision(ship1: Dictionary, ship2: Dictionary) -> Dictionary:
	var distance = ship1.position.distance_to(ship2.position)
	var collision_radius = ship1.stats.size + ship2.stats.size

	# Not colliding
	if distance > collision_radius:
		return {}

	# Calculate collision normal (from ship2 to ship1)
	var collision_normal = (ship1.position - ship2.position)
	if collision_normal.length() < 0.1:
		# Ships are exactly on top of each other - use random direction
		collision_normal = Vector2(randf() * 2 - 1, randf() * 2 - 1)
	collision_normal = collision_normal.normalized()

	# Calculate relative velocity
	var relative_velocity = ship1.velocity - ship2.velocity
	var velocity_along_normal = relative_velocity.dot(collision_normal)

	# Ships are moving apart - no collision response needed
	if velocity_along_normal > 0:
		return {}

	# Calculate impact velocity
	var impact_speed = abs(velocity_along_normal)

	# Apply elastic collision physics
	var mass1 = ship1.stats.mass
	var mass2 = ship2.stats.mass
	var restitution = 0.3  # Ship-ship collisions are less elastic (more crumpling)

	# Calculate impulse scalar
	var impulse_scalar = -(1.0 + restitution) * velocity_along_normal / (1.0 / mass1 + 1.0 / mass2)
	var impulse = collision_normal * impulse_scalar

	# Apply impulse to both ships
	var updated_ship1 = ship1.duplicate(true)
	var updated_ship2 = ship2.duplicate(true)

	updated_ship1.velocity += impulse / mass1
	updated_ship2.velocity -= impulse / mass2

	# Separate the ships to prevent overlap
	var separation = (collision_radius - distance) * 1.01
	var separation_ratio = mass1 / (mass1 + mass2)
	updated_ship1.position += collision_normal * separation * (1.0 - separation_ratio)
	updated_ship2.position -= collision_normal * separation * separation_ratio

	# Calculate damage to both ships based on impact speed and size
	var damage1 = calculate_ship_collision_damage(ship1, ship2, impact_speed)
	var damage2 = calculate_ship_collision_damage(ship2, ship1, impact_speed)

	# Apply damage to ship1
	if damage1 > 0:
		var damage_result = DamageResolver.resolve_hit(
			updated_ship1,
			ship1.position,
			damage1,
			collision_normal.angle()
		)
		updated_ship1 = damage_result.ship_data

	# Apply damage to ship2
	if damage2 > 0:
		var damage_result = DamageResolver.resolve_hit(
			updated_ship2,
			ship2.position,
			damage2,
			(collision_normal * -1).angle()
		)
		updated_ship2 = damage_result.ship_data

	# Create collision event
	var event = {
		type = "ship_ship_collision",
		ship1_id = ship1.ship_id,
		ship2_id = ship2.ship_id,
		impact_speed = impact_speed,
		damage1 = damage1,
		damage2 = damage2,
		position = (ship1.position + ship2.position) / 2.0
	}

	return {
		ship1 = updated_ship1,
		ship2 = updated_ship2,
		event = event
	}

## Calculate damage from ship-obstacle collision based on impact speed and size discrepancy
static func calculate_collision_damage(ship: Dictionary, obstacle: Dictionary, impact_speed: float) -> float:
	# No damage from very slow collisions
	if impact_speed < 20.0:
		return 0.0

	# Base damage scales with impact speed squared (kinetic energy)
	var base_damage = pow(impact_speed / 50.0, 2.0) * 10.0

	# Size discrepancy multiplier - bigger obstacles hurt more
	var ship_size = ship.stats.size
	var obstacle_size = obstacle.radius
	var size_ratio = obstacle_size / ship_size

	# Larger obstacles deal significantly more damage
	var size_multiplier = 1.0 + (size_ratio - 1.0) * 1.5
	size_multiplier = max(0.5, size_multiplier)  # Minimum 0.5x for small obstacles

	# Mass matters too - heavier obstacles deal more damage
	var mass_ratio = obstacle.mass / ship.stats.mass
	var mass_multiplier = sqrt(mass_ratio)  # Square root to smooth the curve

	var total_damage = base_damage * size_multiplier * mass_multiplier

	return total_damage

## Calculate damage from ship-ship collision
static func calculate_ship_collision_damage(receiving_ship: Dictionary, impacting_ship: Dictionary, impact_speed: float) -> float:
	# No damage from very slow collisions
	if impact_speed < 15.0:
		return 0.0

	# Base damage scales with impact speed
	var base_damage = pow(impact_speed / 40.0, 2.0) * 8.0

	# Larger ships hitting you deal more damage
	var size_ratio = impacting_ship.stats.size / receiving_ship.stats.size
	var size_multiplier = sqrt(size_ratio)

	# Heavier ships deal more damage
	var mass_ratio = impacting_ship.stats.mass / receiving_ship.stats.mass
	var mass_multiplier = sqrt(mass_ratio)

	var total_damage = base_damage * size_multiplier * mass_multiplier

	return total_damage
