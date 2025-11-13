class_name CollisionSystem
extends RefCounted

## Pure functional collision system - IMMUTABLE DATA
## Detects hits between projectiles and ships
## Following functional programming principles

# ============================================================================
# MAIN API - Detect collisions and apply damage
# ============================================================================

## Check all collisions - returns {ships: Array, projectiles: Array, hits: Array}
static func process_collisions(ships: Array, projectiles: Array) -> Dictionary:
	var hits = []
	var destroyed_projectile_ids = []

	# Check each projectile against all ships
	for projectile in projectiles:
		var hit = find_hit_for_projectile(projectile, ships)
		if not hit.is_empty():
			hits.append(hit)
			destroyed_projectile_ids.append(projectile.projectile_id)

	# Apply damage to ships
	var updated_ships = apply_hits_to_ships(ships, hits)

	# Remove destroyed projectiles
	var remaining_projectiles = projectiles.filter(
		func(p): return not destroyed_projectile_ids.has(p.projectile_id)
	)

	return {
		ships = updated_ships,
		projectiles = remaining_projectiles,
		hits = hits
	}

# ============================================================================
# HIT DETECTION
# ============================================================================

## Find if projectile hits any ship
static func find_hit_for_projectile(projectile: Dictionary, ships: Array) -> Dictionary:
	for ship in ships:
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
# DAMAGE APPLICATION
# ============================================================================

## Apply all hits to ships - returns new Array of ships
static func apply_hits_to_ships(ships: Array, hits: Array) -> Array:
	# Group hits by ship_id
	var hits_by_ship = {}
	for hit in hits:
		if not hits_by_ship.has(hit.ship_id):
			hits_by_ship[hit.ship_id] = []
		hits_by_ship[hit.ship_id].append(hit)

	# Apply hits to each ship
	return ships.map(func(ship): return apply_hits_to_ship(ship, hits_by_ship.get(ship.ship_id, [])))

static func apply_hits_to_ship(ship: Dictionary, hits: Array) -> Dictionary:
	if hits.is_empty():
		return ship

	# Apply each hit sequentially (immutable)
	var updated_ship = ship
	for hit in hits:
		var damage_result = DamageResolver.resolve_hit(
			updated_ship,
			hit.hit_position,
			hit.damage,
			hit.projectile_angle
		)
		updated_ship = damage_result.ship_data

		# Log damage event
		if BattleEventLoggerAutoload.logger:
			BattleEventLoggerAutoload.logger.log_damage_dealt(
				hit.source_id,
				ship.ship_id,
				hit.damage
			)

	return updated_ship

# ============================================================================
# UTILITY
# ============================================================================

static func merge_dict(base: Dictionary, override: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	for key in override:
		result[key] = override[key]
	return result
