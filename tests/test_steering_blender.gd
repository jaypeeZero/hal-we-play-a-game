extends GutTest

## Behavior tests for SteeringBlender.build_directive().
## Asserts behavioral properties (ordering, presence, direction of change),
## not literal weight values. Data values may be tuned; behaviors must hold.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Minimal ship dict with one internal component at full health.
func _make_ship(ship_id: String = "s1", hull_fraction: float = 1.0) -> Dictionary:
	var max_health := 100
	var cur_health := int(max_health * hull_fraction)
	return {
		"ship_id": ship_id,
		"position": Vector2.ZERO,
		"internals": [
			{
				"component_id": "hull",
				"type": "hull",
				"max_health": max_health,
				"current_health": cur_health,
				"status": "operational" if hull_fraction > 0.0 else "destroyed",
			}
		],
	}

## Minimal target dict.
func _make_target(ship_id: String = "t1", pos: Vector2 = Vector2(1000.0, 0.0)) -> Dictionary:
	return {"ship_id": ship_id, "position": pos}

## Threat that is targeting `target_id`.
func _make_threat_targeting(target_id: String, pos: Vector2 = Vector2(500.0, 0.0)) -> Dictionary:
	return {"ship_id": "threat_x", "position": pos, "target_id": target_id}

## Threat that is not targeting anyone specifically.
func _make_neutral_threat(pos: Vector2 = Vector2(500.0, 0.0)) -> Dictionary:
	return {"ship_id": "threat_y", "position": pos}

## Resolved tactics with explicit mentality_scalar and range_scalar.
func _make_tactics(mentality_scalar: float = 0.5, range_scalar: float = 0.5) -> Dictionary:
	return {
		"mentality_scalar": mentality_scalar,
		"range_scalar":     range_scalar,
	}

func _build(ship: Dictionary, tactics: Dictionary, target: Dictionary, threats: Array, optimal_range: float = 1000.0) -> Dictionary:
	return SteeringBlender.build_directive(ship, tactics, target, threats, optimal_range)


# ---------------------------------------------------------------------------
# 1. Contract completeness — every required field is always present
# ---------------------------------------------------------------------------

func test_directive_always_has_all_contract_keys():
	var d := _build(_make_ship(), _make_tactics(), _make_target(), [])
	assert_true(d.has("engagement_target"), "directive must have engagement_target")
	assert_true(d.has("goal_weights"),      "directive must have goal_weights")
	assert_true(d.has("preferred_range"),   "directive must have preferred_range")
	assert_true(d.has("formation_slot"),    "directive must have formation_slot")
	assert_true(d.has("anchor_position"),   "directive must have anchor_position")


func test_goal_weights_always_has_all_four_keys():
	var d := _build(_make_ship(), _make_tactics(), _make_target(), [])
	var gw: Dictionary = d["goal_weights"]
	assert_true(gw.has("pursue"),     "goal_weights must have pursue")
	assert_true(gw.has("keep_range"), "goal_weights must have keep_range")
	assert_true(gw.has("evade"),      "goal_weights must have evade")
	assert_true(gw.has("formation"),  "goal_weights must have formation")


func test_directive_with_no_target_still_has_all_contract_keys():
	var d := _build(_make_ship(), _make_tactics(), {}, [])
	assert_true(d.has("engagement_target"), "empty-target directive must have engagement_target")
	assert_true(d.has("goal_weights"),      "empty-target directive must have goal_weights")
	assert_true(d.has("preferred_range"),   "empty-target directive must have preferred_range")
	assert_true(d.has("formation_slot"),    "empty-target directive must have formation_slot")
	assert_true(d.has("anchor_position"),   "empty-target directive must have anchor_position")


func test_phase1_formation_fields_are_zero():
	var d := _build(_make_ship(), _make_tactics(), _make_target(), [])
	assert_eq(d["formation_slot"],  Vector2.ZERO, "formation_slot must be ZERO in Phase 1")
	assert_eq(d["anchor_position"], Vector2.ZERO, "anchor_position must be ZERO in Phase 1")


func test_phase1_formation_weight_is_zero():
	var d := _build(_make_ship(), _make_tactics(), _make_target(), [])
	assert_eq(d["goal_weights"]["formation"], 0.0, "formation weight must be 0.0 in Phase 1")


# ---------------------------------------------------------------------------
# 2. engagement_target
# ---------------------------------------------------------------------------

func test_engagement_target_matches_target_ship_id():
	var target := _make_target("enemy_99")
	var d := _build(_make_ship(), _make_tactics(), target, [])
	assert_eq(d["engagement_target"], "enemy_99",
		"engagement_target must equal target.ship_id")


func test_engagement_target_is_empty_when_no_target():
	var d := _build(_make_ship(), _make_tactics(), {}, [])
	assert_eq(d["engagement_target"], "",
		"engagement_target must be empty string when target dict is empty")


# ---------------------------------------------------------------------------
# 3. preferred_range: kite > knife, and scales with weapon_optimal_range
# ---------------------------------------------------------------------------

func test_kite_preferred_range_is_larger_than_knife():
	var ship := _make_ship()
	var knife_tactics := _make_tactics(0.5, 0.0)   # range_scalar = 0 → knife
	var kite_tactics  := _make_tactics(0.5, 1.0)   # range_scalar = 1 → kite
	var d_knife := _build(ship, knife_tactics, _make_target(), [], 1000.0)
	var d_kite  := _build(ship, kite_tactics,  _make_target(), [], 1000.0)
	assert_gt(d_kite["preferred_range"], d_knife["preferred_range"],
		"Kite engagement range must produce a larger preferred_range than knife")


func test_preferred_range_scales_with_weapon_optimal():
	var ship   := _make_ship()
	var tactics := _make_tactics(0.5, 0.5)  # mid range_scalar
	var d_short := _build(ship, tactics, _make_target(), [], 500.0)
	var d_long  := _build(ship, tactics, _make_target(), [], 2000.0)
	assert_gt(d_long["preferred_range"], d_short["preferred_range"],
		"Larger weapon_optimal_range must produce a larger preferred_range")


func test_preferred_range_is_always_positive():
	var ship := _make_ship()
	for rs in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var d := _build(ship, _make_tactics(0.5, rs), _make_target(), [], 0.0)
		assert_gt(d["preferred_range"], 0.0,
			"preferred_range must always be positive even with zero weapon_optimal_range")


func test_mid_range_scalar_preferred_range_is_between_knife_and_kite():
	var ship := _make_ship()
	var optimal := 1000.0
	var d_knife := _build(ship, _make_tactics(0.5, 0.0), _make_target(), [], optimal)
	var d_mid   := _build(ship, _make_tactics(0.5, 0.5), _make_target(), [], optimal)
	var d_kite  := _build(ship, _make_tactics(0.5, 1.0), _make_target(), [], optimal)
	assert_gt(d_mid["preferred_range"], d_knife["preferred_range"],
		"Mid range_scalar preferred_range must be above knife")
	assert_lt(d_mid["preferred_range"], d_kite["preferred_range"],
		"Mid range_scalar preferred_range must be below kite")


# ---------------------------------------------------------------------------
# 4. pursue weight: rises with mentality_scalar
# ---------------------------------------------------------------------------

func test_higher_mentality_yields_higher_pursue_weight():
	var ship   := _make_ship()
	var target := _make_target()
	var d_low  := _build(ship, _make_tactics(0.0, 0.5), target, [])
	var d_high := _build(ship, _make_tactics(1.0, 0.5), target, [])
	assert_gt(d_high["goal_weights"]["pursue"], d_low["goal_weights"]["pursue"],
		"All-out mentality must produce a higher pursue weight than defensive")


func test_defensive_mentality_still_has_positive_pursue_weight():
	# Even a defensive ship nudges toward its target.
	var d := _build(_make_ship(), _make_tactics(0.0, 0.5), _make_target(), [])
	assert_gt(d["goal_weights"]["pursue"], 0.0,
		"Defensive mentality must still produce a positive pursue weight")


func test_pursue_weight_is_strictly_ordered_across_mentality():
	var ship := _make_ship()
	var p0: float  = _build(ship, _make_tactics(0.0,  0.5), _make_target(), [])["goal_weights"]["pursue"]
	var p25: float = _build(ship, _make_tactics(0.25, 0.5), _make_target(), [])["goal_weights"]["pursue"]
	var p50: float = _build(ship, _make_tactics(0.5,  0.5), _make_target(), [])["goal_weights"]["pursue"]
	var p75: float = _build(ship, _make_tactics(0.75, 0.5), _make_target(), [])["goal_weights"]["pursue"]
	var p100: float = _build(ship, _make_tactics(1.0, 0.5), _make_target(), [])["goal_weights"]["pursue"]
	assert_true(p0 < p25,  "pursue: defensive < cautious")
	assert_true(p25 < p50, "pursue: cautious < balanced")
	assert_true(p50 < p75, "pursue: balanced < attacking")
	assert_true(p75 < p100, "pursue: attacking < all_out")


# ---------------------------------------------------------------------------
# 5. evade weight: situational bumps
# ---------------------------------------------------------------------------

func test_being_targeted_raises_evade_weight():
	var ship    := _make_ship("s1")
	var target  := _make_target()
	var threats_with_targeting := [_make_threat_targeting("s1")]
	var d_safe     := _build(ship, _make_tactics(), target, [])
	var d_targeted := _build(ship, _make_tactics(), target, threats_with_targeting)
	assert_gt(d_targeted["goal_weights"]["evade"], d_safe["goal_weights"]["evade"],
		"Being targeted must raise the evade weight")


func test_low_hull_raises_evade_weight():
	var full_hull  := _make_ship("s1", 1.0)
	var crit_hull  := _make_ship("s1", 0.1)   # below HULL_CRITICAL_THRESHOLD
	var target := _make_target()
	var d_full := _build(full_hull, _make_tactics(), target, [])
	var d_crit := _build(crit_hull, _make_tactics(), target, [])
	assert_gt(d_crit["goal_weights"]["evade"], d_full["goal_weights"]["evade"],
		"Critical hull must produce a higher evade weight than full hull")


func test_outnumbered_raises_evade_weight():
	var ship    := _make_ship("s1")
	var target  := _make_target()
	var many_threats := [
		_make_neutral_threat(Vector2(100, 0)),
		_make_neutral_threat(Vector2(200, 0)),
		_make_neutral_threat(Vector2(300, 0)),
	]
	var d_alone      := _build(ship, _make_tactics(), target, [])
	var d_outnumbered := _build(ship, _make_tactics(), target, many_threats)
	assert_gt(d_outnumbered["goal_weights"]["evade"], d_alone["goal_weights"]["evade"],
		"Being outnumbered must raise the evade weight")


func test_evade_weight_accumulates_multiple_situational_bumps():
	var crit_hull := _make_ship("s1", 0.1)
	var threats   := [_make_threat_targeting("s1"), _make_neutral_threat()]
	var d_none := _build(_make_ship("s1", 1.0), _make_tactics(), _make_target(), [])
	var d_all  := _build(crit_hull,             _make_tactics(), _make_target(), threats)
	assert_gt(d_all["goal_weights"]["evade"], d_none["goal_weights"]["evade"],
		"Combined situational pressures must produce a larger evade than baseline")


func test_evade_weight_has_positive_base_even_without_threats():
	var d := _build(_make_ship(), _make_tactics(1.0, 0.5), _make_target(), [])
	assert_gt(d["goal_weights"]["evade"], 0.0,
		"Evade weight must be positive even at full aggression with no threats")


# ---------------------------------------------------------------------------
# 6. keep_range weight is constant (geometry, not mentality-dependent)
# ---------------------------------------------------------------------------

func test_keep_range_weight_is_same_for_all_mentality_scalars():
	var ship := _make_ship()
	var kr_low: float  = _build(ship, _make_tactics(0.0, 0.5), _make_target(), [])["goal_weights"]["keep_range"]
	var kr_high: float = _build(ship, _make_tactics(1.0, 0.5), _make_target(), [])["goal_weights"]["keep_range"]
	assert_eq(kr_low, kr_high,
		"keep_range weight must not vary with mentality_scalar — orbit geometry is always active")


# ---------------------------------------------------------------------------
# 7. All weights are non-negative
# ---------------------------------------------------------------------------

func test_all_weights_are_non_negative():
	var d := _build(
		_make_ship("s1", 0.1),
		_make_tactics(1.0, 1.0),
		_make_target(),
		[_make_threat_targeting("s1"), _make_neutral_threat(), _make_neutral_threat()]
	)
	for key in d["goal_weights"]:
		assert_gte(d["goal_weights"][key], 0.0,
			"goal_weights[%s] must be non-negative" % key)
