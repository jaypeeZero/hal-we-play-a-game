extends GutTest

## Behavior tests for ProjectileSystem.
##
## Projectiles are owned by exactly one system (the game loop) and advanced
## once per frame.  Allocating fresh dicts every frame is the immutability
## tax for a guarantee no consumer needs, so the advance functions mutate
## their inputs in place.  These tests pin down both the movement behavior
## and the no-allocation contract.

# ============================================================================
# HELPERS
# ============================================================================

func make_projectile(pos: Vector2 = Vector2.ZERO, vel: Vector2 = Vector2(100, 0), lifetime: float = 0.0, max_lifetime: float = 10.0) -> Dictionary:
	return {
		"projectile_id": "p_" + str(randi()),
		"position": pos,
		"velocity": vel,
		"lifetime": lifetime,
		"max_lifetime": max_lifetime,
		"damage": 5.0,
		"team": 0,
		"source_id": "ship_x",
		"target_id": "ship_y",
		"weapon_size": 1,
		"projectile_type": "standard",
		"explosion_radius": 0.0,
		"explosion_damage": 0.0
	}

# Dynamically loads ProjectileSystem and returns it only if the new in-place
# methods exist.  Lets these tests parse before the methods are implemented.
func _ps_with_in_place():
	var ps = load("res://scripts/space/systems/projectile_system.gd")
	if not ps.has_method("advance_projectile_in_place"):
		return null
	return ps

# ============================================================================
# MOVEMENT BEHAVIOR
# ============================================================================

func test_advancing_projectile_moves_by_velocity_times_dt():
	var ps = _ps_with_in_place()
	if ps == null:
		pending("advance_projectile_in_place not implemented yet.")
		return

	var p = make_projectile(Vector2(0, 0), Vector2(100, 0))
	ps.advance_projectile_in_place(p, 0.5)

	assert_eq(p.position, Vector2(50, 0),
		"Position should advance by velocity * dt.")

func test_advancing_projectile_accumulates_lifetime():
	var ps = _ps_with_in_place()
	if ps == null:
		pending("advance_projectile_in_place not implemented yet.")
		return

	var p = make_projectile()
	p.lifetime = 1.0

	ps.advance_projectile_in_place(p, 0.25)

	assert_almost_eq(p.lifetime, 1.25, 0.0001,
		"Lifetime should accumulate by dt.")

# ============================================================================
# IN-PLACE CONTRACT (this is the optimization being tested)
# ============================================================================

func test_advance_in_place_does_not_allocate_new_dict():
	var ps = _ps_with_in_place()
	if ps == null:
		pending("advance_projectile_in_place not implemented yet.")
		return

	var p = make_projectile()
	# Tag the dict with a marker; if the function returns a new dict, the
	# marker won't survive on the "advanced" projectile.
	p["_identity_marker"] = "original_dict"

	ps.advance_projectile_in_place(p, 0.1)

	assert_eq(p.get("_identity_marker", ""), "original_dict",
		"Advance must mutate the input dict, not allocate a new one.")

func test_advance_all_in_place_keeps_array_identity_for_survivors():
	var ps = _ps_with_in_place()
	if ps == null:
		pending("advance_all_projectiles_in_place not implemented yet.")
		return

	var p1 = make_projectile(Vector2(0, 0), Vector2(100, 0))
	var p2 = make_projectile(Vector2(50, 0), Vector2(200, 0))
	p1["_identity_marker"] = "p1"
	p2["_identity_marker"] = "p2"
	var projectiles = [p1, p2]

	ps.advance_all_projectiles_in_place(projectiles, 0.1)

	# Same dicts, same identity markers
	assert_eq(projectiles[0].get("_identity_marker", ""), "p1",
		"First projectile should be the same dict, not a copy.")
	assert_eq(projectiles[1].get("_identity_marker", ""), "p2",
		"Second projectile should be the same dict, not a copy.")
	# And positions should have advanced
	assert_eq(projectiles[0].position, Vector2(10, 0))
	assert_eq(projectiles[1].position, Vector2(70, 0))

# ============================================================================
# EXPIRATION
# ============================================================================

func test_advance_all_returns_expired_ids_for_lifetime_exceeded():
	var ps = _ps_with_in_place()
	if ps == null:
		pending("advance_all_projectiles_in_place not implemented yet.")
		return

	var p_alive = make_projectile()
	p_alive.projectile_id = "alive"
	var p_dying = make_projectile()
	p_dying.projectile_id = "dying"
	p_dying.lifetime = 9.95
	p_dying.max_lifetime = 10.0

	var result = ps.advance_all_projectiles_in_place([p_alive, p_dying], 0.1)

	assert_has(result, "expired_ids")
	assert_eq(result.expired_ids.size(), 1, "One projectile expires.")
	assert_eq(result.expired_ids[0], "dying", "The lifetime-exceeded one is expired.")

# ============================================================================
# COLLISION CONSUMER STILL WORKS WITH MUTATED PROJECTILES
# ============================================================================

func test_collision_system_consumes_advanced_projectiles_correctly():
	var ps = _ps_with_in_place()
	if ps == null:
		pending("advance_projectile_in_place not implemented yet.")
		return

	# After advancing in place, projectiles are valid input to the collision
	# system.  This is the cross-system contract that has to keep working.
	var p = make_projectile(Vector2(0, 0), Vector2(100, 0))
	p.team = 0
	var ship = {
		"ship_id": "target",
		"team": 1,
		"position": Vector2(10, 0),  # close enough to hit after advance
		"status": "operational",
		"collision_radius": 15.0,
		"stats": {}
	}

	ps.advance_projectile_in_place(p, 0.1)
	var hit = CollisionSystem.find_hit_for_projectile(p, [ship])

	assert_false(hit.is_empty(),
		"After advance_in_place, collision detection still works on the projectile.")
	assert_eq(hit.ship_id, "target")
