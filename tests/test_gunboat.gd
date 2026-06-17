extends GutTest

## Behavior tests for the Gunboat ship family (Phase 1).
## Tests predicates, crew composition, destroyable mount synthesis, and
## the synced pepperbox grouped-gunner mechanic.
## No data-value assertions — only behavior and structure.


# ─── PREDICATES ───────────────────────────────────────────────────────────────

func test_is_gunboat_true_for_all_variants() -> void:
	for t in FleetDataManager.GUNBOAT_TYPES:
		assert_true(FleetDataManager.is_gunboat(t), "%s should be a gunboat" % t)


func test_is_gunboat_false_for_non_gunboats() -> void:
	for t in ["fighter", "heavy_fighter", "torpedo_boat", "corvette", "capital"]:
		assert_false(FleetDataManager.is_gunboat(t), "%s should not be a gunboat" % t)


func test_gunboats_are_fighter_class() -> void:
	for t in FleetDataManager.GUNBOAT_TYPES:
		assert_true(FleetDataManager.is_fighter_class(t),
			"%s should be fighter-class (uses fighter pilot AI)" % t)


func test_gunboats_are_not_large_ships() -> void:
	for t in FleetDataManager.GUNBOAT_TYPES:
		assert_false(FleetDataManager.is_large_ship(t),
			"%s should not be classified as a large ship" % t)


func test_has_destroyable_mounts_true_for_gunboats() -> void:
	for t in FleetDataManager.GUNBOAT_TYPES:
		assert_true(FleetDataManager.has_destroyable_mounts(t),
			"%s should have destroyable mounts" % t)


func test_has_destroyable_mounts_true_for_large_ships() -> void:
	for t in FleetDataManager.LARGE_SHIP_TYPES:
		assert_true(FleetDataManager.has_destroyable_mounts(t),
			"%s (large ship) should still have destroyable mounts" % t)


func test_has_destroyable_mounts_false_for_pure_fighters() -> void:
	for t in ["fighter", "heavy_fighter", "torpedo_boat"]:
		assert_false(FleetDataManager.has_destroyable_mounts(t),
			"%s (fighter) should not have destroyable mounts" % t)


func test_all_gunboat_types_in_ship_types() -> void:
	for t in FleetDataManager.GUNBOAT_TYPES:
		assert_true(t in FleetDataManager.SHIP_TYPES,
			"%s must be in SHIP_TYPES" % t)


# ─── TEMPLATE LOADING ─────────────────────────────────────────────────────────

func test_each_gunboat_template_loads() -> void:
	for t in FleetDataManager.GUNBOAT_TYPES:
		var tmpl: Dictionary = ShipData.get_ship_template(t)
		assert_false(tmpl.is_empty(), "%s template should load" % t)


func test_each_gunboat_template_has_required_keys() -> void:
	for t in FleetDataManager.GUNBOAT_TYPES:
		var tmpl: Dictionary = ShipData.get_ship_template(t)
		assert_has(tmpl, "stats",         "%s must have stats" % t)
		assert_has(tmpl, "armor_sections","%s must have armor_sections" % t)
		assert_has(tmpl, "internals",     "%s must have internals" % t)
		assert_has(tmpl, "weapons",       "%s must have weapons" % t)


func test_each_gunboat_template_has_three_armor_sections() -> void:
	for t in FleetDataManager.GUNBOAT_TYPES:
		var tmpl: Dictionary = ShipData.get_ship_template(t)
		assert_eq(tmpl.armor_sections.size(), 3,
			"%s should have 3 armor sections (front/middle/back)" % t)


func test_gunboat_templates_type_field_matches() -> void:
	for t in FleetDataManager.GUNBOAT_TYPES:
		var tmpl: Dictionary = ShipData.get_ship_template(t)
		assert_eq(tmpl.get("type", ""), t,
			"%s template type field should match the ship type string" % t)


# ─── DESTROYABLE MOUNTS ───────────────────────────────────────────────────────

func test_gunboat_instances_have_weapon_mount_components() -> void:
	"""Each gunboat weapon should generate a destroyable mount component."""
	for t in FleetDataManager.GUNBOAT_TYPES:
		var ship: Dictionary = ShipData.create_ship_instance(t, 0, Vector2.ZERO)
		assert_false(ship.is_empty(), "%s instance created" % t)
		var weapon_ids: Array = ship.get("weapons", []).map(func(w): return w.get("weapon_id",""))
		var mount_weapon_ids: Array = []
		for comp in ship.get("internals", []):
			if comp.get("type", "") == "weapon_mount":
				mount_weapon_ids.append(comp.get("weapon_id", ""))
		for wid in weapon_ids:
			assert_true(wid in mount_weapon_ids,
				"%s: weapon '%s' should have a destroyable mount component" % [t, wid])


func test_fighter_still_has_no_weapon_mounts() -> void:
	"""Regression: fighters must not gain destroyable mounts after the refactor."""
	var ship: Dictionary = ShipData.create_ship_instance("fighter", 0, Vector2.ZERO)
	for comp in ship.get("internals", []):
		assert_ne(comp.get("type", ""), "weapon_mount",
			"Fighter should have no weapon_mount internals")


# ─── CREW COMPOSITION ─────────────────────────────────────────────────────────

func _count_role(crew: Array, role: int) -> int:
	var n := 0
	for m in crew:
		if int(m.get("role", -1)) == role:
			n += 1
	return n


func test_medic_has_correct_crew_composition() -> void:
	"""gunboat_medic: 1 pilot + 2 gunners + 2 engineers, no captain."""
	var ship: Dictionary = ShipData.create_ship_instance("gunboat_medic", 0, Vector2.ZERO, true)
	var crew: Array = ship.get("crew", [])
	assert_eq(_count_role(crew, CrewData.Role.PILOT),    1, "medic: 1 pilot")
	assert_eq(_count_role(crew, CrewData.Role.GUNNER),   2, "medic: 2 gunners")
	assert_eq(_count_role(crew, CrewData.Role.ENGINEER), 2, "medic: 2 engineers")
	assert_eq(_count_role(crew, CrewData.Role.CAPTAIN),  0, "medic: no captain")


func test_pepperbox_has_correct_crew_composition() -> void:
	"""gunboat_pepperbox: 1 pilot + 3 gunners, no captain."""
	var ship: Dictionary = ShipData.create_ship_instance("gunboat_pepperbox", 0, Vector2.ZERO, true)
	var crew: Array = ship.get("crew", [])
	assert_eq(_count_role(crew, CrewData.Role.PILOT),   1, "pepperbox: 1 pilot")
	assert_eq(_count_role(crew, CrewData.Role.GUNNER),  3, "pepperbox: 3 gunners")
	assert_eq(_count_role(crew, CrewData.Role.CAPTAIN), 0, "pepperbox: no captain")


func test_firecracker_has_correct_crew_composition() -> void:
	"""gunboat_firecracker: 1 pilot + 5 gunners, no captain."""
	var ship: Dictionary = ShipData.create_ship_instance("gunboat_firecracker", 0, Vector2.ZERO, true)
	var crew: Array = ship.get("crew", [])
	assert_eq(_count_role(crew, CrewData.Role.PILOT),   1, "firecracker: 1 pilot")
	assert_eq(_count_role(crew, CrewData.Role.GUNNER),  5, "firecracker: 5 gunners")
	assert_eq(_count_role(crew, CrewData.Role.CAPTAIN), 0, "firecracker: no captain")


func test_all_crew_assigned_to_ship() -> void:
	"""All crew members must be assigned to the ship they're on."""
	for t in FleetDataManager.GUNBOAT_TYPES:
		var ship: Dictionary = ShipData.create_ship_instance(t, 0, Vector2.ZERO, true)
		for member in ship.get("crew", []):
			assert_eq(member.get("assigned_to", ""), ship.ship_id,
				"%s crew member should be assigned to the ship" % t)


# ─── PEPPERBOX GROUPED GUNNER BINDING ─────────────────────────────────────────

func test_pepperbox_gunners_have_weapon_ids_groups() -> void:
	"""Each pepperbox gunner carries a weapon_ids list (grouped binding), not a scalar weapon_id."""
	var ship: Dictionary = ShipData.create_ship_instance("gunboat_pepperbox", 0, Vector2.ZERO, true)
	var crew: Array = ship.get("crew", [])
	for member in crew:
		if int(member.get("role", -1)) == CrewData.Role.GUNNER:
			assert_true(member.has("weapon_ids"),
				"Pepperbox gunner should carry weapon_ids (group), not weapon_id")
			assert_false(member.has("weapon_id"),
				"Pepperbox gunner should NOT carry scalar weapon_id")
			var ids: Array = member.get("weapon_ids", [])
			assert_gt(ids.size(), 0, "Pepperbox gunner weapon_ids group must be non-empty")


func test_pepperbox_each_gunner_group_has_two_guns() -> void:
	"""6 guns / 3 gunners = 2 guns each."""
	var ship: Dictionary = ShipData.create_ship_instance("gunboat_pepperbox", 0, Vector2.ZERO, true)
	var crew: Array = ship.get("crew", [])
	for member in crew:
		if int(member.get("role", -1)) == CrewData.Role.GUNNER:
			assert_eq(member.get("weapon_ids", []).size(), 2,
				"Each pepperbox gunner controls exactly 2 guns")


func test_pepperbox_all_six_guns_covered_by_gunners() -> void:
	"""All 6 weapon_ids are assigned to some gunner."""
	var ship: Dictionary = ShipData.create_ship_instance("gunboat_pepperbox", 0, Vector2.ZERO, true)
	var crew: Array = ship.get("crew", [])
	var all_weapon_ids: Array = ship.get("weapons", []).map(func(w): return w.get("weapon_id",""))
	var assigned_ids: Array = []
	for member in crew:
		if int(member.get("role", -1)) == CrewData.Role.GUNNER:
			for wid in member.get("weapon_ids", []):
				assigned_ids.append(str(wid))
	for wid in all_weapon_ids:
		assert_true(str(wid) in assigned_ids,
			"weapon '%s' must be assigned to a gunner group" % wid)


func test_pepperbox_no_gun_assigned_twice() -> void:
	"""Each gun appears in exactly one gunner's group."""
	var ship: Dictionary = ShipData.create_ship_instance("gunboat_pepperbox", 0, Vector2.ZERO, true)
	var crew: Array = ship.get("crew", [])
	var seen: Dictionary = {}
	for member in crew:
		if int(member.get("role", -1)) == CrewData.Role.GUNNER:
			for wid in member.get("weapon_ids", []):
				var key: String = str(wid)
				assert_false(seen.has(key),
					"gun '%s' should not appear in more than one gunner's group" % key)
				seen[key] = true


func test_medic_and_firecracker_gunners_have_scalar_weapon_id() -> void:
	"""Non-pepperbox gunboats use the standard 1:1 weapon_id binding."""
	for t in ["gunboat_medic", "gunboat_firecracker"]:
		var ship: Dictionary = ShipData.create_ship_instance(t, 0, Vector2.ZERO, true)
		for member in ship.get("crew", []):
			if int(member.get("role", -1)) == CrewData.Role.GUNNER:
				assert_true(member.has("weapon_id"),
					"%s gunner should have scalar weapon_id" % t)
				assert_false(member.has("weapon_ids"),
					"%s gunner should not have weapon_ids group" % t)


# ─── GROUPED GUNNER BIND HELPER ───────────────────────────────────────────────

func test_bind_gunner_groups_assigns_lists() -> void:
	"""bind_gunner_groups assigns weapon_ids lists and does not set weapon_id."""
	var pilot := {"role": CrewData.Role.PILOT, "crew_id": "p"}
	var g1 := {"role": CrewData.Role.GUNNER, "crew_id": "g1"}
	var g2 := {"role": CrewData.Role.GUNNER, "crew_id": "g2"}
	var crew: Array = [pilot, g1, g2]
	var w := func(id: String) -> Dictionary: return {"weapon_id": id}
	var groups: Array = [[w.call("a"), w.call("b")], [w.call("c"), w.call("d")]]

	CrewData.bind_gunner_groups(crew, groups)

	assert_eq(g1.get("weapon_ids"), ["a", "b"], "Gunner 1 gets first group")
	assert_eq(g2.get("weapon_ids"), ["c", "d"], "Gunner 2 gets second group")
	assert_false(g1.has("weapon_id"), "Grouped gunner should not have scalar weapon_id")
	assert_false(pilot.has("weapon_ids"), "Pilot should not be touched by bind_gunner_groups")


# ─── CASUALTY — GROUPED MOUNT ─────────────────────────────────────────────────

func _seeded_rng(s: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _mount(weapon_id: String, status: String) -> Dictionary:
	return {
		"component_id": "mount_%s" % weapon_id,
		"type": "weapon_mount",
		"weapon_id": weapon_id,
		"status": status,
	}


func _ship_with_internals(internals: Array) -> Dictionary:
	return {"internals": internals}


func test_grouped_gunner_survives_when_no_group_mount_destroyed() -> void:
	"""A pepperbox gunner with an intact group takes no casualty."""
	var gunner := {
		"role": CrewData.Role.GUNNER, "crew_id": "g",
		"weapon_ids": ["turret_1", "turret_2"],
	}
	var before := _ship_with_internals([
		_mount("turret_1", "operational"), _mount("turret_2", "operational"),
	])
	var after := _ship_with_internals([
		_mount("turret_1", "operational"), _mount("turret_2", "operational"),
	])
	var result := CasualtySystem.resolve_hull_casualties([gunner], before, after, _seeded_rng())
	assert_eq(result.survivors.size(), 1, "Grouped gunner survives when no mounts destroyed")
	assert_eq(result.deaths.size(),   0)


func test_grouped_gunner_becomes_casualty_when_one_group_mount_destroyed() -> void:
	"""Destroying any gun in a pepperbox group kills its gunner."""
	var gunner := {
		"role": CrewData.Role.GUNNER, "crew_id": "g",
		"weapon_ids": ["turret_1", "turret_2"],
	}
	var before := _ship_with_internals([
		_mount("turret_1", "operational"), _mount("turret_2", "operational"),
	])
	var after := _ship_with_internals([
		_mount("turret_1", "destroyed"),   _mount("turret_2", "operational"),
	])
	var result := CasualtySystem.resolve_hull_casualties([gunner], before, after, _seeded_rng())
	assert_eq(result.deaths.size(), 1, "Grouped gunner dies when one group mount is destroyed")
	assert_eq(result.survivors.size(), 0)


func test_standard_gunner_unaffected_by_other_mount_destruction() -> void:
	"""A 1:1 gunner assigned to turret_1 is not killed when turret_2 is destroyed."""
	var g1 := {"role": CrewData.Role.GUNNER, "crew_id": "g1", "weapon_id": "turret_1"}
	var g2 := {"role": CrewData.Role.GUNNER, "crew_id": "g2", "weapon_id": "turret_2"}
	var before := _ship_with_internals([
		_mount("turret_1", "operational"), _mount("turret_2", "operational"),
	])
	var after := _ship_with_internals([
		_mount("turret_1", "operational"), _mount("turret_2", "destroyed"),
	])
	var result := CasualtySystem.resolve_hull_casualties([g1, g2], before, after, _seeded_rng())
	assert_eq(result.deaths.size(), 1, "Only the gunner whose mount was destroyed dies")
	assert_eq(result.deaths[0].get("crew_id"), "g2")
	assert_eq(result.survivors.size(), 1)
	assert_eq(result.survivors[0].get("crew_id"), "g1")


# ============================================================================
# BUG 2 regression: create_crew_for_ship_type must produce correct gunboat crew
# ============================================================================

## Return the count of crew members with the given role.
func _count_role_in(crew: Array, role: int) -> int:
	var n := 0
	for m in crew:
		if int(m.get("role", -1)) == role:
			n += 1
	return n


func test_bug2_create_crew_for_ship_type_medic_yields_correct_composition() -> void:
	"""BUG 2 regression: create_crew_for_ship_type must NOT return [] for gunboat_medic.
	Enemy and skirmish/roguelike spawn paths call this function — if it returns []
	gunboats spawn crewless."""
	var weapons: Array = ShipData.get_ship_template("gunboat_medic").get("weapons", [])
	var crew: Array = CrewData.create_crew_for_ship_type("gunboat_medic", weapons.size(), 0.5)
	assert_false(crew.is_empty(), "create_crew_for_ship_type must not return [] for gunboat_medic")
	assert_eq(_count_role_in(crew, CrewData.Role.PILOT),    1, "medic: 1 pilot")
	assert_eq(_count_role_in(crew, CrewData.Role.GUNNER),   2, "medic: 2 gunners")
	assert_eq(_count_role_in(crew, CrewData.Role.ENGINEER), 2, "medic: 2 engineers")


func test_bug2_create_crew_for_ship_type_pepperbox_yields_correct_composition() -> void:
	"""BUG 2 regression: create_crew_for_ship_type must NOT return [] for gunboat_pepperbox."""
	var weapons: Array = ShipData.get_ship_template("gunboat_pepperbox").get("weapons", [])
	var crew: Array = CrewData.create_crew_for_ship_type("gunboat_pepperbox", weapons.size(), 0.5)
	assert_false(crew.is_empty(), "create_crew_for_ship_type must not return [] for gunboat_pepperbox")
	assert_eq(_count_role_in(crew, CrewData.Role.PILOT),  1, "pepperbox: 1 pilot")
	assert_eq(_count_role_in(crew, CrewData.Role.GUNNER), 3, "pepperbox: 3 gunners")
	for m in crew:
		if int(m.get("role", -1)) == CrewData.Role.GUNNER:
			assert_true(m.has("weapon_ids"),
				"Pepperbox gunner from create_crew_for_ship_type must carry weapon_ids group")


func test_bug2_create_crew_for_ship_type_firecracker_yields_correct_composition() -> void:
	"""BUG 2 regression: create_crew_for_ship_type must NOT return [] for gunboat_firecracker."""
	var weapons: Array = ShipData.get_ship_template("gunboat_firecracker").get("weapons", [])
	var crew: Array = CrewData.create_crew_for_ship_type("gunboat_firecracker", weapons.size(), 0.5)
	assert_false(crew.is_empty(), "create_crew_for_ship_type must not return [] for gunboat_firecracker")
	assert_eq(_count_role_in(crew, CrewData.Role.PILOT),  1, "firecracker: 1 pilot")
	assert_eq(_count_role_in(crew, CrewData.Role.GUNNER), 5, "firecracker: 5 gunners")
	for m in crew:
		if int(m.get("role", -1)) == CrewData.Role.GUNNER:
			assert_true(m.has("weapon_id"),
				"Firecracker gunner must carry scalar weapon_id binding")


func test_bug2_skirmish_empty_hull_gunboat_has_complement_slots() -> void:
	"""BUG 2 regression: SkirmishFleet.empty_hull for a gunboat must produce a
	non-empty complement so a player can staff the hull."""
	for gbt in FleetDataManager.GUNBOAT_TYPES:
		var hull: Dictionary = SkirmishFleet.empty_hull(gbt, 99)
		assert_false(hull.get("complement", []).is_empty(),
			"%s empty_hull must have complement slots" % gbt)
		var complement: Array = hull.get("complement", [])
		var has_pilot := false
		var has_gunner := false
		for slot in complement:
			if slot.get("role", -1) == CrewData.Role.PILOT:
				has_pilot = true
			elif slot.get("role", -1) == CrewData.Role.GUNNER:
				has_gunner = true
		assert_true(has_pilot,  "%s complement must include a pilot slot" % gbt)
		assert_true(has_gunner, "%s complement must include gunner slot(s)" % gbt)


func test_bug2_enemy_spawn_path_medic_crew_not_empty() -> void:
	"""BUG 2 regression: the enemy spawn path (create_crew_for_ship_type) must
	produce a non-empty crew for all gunboat variants at any skill level."""
	for gbt in FleetDataManager.GUNBOAT_TYPES:
		for skill in [0.0, 0.5, 1.0]:
			var weapons: Array = ShipData.get_ship_template(gbt).get("weapons", [])
			var crew: Array = CrewData.create_crew_for_ship_type(gbt, weapons.size(), skill)
			assert_false(crew.is_empty(),
				"Enemy spawn of %s at skill %.1f must produce non-empty crew" % [gbt, skill])
			assert_gt(_count_role_in(crew, CrewData.Role.PILOT), 0,
				"%s crew must include at least one pilot" % gbt)
			assert_gt(_count_role_in(crew, CrewData.Role.GUNNER), 0,
				"%s crew must include at least one gunner" % gbt)
