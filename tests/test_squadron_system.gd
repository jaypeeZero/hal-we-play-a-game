extends GutTest

## Tests for SquadronSystem and SquadronData.
## Tests behavior only — no assertions on specific squadron_id values or
## time-derived data.


func _make_hull(hull_id: String, ship_type: String = "fighter") -> Dictionary:
	return {"hull_id": hull_id, "ship_type": ship_type}


func _make_fleet(hull_specs: Array) -> Array:
	return hull_specs.map(func(s): return _make_hull(s[0], s[1]))


# --- SquadronData.create ---

func test_create_returns_free_mission() -> void:
	var sq := SquadronData.create("Alpha")
	assert_eq(sq.get("mission"), SquadronData.Mission.FREE)


func test_create_returns_empty_hull_ids() -> void:
	var sq := SquadronData.create("Alpha")
	assert_eq(sq.get("hull_ids", []).size(), 0)


func test_create_has_non_empty_name() -> void:
	var sq := SquadronData.create("Alpha")
	assert_eq(sq.get("name"), "Alpha")


func test_create_ids_are_unique() -> void:
	var a := SquadronData.create("A")
	var b := SquadronData.create("B")
	assert_ne(a.get("squadron_id"), b.get("squadron_id"))


# --- create_squadron ---

func test_create_squadron_appends_new_entry() -> void:
	var result := SquadronSystem.create_squadron([], "Bravo")
	assert_eq(result.size(), 1)
	assert_eq(result[0].get("name"), "Bravo")


func test_create_squadron_does_not_mutate_input() -> void:
	var original: Array = []
	var result := SquadronSystem.create_squadron(original, "Bravo")
	assert_eq(original.size(), 0)
	assert_eq(result.size(), 1)


# --- add_hull / remove_hull ---

func test_add_hull_places_hull_in_squadron() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var sq_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.add_hull(squads, sq_id, "hull_1")
	assert_true("hull_1" in squads[0].get("hull_ids", []))


func test_add_hull_removes_from_previous_squadron() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	squads = SquadronSystem.create_squadron(squads, "Bravo")
	var alpha_id: String = squads[0].get("squadron_id")
	var bravo_id: String = squads[1].get("squadron_id")

	squads = SquadronSystem.add_hull(squads, alpha_id, "hull_1")
	squads = SquadronSystem.add_hull(squads, bravo_id, "hull_1")

	assert_false("hull_1" in squads[0].get("hull_ids", []))
	assert_true("hull_1" in squads[1].get("hull_ids", []))


func test_remove_hull_takes_hull_out() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var sq_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.add_hull(squads, sq_id, "hull_1")
	squads = SquadronSystem.remove_hull(squads, "hull_1")
	assert_false("hull_1" in squads[0].get("hull_ids", []))


func test_remove_hull_from_nowhere_is_harmless() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var result := SquadronSystem.remove_hull(squads, "nonexistent")
	assert_eq(result.size(), 1)


# --- unassigned_hulls ---

func test_unassigned_hulls_returns_all_when_no_squadrons() -> void:
	var hulls := ["h1", "h2", "h3"]
	var result := SquadronSystem.unassigned_hulls([], hulls)
	assert_eq(result.size(), 3)


func test_unassigned_hulls_excludes_assigned() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var sq_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.add_hull(squads, sq_id, "h1")
	var result := SquadronSystem.unassigned_hulls(squads, ["h1", "h2"])
	assert_eq(result.size(), 1)
	assert_true("h2" in result)


# --- get_mission ---

func test_get_mission_returns_free_for_unassigned_hull() -> void:
	var result := SquadronSystem.get_mission([], "some_hull")
	assert_eq(result.get("mission"), SquadronData.Mission.FREE)
	assert_eq(result.get("params", {}).size(), 0)


func test_get_mission_returns_set_mission() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var sq_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.add_hull(squads, sq_id, "h1")
	squads = SquadronSystem.set_mission(squads, sq_id, SquadronData.Mission.INTERCEPT, {"priority_class": "fighter"})
	var result := SquadronSystem.get_mission(squads, "h1")
	assert_eq(result.get("mission"), SquadronData.Mission.INTERCEPT)
	assert_eq(result.get("params", {}).get("priority_class"), "fighter")


# --- prune_for_roster ---

func test_prune_removes_lost_hull_ids() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var sq_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.add_hull(squads, sq_id, "h1")
	squads = SquadronSystem.add_hull(squads, sq_id, "h2")
	squads = SquadronSystem.prune_for_roster(squads, ["h1"])
	assert_false("h1" in squads[0].get("hull_ids", []))
	assert_true("h2" in squads[0].get("hull_ids", []))


func test_prune_deletes_empty_squadrons() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var sq_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.add_hull(squads, sq_id, "h1")
	squads = SquadronSystem.prune_for_roster(squads, ["h1"])
	assert_eq(squads.size(), 0)


func test_prune_keeps_non_empty_squadrons() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var sq_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.add_hull(squads, sq_id, "h1")
	squads = SquadronSystem.add_hull(squads, sq_id, "h2")
	squads = SquadronSystem.prune_for_roster(squads, ["h1"])
	assert_eq(squads.size(), 1)


func test_prune_with_empty_lost_list_is_no_op() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var sq_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.add_hull(squads, sq_id, "h1")
	var pruned := SquadronSystem.prune_for_roster(squads, [])
	assert_eq(pruned[0].get("hull_ids", []).size(), 1)


# --- default_squadrons_for_fleet ---

func test_default_produces_one_squadron_per_ship_type() -> void:
	var fleet := _make_fleet([
		["h1", "fighter"], ["h2", "fighter"], ["h3", "corvette"],
	])
	var squads := SquadronSystem.default_squadrons_for_fleet(fleet)
	assert_eq(squads.size(), 2)


func test_default_assigns_all_hulls() -> void:
	var fleet := _make_fleet([
		["h1", "fighter"], ["h2", "fighter"], ["h3", "corvette"],
	])
	var squads := SquadronSystem.default_squadrons_for_fleet(fleet)
	var all_assigned: Array = []
	for sq in squads:
		all_assigned.append_array(sq.get("hull_ids", []))
	assert_true("h1" in all_assigned)
	assert_true("h2" in all_assigned)
	assert_true("h3" in all_assigned)


func test_default_groups_same_type_together() -> void:
	var fleet := _make_fleet([
		["h1", "fighter"], ["h2", "fighter"],
	])
	var squads := SquadronSystem.default_squadrons_for_fleet(fleet)
	assert_eq(squads.size(), 1)
	assert_eq(squads[0].get("hull_ids", []).size(), 2)


func _make_fleet_of_type(count: int, ship_type: String) -> Array:
	var fleet: Array = []
	for i in count:
		fleet.append(_make_hull("%s_h%d" % [ship_type, i], ship_type))
	return fleet


func _collect_hull_ids(squads: Array) -> Array:
	var all_assigned: Array = []
	for sq in squads:
		all_assigned.append_array(sq.get("hull_ids", []))
	return all_assigned


func test_default_caps_squadron_size() -> void:
	var fleet := _make_fleet_of_type(SquadronSystem.MAX_AUTO_SQUADRON_SIZE * 2 + 2, "fighter")
	var squads := SquadronSystem.default_squadrons_for_fleet(fleet)
	for sq in squads:
		assert_true(
			sq.get("hull_ids", []).size() <= SquadronSystem.MAX_AUTO_SQUADRON_SIZE,
			"Squadron exceeds max auto size"
		)


func test_default_oversized_group_assigns_every_hull_exactly_once() -> void:
	var fleet := _make_fleet_of_type(SquadronSystem.MAX_AUTO_SQUADRON_SIZE * 2 + 2, "fighter")
	var squads := SquadronSystem.default_squadrons_for_fleet(fleet)
	var all_assigned := _collect_hull_ids(squads)
	assert_eq(all_assigned.size(), fleet.size())
	for hull in fleet:
		assert_true(hull["hull_id"] in all_assigned)


func test_default_small_group_keeps_unnumbered_name() -> void:
	var fleet := _make_fleet_of_type(SquadronSystem.MAX_AUTO_SQUADRON_SIZE, "fighter")
	var squads := SquadronSystem.default_squadrons_for_fleet(fleet)
	assert_eq(squads.size(), 1)
	assert_false(squads[0].get("name", "").ends_with("1"))


func test_default_split_squadrons_get_distinct_names() -> void:
	var fleet := _make_fleet_of_type(SquadronSystem.MAX_AUTO_SQUADRON_SIZE + 1, "fighter")
	var squads := SquadronSystem.default_squadrons_for_fleet(fleet)
	assert_true(squads.size() > 1)
	var names: Dictionary = {}
	for sq in squads:
		names[sq.get("name", "")] = true
	assert_eq(names.size(), squads.size())


func test_default_split_squadrons_do_not_mix_types() -> void:
	var fleet := _make_fleet_of_type(SquadronSystem.MAX_AUTO_SQUADRON_SIZE + 2, "fighter")
	fleet.append_array(_make_fleet_of_type(SquadronSystem.MAX_AUTO_SQUADRON_SIZE + 2, "corvette"))
	var squads := SquadronSystem.default_squadrons_for_fleet(fleet)
	for sq in squads:
		var types: Dictionary = {}
		for hid in sq.get("hull_ids", []):
			types[hid.split("_")[0]] = true
		assert_eq(types.size(), 1, "Squadron mixes ship types")


func test_default_each_squadron_mission_is_free() -> void:
	var fleet := _make_fleet([["h1", "fighter"], ["h2", "corvette"]])
	var squads := SquadronSystem.default_squadrons_for_fleet(fleet)
	for sq in squads:
		assert_eq(sq.get("mission"), SquadronData.Mission.FREE)


# --- rename / delete ---

func test_rename_squadron_changes_name() -> void:
	var squads := SquadronSystem.create_squadron([], "Old")
	var sq_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.rename_squadron(squads, sq_id, "New")
	assert_eq(squads[0].get("name"), "New")


func test_delete_squadron_removes_it() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	squads = SquadronSystem.create_squadron(squads, "Bravo")
	var alpha_id: String = squads[0].get("squadron_id")
	squads = SquadronSystem.delete_squadron(squads, alpha_id)
	assert_eq(squads.size(), 1)
	assert_eq(squads[0].get("name"), "Bravo")


# --- immutability ---

func test_add_hull_does_not_mutate_input() -> void:
	var squads := SquadronSystem.create_squadron([], "Alpha")
	var sq_id: String = squads[0].get("squadron_id")
	var original_hull_ids: Array = squads[0].get("hull_ids", []).duplicate()
	SquadronSystem.add_hull(squads, sq_id, "h1")
	assert_eq(squads[0].get("hull_ids", []).size(), original_hull_ids.size())
