extends GutTest

## Aggression scales how hard the area leash pulls a ship back to its
## patrol area. With no target, leash applies normally regardless of
## aggression; with a target, low aggression hugs harder, high aggression
## releases the leash entirely.

const PATROL_RADIUS: float = 100.0


func _make_ship_outside_area(distance: float, aggression: float, has_target: bool) -> Dictionary:
	var ship: Dictionary = {
		"ship_id": "ship",
		"position": Vector2(distance, 0.0),  # outside area, east of center
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"angular_velocity": 0.0,
		"status": "operational",
		"stats": {
			"max_speed": 300.0,
			"acceleration": 100.0,
			"turn_rate": 3.0,
			"size": 16.0,
		},
		"assigned_area": {
			"center": Vector2.ZERO,
			"radius": PATROL_RADIUS,
		},
		"orders": {
			"current_order": "engage",
			"target_id": "enemy_1" if has_target else "",
		},
		"crew_modifiers": {
			"pilot_aggression": aggression,
		},
	}
	return ship


# Desired heading is "due east" (toward target far away from area). The
# ship sits east of the patrol center; the leash will try to pull it back
# west. The pull is measured by how far the effective heading rotates from
# the desired heading toward the return heading.
const DESIRED_HEADING: float = PI / 2.0  # face east in this game's coordinate system
const RETURN_HEADING: float = -PI / 2.0  # face west, back toward area center


func _heading_pull_amount(ship: Dictionary, desired: float) -> float:
	var effective: float = MovementSystem.apply_area_leash(ship, desired)
	# Distance between desired and effective, normalized to π
	var diff: float = abs(angle_difference(desired, effective))
	return diff


func test_no_target_leashes_normally_regardless_of_aggression():
	# Same distance outside area, both should produce the same pull when no
	# target is set.
	var dist: float = PATROL_RADIUS * 1.5
	var timid: Dictionary = _make_ship_outside_area(dist, 0.0, false)
	var berserk: Dictionary = _make_ship_outside_area(dist, 1.0, false)
	var p_timid: float = _heading_pull_amount(timid, DESIRED_HEADING)
	var p_berserk: float = _heading_pull_amount(berserk, DESIRED_HEADING)
	assert_almost_eq(p_timid, p_berserk, 0.0001,
		"Without a target, leash pull is independent of aggression")


func test_high_aggression_with_target_releases_leash():
	var dist: float = PATROL_RADIUS * 1.5
	var ship: Dictionary = _make_ship_outside_area(dist, 1.0, true)
	var pull: float = _heading_pull_amount(ship, DESIRED_HEADING)
	assert_almost_eq(pull, 0.0, 0.0001,
		"At full aggression with a target, leash does not pull")


func test_low_aggression_with_target_pulls_harder_than_baseline():
	var dist: float = PATROL_RADIUS * 1.25
	var timid: Dictionary = _make_ship_outside_area(dist, 0.0, true)
	var baseline: Dictionary = _make_ship_outside_area(dist, 0.5, true)
	var p_timid: float = _heading_pull_amount(timid, DESIRED_HEADING)
	var p_baseline: float = _heading_pull_amount(baseline, DESIRED_HEADING)
	assert_gt(p_timid, p_baseline,
		"Low aggression with a target produces a stronger pull than baseline")


func test_baseline_aggression_matches_unconfigured_behavior():
	# A ship with pilot_aggression = 0.5 should rotate the heading by the
	# same amount as a ship with no crew_modifiers at all.
	var dist: float = PATROL_RADIUS * 1.5
	var configured: Dictionary = _make_ship_outside_area(dist, 0.5, true)
	var unconfigured: Dictionary = _make_ship_outside_area(dist, 0.5, true)
	unconfigured.crew_modifiers = {}
	var p_configured: float = _heading_pull_amount(configured, DESIRED_HEADING)
	var p_unconfigured: float = _heading_pull_amount(unconfigured, DESIRED_HEADING)
	assert_almost_eq(p_configured, p_unconfigured, 0.0001,
		"aggression=0.5 reproduces the original (unconfigured) leash strength")


func test_high_aggression_without_target_still_returns_to_patrol():
	# Even an extremely aggressive pilot returns to patrol when there's no
	# enemy in detection.
	var dist: float = PATROL_RADIUS * 1.5
	var ship: Dictionary = _make_ship_outside_area(dist, 1.0, false)
	var pull: float = _heading_pull_amount(ship, DESIRED_HEADING)
	assert_gt(pull, 0.0,
		"High aggression without a target still respects the leash")
