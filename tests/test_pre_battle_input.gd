extends GutTest

## Tests for PreBattleInput - FUNCTIONALITY ONLY.
## Validates pick / drag / clamp / select behaviors without booting the
## scene or touching real ShipData templates. Entries carry their own
## hull_length, so the input class needs nothing external.

const BOUNDS := Rect2(Vector2(200, 200), Vector2(4600, 3100))
const LARGE_HULL: float = 200.0
const SMALL_HULL: float = 20.0
const PATROL_RADIUS: float = 700.0


func _make_entry(pos: Vector2, hull_length: float, patrol_center: Vector2 = Vector2(2500, 1750), patrol_radius: float = PATROL_RADIUS) -> Dictionary:
	return {
		"ship_type": "fighter",
		"team": 0,
		"position": pos,
		"patrol_center": patrol_center,
		"patrol_radius": patrol_radius,
		"hull_length": hull_length,
	}


func _make_input(entries: Array) -> PreBattleInput:
	return PreBattleInput.new(entries, BOUNDS)


# ============================================================================
# Hit testing & selection
# ============================================================================

func test_clicking_on_ship_body_selects_that_ship():
	var entries: Array = [
		_make_entry(Vector2(500, 500), LARGE_HULL),
		_make_entry(Vector2(2000, 2000), LARGE_HULL),
	]
	var input := _make_input(entries)
	var result := input.on_mouse_down(Vector2(2000, 2000))
	assert_eq(result, PreBattleInput.RESULT_SELECTED,
		"First click on a ship should select (not drag) it")
	assert_eq(input.selected_index, 1, "Selection should target the picked entry")
	assert_eq(input.state, PreBattleInput.STATE_IDLE,
		"State stays IDLE — drag only starts on a second click of the same ship")


func test_clicking_empty_space_with_no_selection_is_a_noop():
	var entries: Array = [_make_entry(Vector2(500, 500), LARGE_HULL)]
	var input := _make_input(entries)
	var result := input.on_mouse_down(Vector2(4000, 3000))
	assert_eq(result, PreBattleInput.RESULT_NONE,
		"Clicking empty space with nothing selected should be a noop")
	assert_eq(input.selected_index, -1, "Selection should remain cleared")
	assert_eq(input.state, PreBattleInput.STATE_IDLE)


func test_clicking_empty_space_when_selected_deselects():
	var ship_pos := Vector2(500, 500)
	var entries: Array = [_make_entry(ship_pos, LARGE_HULL)]
	var input := _make_input(entries)
	input.on_mouse_down(ship_pos)
	assert_eq(input.selected_index, 0)
	var result := input.on_mouse_down(Vector2(4000, 3000))
	assert_eq(result, PreBattleInput.RESULT_DESELECTED,
		"Clicking empty space when selected should deselect")
	assert_eq(input.selected_index, -1)


func test_clicking_a_different_ship_switches_selection():
	var entries: Array = [
		_make_entry(Vector2(500, 500), LARGE_HULL),
		_make_entry(Vector2(3000, 2000), LARGE_HULL),
	]
	var input := _make_input(entries)
	input.on_mouse_down(Vector2(500, 500))
	assert_eq(input.selected_index, 0)
	var result := input.on_mouse_down(Vector2(3000, 2000))
	assert_eq(result, PreBattleInput.RESULT_SELECTED,
		"Clicking a different ship switches selection")
	assert_eq(input.selected_index, 1)
	assert_eq(input.state, PreBattleInput.STATE_IDLE,
		"Switching selection does not start a drag this click")


func test_clicking_already_selected_ship_starts_ship_drag():
	var ship_pos := Vector2(500, 500)
	var entries: Array = [_make_entry(ship_pos, LARGE_HULL)]
	var input := _make_input(entries)
	input.on_mouse_down(ship_pos)
	var result := input.on_mouse_down(ship_pos)
	assert_eq(result, PreBattleInput.RESULT_DRAG_SHIP,
		"Re-clicking the selected ship begins a ship drag")
	assert_eq(input.state, PreBattleInput.STATE_DRAGGING_SHIP)
	assert_eq(input.dragging_index, 0)


func test_small_ships_remain_pickable_via_min_pick_radius():
	# A fighter-sized hull has hull_length/2 well under MIN_PICK_RADIUS, so
	# a click slightly off-center should still select.
	var ship_pos := Vector2(1000, 1000)
	var entries: Array = [_make_entry(ship_pos, SMALL_HULL)]
	var input := _make_input(entries)
	var off_center := ship_pos + Vector2(PreBattleInput.MIN_PICK_RADIUS - 1.0, 0.0)
	var result := input.on_mouse_down(off_center)
	assert_eq(result, PreBattleInput.RESULT_SELECTED,
		"Clicks within MIN_PICK_RADIUS should pick small ships")


# ============================================================================
# Patrol-circle drag
# ============================================================================

func test_clicking_selected_ships_ring_starts_circle_drag():
	var ship_pos := Vector2(500, 500)
	var patrol_center := Vector2(2500, 1750)
	var entries: Array = [_make_entry(ship_pos, LARGE_HULL, patrol_center)]
	var input := _make_input(entries)
	input.on_mouse_down(ship_pos)
	var ring_point := patrol_center + Vector2(PATROL_RADIUS, 0.0)
	var result := input.on_mouse_down(ring_point)
	assert_eq(result, PreBattleInput.RESULT_DRAG_CIRCLE,
		"Clicking on the selected ship's ring should start circle drag")
	assert_eq(input.state, PreBattleInput.STATE_DRAGGING_CIRCLE)


func test_non_selected_rings_are_not_interactive():
	# Two ships with separate patrol centers; the unselected ship's ring
	# should not be a hit target.
	var entries: Array = [
		_make_entry(Vector2(500, 500), LARGE_HULL, Vector2(1500, 1750)),
		_make_entry(Vector2(4000, 2500), LARGE_HULL, Vector2(3500, 1750)),
	]
	var input := _make_input(entries)
	input.on_mouse_down(Vector2(500, 500))
	assert_eq(input.selected_index, 0)
	var other_ring_point := Vector2(3500, 1750) + Vector2(PATROL_RADIUS, 0.0)
	var result := input.on_mouse_down(other_ring_point)
	assert_ne(result, PreBattleInput.RESULT_DRAG_CIRCLE,
		"Clicking on a non-selected ship's ring must not start circle drag")
	assert_ne(input.state, PreBattleInput.STATE_DRAGGING_CIRCLE)


func test_drag_circle_updates_patrol_center_not_position():
	var ship_pos := Vector2(500, 500)
	var patrol_center := Vector2(2500, 1750)
	var entries: Array = [_make_entry(ship_pos, LARGE_HULL, patrol_center)]
	var input := _make_input(entries)
	input.on_mouse_down(ship_pos)
	var ring_point := patrol_center + Vector2(PATROL_RADIUS, 0.0)
	input.on_mouse_down(ring_point)
	# Move 300u east; drag_offset preserved so center moves by the same delta.
	input.on_mouse_motion(ring_point + Vector2(300, 0))
	assert_eq(entries[0]["patrol_center"], patrol_center + Vector2(300, 0),
		"Circle drag should translate patrol_center")
	assert_eq(entries[0]["position"], ship_pos,
		"Circle drag must not modify position")
	assert_eq(float(entries[0]["patrol_radius"]), PATROL_RADIUS,
		"Circle drag must not modify patrol_radius")


func test_drag_circle_clamps_patrol_center_to_bounds():
	var ship_pos := Vector2(500, 500)
	var patrol_center := Vector2(2500, 1750)
	var entries: Array = [_make_entry(ship_pos, LARGE_HULL, patrol_center)]
	var input := _make_input(entries)
	input.on_mouse_down(ship_pos)
	var ring_point := patrol_center + Vector2(PATROL_RADIUS, 0.0)
	input.on_mouse_down(ring_point)
	input.on_mouse_motion(Vector2(99999, 99999))
	var clamped: Vector2 = entries[0]["patrol_center"]
	assert_lte(clamped.x, BOUNDS.end.x, "patrol_center x clamped within bounds")
	assert_lte(clamped.y, BOUNDS.end.y, "patrol_center y clamped within bounds")
	assert_gte(clamped.x, BOUNDS.position.x)
	assert_gte(clamped.y, BOUNDS.position.y)


# ============================================================================
# Ship drag (existing behavior — drag only starts when clicking selected ship)
# ============================================================================

func test_ship_drag_updates_only_position_not_patrol_center():
	var original_patrol := Vector2(2500, 1750)
	var ship_pos := Vector2(1000, 1000)
	var entries: Array = [_make_entry(ship_pos, LARGE_HULL, original_patrol)]
	var input := _make_input(entries)
	input.on_mouse_down(ship_pos)  # select
	input.on_mouse_down(ship_pos)  # drag
	input.on_mouse_motion(Vector2(1500, 1200))
	assert_eq(entries[0]["position"], Vector2(1500, 1200),
		"Drag should move the ship's spawn position")
	assert_eq(entries[0]["patrol_center"], original_patrol,
		"Ship drag must never modify patrol_center")


func test_ship_drag_clamps_to_battlefield_bounds():
	var ship_pos := Vector2(1000, 1000)
	var entries: Array = [_make_entry(ship_pos, LARGE_HULL)]
	var input := _make_input(entries)
	input.on_mouse_down(ship_pos)  # select
	input.on_mouse_down(ship_pos)  # drag
	input.on_mouse_motion(Vector2(99999, 99999))
	var clamped: Vector2 = entries[0]["position"]
	assert_lte(clamped.x, BOUNDS.end.x, "x should be clamped within bounds")
	assert_lte(clamped.y, BOUNDS.end.y, "y should be clamped within bounds")
	assert_gte(clamped.x, BOUNDS.position.x, "x should not fall below bounds")
	assert_gte(clamped.y, BOUNDS.position.y, "y should not fall below bounds")

	input.on_mouse_motion(Vector2(-99999, -99999))
	clamped = entries[0]["position"]
	assert_gte(clamped.x, BOUNDS.position.x, "x should be clamped to lower bound")
	assert_gte(clamped.y, BOUNDS.position.y, "y should be clamped to lower bound")


func test_motion_outside_drag_is_a_noop():
	var entries: Array = [_make_entry(Vector2(1000, 1000), LARGE_HULL)]
	var input := _make_input(entries)
	var idx := input.on_mouse_motion(Vector2(1500, 1500))
	assert_eq(idx, -1, "Motion in IDLE state should report no drag")
	assert_eq(entries[0]["position"], Vector2(1000, 1000),
		"Motion in IDLE state must not move ships")


# ============================================================================
# State transitions
# ============================================================================

func test_mouse_up_returns_to_idle_but_keeps_selection():
	var ship_pos := Vector2(1000, 1000)
	var entries: Array = [_make_entry(ship_pos, LARGE_HULL)]
	var input := _make_input(entries)
	input.on_mouse_down(ship_pos)  # select
	input.on_mouse_down(ship_pos)  # drag
	var released := input.on_mouse_up()
	assert_eq(released, 0, "Mouse up should report the released entry index")
	assert_eq(input.state, PreBattleInput.STATE_IDLE,
		"State should return to IDLE after release")
	assert_eq(input.dragging_index, -1, "Dragging index should clear on release")
	assert_eq(input.selected_index, 0,
		"Selection persists after a drop so the user can keep editing")


func test_mouse_up_without_drag_returns_negative():
	var entries: Array = [_make_entry(Vector2(1000, 1000), LARGE_HULL)]
	var input := _make_input(entries)
	var released := input.on_mouse_up()
	assert_eq(released, -1, "Mouse up while idle should report no released drag")
	assert_eq(input.state, PreBattleInput.STATE_IDLE)


func test_clear_selection_resets_state_and_index():
	var ship_pos := Vector2(1000, 1000)
	var entries: Array = [_make_entry(ship_pos, LARGE_HULL)]
	var input := _make_input(entries)
	input.on_mouse_down(ship_pos)  # select
	input.on_mouse_down(ship_pos)  # drag
	input.clear_selection()
	assert_eq(input.selected_index, -1)
	assert_eq(input.state, PreBattleInput.STATE_IDLE)
	assert_eq(input.dragging_index, -1)
