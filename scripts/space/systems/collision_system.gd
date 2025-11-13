class_name CollisionSystem
extends RefCounted

## Pure functional collision system - IMMUTABLE DATA
## Detects hits between projectiles and ships
## Following functional programming principles

# ============================================================================
# MAIN API - Detect collisions and apply damage
# ============================================================================

## Check all collisions - returns {ships: Array, projectiles: Array, hits: Array, visual_effects: Array}
static func process_collisions(ships: Array, projectiles: Array) -> Dictionary:
	var hits = []
	var destroyed_projectile_ids = []
	var visual_effects = []

	# Filter out null values
	var valid_ships = ships.filter(func(s): return s != null)
	var valid_projectiles = projectiles.filter(func(p): return p != null)

	# Check each projectile against all ships
	for projectile in valid_projectiles:
		var hit = find_hit_for_projectile(projectile, valid_ships)
		if not hit.is_empty():
			hits.append(hit)
			destroyed_projectile_ids.append(projectile.projectile_id)

	# Apply damage to ships and generate visual effects
	var result = apply_hits_to_ships_with_effects(valid_ships, hits)
	var updated_ships = result.ships
	visual_effects = result.visual_effects

	# Remove destroyed projectiles
	var remaining_projectiles = valid_projectiles.filter(
		func(p): return not destroyed_projectile_ids.has(p.projectile_id)
	)

	return {
		ships = updated_ships,
		projectiles = remaining_projectiles,
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

## Apply all hits to ships - returns new Array of ships (deprecated, kept for compatibility)
static func apply_hits_to_ships(ships: Array, hits: Array) -> Array:
	var result = apply_hits_to_ships_with_effects(ships, hits)
	return result.ships

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

## Apply hits to ship - returns new ship (deprecated, kept for compatibility)
static func apply_hits_to_ship(ship: Dictionary, hits: Array) -> Dictionary:
	var result = apply_hits_to_ship_with_effects(ship, hits)
	return result.ship

# ============================================================================
# UTILITY
# ============================================================================

static func merge_dict(base: Dictionary, override: Dictionary) -> Dictionary:
	var result = base.duplicate(true)
	for key in override:
		result[key] = override[key]
	return result
