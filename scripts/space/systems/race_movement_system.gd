class_name RaceMovementSystem
extends RefCounted

## Thin glue that flies a racer toward a marker using the REAL flight AI.
##
## There is deliberately NO racing-specific flight math here: the whole point
## of the race screen is to exercise and tune the combat steering/physics, so a
## racer is driven exactly like a ship carrying a "tactical" order that pursues
## a point. We present the next marker as a pursuit target and delegate to
## MovementSystem.calculate_blended_control (live steering blend) and
## MovementSystem.apply_space_physics (the flight model + crew_modifiers).

## Synthetic target id for the marker a racer is currently chasing.
const MARKER_TARGET_ID := "__race_marker__"


## Steering-order block that makes a ship pursue a point and fly onto it.
## Merged into ship.orders once at race setup; the real steering reads these
## fields every frame. pursue-only weights + zero preferred_range = "go here".
static func pursuit_orders() -> Dictionary:
	"""Return the orders block that drives pure waypoint pursuit via real steering."""
	return {
		"current_order": "tactical",
		"engagement_target": MARKER_TARGET_ID,
		"target_id": MARKER_TARGET_ID,
		"goal_weights": {"pursue": 1.0, "keep_range": 0.0, "evade": 0.0, "formation": 0.0},
		"preferred_range": 0.0,
		"facing_mode": "auto",
		"formation_slot": Vector2.ZERO,
		"anchor_position": Vector2.ZERO,
		"support_pos": null,
	}


## Advance one racer by one tick toward marker_pos using the real flight AI.
## nearby_racers feeds the steering's boids separation so the grid doesn't pile
## up. Returns the new ship dict (position/velocity/rotation updated).
static func update_racer(ship: Dictionary, marker_pos: Vector2,
		nearby_racers: Array, delta: float) -> Dictionary:
	"""Fly the racer toward marker_pos via calculate_blended_control + physics."""
	var target := {"ship_id": MARKER_TARGET_ID, "position": marker_pos}
	var pilot_control := MovementSystem.calculate_blended_control(
		ship, target, [], nearby_racers, [], delta)
	return MovementSystem.apply_space_physics(ship, pilot_control, delta)
