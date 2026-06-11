extends GutTest

## Doctrine panel behaviors (plan 06): the ship dropdown is the scope
## selector (fleet / class / hull), crew are operated on only through the
## crew dropdown, and edits land in RoguelikeRun.doctrine. Rendering is
## not asserted — the defining behaviors are.

var _saved_run_state: Dictionary


func before_each() -> void:
	_saved_run_state = {
		"active": RoguelikeRun.active,
		"started_first_battle": RoguelikeRun.started_first_battle,
		"fleet": RoguelikeRun.fleet.duplicate(true),
		"fleet_ships": RoguelikeRun.fleet_ships.duplicate(true),
		"fleet_crew": RoguelikeRun.fleet_crew.duplicate(true),
		"doctrine": RoguelikeRun.doctrine.duplicate(true),
		"enemy_fleet": RoguelikeRun.enemy_fleet.duplicate(true),
	}
	RoguelikeRun.start_run({"fighter": 2, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0})


func after_each() -> void:
	RoguelikeRun.active = _saved_run_state.active
	RoguelikeRun.started_first_battle = _saved_run_state.started_first_battle
	RoguelikeRun.fleet = _saved_run_state.fleet
	RoguelikeRun.fleet_ships = _saved_run_state.fleet_ships
	RoguelikeRun.fleet_crew = _saved_run_state.fleet_crew
	RoguelikeRun.doctrine = _saved_run_state.doctrine
	RoguelikeRun.enemy_fleet = _saved_run_state.enemy_fleet


func _make_entries() -> Array:
	var entries: Array = []
	for _i in range(2):
		entries.append({"team": 0, "ship_type": "fighter", "position": Vector2.ZERO,
			"patrol_center": Vector2.ZERO, "patrol_radius": 100.0, "hull_length": 10.0})
	return entries


func _make_panel() -> DoctrinePanel:
	var panel = DoctrinePanel.new()
	add_child_autofree(panel)
	panel.setup(_make_entries())
	return panel


## Index of the first hull option in the ship dropdown
## (after "Entire fleet" and one "All Fighters" class option).
const FIRST_HULL_OPTION := 2


func test_ship_dropdown_offers_fleet_class_and_hull_scopes():
	var panel = _make_panel()
	# 1 fleet + 1 class (only fighters present) + 2 hulls
	assert_eq(panel._ship_dropdown.item_count, 4,
		"Dropdown should offer fleet, one class, and each hull")


func test_selecting_a_hull_in_dropdown_selects_it_on_the_map():
	var panel = _make_panel()
	watch_signals(panel)

	panel._ship_dropdown.select(FIRST_HULL_OPTION)
	panel._on_ship_selected(FIRST_HULL_OPTION)

	assert_signal_emitted_with_parameters(panel, "hull_selected", [0])


func test_map_click_syncs_dropdown_without_echoing_back():
	var panel = _make_panel()
	watch_signals(panel)

	panel.sync_to_entry(1)

	assert_eq(panel._ship_dropdown.selected, FIRST_HULL_OPTION + 1,
		"Clicking the second fighter on the map should select its dropdown entry")
	assert_signal_not_emitted(panel, "hull_selected",
		"Programmatic sync must not loop back into map selection")


func test_add_at_fleet_scope_writes_fleet_doctrine():
	var panel = _make_panel()

	panel._on_add_pressed()

	assert_eq(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_FLEET].size(), 1,
		"Adding with the fleet selected should create a fleet-wide instruction")


func test_add_with_hull_selected_targets_the_crew_member_from_the_dropdown():
	var panel = _make_panel()
	panel._ship_dropdown.select(FIRST_HULL_OPTION)
	panel._on_ship_selected(FIRST_HULL_OPTION)
	var member = panel._current_crew_member()
	assert_false(member.is_empty(), "Hull selection should expose its crew in the crew dropdown")

	panel._on_add_pressed()

	assert_true(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CREW].has(member.crew_id),
		"Adding with a hull selected should create a personal order for the dropdown's crew member")
	assert_true(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_FLEET].is_empty(),
		"No fleet-wide instruction should be created")


func test_remove_clears_the_instruction_at_the_edited_scope():
	var panel = _make_panel()
	panel._on_add_pressed()
	var template_id: String = RoguelikeRun.doctrine[DoctrineSystem.SCOPE_FLEET].keys()[0]

	panel._on_remove_pressed(template_id)

	assert_true(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_FLEET].is_empty(),
		"Remove should clear the instruction from the edited scope")


# ROSTER MODE (Edit Fleet screen — no battle plan, no map)

func _make_roster_panel() -> DoctrinePanel:
	var panel = DoctrinePanel.new()
	add_child_autofree(panel)
	panel.setup_from_roster()
	return panel


func test_roster_mode_offers_a_hull_per_crew_group():
	var panel = _make_roster_panel()

	var hull_count := 0
	for option in panel._ship_options:
		if option.kind == DoctrinePanel.KIND_HULL:
			hull_count += 1
	assert_eq(hull_count, RoguelikeRun.fleet_crew.size(),
		"Roster mode should offer every crew group as a hull, with no battle plan")


func test_roster_mode_hull_selection_does_not_emit_a_map_signal():
	var panel = _make_roster_panel()
	watch_signals(panel)

	panel._ship_dropdown.select(FIRST_HULL_OPTION)
	panel._on_ship_selected(FIRST_HULL_OPTION)

	assert_signal_not_emitted(panel, "hull_selected",
		"There is no map at Edit Fleet, so selecting a hull must not emit hull_selected")


func test_roster_mode_add_with_hull_selected_writes_crew_doctrine():
	var panel = _make_roster_panel()
	panel._ship_dropdown.select(FIRST_HULL_OPTION)
	panel._on_ship_selected(FIRST_HULL_OPTION)
	var member = panel._current_crew_member()
	assert_false(member.is_empty(), "Hull selection should expose its crew")

	panel._on_add_pressed()

	assert_true(RoguelikeRun.doctrine[DoctrineSystem.SCOPE_CREW].has(member.crew_id),
		"Per-crew doctrine should be editable at Edit Fleet via the crew dropdown")


func test_refresh_roster_tracks_added_hulls():
	var panel = _make_roster_panel()
	var before := RoguelikeRun.fleet_crew.size()

	RoguelikeRun.reconcile_roster_to_counts({"fighter": before + 2,
		"heavy_fighter": 0, "torpedo_boat": 0, "corvette": 0, "capital": 0})
	panel.refresh_roster()

	var hull_count := 0
	for option in panel._ship_options:
		if option.kind == DoctrinePanel.KIND_HULL:
			hull_count += 1
	assert_eq(hull_count, before + 2,
		"After a reconcile, refreshing the panel should show the new hulls")
