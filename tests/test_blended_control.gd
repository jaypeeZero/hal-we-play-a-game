extends GutTest

## Behavior tests for MovementSystem.calculate_blended_control().
## Tests assert motion behaviors (closes, backs off, faces threat) given
## synthetic ship+target dicts with pre-written goal_weights/preferred_range.
## No literals specific to tuning values.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const OPTIMAL_RANGE := 1500.0   # arbitrary world units, mid-combat scale

## Minimal ship dict with a position, velocity, rotation, and orders.
func _make_ship(
	pos: Vector2,
	preferred_range: float,
	goal_weights: Dictionary,
	velocity: Vector2 = Vector2.ZERO
) -> Dictionary:
	return {
		"ship_id": "test_ship",
		"type": "fighter",
		"position": pos,
		"velocity": velocity,
		"rotation": 0.0,
		"status": "operational",
		"stats": {
			"max_speed": 300.0,
			"acceleration": 100.0,
			"turn_rate": 3.0,
			"size": 15.0,
		},
		"orders": {
			"current_order": "tactical",
			"engagement_target": "target_1",
			"goal_weights": goal_weights,
			"preferred_range": preferred_range,
			"formation_slot":  Vector2.ZERO,
			"anchor_position": Vector2.ZERO,
		},
		"crew_modifiers": {},
	}

## Minimal target dict.
func _make_target(pos: Vector2, ship_id: String = "target_1") -> Dictionary:
	return {"ship_id": ship_id, "position": pos}

## Threat at a given position (no target_id needed for blended_control).
func _make_threat(pos: Vector2) -> Dictionary:
	return {"ship_id": "threat_x", "position": pos}

## Balanced weights: all goals contribute.
func _balanced_weights() -> Dictionary:
	return {"pursue": 0.5, "keep_range": 0.4, "evade": 0.1, "formation": 0.0}

## Pursuit-dominant weights.
func _chase_weights() -> Dictionary:
	return {"pursue": 1.0, "keep_range": 0.3, "evade": 0.05, "formation": 0.0}

## Evade-dominant weights.
func _evade_weights() -> Dictionary:
	return {"pursue": 0.05, "keep_range": 0.1, "evade": 1.0, "formation": 0.0}

## Returns the angle (radians) a ship with heading `h` is visually facing.
func _heading_to_dir(h: float) -> Vector2:
	return Vector2(sin(h), -cos(h))


# ---------------------------------------------------------------------------
# 1. Return struct always has required pilot_control keys
# ---------------------------------------------------------------------------

func test_blended_control_always_returns_all_pilot_control_keys():
	var ship   := _make_ship(Vector2.ZERO, OPTIMAL_RANGE, _balanced_weights())
	var target := _make_target(Vector2(2000, 0))
	var ctrl   := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	assert_true(ctrl.has("desired_heading"), "must have desired_heading")
	assert_true(ctrl.has("throttle"),        "must have throttle")
	assert_true(ctrl.has("thrust_active"),   "must have thrust_active")
	assert_true(ctrl.has("is_braking"),      "must have is_braking")
	assert_true(ctrl.has("lateral_thrust"),  "must have lateral_thrust")


func test_blended_control_with_no_target_still_returns_all_keys():
	var ship := _make_ship(Vector2.ZERO, OPTIMAL_RANGE, _balanced_weights())
	var ctrl := MovementSystem.calculate_blended_control(ship, {}, [], [], [], 0.016)
	assert_true(ctrl.has("desired_heading"), "no-target: must have desired_heading")
	assert_true(ctrl.has("throttle"),        "no-target: must have throttle")
	assert_true(ctrl.has("thrust_active"),   "no-target: must have thrust_active")
	assert_true(ctrl.has("is_braking"),      "no-target: must have is_braking")
	assert_true(ctrl.has("lateral_thrust"),  "no-target: must have lateral_thrust")


# ---------------------------------------------------------------------------
# 2. Closing behavior: distant target with short preferred_range → positive throttle
# ---------------------------------------------------------------------------

func test_distant_target_with_short_preferred_range_applies_throttle():
	# Ship at origin; target very far away; preferred_range << distance.
	# Pursuit + keep_range both push the ship toward target → throttle > 0.
	var ship   := _make_ship(Vector2.ZERO, 200.0, _chase_weights())
	var target := _make_target(Vector2(5000, 0))
	var ctrl   := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	assert_gt(ctrl["throttle"], 0.0,
		"With a distant target and short preferred_range the ship must apply positive throttle")


func test_distant_target_is_not_braking():
	var ship   := _make_ship(Vector2.ZERO, 200.0, _chase_weights())
	var target := _make_target(Vector2(5000, 0))
	var ctrl   := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	assert_false(ctrl["is_braking"],
		"A ship closing on a distant target must not be braking")


# ---------------------------------------------------------------------------
# 3. Range-keeping behavior: close target with large preferred_range → brakes / backs off
# ---------------------------------------------------------------------------

func test_target_inside_preferred_range_triggers_braking_or_backoff():
	# preferred_range is large; target is very close (inside range).
	# keep_range pushes outward; within LATERAL_THRUST_RANGE the ship faces target
	# and brakes to stop the inward drift.
	var large_range: float = 3000.0
	var close_pos: Vector2 = Vector2(100, 0)   # well inside preferred_range
	var ship := _make_ship(Vector2.ZERO, large_range, _balanced_weights())
	var target := _make_target(close_pos)
	var ctrl := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	# At close range (inside LATERAL_THRUST_RANGE) braking or lateral correction
	# must apply. Either is acceptable — both express "back off."
	assert_true(ctrl["is_braking"] or ctrl["throttle"] == 0.0,
		"Ship with target inside preferred_range must brake or cut throttle")


# ---------------------------------------------------------------------------
# 4. Evade behavior: dominant evade weight + nearby threat → heading points away
# ---------------------------------------------------------------------------

func test_dominant_evade_weight_faces_away_from_threat():
	# Threat is to the right (+X). Ship uses evade-dominant weights.
	# At far range (no target or target very far) the ship should face AWAY from threat.
	var threat_pos: Vector2 = Vector2(1000, 0)
	var ship   := _make_ship(Vector2.ZERO, OPTIMAL_RANGE, _evade_weights())
	# Place target very far so threat dominates and we're outside LATERAL_THRUST_RANGE
	var target := _make_target(Vector2(50000, 0))
	var threats := [_make_threat(threat_pos)]
	var ctrl := MovementSystem.calculate_blended_control(ship, target, threats, [], [], 0.016)
	# The heading should have a leftward (−X) component, i.e. facing away from threat.
	var facing: Vector2 = _heading_to_dir(ctrl["desired_heading"])
	assert_lt(facing.x, 0.0,
		"With dominant evade weight and threat to the right, ship must face left (away from threat)")


# ---------------------------------------------------------------------------
# 5. Facing decouples from move at close range: faces target while strafing
# ---------------------------------------------------------------------------

func test_close_range_target_produces_heading_toward_target():
	# Target is to the right (+X) at close range (< LATERAL_THRUST_RANGE).
	# Ship must face the target regardless of the blended move direction.
	var target_pos: Vector2 = Vector2(500, 0)   # close range
	var ship   := _make_ship(Vector2.ZERO, OPTIMAL_RANGE, _balanced_weights())
	var target := _make_target(target_pos)
	var ctrl   := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	var facing: Vector2 = _heading_to_dir(ctrl["desired_heading"])
	assert_gt(facing.x, 0.0,
		"At close range the ship must face the target (rightward heading) regardless of move blend")


func test_close_range_can_produce_nonzero_lateral_thrust():
	# With a blended move that has a perpendicular component to facing,
	# lateral_thrust should be non-zero when close to the target.
	# Use an evade threat from below and target to the right.
	var target_pos: Vector2  = Vector2(500, 0)
	var threat_pos: Vector2  = Vector2(0, -500)   # threat below → evade pushes up (+Y)
	var ship   := _make_ship(Vector2.ZERO, OPTIMAL_RANGE, _balanced_weights())
	var target := _make_target(target_pos)
	var threats := [_make_threat(threat_pos)]
	var ctrl := MovementSystem.calculate_blended_control(ship, target, threats, [], [], 0.016)
	# When the ship faces the target (right) and evade pushes up, the perpendicular
	# component is non-zero → lateral_thrust should be non-zero.
	assert_ne(ctrl["lateral_thrust"], 0.0,
		"Close-range with a perpendicular threat must produce non-zero lateral_thrust")


# ---------------------------------------------------------------------------
# 6. Empty orders gracefully handled (no crash, reasonable defaults)
# ---------------------------------------------------------------------------

func test_no_orders_does_not_crash():
	var ship_no_orders := {
		"ship_id": "bare",
		"type": "fighter",
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"stats": {"max_speed": 300.0, "acceleration": 100.0, "turn_rate": 3.0, "size": 15.0},
		"orders": {},
		"crew_modifiers": {},
	}
	var target := _make_target(Vector2(2000, 0))
	# Must not crash — just return a valid struct.
	var ctrl := MovementSystem.calculate_blended_control(ship_no_orders, target, [], [], [], 0.016)
	assert_true(ctrl.has("desired_heading"), "bare orders: must still return desired_heading")


# ---------------------------------------------------------------------------
# 7. thrust_active reflects throttle
# ---------------------------------------------------------------------------

func test_thrust_active_true_when_throttle_above_threshold():
	var ship   := _make_ship(Vector2.ZERO, 200.0, _chase_weights())
	var target := _make_target(Vector2(5000, 0))
	var ctrl   := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	assert_eq(ctrl["thrust_active"], ctrl["throttle"] > 0.1,
		"thrust_active must equal (throttle > 0.1)")


# ---------------------------------------------------------------------------
# 8. Formation goal: dominant formation weight + far slot → steers toward slot
# ---------------------------------------------------------------------------

## Ship with a dominant formation weight and explicit formation_slot.
func _make_ship_with_slot(
	pos: Vector2,
	preferred_range: float,
	goal_weights: Dictionary,
	formation_slot: Vector2
) -> Dictionary:
	return {
		"ship_id": "test_ship",
		"type": "fighter",
		"position": pos,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"stats": {
			"max_speed": 300.0,
			"acceleration": 100.0,
			"turn_rate": 3.0,
			"size": 15.0,
		},
		"orders": {
			"current_order": "tactical",
			"engagement_target": "target_1",
			"goal_weights": goal_weights,
			"preferred_range": preferred_range,
			"formation_slot":  formation_slot,
			"anchor_position": Vector2.ZERO,
		},
		"crew_modifiers": {},
	}

## Formation-dominant weights: the ship should hold its slot.
func _formation_weights() -> Dictionary:
	return {"pursue": 0.05, "keep_range": 0.1, "evade": 0.05, "formation": 2.0}


func test_dominant_formation_weight_steers_toward_far_slot():
	# Formation slot is far above the ship (+Y); target is to the right (+X).
	# With formation weight >> others the heading should have a strong +Y component.
	var ship_pos: Vector2     = Vector2.ZERO
	var slot_pos: Vector2     = Vector2(0.0, 5000.0)   # far above
	var target_pos: Vector2   = Vector2(5000.0, 0.0)   # far right
	var ship   := _make_ship_with_slot(ship_pos, OPTIMAL_RANGE, _formation_weights(), slot_pos)
	var target := _make_target(target_pos)
	var ctrl   := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	var facing: Vector2 = _heading_to_dir(ctrl["desired_heading"])
	assert_gt(facing.y, 0.0,
		"With dominant formation weight and slot above, ship must have upward (+Y) heading component")


func test_formation_slot_at_ship_position_does_not_override_pursuit():
	# When formation_slot == ship position, the formation goal vector is ~zero
	# and pursue + keep_range dominate → ship should close on distant target.
	var ship_pos: Vector2   = Vector2.ZERO
	var slot_pos: Vector2   = Vector2.ZERO    # slot is right here
	var target_pos: Vector2 = Vector2(5000.0, 0.0)
	var ship   := _make_ship_with_slot(ship_pos, 200.0, _formation_weights(), slot_pos)
	var target := _make_target(target_pos)
	var ctrl   := MovementSystem.calculate_blended_control(ship, target, [], [], [], 0.016)
	# Slot is zero-distance → formation goal vanishes; pursue takes over.
	assert_gt(ctrl["throttle"], 0.0,
		"With formation slot at ship position, the ship must still apply throttle toward the distant target")
