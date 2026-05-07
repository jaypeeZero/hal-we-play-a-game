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

const STATE_IDLE: int = 0
const STATE_DRAGGING_SHIP: int = 1
const STATE_DRAGGING_CIRCLE: int = 2

## on_mouse_down result codes.
const RESULT_NONE: int = 0           # nothing meaningful happened
const RESULT_SELECTED: int = 1       # selection changed (no drag started)
const RESULT_DRAG_SHIP: int = 2      # already-selected ship → drag started
const RESULT_DRAG_CIRCLE: int = 3    # selected ship's ring → circle drag started
const RESULT_DESELECTED: int = 4     # empty click cleared selection

# Floor on hit-test radius so small ships stay clickable when zoomed out.
const MIN_PICK_RADIUS: float = 60.0
# Tolerance band around the selected entry's patrol ring for circle-drag pick.
const RING_TOLERANCE: float = 20.0

var state: int = STATE_IDLE
var dragging_index: int = -1
var selected_index: int = -1
var drag_offset: Vector2 = Vector2.ZERO
var bounds: Rect2
var entries: Array


func _init(entries_ref: Array, bounds_rect: Rect2) -> void:
	entries = entries_ref
	bounds = bounds_rect


func pick_ship_at(world_pos: Vector2) -> int:
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var ship_pos: Vector2 = entry["position"]
		var hull_length: float = float(entry.get("hull_length", 0.0))
		var pick_radius: float = max(hull_length * 0.5, MIN_PICK_RADIUS)
		if world_pos.distance_to(ship_pos) <= pick_radius:
			return i
	return -1


## Hit-test priority:
##   1. Ship body — if same as selected_index, start ship drag; otherwise
##      switch selection only (no drag this click; user clicks again to drag).
##   2. Selected entry's patrol ring — start circle drag.
##   3. Empty space — deselect.
func on_mouse_down(world_pos: Vector2) -> int:
	var idx := pick_ship_at(world_pos)
	if idx >= 0:
		if idx == selected_index:
			state = STATE_DRAGGING_SHIP
			dragging_index = idx
			drag_offset = world_pos - entries[idx]["position"]
			return RESULT_DRAG_SHIP
		selected_index = idx
		return RESULT_SELECTED

	if selected_index >= 0 and _is_on_selected_ring(world_pos):
		state = STATE_DRAGGING_CIRCLE
		dragging_index = selected_index
		drag_offset = world_pos - entries[selected_index]["patrol_center"]
		return RESULT_DRAG_CIRCLE

	if selected_index >= 0:
		selected_index = -1
		return RESULT_DESELECTED
	return RESULT_NONE


func on_mouse_motion(world_pos: Vector2) -> int:
	if state == STATE_DRAGGING_SHIP:
		var target: Vector2 = world_pos - drag_offset
		entries[dragging_index]["position"] = _clamp_to_bounds(target)
		return dragging_index
	if state == STATE_DRAGGING_CIRCLE:
		var target_center: Vector2 = world_pos - drag_offset
		entries[dragging_index]["patrol_center"] = _clamp_to_bounds(target_center)
		return dragging_index
	return -1


func on_mouse_up() -> int:
	var released_index := dragging_index
	state = STATE_IDLE
	dragging_index = -1
	drag_offset = Vector2.ZERO
	return released_index


func clear_selection() -> void:
	selected_index = -1
	dragging_index = -1
	drag_offset = Vector2.ZERO
	state = STATE_IDLE


func _is_on_selected_ring(world_pos: Vector2) -> bool:
	var entry: Dictionary = entries[selected_index]
	var center: Vector2 = entry["patrol_center"]
	var radius: float = float(entry["patrol_radius"])
	return absf(world_pos.distance_to(center) - radius) < RING_TOLERANCE


func _clamp_to_bounds(p: Vector2) -> Vector2:
	return Vector2(
		clamp(p.x, bounds.position.x, bounds.end.x),
		clamp(p.y, bounds.position.y, bounds.end.y)
	)
