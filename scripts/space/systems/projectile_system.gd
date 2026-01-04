class_name ProjectileSystem
extends RefCounted

## Pure functional projectile system - IMMUTABLE DATA
## Processes projectile movement, lifetime, and spawning
## Following functional programming principles

# ============================================================================
# MAIN API - Process projectiles
# ============================================================================

## Update single projectile - returns {projectile: Dictionary, expired: bool}
static func update_projectile(projectile_data: Dictionary, delta: float) -> Dictionary:
	var new_position = projectile_data.position + projectile_data.velocity * delta
	var new_lifetime = projectile_data.lifetime + delta

	if new_lifetime >= projectile_data.max_lifetime:
		return {projectile = projectile_data, expired = true}

	return {
		projectile = DictUtils.merge_dict(projectile_data, {
			position = new_position,
			lifetime = new_lifetime
		}),
		expired = false
	}

## Update all projectiles - returns {projectiles: Array, expired_ids: Array}
static func update_all_projectiles(projectiles: Array, delta: float) -> Dictionary:
	var results = projectiles.map(func(p): return update_projectile(p, delta))

	return {
		projectiles = results.filter(func(r): return not r.expired).map(func(r): return r.projectile),
		expired_ids = results.filter(func(r): return r.expired).map(func(r): return r.projectile.projectile_id)
	}

# ============================================================================
# PROJECTILE CREATION
# ============================================================================

static var _next_projectile_id: int = 0

## Create projectile from fire command
static func create_projectile(fire_command: Dictionary, team: int) -> Dictionary:
	var projectile_id = "projectile_" + str(_next_projectile_id)
	_next_projectile_id += 1

	# Check if this is a torpedo (has explosion properties)
	var explosion_radius = fire_command.get("explosion_radius", 0.0)
	var explosion_damage = fire_command.get("explosion_damage", 0.0)
	var is_torpedo = explosion_radius > 0.0

	# Torpedoes get longer lifetime due to slower speed
	var max_lifetime = 15.0 if is_torpedo else 10.0

	return {
		projectile_id = projectile_id,
		position = fire_command.spawn_position,
		velocity = fire_command.velocity,
		damage = fire_command.damage,
		source_id = fire_command.get("ship_id", "unknown"),
		target_id = fire_command.get("target_id", ""),
		team = team,
		lifetime = 0.0,
		max_lifetime = max_lifetime,
		weapon_size = fire_command.get("weapon_size", 1),
		projectile_type = "explosive" if is_torpedo else "standard",
		explosion_radius = explosion_radius,
		explosion_damage = explosion_damage
	}

## Spawn projectiles from fire commands - returns Array of projectile_data
static func spawn_projectiles(fire_commands: Array, team: int) -> Array:
	return fire_commands.map(func(cmd): return create_projectile(cmd, team))

