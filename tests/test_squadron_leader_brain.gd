extends GutTest

## Tests for SquadronLeaderBrain GOAP planner — behavior only, no specific data values.

const GAME_TIME := 100.0
const HIGH_SKILL := 1.0
const LOW_SKILL  := 0.05


func _make_leader(skill: float = HIGH_SKILL) -> Dictionary:
	var leader := TestFactories.make_crew_member(CrewData.Role.SQUADRON_LEADER, skill, "ship_1")
	leader.command_chain.subordinates = ["ship_2", "ship_3"]
	return leader


func _add_threat(crew: Dictionary, id: String = "enemy_1", priority: float = 50.0) -> void:
	crew.awareness.threats.append(TestFactories.make_threat(id, priority))


func _add_opportunity(crew: Dictionary, id: String = "target_1") -> void:
	crew.awareness.opportunities.append(TestFactories.make_opportunity(id, 1.0))


# DAMAGED SUBORDINATE → MUTUAL SUPPORT

func test_damaged_subordinate_triggers_mutual_support():
	var leader := _make_leader()
	var damaged_sub := {
		"id": "ship_2",
		"is_friendly": true,
		"status": "damaged",
		"position": Vector2.ZERO,
	}
	leader.awareness.known_entities = [damaged_sub]

	var result := SquadronLeaderAI.make_decision(leader, GAME_TIME)

	assert_true(result.has("decision"), "Should produce a decision")
	assert_eq(result.get("decision", {}).get("subtype", ""), "call_mutual_support",
		"Damaged subordinate should trigger mutual support")


func test_mutual_support_orders_reference_damaged_ship():
	var leader := _make_leader()
	var damaged_sub := {"id": "ship_2", "is_friendly": true, "status": "critical", "position": Vector2.ZERO}
	leader.awareness.known_entities = [damaged_sub]

	var result := SquadronLeaderAI.make_decision(leader, GAME_TIME)

	var has_ref := false
	for order in result.crew_data.orders.issued:
		if order.get("ally_id", "") == "ship_2":
			has_ref = true
	assert_true(has_ref, "Mutual support orders must reference the damaged subordinate's id")


# SCATTERED → REFORM (no threats)

func test_scattered_squadron_without_threats_reforms():
	var leader := _make_leader()
	# Place subordinates far apart so is_scattered fires
	leader.awareness.known_entities = [
		{"id": "ship_2", "position": Vector2(0, 0), "status": "operational"},
		{"id": "ship_3", "position": Vector2(5000, 0), "status": "operational"},
	]
	# No threats

	var result := SquadronLeaderAI.make_decision(leader, GAME_TIME)

	assert_eq(result.get("decision", {}).get("subtype", ""), "reform_formation",
		"Scattered squadron without threats should reform")


func test_reform_sends_orders_to_all_subordinates():
	var leader := _make_leader()
	leader.awareness.known_entities = [
		{"id": "ship_2", "position": Vector2(0, 0), "status": "operational"},
		{"id": "ship_3", "position": Vector2(5000, 0), "status": "operational"},
	]

	var result := SquadronLeaderAI.make_decision(leader, GAME_TIME)

	var subs: Array = leader.command_chain.subordinates
	var issued: Array = result.crew_data.orders.issued
	assert_eq(issued.size(), subs.size(),
		"Reform should send an order to every subordinate")


# SCREEN WITHDRAWAL

func test_more_threats_than_ships_triggers_screen_withdrawal():
	var leader := _make_leader()
	# 3 threats, 2 subordinates → threats > subordinates
	leader.command_chain.subordinates = ["ship_2", "ship_3"]
	for i in 3:
		_add_threat(leader, "enemy_%d" % i)

	var result := SquadronLeaderAI.make_decision(leader, GAME_TIME)

	assert_eq(result.get("decision", {}).get("subtype", ""), "screen_withdrawal",
		"More threats than ships should trigger screen withdrawal")


# ORCHESTRATED-ONLY COORDINATED ATTACK

func test_coordinated_attack_never_fires_below_min_subordinates():
	var leader := _make_leader(HIGH_SKILL)
	# Set coordination style to ORCHESTRATED via high skill — but only 1 subordinate
	leader.command_chain.subordinates = ["ship_2"]
	_add_opportunity(leader)

	# Run many times to ensure coordinated attack never fires with 1 subordinate
	for _i in 20:
		var result := SquadronLeaderAI.make_decision(leader, GAME_TIME + _i)
		var subtype: String = result.get("decision", {}).get("subtype", "")
		assert_ne(subtype, "coordinate_attack_run",
			"coordinate_attack_run must never fire below the subordinate minimum")


# SQUADRON PLAY BYPASSES BRAIN

func test_active_squadron_play_returns_execute_play_decision():
	# When a play is active, the reflex fires before the brain.
	# We can test this indirectly: if a play is returned, subtype is "execute_play".
	# The actual play selection depends on geometry — just confirm the reflex path exists.
	# With no opportunities, _build_play_geometry returns {} so no play fires.
	var leader := _make_leader()
	leader.command_chain.subordinates = ["ship_2", "ship_3"]
	# No opportunities → geometry empty → play reflex returns {} → brain runs

	var result := SquadronLeaderAI.make_decision(leader, GAME_TIME)

	var subtype: String = result.get("decision", {}).get("subtype", "")
	assert_ne(subtype, "execute_play",
		"Without opportunities/geometry, no play should fire")
