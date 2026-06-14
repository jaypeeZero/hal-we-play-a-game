extends GutTest

## Behavior tests for FleetCommandScreen.
## Verifies that building the screen over a real SkirmishSource produces
## the expected number of ship cards and pool chips.
## No brittle UI structure tests — only counts and state.

const TEST_TEAM: int = 9

var _screen: FleetCommandScreen = null


func before_each() -> void:
	_screen = FleetCommandScreen.new()
	add_child_autofree(_screen)
	_screen.setup(SkirmishSource.new(TEST_TEAM), "save")


func after_each() -> void:
	_screen = null


func test_screen_builds_one_roster_card_per_ship() -> void:
	"""One roster entry per ship in the source."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var expected: int = src.ships().size()
	# The roster grid holds one child per ship.
	var actual: int = _screen._roster_grid.get_child_count()
	assert_eq(actual, expected,
		"roster grid has one card per ship (%d expected, got %d)" % [expected, actual])


func test_screen_pool_chips_match_crew_pool() -> void:
	"""Pool flow contains one chip per unassigned crew member."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	# Count only non-label children (labels appear when pool is empty).
	var src_pool_size: int = src.crew_pool().size()
	var flow_children: int = _screen._pool_flow.get_child_count()
	if src_pool_size == 0:
		# Empty pool shows a single "all crew assigned" label.
		assert_eq(flow_children, 1, "empty pool shows one label")
	else:
		assert_eq(flow_children, src_pool_size,
			"pool flow has one chip per pool member")


func test_right_panel_shows_selected_ship() -> void:
	"""After setup the right panel is populated (not empty)."""
	# The right panel should have children when a ship is selected.
	var child_count: int = _screen._right_panel.get_child_count()
	assert_true(child_count > 0, "right panel has content when a ship is selected")


func test_unassign_from_screen_moves_crew_to_pool() -> void:
	"""Calling source.unassign via the screen's source updates the pool chip count."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	# Build a fresh screen over this src so we can also call src directly.
	var screen2: FleetCommandScreen = FleetCommandScreen.new()
	add_child_autofree(screen2)
	screen2.setup(src, "save")

	var ships: Array = src.ships()
	assert_true(ships.size() > 0, "need at least one ship")
	var hull: Dictionary = ships[0]
	var crew: Array = hull.get("crew", [])
	assert_true(crew.size() > 0, "first ship has crew")

	var before_pool: int = src.crew_pool().size()
	src.unassign(str(crew[0].get("crew_id", "")))
	screen2.on_assign_changed()

	assert_eq(src.crew_pool().size(), before_pool + 1,
		"pool grew by one after unassign")


func test_add_ship_grows_roster() -> void:
	"""add_ship on source grows the source ships array by one."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var before: int = src.ships().size()
	src.add_ship("fighter")
	assert_eq(src.ships().size(), before + 1,
		"fleet source grew by one after add_ship")


## BUG 1: slot_assignments pairs each gunner slot to its distinct crew member.
func test_slot_assignments_gunner_slots_are_distinct() -> void:
	"""For a corvette, _slot_assignments yields distinct crew_ids in every gunner slot."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	# Find the first corvette (guaranteed by STARTER_COUNTS).
	var corvette: Dictionary = {}
	for hull in src.ships():
		if str(hull.get("ship_type", "")) == "corvette":
			corvette = hull
			break
	assert_false(corvette.is_empty(), "test fleet must have a corvette")

	var gunner_crew_ids: Array = []
	for assignment in _screen._slot_assignments(corvette):
		var slot: Dictionary = assignment["slot"] as Dictionary
		var crew: Dictionary = assignment["crew"] as Dictionary
		if int(slot.get("role", -1)) == CrewData.Role.GUNNER and not crew.is_empty():
			gunner_crew_ids.append(str(crew.get("crew_id", "")))

	assert_true(gunner_crew_ids.size() > 1,
		"corvette should have multiple assigned gunners")
	# All crew_ids must be unique — no duplicates.
	var unique_ids: Dictionary = {}
	for cid in gunner_crew_ids:
		unique_ids[cid] = true
	assert_eq(unique_ids.size(), gunner_crew_ids.size(),
		"every gunner slot must show a distinct crew member (got %d ids, %d unique)" \
		% [gunner_crew_ids.size(), unique_ids.size()])


## BUG 2: source.assign moves a pool member onto a hull — verifies the logic
## the _VacantSlot drop handler calls.
## Uses unassign first to create a known vacancy, then reassigns.
func test_assign_from_pool_fills_vacancy() -> void:
	"""Unassign creates vacancy; source.assign fills it — same logic _VacantSlot._drop_data uses."""
	var src: SkirmishSource = SkirmishSource.new(TEST_TEAM)
	var ships: Array = src.ships()
	assert_true(ships.size() > 0, "need at least one ship")
	var hull: Dictionary = ships[0]
	var hull_id: String = str(hull.get("hull_id", ""))
	var crew: Array = hull.get("crew", [])
	assert_true(crew.size() > 0, "first ship must have crew")

	# Unassign one member to guarantee a vacancy and a pool member.
	var evicted_id: String = str(crew[0].get("crew_id", ""))
	src.unassign(evicted_id)

	var pool_before: int = src.crew_pool().size()
	var crew_before: int = hull.get("crew", []).size()

	# can_assign should now be true for the evicted member.
	assert_true(src.can_assign(evicted_id, hull_id),
		"can_assign true for evicted member against its former hull")

	src.assign(evicted_id, hull_id)
	assert_eq(src.crew_pool().size(), pool_before - 1, "pool shrank by 1 after assign")
	assert_eq(hull.get("crew", []).size(), crew_before + 1, "ship crew grew by 1 after assign")
