extends GutTest

## Tests for GunnerBrain GOAP planner — behavior only, no specific data values.

const GAME_TIME := 100.0


func _make_gunner(ship_id: String = "ship_1") -> Dictionary:
	return TestFactories.make_crew_gunner(TestFactories.DEFAULT_CREW_SKILL, ship_id)


func _add_opportunities(crew: Dictionary, count: int, status: String = "operational") -> void:
	for i in count:
		var opp := TestFactories.make_opportunity("target_%d" % i, 1.0)
		opp["status"] = status
		crew.awareness.opportunities.append(opp)


# CAPTAIN ORDER REFLEX

func test_captain_order_fires_at_ordered_target_even_with_no_opportunities():
	var gunner := _make_gunner()
	var ordered_target := "special_target"
	gunner.orders.received = {
		"type": "engage",
		"subtype": "fire",
		"target_id": ordered_target,
	}
	# No opportunities in awareness — brain would return empty, but reflex fires first

	var result := GunnerAI.make_decision(gunner, GAME_TIME)

	assert_true(result.has("decision"), "Captain order should produce a decision")
	assert_eq(result.decision.get("target_id", ""), ordered_target,
		"Decision should target the captain-ordered ship")
	assert_eq(result.decision.get("type", ""), "fire", "Decision type should be fire")


func test_captain_order_clears_received_order():
	var gunner := _make_gunner()
	gunner.orders.received = {"type": "engage", "subtype": "fire", "target_id": "t1"}

	var result := GunnerAI.make_decision(gunner, GAME_TIME)

	assert_null(result.crew_data.orders.received, "Received order should be cleared after execution")


# NO TARGETS

func test_no_opportunities_produces_no_fire_decision():
	var gunner := _make_gunner()
	# no opportunities added

	var result := GunnerAI.make_decision(gunner, GAME_TIME)

	# When no targets exist, the "decision" key is absent (matches old behavior)
	var has_fire: bool = result.has("decision") and result.get("decision", {}).get("type", "") == "fire"
	assert_false(has_fire, "No opportunities should yield no fire decision")


func test_no_opportunities_advances_next_decision_time():
	var gunner := _make_gunner()

	var result := GunnerAI.make_decision(gunner, GAME_TIME)

	assert_gt(result.crew_data.next_decision_time, GAME_TIME,
		"next_decision_time should advance even when no targets present")


# PLAN LOCK

func test_plan_lock_retains_action_within_lock_window():
	var gunner := _make_gunner()
	_add_opportunities(gunner, 1)

	# First decide — commits a plan lock
	var result1 := GunnerAI.make_decision(gunner, GAME_TIME)
	var first_subtype: String = result1.get("decision", {}).get("subtype", "")

	# Second decide shortly after — should pick the same action (plan lock active)
	var result2 := GunnerAI.make_decision(result1.crew_data, GAME_TIME + 0.1)
	var second_subtype: String = result2.get("decision", {}).get("subtype", "")

	assert_eq(first_subtype, second_subtype,
		"Plan lock should retain the chosen action across closely-spaced decisions")


# DECISION TIME CADENCES

func test_suppressive_fire_has_shorter_redecide_than_standard():
	# Suppressive cadence is much shorter than standard — verify they differ
	assert_lt(GunnerAction.SUPPRESSIVE_REDECIDE_DELAY, GunnerAction.HOLD_REDECIDE_MIN,
		"Suppressive fire should re-decide much faster than standard fire")


func test_next_decision_time_advances_for_any_decision():
	var gunner := _make_gunner()
	_add_opportunities(gunner, 1)

	var result := GunnerAI.make_decision(gunner, GAME_TIME)

	assert_gt(result.crew_data.next_decision_time, GAME_TIME,
		"next_decision_time must always advance after a decision")


# STANDARD FIRE — TARGETS PRESENT

func test_with_targets_produces_a_fire_decision():
	var gunner := _make_gunner()
	_add_opportunities(gunner, 1)

	var result := GunnerAI.make_decision(gunner, GAME_TIME)

	assert_true(result.has("decision"), "Should produce a decision when targets present")
	assert_eq(result.decision.get("type", ""), "fire", "Decision type should be fire")


func test_fire_decision_references_a_known_target():
	var gunner := _make_gunner()
	_add_opportunities(gunner, 2)
	var target_ids: Array = gunner.awareness.opportunities.map(func(o): return o.get("id", ""))

	var result := GunnerAI.make_decision(gunner, GAME_TIME)

	var chosen: String = result.get("decision", {}).get("target_id", "")
	assert_true(chosen in target_ids, "Fire decision must reference a target from opportunities")
