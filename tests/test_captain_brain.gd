extends GutTest

## Tests for CaptainBrain GOAP planner — behavior only, no specific data values.

const GAME_TIME := 100.0
const HIGH_SKILL := 1.0
const LOW_SKILL  := 0.05


func _make_captain(skill: float = HIGH_SKILL, ship_id: String = "ship_1") -> Dictionary:
	return TestFactories.make_crew_captain(skill, ship_id)


# SQUADRON-LEADER ORDER REFLEX

func test_squadron_leader_order_executes_before_brain():
	var captain := _make_captain()
	captain.orders.received = {"type": "engage", "subtype": "pursue", "target_id": "enemy_1"}

	var result := CaptainAI.make_decision(captain, GAME_TIME)

	assert_true(result.has("decision"), "Order should produce a decision")
	assert_eq(result.decision.get("subtype", ""), "engage",
		"Order should be reflected in the decision subtype")
	assert_null(result.crew_data.orders.received, "Received order should be cleared")


func test_order_broken_down_for_subordinates():
	var captain := _make_captain()
	captain.command_chain.subordinates = ["pilot_x", "gunner_x"]
	captain.orders.received = {"type": "engage", "subtype": "pursue", "target_id": "t1"}

	var result := CaptainAI.make_decision(captain, GAME_TIME)

	assert_false(result.crew_data.orders.issued.is_empty(),
		"Squadron-leader order should be broken down into subordinate orders")


# DECISIONS ALWAYS PAIR WITH ORDERS

func test_every_decision_includes_issued_orders_array():
	var captain := _make_captain()
	captain.awareness.threats = [TestFactories.make_threat("t1", 100.0)]
	captain.awareness.opportunities = [TestFactories.make_opportunity("e1", 1.0)]

	var result := CaptainAI.make_decision(captain, GAME_TIME)

	# Orders may be empty if no subordinates, but the issued field should be set
	assert_not_null(result.crew_data.orders.issued,
		"Captain always writes orders.issued (may be empty array if no subordinates)")


# TACTICAL+ STYLE GATING

func test_adaptive_only_aggressive_pursuit_not_selected_at_low_skill():
	# Low skill → REACTIVE style → aggressive_pursuit should never be chosen
	var captain := _make_captain(LOW_SKILL)
	captain.awareness.opportunities = [TestFactories.make_opportunity("e1", 1.0)]
	# No threats — the only precondition for aggressive_pursuit besides ADAPTIVE style

	# Run multiple decisions to account for any randomness
	for _i in 10:
		var result := CaptainAI.make_decision(captain, GAME_TIME + _i)
		var subtype: String = result.get("decision", {}).get("subtype", "")
		assert_ne(subtype, "aggressive_pursuit",
			"ADAPTIVE-only action must never appear at low (REACTIVE) skill")


# SUPPORT ALLY

func test_tactical_captain_with_damaged_friendly_chooses_support_over_engage():
	# HIGH_SKILL → TACTICAL or ADAPTIVE style
	var captain := _make_captain(HIGH_SKILL)
	captain.awareness.opportunities = [TestFactories.make_opportunity("e1", 1.0)]
	captain.awareness.known_entities = [{
		"id": "ally_1",
		"is_friendly": true,
		"status": "damaged",
	}]

	var result := CaptainAI.make_decision(captain, GAME_TIME)

	assert_true(result.has("decision"), "Should produce a decision")
	assert_eq(result.get("decision", {}).get("subtype", ""), "support_ally",
		"Tactical captain with damaged friendly should prefer support_ally over engage")


# CADENCE

func test_next_decision_time_always_advances():
	var captain := _make_captain()

	var result := CaptainAI.make_decision(captain, GAME_TIME)

	assert_gt(result.crew_data.next_decision_time, GAME_TIME,
		"next_decision_time must always advance after a captain decision")
