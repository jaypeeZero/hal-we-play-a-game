extends GutTest

## Tests for CaptainBrain GOAP planner — behavior only, no specific data values.
##
## Phase 4c update: command orders (engage/withdraw/hold) are now BLENDED —
## they set ship.orders.posture / ship.orders.focus_target and let CaptainBrain
## run normally, rather than short-circuiting into discrete sub-orders.

const GAME_TIME := 100.0
const HIGH_SKILL := 1.0
const LOW_SKILL  := 0.05


func _make_captain(skill: float = HIGH_SKILL, ship_id: String = "ship_1") -> Dictionary:
	return TestFactories.make_crew_captain(skill, ship_id)


# BLENDED COMMAND ORDER ABSORPTION (replaces old short-circuit tests)

func test_engage_order_absorbed_and_clears_received():
	## Phase 4c: engage order is ABSORBED (not short-circuited). orders.received
	## must be null after the call; ship.orders.focus_target must be set.
	var captain := _make_captain()
	captain.orders.received = {"type": "engage", "subtype": "pursue", "target_id": "enemy_1"}

	var result := CaptainAI.make_decision(captain, GAME_TIME)

	assert_true(result.has("decision"), "Absorbed order must still produce a decision (from CaptainBrain)")
	assert_null(result.crew_data.orders.get("received"),
		"orders.received must be null after blended absorption")
	assert_eq(result.crew_data.orders.get("focus_target", ""), "enemy_1",
		"Engage order must stamp ship.orders.focus_target with the target_id")


func test_engage_order_does_not_produce_discrete_pursue_subtype():
	## The old short-circuit emitted subtype "engage" (discrete). The new path
	## lets CaptainBrain run — subtype will be whatever the brain picks, never
	## the raw order type echoed as a discrete maneuver.
	var captain := _make_captain()
	captain.command_chain.subordinates = ["pilot_x", "gunner_x"]
	captain.orders.received = {"type": "engage", "subtype": "pursue", "target_id": "t1"}

	var result := CaptainAI.make_decision(captain, GAME_TIME)

	# orders.received was absorbed — no discrete breakdown should have run.
	assert_null(result.crew_data.orders.get("received"),
		"orders.received must be cleared by the absorber")
	# The issued orders from CaptainBrain may be empty (no subordinates in bare
	# captain fixture), but there must NOT be discrete pursue orders per old path.
	var issued: Array = result.crew_data.orders.get("issued", [])
	var pursue_orders := issued.filter(func(o): return o.get("subtype","") == "pursue")
	assert_eq(pursue_orders.size(), 0,
		"Absorbed engage order must NOT produce discrete 'pursue' subordinate orders")


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
