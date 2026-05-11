class_name PreBattleInput
extends RefCounted

## Pure input state machine for the pre-battle screen. Owns drag state,
## current selection, and hit-tests against BattlePlan entries; no scene
## dependencies, so it can be exercised under GUT without instantiating
## ships or cameras.
##
## Entries are taken by reference (Array of Dictionary) and mutated in place
## when the caller drags a ship or its patrol ring. Each entry must carry
## `position` (Vector2), `hull_length` (float), `patrol_center` (Vector2),
## and `patrol_radius` (float).
##
## Selection is multi: `selected_indices` is the source of truth. Use
## `is_selected(idx)` for hit-tests in the renderer.

const STATE_IDLE: int = 0
const STATE_DRAGGING_SHIP: int = 1
const STATE_DRAGGING_CIRCLE: int = 2
const STATE_BOX_SELECT: int = 3

## on_mouse_down result codes.
const RESULT_NONE: int = 0           # nothing meaningful happened
const RESULT_SELECTED: int = 1       # selection changed (no drag started)
const RESULT_DRAG_SHIP: int = 2      # already-selected ship → drag started
const RESULT_DRAG_CIRCLE: int = 3    # selected ship's ring → circle drag started
const RESULT_DESELECTED: int = 4     # empty click cleared selection
const RESULT_SELECTION_TOGGLED: int = 5  # ctrl-click added/removed a ship
const RESULT_BOX_START: int = 6      # shift-down started a box-select drag

# Floor on hit-test radius so small ships stay clickable when zoomed out.
const MIN_PICK_RADIUS: float = 60.0
# A box-select gesture that ends with a sub-pixel rectangle is treated as a
# stray shift-click; selection is left untouched rather than cleared.
const BOX_MIN_SIZE: float = 4.0

var state: int = STATE_IDLE
var dragging_index: int = -1
var selected_indices: Array[int] = []
var drag_offset: Vector2 = Vector2.ZERO
# index -> Vector2 offset captured at ship-drag start so the group preserves
# its formation as the cursor moves.
var ship_drag_offsets: Dictionary = {}
var box_start: Vector2 = Vector2.ZERO
var box_end: Vector2 = Vector2.ZERO
var bounds: Rect2
var entries: Array


func _init(entries_ref: Array, bounds_rect: Rect2) -> void:
	entries = entries_ref
	bounds = bounds_rect


func is_selected(idx: int) -> bool:
	return selected_indices.has(idx)


func pick_ship_at(world_pos: Vector2) -> int:
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var ship_pos: Vector2 = entry["position"]
		var hull_length: float = float(entry.get("hull_length", 0.0))
		var pick_radius: float = max(hull_length * 0.5, MIN_PICK_RADIUS)
		if world_pos.distance_to(ship_pos) <= pick_radius:
			return i
	return -1


## Returns the index of a currently-selected ship whose patrol disc contains
## world_pos, or -1 if none. Only selected ships' patrol areas are pickable.
func pick_patrol_area_at(world_pos: Vector2) -> int:
	for idx in selected_indices:
		var entry: Dictionary = entries[idx]
		var center: Vector2 = entry["patrol_center"]
		var radius: float = float(entry["patrol_radius"])
		if world_pos.distance_to(center) <= radius:
			return idx
	return -1


## Hit-test priority (modifier-aware):
##   * shift held → always begin a box-select drag from world_pos.
##   * ship body + ctrl → toggle that ship in/out of the selection.
##   * ship body, already in selection → start ship drag (group formation).
##   * ship body, not selected → replace selection with this single ship.
##   * inside a selected ship's patrol disc → start circle drag (all selected
##     rings collapse to the same point as the cursor moves).
##   * empty space with a selection → deselect.
func on_mouse_down(world_pos: Vector2, shift_held: bool = false, ctrl_held: bool = false) -> int:
	if shift_held:
		state = STATE_BOX_SELECT
		box_start = world_pos
		box_end = world_pos
		return RESULT_BOX_START

	var idx := pick_ship_at(world_pos)
	if idx >= 0:
		if ctrl_held:
			if is_selected(idx):
				selected_indices.erase(idx)
			else:
				selected_indices.append(idx)
			return RESULT_SELECTION_TOGGLED
		if is_selected(idx):
			state = STATE_DRAGGING_SHIP
			dragging_index = idx
			_capture_ship_drag_offsets(world_pos)
			return RESULT_DRAG_SHIP
		selected_indices.clear()
		selected_indices.append(idx)
		return RESULT_SELECTED

	var ring_idx := pick_patrol_area_at(world_pos)
	if ring_idx >= 0:
		state = STATE_DRAGGING_CIRCLE
		dragging_index = ring_idx
		drag_offset = world_pos - entries[ring_idx]["patrol_center"]
		return RESULT_DRAG_CIRCLE

	if selected_indices.size() > 0:
		selected_indices.clear()
		return RESULT_DESELECTED
	return RESULT_NONE


func on_mouse_motion(world_pos: Vector2) -> int:
	if state == STATE_DRAGGING_SHIP:
		for i in ship_drag_offsets.keys():
			var target: Vector2 = world_pos - ship_drag_offsets[i]
			entries[i]["position"] = _clamp_to_bounds(target)
		return dragging_index
	if state == STATE_DRAGGING_CIRCLE:
		var new_center: Vector2 = _clamp_to_bounds(world_pos - drag_offset)
		for i in selected_indices:
			entries[i]["patrol_center"] = new_center
		return dragging_index
	if state == STATE_BOX_SELECT:
		box_end = world_pos
		return -1
	return -1


func on_mouse_up() -> int:
	var released := dragging_index
	if state == STATE_BOX_SELECT:
		_finalize_box_select()
		released = -1
	state = STATE_IDLE
	dragging_index = -1
	drag_offset = Vector2.ZERO
	ship_drag_offsets.clear()
	return released


func clear_selection() -> void:
	selected_indices.clear()
	dragging_index = -1
	drag_offset = Vector2.ZERO
	ship_drag_offsets.clear()
	state = STATE_IDLE


## Normalised rect spanning the current box-select gesture; safe to call any
## time but only meaningful while state == STATE_BOX_SELECT.
func get_box_rect() -> Rect2:
	var x_min: float = min(box_start.x, box_end.x)
	var y_min: float = min(box_start.y, box_end.y)
	var x_max: float = max(box_start.x, box_end.x)
	var y_max: float = max(box_start.y, box_end.y)
	return Rect2(Vector2(x_min, y_min), Vector2(x_max - x_min, y_max - y_min))


func _capture_ship_drag_offsets(world_pos: Vector2) -> void:
	ship_drag_offsets.clear()
	for i in selected_indices:
		ship_drag_offsets[i] = world_pos - entries[i]["position"]


func _finalize_box_select() -> void:
	var rect := get_box_rect()
	if rect.size.x < BOX_MIN_SIZE and rect.size.y < BOX_MIN_SIZE:
		return
	selected_indices.clear()
	for i in range(entries.size()):
		var pos: Vector2 = entries[i]["position"]
		if rect.has_point(pos):
			selected_indices.append(i)


func _clamp_to_bounds(p: Vector2) -> Vector2:
	return Vector2(
		clamp(p.x, bounds.position.x, bounds.end.x),
		clamp(p.y, bounds.position.y, bounds.end.y)
	)
