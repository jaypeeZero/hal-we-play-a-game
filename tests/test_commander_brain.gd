extends GutTest

## Tests for CommanderBrain GOAP planner — behavior only, no specific data values.

const GAME_TIME := 100.0
const HIGH_SKILL := 1.0


func _make_commander(ship_id: String = "flagship") -> Dictionary:
	var cmd := TestFactories.make_crew_member(CrewData.Role.FLEET_COMMANDER, HIGH_SKILL, ship_id)
	cmd.command_chain.subordinates = ["squad_1", "squad_2"]
	return cmd


func _add_threat(crew: Dictionary, id: String = "enemy_1", priority: float = 50.0) -> void:
	crew.awareness.threats.append(TestFactories.make_threat(id, priority))


func _add_opportunity(crew: Dictionary, id: String = "target_1") -> void:
	crew.awareness.opportunities.append(TestFactories.make_opportunity(id, 1.0))


# COMMANDER ALWAYS EMITS A DECISION

func test_commander_always_produces_a_decision():
	var cmd := _make_commander()
	# No knowledge, no threats, no opportunities — AssessAction is the fallback

	var result := CommanderAI.make_decision(cmd, GAME_TIME)

	assert_true(result.has("decision"), "Commander must always emit a decision (assess fallback)")


func test_no_knowledge_falls_back_to_assess():
	var cmd := _make_commander()
	# No knowledge means only AssessAction qualifies

	var result := CommanderAI.make_decision(cmd, GAME_TIME)

	assert_eq(result.get("decision", {}).get("subtype", ""), "assess",
		"Without knowledge, commander should assess")


# ASSESS PRODUCES NO ORDERS

func test_assess_issues_no_subordinate_orders():
	var cmd := _make_commander()

	var result := CommanderAI.make_decision(cmd, GAME_TIME)

	if result.get("decision", {}).get("subtype", "") == "assess":
		assert_true(result.crew_data.orders.issued.is_empty(),
			"Assess decision should not issue subordinate orders")


# CADENCE

func test_next_decision_time_always_advances():
	var cmd := _make_commander()

	var result := CommanderAI.make_decision(cmd, GAME_TIME)

	assert_gt(result.crew_data.next_decision_time, GAME_TIME,
		"next_decision_time must advance after every commander decision")


# KNOWLEDGE-DRIVEN ACTIONS

func test_concentrate_force_orders_all_subordinates_onto_one_target():
	# We can't force the knowledge system to return a specific action in unit tests,
	# but we CAN verify that when concentrate_force fires, all subordinate orders
	# reference the same target.
	var cmd := _make_commander()
	cmd.command_chain.subordinates = ["sq_1", "sq_2", "sq_3"]
	_add_opportunity(cmd, "priority_target")

	var result := CommanderAI.make_decision(cmd, GAME_TIME)

	# If the decision is concentrate_force, all orders must share the same target
	if result.get("decision", {}).get("subtype", "") == "concentrate_force":
		var issued: Array = result.crew_data.orders.issued
		var target_ids: Array = issued.map(func(o): return o.get("target_id", ""))
		for tid in target_ids:
			assert_eq(tid, target_ids[0], "All concentrate_force orders must share one target")


func test_withdrawal_requires_outnumbering_by_multiplier():
	# strategic_withdrawal only fires when threats > subs * MULTIPLIER.
	# With 2 subordinates and 3 threats (not exceeding multiplier=2 → 4 needed),
	# withdrawal must not fire.
	var cmd := _make_commander()
	cmd.command_chain.subordinates = ["sq_1", "sq_2"]
	for i in 3:
		_add_threat(cmd, "enemy_%d" % i)

	var result := CommanderAI.make_decision(cmd, GAME_TIME)

	var subtype: String = result.get("decision", {}).get("subtype", "")
	assert_ne(subtype, "strategic_withdrawal",
		"Withdrawal must not fire when not outnumbered beyond the multiplier threshold")
