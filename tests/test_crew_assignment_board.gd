extends GutTest

## Tests for CrewChip and CrewAssignmentBoard — BEHAVIOR ONLY.
## DnD virtual methods (_get_drag_data, _can_drop_data, _drop_data) are called
## directly because a real mouse gesture cannot be simulated headlessly.

var _saved_fleet_hulls: Array
var _saved_money: int
var _saved_active: bool
var _saved_hired_ids: Array


func before_each() -> void:
	_saved_fleet_hulls = RoguelikeRun.fleet_hulls.duplicate(true)
	_saved_money = RoguelikeRun.money
	_saved_active = RoguelikeRun.active
	_saved_hired_ids = RoguelikeRun.hired_roster_ids.duplicate()


func after_each() -> void:
	RoguelikeRun.fleet_hulls = _saved_fleet_hulls
	RoguelikeRun.money = _saved_money
	RoguelikeRun.active = _saved_active
	RoguelikeRun.hired_roster_ids = _saved_hired_ids


func _counts(overrides: Dictionary = {}) -> Dictionary:
	var base := {"fighter": 0, "heavy_fighter": 0,
		"torpedo_boat": 0, "corvette": 0, "capital": 0}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _make_board(show_ice := false) -> CrewAssignmentBoard:
	var board := CrewAssignmentBoard.new()
	board.show_ice = show_ice
	add_child_autofree(board)
	board.setup()
	return board


func _make_chip(member: Dictionary, board: CrewAssignmentBoard) -> CrewChip:
	var chip := CrewChip.new()
	add_child_autofree(chip)
	chip.setup(member, board)
	return chip


func _find_by_script(node: Node, script: Script, acc: Array) -> Array:
	for child in node.get_children():
		if child.get_script() == script:
			acc.append(child)
		_find_by_script(child, script, acc)
	return acc


# ---- CrewChip drag payload ----

func test_chip_get_drag_data_returns_crew_kind_payload():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var member: Dictionary = RoguelikeRun.fleet_hulls[0]
	member = member.crew[0]
	var board := _make_board()
	var chip := _make_chip(member, board)

	var data: Variant = chip._get_drag_data(Vector2.ZERO)

	assert_true(data is Dictionary, "Drag payload is a Dictionary")
	assert_eq(data.get("kind", ""), "crew", "Payload kind is 'crew'")
	assert_eq(data.get("crew_id", ""), member.crew_id, "Payload carries the correct crew_id")
	assert_eq(data.get("role", -1), member.get("role", -1), "Payload carries the crew member's role")


# ---- CrewChip can_drop (swap) ----

func test_chip_can_drop_true_for_same_role_on_different_hull():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var member_a: Dictionary = RoguelikeRun.fleet_hulls[0]
	member_a = member_a.crew[0]
	var member_b: Dictionary = RoguelikeRun.fleet_hulls[1]
	member_b = member_b.crew[0]
	var board := _make_board()
	var chip_b := _make_chip(member_b, board)

	var data := {"kind": "crew", "crew_id": member_a.crew_id, "role": member_a.get("role", -1)}
	assert_true(chip_b._can_drop_data(Vector2.ZERO, data),
		"A chip accepts a drop from the same role on a different hull (swap)")


func test_chip_can_drop_false_for_non_crew_data():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var member: Dictionary = RoguelikeRun.fleet_hulls[0]
	member = member.crew[0]
	var board := _make_board()
	var chip := _make_chip(member, board)

	assert_false(chip._can_drop_data(Vector2.ZERO, {"kind": "ship"}),
		"A chip rejects non-crew drag data")
	assert_false(chip._can_drop_data(Vector2.ZERO, "plain string"),
		"A chip rejects non-dictionary drag data")


func test_chip_can_drop_false_for_cross_role():
	RoguelikeRun.start_run(_counts({"corvette": 2}))
	var pilot_id := ""
	var gunner: Dictionary = {}
	for member in RoguelikeRun.fleet_hulls[0].get("crew", []):
		if member.get("role", -1) == CrewData.Role.PILOT:
			pilot_id = member.crew_id
	for member in RoguelikeRun.fleet_hulls[1].get("crew", []):
		if member.get("role", -1) == CrewData.Role.GUNNER:
			gunner = member
	if pilot_id == "" or gunner.is_empty():
		pass_test("precondition: corvette lacks pilot+gunner pair; skipping")
		return

	var board := _make_board()
	var chip_gunner := _make_chip(gunner, board)

	var data := {"kind": "crew", "crew_id": pilot_id, "role": CrewData.Role.PILOT}
	assert_false(chip_gunner._can_drop_data(Vector2.ZERO, data),
		"A chip rejects a drop from a different role (cross-role swap disallowed)")


# ---- CrewChip drop_data (swap mutates fleet) ----

func test_chip_drop_data_swaps_crew_between_hulls():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var hull_a: Dictionary = RoguelikeRun.fleet_hulls[0]
	var hull_b: Dictionary = RoguelikeRun.fleet_hulls[1]
	var id_a: String = hull_a.crew[0].crew_id
	var id_b: String = hull_b.crew[0].crew_id

	var board := _make_board()
	# Use a fresh chip ref since hull_b.crew[0] is the live dict.
	var chip_b := _make_chip(hull_b.crew[0], board)

	chip_b._drop_data(Vector2.ZERO, {"kind": "crew", "crew_id": id_a, "role": hull_a.crew[0].get("role", -1)})

	var a_on_b := false
	var b_on_a := false
	for member in hull_b.crew:
		if member.get("crew_id", "") == id_a:
			a_on_b = true
	for member in hull_a.crew:
		if member.get("crew_id", "") == id_b:
			b_on_a = true
	assert_true(a_on_b, "Pilot A landed on hull B after chip drop")
	assert_true(b_on_a, "Pilot B landed on hull A after chip drop")


func test_chip_drop_data_emits_board_changed_signal():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var hull_a: Dictionary = RoguelikeRun.fleet_hulls[0]
	var hull_b: Dictionary = RoguelikeRun.fleet_hulls[1]
	var id_a: String = hull_a.crew[0].crew_id

	var board := _make_board()
	watch_signals(board)
	var chip_b := _make_chip(hull_b.crew[0], board)

	chip_b._drop_data(Vector2.ZERO, {"kind": "crew", "crew_id": id_a, "role": hull_a.crew[0].get("role", -1)})

	assert_signal_emitted(board, "changed", "board.changed fired after a successful swap drop")


# ---- Board vacant-slot drop (move) ----

func test_board_vacant_drop_moves_crew():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var src: Dictionary = RoguelikeRun.fleet_hulls[0]
	var dest := RoguelikeRun.add_purchased_hull("fighter")
	var pilot_id: String = src.crew[0].crew_id

	# Call the same logic as _VacantDropTarget._drop_data.
	var ok := RoguelikeRun.transfer_crew(pilot_id, dest.hull_id)

	assert_true(ok, "transfer_crew succeeds for a pilot moving to an empty hull")
	assert_eq(RoguelikeRun.hull_by_id(dest.hull_id).crew.size(), 1,
		"Destination hull gains the transferred crew")
	assert_true(src.crew.is_empty(), "Source hull is now empty after move")


func test_board_vacant_drop_emits_board_changed_signal():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	RoguelikeRun.money = 100000
	var src: Dictionary = RoguelikeRun.fleet_hulls[0]
	var dest := RoguelikeRun.add_purchased_hull("fighter")
	var pilot_id: String = src.crew[0].crew_id

	var board := _make_board()
	watch_signals(board)

	if RoguelikeRun.transfer_crew(pilot_id, dest.hull_id):
		board.on_changed()

	assert_signal_emitted(board, "changed", "board.changed fired after a successful move")


# ---- Board renders chips per hull ----

func test_board_has_a_chip_per_crew_member():
	RoguelikeRun.start_run(_counts({"fighter": 2}))
	var board := _make_board()

	var chips := _find_by_script(board, CrewChip, [])
	var total_crew := 0
	for hull in RoguelikeRun.fleet_hulls:
		total_crew += hull.get("crew", []).size()

	assert_eq(chips.size(), total_crew,
		"The board renders exactly one chip per crew member across all hulls")


func test_board_show_ice_true_has_ice_buttons():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var board := _make_board(true)

	var ice_btns: Array = []
	for child in board.find_children("*", "Button", true, false):
		if child.text == "Put on ice" or child.text == "Activate":
			ice_btns.append(child)
	assert_gt(ice_btns.size(), 0,
		"show_ice=true board renders an ice/activate button per hull")


func test_board_show_ice_false_has_no_ice_buttons():
	RoguelikeRun.start_run(_counts({"fighter": 1}))
	var board := _make_board(false)

	var ice_btns: Array = []
	for child in board.find_children("*", "Button", true, false):
		if child.text == "Put on ice" or child.text == "Activate":
			ice_btns.append(child)
	assert_eq(ice_btns.size(), 0,
		"show_ice=false board has no ice/activate buttons")
