extends GutTest

## Phase 3b: focus-fire command layer.
##
## Tests cover three behaviours:
##   1. Leader decision — squadron_leader with high concentration issues
##      focus_target orders to each subordinate; with low concentration issues none.
##   2. Pilot absorption — absorbing a focus_target order stores target_id in
##      crew.focus_assignment, leaves decision blended (not discrete pursue),
##      and clears orders.received.
##   3. Targeting boost — focus_assignment + concentration lifts the designated
##      enemy above an equal non-focused enemy; near-zero concentration gives
##      negligible boost; absent focus_assignment leaves weight unchanged.
##
## These tests are behaviour-only. They do not assert specific numeric scores —
## only ordering (ranked[0].id) and structural invariants (field presence, null
## state). Mirrors the style of test_tactics_targeting_weight.gd.

# ── Factories ─────────────────────────────────────────────────────────────────

## Minimal crew dict for _issue_focus_commands / _absorb_focus_order tests.
## Uses the same shape as test_command_designation_system.gd local factories.
func _make_leader(id: String, ship_id: String, subordinates: Array,
		concentration: float) -> Dictionary:
	return {
		"crew_id": id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"command_hat": "squadron_leader",
		"command_chain": {"superior": null, "subordinates": subordinates},
		"stats": {
			"skills": {"piloting": 0.8, "leadership": 0.8, "tactics": 0.8},
			"reaction_time": 0.1,
			"decision_time": 0.3,
			"stress": 0.0,
			"fatigue": 0.0,
		},
		"tactics": {"concentration": concentration, "priority": "nearest", "sector_focus": "none"},
		"awareness": {
			"threats": [],
			"opportunities": [{"id": "enemy_1", "type": "ship", "_opportunity_score": 90.0}],
			"known_entities": [],
		},
		"orders": {"received": null, "current": null, "issued": []},
		"current_target": "",
		"last_focus_command_time": -999.0,  # ensure cadence doesn't block
		"last_formation_command_time": -999.0,
	}

func _make_pilot_with_order(crew_id: String, ship_id: String, target_id: String) -> Dictionary:
	return {
		"crew_id": crew_id,
		"role": CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"command_hat": "",
		"command_chain": {"superior": "leader_1", "subordinates": []},
		"stats": {
			"skills": {"piloting": 0.7, "tactics": 0.7, "awareness": 0.7,
				"aim": 0.7, "composure": 0.7, "aggression": 0.5, "machinery": 0.7},
			"reaction_time": 0.1,
			"decision_time": 0.3,
			"stress": 0.0,
			"fatigue": 0.0,
			"awareness_range": 1000.0,
		},
		"tactics": {"concentration": 0.8, "priority": "nearest", "sector_focus": "none"},
		"awareness": {"threats": [], "opportunities": [], "known_entities": []},
		"orders": {
			"received": {"type": "focus_target", "target_id": target_id},
			"current": null,
			"issued": [],
		},
		"current_action": "idle",
		"next_decision_time": 0.0,
		"play_assignment": null,
		"formation_assignment": null,
	}

## Entity info snapshot — mirrors _make_entity_info in test_tactics_targeting_weight.gd.
func _make_entity(id: String, ship_type: String, pos: Vector2,
		own_pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var to_own := own_pos - pos
	var vel := Vector2.ZERO
	if to_own.length() > 0.001:
		vel = to_own.normalized() * 100.0  # uniform closing speed
	return {
		"id": id,
		"type": "ship",
		"ship_type": ship_type,
		"team": 1,
		"position": pos,
		"velocity": vel,
		"status": "operational",
		"_threat_priority": 80.0,
	}

func _make_ship_dict(id: String, ship_type: String, pos: Vector2, team: int) -> Dictionary:
	return {
		"ship_id": id,
		"type": ship_type,
		"team": team,
		"position": pos,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"armor_sections": [
			{"section_id": "front", "current_armor": 100, "max_armor": 100,
			 "size": 1.0, "arc": {"start": -90.0, "end": 90.0}}
		],
		"internals": [],
		"weapons": [],
	}

# ── Deliverable 1: Leader focus decision ──────────────────────────────────────

func test_leader_with_high_concentration_issues_focus_target_to_each_subordinate():
	## squadron_leader with concentration > CONCENTRATION_THRESHOLD must issue
	## one focus_target order per subordinate, all naming the same designated enemy.
	var leader := _make_leader("leader_1", "ship_l", ["sub_a", "sub_b"], 0.8)
	var ship_data := {"ship_id": "ship_l", "team": 0, "position": Vector2.ZERO}
	var ships: Array = []

	var result := CrewAISystem._issue_focus_commands(leader, ship_data, 0.0, ships)

	var orders_dict: Dictionary = result.get("orders", {})
	var issued: Array = orders_dict.get("issued", [])
	var focus_orders: Array = issued.filter(func(o): return o.get("type", "") == "focus_target")

	assert_eq(focus_orders.size(), 2,
		"Leader with high concentration must issue one focus_target per subordinate.")
	assert_eq(focus_orders[0].get("target_id", ""), "enemy_1",
		"focus_target order must name the designated enemy from opportunities.")
	assert_eq(focus_orders[1].get("target_id", ""), "enemy_1",
		"All focus_target orders must name the same designated enemy.")
	# Subordinate routing
	var recipients: Array = focus_orders.map(func(o): return o.get("to", ""))
	assert_true(recipients.has("sub_a"), "Order for sub_a must be present.")
	assert_true(recipients.has("sub_b"), "Order for sub_b must be present.")


func test_leader_with_low_concentration_issues_no_focus_orders():
	## concentration below CONCENTRATION_THRESHOLD → no focus_target orders.
	## Ships spread per their own 3a priority instead.
	var leader := _make_leader("leader_1", "ship_l", ["sub_a", "sub_b"], 0.2)
	var ship_data := {"ship_id": "ship_l", "team": 0, "position": Vector2.ZERO}
	var ships: Array = []

	var result := CrewAISystem._issue_focus_commands(leader, ship_data, 0.0, ships)

	var orders_dict: Dictionary = result.get("orders", {})
	var issued: Array = orders_dict.get("issued", [])
	var focus_orders: Array = issued.filter(func(o): return o.get("type", "") == "focus_target")

	assert_eq(focus_orders.size(), 0,
		"Leader with low concentration must not issue any focus_target orders.")


func test_leader_prefers_current_target_over_top_opportunity():
	## When current_target is set, that ship is designated — not the top opportunity.
	var leader := _make_leader("leader_1", "ship_l", ["sub_a"], 0.9)
	leader["current_target"] = "pinned_enemy"
	var ship_data := {"ship_id": "ship_l", "team": 0, "position": Vector2.ZERO}

	var result := CrewAISystem._issue_focus_commands(leader, ship_data, 0.0, [])
	var orders_dict: Dictionary = result.get("orders", {})
	var issued: Array = orders_dict.get("issued", [])
	var focus_orders: Array = issued.filter(func(o): return o.get("type", "") == "focus_target")

	assert_eq(focus_orders[0].get("target_id", ""), "pinned_enemy",
		"Leader must use current_target as the designated enemy when it is set.")


func test_leader_sets_own_focus_assignment():
	## The leader itself also gains focus_assignment so targeting_weight boosts apply.
	var leader := _make_leader("leader_1", "ship_l", ["sub_a"], 0.9)
	var result := CrewAISystem._issue_focus_commands(
		leader, {"ship_id": "ship_l"}, 0.0, [])
	assert_eq(result.get("focus_assignment", ""), "enemy_1",
		"Leader must write its own focus_assignment after issuing focus orders.")


func test_leader_cadence_prevents_double_issue():
	## If not enough time has passed, no new orders are issued.
	var leader := _make_leader("leader_1", "ship_l", ["sub_a"], 0.9)
	leader["last_focus_command_time"] = 0.0  # just issued
	var game_time_too_soon := 1.0  # less than FOCUS_CADENCE (3.0)

	var result := CrewAISystem._issue_focus_commands(
		leader, {"ship_id": "ship_l"}, game_time_too_soon, [])
	var orders_d: Dictionary = result.get("orders", {})
	var issued: Array = orders_d.get("issued", [])
	assert_eq(issued.size(), 0,
		"Leader must not re-issue focus orders before FOCUS_CADENCE has elapsed.")

# ── Deliverable 2: Pilot absorption ───────────────────────────────────────────

func test_absorb_focus_order_stores_target_in_focus_assignment():
	## Receiving a focus_target order must store target_id in crew.focus_assignment.
	var pilot := _make_pilot_with_order("pilot_1", "ship_p", "enemy_42")
	var ships: Array = []

	var result := CrewAISystem._absorb_focus_order(pilot, ships)

	assert_eq(result.get("focus_assignment", ""), "enemy_42",
		"focus_assignment must hold the designated target_id after absorption.")


func test_absorb_focus_order_clears_orders_received():
	## orders.received must be null after absorption — prevents execute_pilot_order.
	var pilot := _make_pilot_with_order("pilot_1", "ship_p", "enemy_42")

	var result := CrewAISystem._absorb_focus_order(pilot, [])

	var ord: Dictionary = result.get("orders", {})
	assert_null(ord.get("received"),
		"orders.received must be null after absorbing a focus_target order.")


func test_absorb_focus_order_does_not_affect_non_focus_orders():
	## A received order of a different type must pass through unchanged.
	var pilot := _make_pilot_with_order("pilot_1", "ship_p", "enemy_42")
	pilot.orders.received = {"type": "formation_slot", "formation_assignment": {}}

	var result := CrewAISystem._absorb_focus_order(pilot, [])

	var ord2: Dictionary = result.get("orders", {})
	assert_not_null(ord2.get("received"),
		"Non-focus_target orders must not be consumed by _absorb_focus_order.")


func test_pilot_decision_stays_blended_after_focus_absorption():
	## After absorbing a focus_target order the pilot's decision must NOT be
	## a discrete pursue — it must stay in the blended tactical path.
	## We verify this structurally: the returned decision subtype must not be
	## exactly "pursue" (which is the discrete-order short-circuit output).
	## A fully-wired pilot requires too many dependencies for a unit test, so
	## we check that _absorb_focus_order does not itself produce any decision
	## and leaves orders.received=null (the blended path runs next).
	var pilot := _make_pilot_with_order("pilot_1", "ship_p", "enemy_42")

	var absorbed := CrewAISystem._absorb_focus_order(pilot, [])

	# Absorption itself returns a crew dict, not a {crew_data, decision} pair.
	assert_true(absorbed is Dictionary, "Absorption must return the crew dict directly.")
	var abs_ord: Dictionary = absorbed.get("orders", {})
	assert_null(abs_ord.get("received"),
		"Cleared orders.received ensures execute_pilot_order is NOT triggered.")
	# focus_assignment is set — the blended decision will use it as a weight hint.
	assert_ne(absorbed.get("focus_assignment", ""), "",
		"focus_assignment must be populated so the blended path can use it.")

# ── Deliverable 3: Targeting weight boost ─────────────────────────────────────

## Crew with focus_assignment set and high concentration.
func _make_focused_crew(focus_id: String, concentration: float) -> Dictionary:
	var crew = CrewData.create_crew_member(CrewData.Role.PILOT, 1.0)
	crew.assigned_to = "own_ship"
	crew.stats.skills.awareness = 1.0
	crew.stats.skills.tactics = 1.0
	crew["tactics"] = {"concentration": concentration, "priority": "nearest", "sector_focus": "none"}
	crew["focus_assignment"] = focus_id
	return crew

func _own_ship() -> Dictionary:
	return {
		"ship_id": "own_ship",
		"team": 0,
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"status": "operational",
		"type": "fighter",
	}

func test_focus_boost_ranks_designated_enemy_above_equal_non_focused():
	## Two identical fighters at the same distance: the focused one must rank first.
	var own := _own_ship()
	var pos := Vector2(400, 0)

	var focused_info := _make_entity("focused", "fighter", pos)
	var other_info   := _make_entity("other",   "fighter", pos)
	var all_ships := [
		own,
		_make_ship_dict("focused", "fighter", pos, 1),
		_make_ship_dict("other",   "fighter", pos, 1),
	]

	var crew := _make_focused_crew("focused", 0.9)
	var ranked := InformationSystem.identify_threats(
		[focused_info, other_info], own, crew, all_ships)

	assert_gte(ranked.size(), 2, "Both enemies must be visible.")
	assert_eq(ranked[0].id, "focused",
		"Focus boost: designated enemy must rank above identical non-focused enemy.")


func test_focus_boost_near_zero_concentration_is_negligible():
	## With concentration ≈ 0, the boost is lerp(1, FOCUS_MAX_BOOST, 0) = 1.0,
	## so focus makes no difference. Two enemies with same distance/type should
	## not be deterministically reordered by focus alone.
	## We verify: the weight difference between focused and non-focused is minimal.
	var tactics := {"concentration": 0.0, "priority": "nearest", "sector_focus": "none"}
	var own := _own_ship()
	var pos := Vector2(400, 0)

	var entity_focused := _make_entity("focused", "fighter", pos)
	var entity_other   := _make_entity("other",   "fighter", pos)
	var all_ships := [
		own,
		_make_ship_dict("focused", "fighter", pos, 1),
		_make_ship_dict("other",   "fighter", pos, 1),
	]

	var w_focused := InformationSystem.targeting_weight(
		entity_focused, own, tactics, all_ships, "focused", 0.0)
	var w_other   := InformationSystem.targeting_weight(
		entity_other,   own, tactics, all_ships, "focused", 0.0)

	# lerp(1, FOCUS_MAX_BOOST, 0) == 1 → weights must be equal
	assert_almost_eq(w_focused, w_other, 0.001,
		"At concentration=0 focus boost must be 1.0 (neutral), so weights are equal.")


func test_no_focus_assignment_leaves_weight_unchanged():
	## crew with no focus_assignment must produce the same weight as 3a behaviour.
	## Verify that targeting_weight with focus_assignment="" matches a call
	## with no focus args (the default).
	var tactics := {"concentration": 0.9, "priority": "nearest", "sector_focus": "none"}
	var own := _own_ship()
	var pos := Vector2(300, 0)
	var entity := _make_entity("target", "fighter", pos)
	var all_ships := [own, _make_ship_dict("target", "fighter", pos, 1)]

	var w_no_focus := InformationSystem.targeting_weight(entity, own, tactics, all_ships)
	var w_empty    := InformationSystem.targeting_weight(entity, own, tactics, all_ships, "", 0.9)

	assert_almost_eq(w_no_focus, w_empty, 0.001,
		"Empty focus_assignment must produce identical weight to the 3a (no-focus) call.")


func test_focus_boost_scales_with_concentration():
	## Weight at concentration=1.0 must be greater than at concentration=0.5,
	## which must be greater than at concentration=0.0.
	var tactics := {"concentration": 1.0, "priority": "nearest", "sector_focus": "none"}
	var own := _own_ship()
	var pos := Vector2(400, 0)
	var entity := _make_entity("focused", "fighter", pos)
	var all_ships := [own, _make_ship_dict("focused", "fighter", pos, 1)]

	var w_full := InformationSystem.targeting_weight(entity, own, tactics, all_ships, "focused", 1.0)
	var w_half := InformationSystem.targeting_weight(entity, own, tactics, all_ships, "focused", 0.5)
	var w_none := InformationSystem.targeting_weight(entity, own, tactics, all_ships, "focused", 0.0)

	assert_gt(w_full, w_half, "concentration=1.0 must give higher boost than 0.5.")
	assert_gt(w_half, w_none, "concentration=0.5 must give higher boost than 0.0.")
	assert_almost_eq(w_none, InformationSystem.targeting_weight(
			entity, own, tactics, all_ships), 0.001,
		"concentration=0.0 boost must equal baseline (3a) weight.")
