class_name ProjectileSystem
extends RefCounted

## Projectile state and movement.
##
## Projectiles are owned by the game loop, advanced once per frame, and
## consumed by the collision system in the same frame.  No other system
## holds onto a projectile dict, and the previous-frame state is dead the
## instant the next frame starts.
##
## Per-frame allocation of fresh projectile dicts (via merge_dict) was the
## immutability tax for a guarantee no consumer needs.  The advance_* fns
## below MUTATE THE PROJECTILE DICTS IN PLACE.  Their names end in
## `_in_place` to make the contract explicit at every call site.
##
## If you ever need a snapshot of a projectile (e.g. for a replay buffer),
## duplicate it BEFORE handing it to advance_*_in_place.

# ============================================================================
# MOVEMENT (MUTATES IN PLACE)
# ============================================================================

## Advance one projectile by `dt` seconds, mutating its position and lifetime.
## Returns true if the projectile has now exceeded its max_lifetime.
##
## MUTATES: projectile_data.position, projectile_data.lifetime
static func advance_projectile_in_place(projectile_data: Dictionary, dt: float) -> bool:
	projectile_data.position += projectile_data.velocity * dt
	projectile_data.lifetime += dt
	return projectile_data.lifetime >= projectile_data.max_lifetime

## Advance every projectile in `projectiles` by `dt` seconds.
## Returns {expired_ids: Array} -- the projectile dicts in the input array are
## mutated in place, so the caller's `_projectiles` list is now up to date.
## The caller is responsible for removing expired entries.
##
## MUTATES: every dict in the projectiles array.
static func advance_all_projectiles_in_place(projectiles: Array, dt: float) -> Dictionary:
	var expired_ids: Array = []
	for projectile in projectiles:
		if projectile == null:
			continue
		var expired = advance_projectile_in_place(projectile, dt)
		if expired:
			expired_ids.append(projectile.projectile_id)
	return {"expired_ids": expired_ids}

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
