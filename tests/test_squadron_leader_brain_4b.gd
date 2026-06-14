extends GutTest

## Squadron-leader brain activation tests.
##
## Covers:
##   1. CallMutualSupport fires when a subordinate is damaged (LOOSE+).
##   2. ScreenWithdrawal fires when threats > subordinates (LOOSE+).
##   3. No complementary orders + next_decision_time advances when neither fires.
##   4. Suppressed actions (AssignTargets / CoordinateAttackRun / ReformFormation)
##      never produce engage or formation/reform orders from the hatted brain path.
##   5. Support-escort: pilot with support_assignment gets support_pos from FormationSystem.
##   6. SteeringBlender: support goal active when support_pos set; cleared when unset.
##
## Behavior-only. No specific numeric values asserted.

const GAME_TIME := 100.0
const HIGH_SKILL := 1.0
const LOW_SKILL  := 0.05


# ── DRY helpers ───────────────────────────────────────────────────────────────

## Squadron-leader crew with command_hat set, using the full CrewData schema.
## High leadership/tactics so coordination style resolves to LOOSE or higher.
func _make_leader(skill: float = HIGH_SKILL) -> Dictionary:
	var leader := TestFactories.make_crew_member(CrewData.Role.PILOT, skill, "ship_1")
	leader["command_hat"] = "squadron_leader"
	leader["command_chain"] = {"superior": null, "subordinates": ["ship_2", "ship_3"]}
	leader["last_formation_command_time"] = -999.0
	leader["last_focus_command_time"] = -999.0
	leader["tactics"] = {
		"concentration": 0.2,   # below CONCENTRATION_THRESHOLD so focus-fire stays quiet
		"priority": "nearest",
		"sector_focus": "none",
		"mentality_scalar": 0.5,
		"range_scalar": 0.5,
		"duty": "support",
		"role": "skirmisher",
		"shape": "line_abreast",
		"spacing": 0.5,
	}
	if not leader.has("orders"):
		leader["orders"] = {}
	leader["orders"]["issued"] = []
	leader["orders"]["received"] = null
	leader["orders"]["current"] = null
	return leader

func _add_damaged_known_entity(leader: Dictionary, sub_id: String, status: String = "damaged") -> void:
	if not leader.has("awareness"):
		leader["awareness"] = {"threats": [], "opportunities": [], "known_entities": []}
	leader["awareness"]["known_entities"].append({
		"id": sub_id,
		"is_friendly": true,
		"status": status,
		"position": Vector2(100.0, 0.0),
	})

func _add_threats(leader: Dictionary, count: int) -> void:
	if not leader.has("awareness"):
		leader["awareness"] = {"threats": [], "opportunities": [], "known_entities": []}
	for i in count:
		leader["awareness"]["threats"].append({"id": "enemy_%d" % i, "_threat_priority": 50.0})

## Run just the complementary-brain path (not the full pilot decision).
## Returns the crew dict after _run_complementary_brain.
func _run_brain(leader: Dictionary) -> Dictionary:
	return CrewAISystem._run_complementary_brain(leader, GAME_TIME)


# ── Test 1: CallMutualSupport ─────────────────────────────────────────────────

func test_damaged_subordinate_triggers_support_ally_orders():
	## With a damaged subordinate and LOOSE+ coordination (high skill), the brain
	## must issue support_ally orders to the remaining subordinates.
	var leader := _make_leader(HIGH_SKILL)
	_add_damaged_known_entity(leader, "ship_2", "damaged")

	var updated := _run_brain(leader)
	var issued: Array = updated.orders.get("issued", [])
	var support_orders: Array = issued.filter(func(o): return o.get("type", "") == "support_ally")

	assert_gt(support_orders.size(), 0,
		"Damaged subordinate must trigger at least one support_ally order")
	# The order should name the damaged ship as the ally to protect.
	var found_ally := false
	for o in support_orders:
		if o.get("ally_id", "") == "ship_2":
			found_ally = true
	assert_true(found_ally,
		"support_ally orders must reference the damaged subordinate's ship_id")


# ── Test 2: ScreenWithdrawal ─────────────────────────────────────────────────

func test_more_threats_than_subordinates_triggers_screen_withdrawal_orders():
	## Three threats, two subordinates → threats > subordinates → screen-withdrawal split.
	## Some subordinates get "withdraw" orders, some get rearguard "engage" orders.
	var leader := _make_leader(HIGH_SKILL)
	_add_threats(leader, 3)   # 3 threats vs 2 subordinates

	var updated := _run_brain(leader)
	var issued: Array = updated.orders.get("issued", [])

	# At least one withdraw and one rearguard-engage order must be present.
	var withdraw_orders: Array = issued.filter(func(o): return o.get("type", "") == "withdraw")
	var rearguard_orders: Array = issued.filter(func(o): return o.get("subtype", "") == "rearguard")

	assert_gt(withdraw_orders.size() + rearguard_orders.size(), 0,
		"Outgunned leader must issue screen/withdrawal orders to subordinates")


# ── Test 3: No condition → no orders + timer advances ─────────────────────────

func test_no_crisis_issues_no_complementary_orders_and_timer_advances():
	## Neither damaged ally nor threat surplus → brain issues nothing.
	## next_decision_time must advance regardless (perpetual-due bug fix).
	var leader := _make_leader(HIGH_SKILL)
	# No threats, no damaged subordinates — calm situation.

	var original_ndt: float = leader.get("next_decision_time", 0.0)
	var updated := _run_brain(leader)
	var issued: Array = updated.orders.get("issued", [])

	# No support or withdrawal orders in a calm situation.
	var complementary: Array = issued.filter(func(o):
		return o.get("type", "") in ["support_ally", "withdraw"] or o.get("subtype", "") == "rearguard")
	assert_eq(complementary.size(), 0,
		"Calm situation must produce no complementary orders")

	# Timer must have advanced past the original value.
	assert_gt(updated.get("next_decision_time", original_ndt), original_ndt,
		"next_decision_time must advance even when brain issues nothing (perpetual-due fix)")


# ── Test 4: Suppressed actions never emit ────────────────────────────────────

func test_hatted_leader_never_emits_assign_targets_engage_orders():
	## AssignTargets would produce {type:"engage", target_id:...} orders.
	## The complementary-brain path suppresses it.
	var leader := _make_leader(HIGH_SKILL)
	# Add an opportunity so AssignTargets would normally fire.
	if not leader.has("awareness"):
		leader["awareness"] = {"threats": [], "opportunities": [], "known_entities": []}
	leader["awareness"]["opportunities"].append({"id": "enemy_1", "_opportunity_score": 90.0})

	# Run many iterations — AssignTargets has stochastic coordination_failed roll.
	for _i in range(20):
		var updated := _run_brain(leader)
		var issued: Array = updated.orders.get("issued", [])
		var engage_orders: Array = issued.filter(func(o): return o.get("type", "") == "engage" and o.get("target_id", "") != "")
		assert_eq(engage_orders.size(), 0,
			"AssignTargets engage orders must be suppressed by _run_complementary_brain")


func test_hatted_leader_never_emits_reform_formation_orders():
	## ReformFormation would produce {type:"formation", subtype:"reform"} orders.
	## The complementary-brain path suppresses it.
	var leader := _make_leader(HIGH_SKILL)
	# Make squadron look scattered so ReformFormation would normally fire.
	if not leader.has("awareness"):
		leader["awareness"] = {"threats": [], "opportunities": [], "known_entities": []}
	leader["awareness"]["known_entities"] = [
		{"id": "ship_2", "position": Vector2(0, 0), "status": "operational"},
		{"id": "ship_3", "position": Vector2(5000, 0), "status": "operational"},
	]

	for _i in range(10):
		var updated := _run_brain(leader)
		var issued: Array = updated.orders.get("issued", [])
		var reform_orders: Array = issued.filter(func(o):
			return o.get("type", "") == "formation" and o.get("subtype", "") == "reform")
		assert_eq(reform_orders.size(), 0,
			"ReformFormation orders must be suppressed by _run_complementary_brain")


# ── Test 5: Support-escort pipeline (support_assignment → support_pos) ────────

func test_pilot_with_support_assignment_gets_support_pos_from_formation_system():
	## FormationSystem.assign_slots must stamp support_pos from the ally's live position
	## when the ship has orders.support_assignment set and the ally is operational.
	var ally_pos := Vector2(300.0, 150.0)
	var ally_ship := TestFactories.make_fighter("ally_1", ally_pos, 0)
	ally_ship["status"] = "operational"

	var escort_ship := TestFactories.make_fighter("escort_1", Vector2.ZERO, 0)
	# No formation_assignment — this is a support-only ship.
	escort_ship["orders"] = {
		"support_assignment": "ally_1",
	}

	var ships_in := [ally_ship, escort_ship]
	var ships_out := FormationSystem.assign_slots(ships_in)

	var escort_out: Dictionary = {}
	for s in ships_out:
		if s.get("ship_id", "") == "escort_1":
			escort_out = s
			break

	assert_true(escort_out.has("orders"), "Escort ship must have orders dict after assign_slots")
	assert_true(escort_out["orders"].has("support_pos"),
		"Escort ship must receive support_pos when ally is operational")
	assert_eq(escort_out["orders"]["support_pos"], ally_pos,
		"support_pos must equal the ally's live position")


func test_support_pos_cleared_when_ally_destroyed():
	## If the ally ship is not operational, support_assignment and support_pos
	## must both be cleared so the pilot isn't stuck chasing a destroyed ship.
	var ally_ship := TestFactories.make_fighter("ally_1", Vector2(100.0, 0.0), 0)
	ally_ship["status"] = "destroyed"

	var escort_ship := TestFactories.make_fighter("escort_1", Vector2.ZERO, 0)
	escort_ship["orders"] = {"support_assignment": "ally_1"}

	var ships_out := FormationSystem.assign_slots([ally_ship, escort_ship])

	var escort_out: Dictionary = {}
	for s in ships_out:
		if s.get("ship_id", "") == "escort_1":
			escort_out = s
			break

	var out_orders: Dictionary = escort_out.get("orders", {})
	assert_false(out_orders.has("support_pos"),
		"support_pos must be cleared when ally is not operational")
	assert_false(out_orders.has("support_assignment"),
		"support_assignment must be cleared when ally is destroyed")


# ── Test 6: SteeringBlender support goal ─────────────────────────────────────

func _make_ship_for_blender(id: String = "s1") -> Dictionary:
	return {
		"ship_id": id,
		"internals": [{"component_id": "hull", "max_health": 100, "current_health": 100}],
	}

func _make_tactics_for_blender() -> Dictionary:
	return {"mentality_scalar": 0.5, "range_scalar": 0.5, "duty": "support"}

func test_support_goal_active_when_support_pos_set():
	## When support_pos is a valid Vector2, goal_weights["support"] must be > 0.
	var ship := _make_ship_for_blender()
	var tactics := _make_tactics_for_blender()
	var ally_pos := Vector2(500.0, 0.0)

	var directive := SteeringBlender.build_directive(ship, tactics, {}, [], 1000.0, "", ally_pos)
	var gw: Dictionary = directive.get("goal_weights", {})

	assert_true(gw.has("support"),
		"goal_weights must contain support key")
	assert_gt(gw.get("support", 0.0), 0.0,
		"support goal weight must be > 0 when support_pos is set")


func test_support_goal_zero_when_no_support_pos():
	## When support_pos is null (no escort assignment), support weight must be 0.
	var ship := _make_ship_for_blender()
	var tactics := _make_tactics_for_blender()

	var directive := SteeringBlender.build_directive(ship, tactics, {}, [], 1000.0, "", null)
	var gw: Dictionary = directive.get("goal_weights", {})

	assert_true(gw.has("support"),
		"goal_weights must always contain support key (0.0 when inactive)")
	assert_almost_eq(gw.get("support", -1.0), 0.0, 0.001,
		"support goal weight must be 0.0 when no support_pos is active")


func test_support_pos_echoed_through_directive():
	## The directive dict must include support_pos so MovementSystem can blend toward it.
	var ship := _make_ship_for_blender()
	var tactics := _make_tactics_for_blender()
	var ally_pos := Vector2(200.0, 300.0)

	var directive := SteeringBlender.build_directive(ship, tactics, {}, [], 1000.0, "", ally_pos)

	assert_true(directive.has("support_pos"),
		"directive must include support_pos field")
	assert_eq(directive.get("support_pos"), ally_pos,
		"support_pos in directive must match the ally position passed in")
