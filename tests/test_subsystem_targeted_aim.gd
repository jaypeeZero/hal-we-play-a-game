extends GutTest

## SUBSYSTEM-style fire must (a) lead at the chosen subsystem rather than
## ship center, and (b) bias damage routing to the intended subsystem on
## armor penetration. Behavior-only.

const TRIALS: int = 200


func _make_target_with_internals(internals: Array) -> Dictionary:
	return {
		"ship_id": "target",
		"team": 1,
		"position": Vector2.ZERO,
		"rotation": 0.0,
		"velocity": Vector2.ZERO,
		"status": "operational",
		"stats": {},
		"base_stats": {},
		"armor_sections": [{
			"section_id": "all",
			"arc": {"start": 0.0, "end": 360.0},
			"current_armor": 0,
			"max_armor": 10,
			"position_offset": Vector2.ZERO,
			"size": 1,
		}],
		"internals": internals,
	}


func _engine_component() -> Dictionary:
	return {
		"component_id": "engine",
		"type": "engine",
		"section_id": "all",
		"position_offset": Vector2(0, 6),
		"current_health": 25,
		"max_health": 25,
		"status": "operational",
		"tactical_value": 3.0,
		"effect_on_ship": {},
	}


func _hull_component() -> Dictionary:
	return {
		"component_id": "hull_filler",
		"type": "structure",
		"section_id": "all",
		"position_offset": Vector2(0, -6),
		"current_health": 100,
		"max_health": 100,
		"status": "operational",
		"tactical_value": 1.0,
		"effect_on_ship": {},
	}


func test_pick_target_subsystem_prefers_high_tactical_value():
	var target: Dictionary = _make_target_with_internals([_hull_component(), _engine_component()])
	var picked: Dictionary = WeaponSystem.pick_target_subsystem(target)
	assert_eq(picked.get("component_id"), "engine", "Engines outweigh hull on tactical value")


func test_pick_target_subsystem_skips_destroyed():
	var dead_engine: Dictionary = _engine_component()
	dead_engine.status = "destroyed"
	var target: Dictionary = _make_target_with_internals([dead_engine, _hull_component()])
	var picked: Dictionary = WeaponSystem.pick_target_subsystem(target)
	assert_eq(picked.get("component_id"), "hull_filler", "Destroyed components are not retargeted")


func test_intended_subsystem_only_set_for_subsystem_style():
	var target: Dictionary = _make_target_with_internals([_engine_component()])
	var simple_ship: Dictionary = {
		"crew_modifiers": {"targeting_style": CrewIntegrationSystem.TargetingStyle.SIMPLE}
	}
	var elite_ship: Dictionary = {
		"crew_modifiers": {"targeting_style": CrewIntegrationSystem.TargetingStyle.SUBSYSTEM}
	}
	assert_eq(WeaponSystem.pick_intended_subsystem(simple_ship, target), "")
	assert_eq(WeaponSystem.pick_intended_subsystem(elite_ship, target), "engine")


func test_subsystem_intent_routes_damage_preferentially():
	# With intent set, the damage resolver should route hits to the engine
	# substantially more often than the closest-component default.
	var hits_to_engine: int = 0
	for _i in TRIALS:
		var target: Dictionary = _make_target_with_internals([_hull_component(), _engine_component()])
		# Hit position is closer to the hull filler at (0,-6); without intent
		# the closest internal is hull_filler.
		var result: Dictionary = DamageResolver.resolve_hit(
			target, Vector2(0, -6), 5, 0.0, 1, "engine"
		)
		var info = result.hit_result.get("internal_hit", {})
		if info.get("component_id", "") == "engine":
			hits_to_engine += 1

	# With SUBSYSTEM_INTENDED_HIT_BIAS = 0.7 and the closest fallback being
	# hull_filler (not engine), engine routing should dominate without intent
	# entirely.
	assert_gt(hits_to_engine, int(TRIALS * 0.5),
		"Intended subsystem routing should land >50% engine hits even when closest is hull")


func test_damage_resolver_falls_back_to_closest_without_intent():
	var hits_to_engine: int = 0
	for _i in TRIALS:
		var target: Dictionary = _make_target_with_internals([_hull_component(), _engine_component()])
		var result: Dictionary = DamageResolver.resolve_hit(
			target, Vector2(0, -6), 5, 0.0, 1
		)
		var info = result.hit_result.get("internal_hit", {})
		if info.get("component_id", "") == "engine":
			hits_to_engine += 1
	assert_eq(hits_to_engine, 0, "Without intent, hits land on the closest component")
