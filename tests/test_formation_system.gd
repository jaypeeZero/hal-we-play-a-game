extends GutTest

## Behavior tests for FormationSystem — command-layer contract (Step B).
##
## Formation assignments now come from the squadron leader's crew decision,
## not from crew["tactics"].  Tests cover:
##   - The resolver (assign_slots reads formation_assignment, writes world pos)
##   - The slot_offset geometry (unchanged pure helper)
##   - The squadron-leader decision (issues formation_slot orders)
##   - The pilot absorption (clears received, stores formation_assignment)
##
## No test is tied to specific data values or ship template numbers.

# ─── Helpers ─────────────────────────────────────────────────────────────────

## Minimal ship with an explicit formation_assignment.
func _make_ship_with_assignment(
	ship_id: String,
	team: int,
	pos: Vector2,
	lead_ship_id: String,
	shape: String,
	slot_index: int,
	slot_count: int,
	spacing: float = 0.5
) -> Dictionary:
	return {
		"ship_id":  ship_id,
		"team":     team,
		"position": pos,
		"velocity": Vector2.ZERO,
		"status":   "operational",
		"orders": {
			"formation_assignment": {
				"shape":        shape,
				"slot_index":   slot_index,
				"slot_count":   slot_count,
				"spacing":      spacing,
				"lead_ship_id": lead_ship_id,
			},
		},
	}

## Minimal ship with NO formation_assignment (unassigned).
func _make_ship_plain(ship_id: String, team: int, pos: Vector2) -> Dictionary:
	return {
		"ship_id":  ship_id,
		"team":     team,
		"position": pos,
		"velocity": Vector2.ZERO,
		"status":   "operational",
		"orders": {},
	}

## Build a lead ship (no formation_assignment; has velocity for heading).
func _make_lead(ship_id: String, team: int, pos: Vector2, vel: Vector2 = Vector2.ZERO) -> Dictionary:
	var s := _make_ship_plain(ship_id, team, pos)
	s["velocity"] = vel
	return s

## Minimal crew dict for a squadron leader.
func _make_squadron_leader_crew(
	crew_id: String,
	ship_id: String,
	subordinates: Array,
	leadership_skill: float = 0.8,
	formation_shape: String = "wall",
	formation_spacing: float = 0.5
) -> Dictionary:
	return {
		"crew_id":    crew_id,
		"role":       CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"command_hat": "squadron_leader",
		"is_squadron_leader": true,
		"command_chain": {
			"superior": null,
			"subordinates": subordinates,
		},
		"stats": {
			"stress":         0.0,
			"fatigue":        0.0,
			"decision_time":  0.5,
			"reaction_time":  0.3,
			"skills": {
				"piloting":    0.7,
				"tactics":     leadership_skill,
				"leadership":  leadership_skill,
				"composure":   0.5,
				"aim":         0.5,
				"machinery":   0.5,
			},
		},
		"tactics": {
			"shape":   formation_shape,
			"spacing": formation_spacing,
		},
		"orders": {
			"received": null,
			"issued":   [],
			"current":  null,
		},
		"awareness": {
			"threats":        [],
			"opportunities":  [],
			"known_entities": [],
		},
		"current_action": "idle",
		"next_decision_time": 0.0,
		"last_formation_command_time": -999.0,
	}

## Minimal pilot crew dict that already has a formation_slot order in received.
func _make_pilot_with_received_formation(
	crew_id: String,
	ship_id: String,
	fa: Dictionary
) -> Dictionary:
	return {
		"crew_id":    crew_id,
		"role":       CrewData.Role.PILOT,
		"assigned_to": ship_id,
		"command_hat": "",
		"is_squadron_leader": false,
		"command_chain": {
			"superior": "leader_1",
			"subordinates": [],
		},
		"stats": {
			"stress":         0.0,
			"fatigue":        0.0,
			"decision_time":  0.5,
			"reaction_time":  0.3,
			"skills": {
				"piloting":   0.7,
				"tactics":    0.5,
				"composure":  0.5,
				"aim":        0.5,
				"machinery":  0.5,
			},
		},
		"tactics": {},
		"orders": {
			"received": {
				"type": "formation_slot",
				"formation_assignment": fa,
			},
			"issued":  [],
			"current": null,
		},
		"awareness": {
			"threats":        [],
			"opportunities":  [],
			"known_entities": [],
		},
		"current_action": "idle",
		"next_decision_time": 0.0,
	}


## Extract the projection spread of formation_slot fields along an axis.
func _slot_spread(ships: Array, axis: Vector2) -> float:
	var projs: Array = []
	for s in ships:
		var slot: Variant = s.get("orders", {}).get("formation_slot", null)
		if slot != null:
			projs.append(slot.dot(axis))
	if projs.is_empty():
		return 0.0
	return projs.max() - projs.min()


# ─── Resolver tests ───────────────────────────────────────────────────────────

func test_resolver_wall_shape_spreads_perpendicular_to_enemy():
	# Lead ship at origin; enemy at (4000,0) → facing axis is +X.
	# Wall wingmen should spread along Y (perpendicular to the axis).
	var lead := _make_lead("lead", 0, Vector2.ZERO)
	var enemy := _make_ship_plain("enemy", 1, Vector2(4000, 0))
	var ships: Array = [lead, enemy]
	for i in range(3):
		ships.append(_make_ship_with_assignment(
			"wing_%d" % i, 0, Vector2(-100, i * 50),
			"lead", "wall", i, 3, 0.5
		))

	var result := FormationSystem.assign_slots(ships)
	var wingmen := result.filter(func(s): return s.get("ship_id", "").begins_with("wing_"))

	var spread_x: float = _slot_spread(wingmen, Vector2(1, 0))
	var spread_y: float = _slot_spread(wingmen, Vector2(0, 1))

	assert_gt(spread_y, spread_x,
		"Wall formation must spread more along perp (Y) than toward enemy (X)")


func test_resolver_wedge_shape_lead_slot_furthest_forward():
	# Wedge slot_index=0 should be furthest forward (highest X) toward enemy.
	var lead := _make_lead("lead", 0, Vector2.ZERO)
	var enemy := _make_ship_plain("enemy", 1, Vector2(4000, 0))
	var ships: Array = [lead, enemy]
	ships.append(_make_ship_with_assignment("wing_0", 0, Vector2.ZERO, "lead", "wedge", 0, 3))
	ships.append(_make_ship_with_assignment("wing_1", 0, Vector2.ZERO, "lead", "wedge", 1, 3))
	ships.append(_make_ship_with_assignment("wing_2", 0, Vector2.ZERO, "lead", "wedge", 2, 3))

	var result := FormationSystem.assign_slots(ships)

	var slot0_x: float = -INF
	var max_other_x: float = -INF
	for s in result:
		var slot: Variant = s.get("orders", {}).get("formation_slot", null)
		if slot == null:
			continue
		if s["ship_id"] == "wing_0":
			slot0_x = slot.x
		else:
			max_other_x = max(max_other_x, slot.x)

	assert_gt(slot0_x, max_other_x,
		"Wedge slot_index=0 must be furthest toward enemy (highest X component)")


func test_resolver_wider_spacing_produces_larger_separation():
	var lead := _make_lead("lead", 0, Vector2.ZERO)
	var enemy := _make_ship_plain("enemy", 1, Vector2(4000, 0))

	var ships_tight: Array = [lead.duplicate(true), enemy.duplicate(true)]
	var ships_loose: Array = [lead.duplicate(true), enemy.duplicate(true)]
	for i in range(3):
		ships_tight.append(_make_ship_with_assignment(
			"w%d" % i, 0, Vector2.ZERO, "lead", "wall", i, 3, 0.0))
		ships_loose.append(_make_ship_with_assignment(
			"w%d" % i, 0, Vector2.ZERO, "lead", "wall", i, 3, 1.0))

	var tight := FormationSystem.assign_slots(ships_tight).filter(
		func(s): return s.get("ship_id", "").begins_with("w"))
	var loose := FormationSystem.assign_slots(ships_loose).filter(
		func(s): return s.get("ship_id", "").begins_with("w"))

	assert_gt(
		_slot_spread(loose, Vector2(0, 1)),
		_slot_spread(tight, Vector2(0, 1)),
		"spacing=1 must produce wider lateral separation than spacing=0"
	)


func test_resolver_slots_rotate_with_enemy_bearing():
	# Enemy at right (+X): wall spreads along Y.
	# Enemy above (+Y): wall spreads along X.
	var lead_a := _make_lead("lead", 0, Vector2.ZERO)
	var ships_a: Array = [lead_a, _make_ship_plain("enemy", 1, Vector2(4000, 0))]
	for i in range(4):
		ships_a.append(_make_ship_with_assignment("w%d" % i, 0, Vector2.ZERO, "lead", "wall", i, 4))

	var lead_b := _make_lead("lead", 0, Vector2.ZERO)
	var ships_b: Array = [lead_b, _make_ship_plain("enemy", 1, Vector2(0, 4000))]
	for i in range(4):
		ships_b.append(_make_ship_with_assignment("w%d" % i, 0, Vector2.ZERO, "lead", "wall", i, 4))

	var wm_a := FormationSystem.assign_slots(ships_a).filter(
		func(s): return s.get("ship_id", "").begins_with("w"))
	var wm_b := FormationSystem.assign_slots(ships_b).filter(
		func(s): return s.get("ship_id", "").begins_with("w"))

	assert_gt(_slot_spread(wm_a, Vector2(0, 1)), _slot_spread(wm_a, Vector2(1, 0)),
		"Enemy to right: wall must spread more along Y")
	assert_gt(_slot_spread(wm_b, Vector2(1, 0)), _slot_spread(wm_b, Vector2(0, 1)),
		"Enemy above: wall must spread more along X")


func test_no_formation_assignment_clears_slot():
	var ship := _make_ship_plain("solo", 0, Vector2(100, 100))
	# Pre-populate stale slot data to confirm it is cleared.
	ship["orders"]["formation_slot"] = Vector2(999, 999)
	ship["orders"]["anchor_position"] = Vector2(888, 888)

	var result := FormationSystem.assign_slots([ship])
	assert_false(result[0]["orders"].has("formation_slot"),
		"Ship with no formation_assignment must have formation_slot removed")
	assert_false(result[0]["orders"].has("anchor_position"),
		"Ship with no formation_assignment must have anchor_position removed")


func test_assign_slots_does_not_mutate_input():
	var lead := _make_lead("lead", 0, Vector2.ZERO)
	var enemy := _make_ship_plain("enemy", 1, Vector2(3000, 0))
	var wing := _make_ship_with_assignment("w0", 0, Vector2.ZERO, "lead", "wall", 0, 1)
	var ships: Array = [lead, enemy, wing]
	var before_orders: Dictionary = wing["orders"].duplicate(true)
	FormationSystem.assign_slots(ships)
	assert_eq(wing["orders"], before_orders,
		"assign_slots must not mutate input ship orders")


# ─── slot_offset geometry (pure helper — unchanged) ──────────────────────────

func test_wall_offset_is_flat_line():
	var count := 5
	var ys: Array = []
	for i in range(count):
		ys.append(FormationSystem.slot_offset("wall", i, count, 0.5, 0.5, "wingman").y)
	assert_almost_eq(ys.min(), ys.max(), 0.1,
		"Wall slots must all have the same y component (flat line)")


func test_wedge_index0_furthest_forward():
	var count := 5
	var lead_y: float = FormationSystem.slot_offset("wedge", 0, count, 0.5, 0.5, "wingman").y
	for i in range(1, count):
		var arm_y: float = FormationSystem.slot_offset("wedge", i, count, 0.5, 0.5, "wingman").y
		assert_gt(lead_y, arm_y,
			"Wedge index 0 must have higher y (closer to enemy) than arm %d" % i)


func test_wall_lateral_offsets_are_centered():
	var count := 4
	var total: float = 0.0
	for i in range(count):
		total += FormationSystem.slot_offset("wall", i, count, 0.5, 0.5, "wingman").x
	assert_almost_eq(total, 0.0, 1.0, "Wall lateral offsets must sum to ~0")


# ─── Squadron-leader decision tests ──────────────────────────────────────────

func test_leader_issues_formation_orders_for_each_wingman():
	var subordinates := ["wm_a", "wm_b", "wm_c"]
	var leader := _make_squadron_leader_crew(
		"leader_1", "ship_lead", subordinates, 0.9, "wall", 0.5)
	var ship_data := {
		"ship_id":  "ship_lead",
		"team":     0,
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"status":   "operational",
		"orders":   {},
	}

	var updated := CrewAISystem._issue_formation_commands(leader, ship_data, 10.0)
	var issued: Array = updated.get("orders", {}).get("issued", [])

	assert_eq(issued.size(), subordinates.size(),
		"Leader must issue one formation_slot order per wingman")
	for order in issued:
		assert_eq(order.get("type", ""), "formation_slot",
			"Issued order type must be 'formation_slot'")
		assert_true(order.has("formation_assignment"),
			"formation_slot order must carry a formation_assignment block")
		assert_eq(
			order["formation_assignment"].get("lead_ship_id", ""), "ship_lead",
			"formation_assignment must reference the leader's ship_id"
		)


func test_leader_cadence_throttles_reissue():
	var leader := _make_squadron_leader_crew(
		"leader_1", "ship_lead", ["wm_a"], 0.0)  # skill=0 → longest cadence
	var ship_data := {
		"ship_id":  "ship_lead",
		"team":     0,
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"status":   "operational",
		"orders":   {},
	}
	# First call — should issue (last_time is -999).
	var first := CrewAISystem._issue_formation_commands(leader, ship_data, 0.0)
	var count_after_first: int = first.get("orders", {}).get("issued", []).size()
	assert_gt(count_after_first, 0, "Leader must issue on first call")

	# Immediately call again — cadence not expired, nothing added.
	var second := CrewAISystem._issue_formation_commands(first, ship_data, 0.1)
	assert_eq(
		second.get("orders", {}).get("issued", []).size(),
		count_after_first,
		"Leader must not reissue before cadence expires"
	)


func test_leader_skill_gates_cadence_length():
	# High-skill cadence must be shorter than low-skill cadence.
	var cadence_high := (
		CrewAISystem.FORMATION_COMMAND_CADENCE_BASE
		+ CrewAISystem.FORMATION_COMMAND_CADENCE_SKILL_SCALE * (1.0 - 1.0)
	)
	var cadence_low := (
		CrewAISystem.FORMATION_COMMAND_CADENCE_BASE
		+ CrewAISystem.FORMATION_COMMAND_CADENCE_SKILL_SCALE * (1.0 - 0.0)
	)
	assert_lt(cadence_high, cadence_low,
		"High-skill leader cadence must be shorter than low-skill cadence")


# ─── Pilot absorption tests ───────────────────────────────────────────────────

func test_pilot_absorbs_formation_order_clears_received():
	var fa := {"shape": "wall", "slot_index": 1, "slot_count": 3,
		"spacing": 0.5, "lead_ship_id": "ship_lead"}
	var pilot := _make_pilot_with_received_formation("p1", "ship_wing", fa)
	var ships: Array = [{
		"ship_id":  "ship_wing",
		"team":     0,
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"status":   "operational",
		"orders":   {},
	}]

	var updated := CrewAISystem._absorb_formation_order(pilot, ships)

	assert_null(updated.get("orders", {}).get("received"),
		"orders.received must be null after absorbing formation_slot order")


func test_pilot_absorbs_formation_order_stores_assignment():
	var fa := {"shape": "wedge", "slot_index": 0, "slot_count": 2,
		"spacing": 0.7, "lead_ship_id": "ship_lead"}
	var pilot := _make_pilot_with_received_formation("p1", "ship_wing", fa)
	var ships: Array = [{
		"ship_id":  "ship_wing",
		"team":     0,
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"status":   "operational",
		"orders":   {},
	}]

	var updated := CrewAISystem._absorb_formation_order(pilot, ships)

	assert_true(updated.has("formation_assignment"),
		"Absorbed formation_slot must set crew['formation_assignment']")
	assert_eq(updated["formation_assignment"].get("shape", ""), "wedge",
		"formation_assignment.shape must match the order")
	assert_eq(updated["formation_assignment"].get("slot_index", -1), 0,
		"formation_assignment.slot_index must match the order")


func test_pilot_absorbs_formation_order_stamps_ship_orders():
	var fa := {"shape": "wall", "slot_index": 1, "slot_count": 3,
		"spacing": 0.5, "lead_ship_id": "ship_lead"}
	var pilot := _make_pilot_with_received_formation("p1", "ship_wing", fa)
	var ship_dict := {
		"ship_id":  "ship_wing",
		"team":     0,
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"status":   "operational",
		"orders":   {},
	}
	var ships: Array = [ship_dict]

	CrewAISystem._absorb_formation_order(pilot, ships)

	assert_true(ships[0]["orders"].has("formation_assignment"),
		"Absorption must stamp formation_assignment onto ship.orders")
	assert_eq(ships[0]["orders"]["formation_assignment"].get("shape", ""), "wall",
		"Stamped ship formation_assignment.shape must match the order")


func test_pilot_non_formation_received_order_not_consumed():
	# An "engage" order must not be touched by _absorb_formation_order.
	var pilot := {
		"crew_id":    "p1",
		"role":       CrewData.Role.PILOT,
		"assigned_to": "ship_wing",
		"command_hat": "",
		"is_squadron_leader": false,
		"command_chain": {"superior": "c1", "subordinates": []},
		"stats": {"stress": 0.0, "fatigue": 0.0, "decision_time": 0.5,
			"reaction_time": 0.3, "skills": {"piloting": 0.5, "tactics": 0.5,
			"composure": 0.5, "aim": 0.5, "machinery": 0.5}},
		"tactics": {},
		"orders": {
			"received": {"type": "engage", "target_id": "enemy_1"},
			"issued":   [],
			"current":  null,
		},
		"awareness": {"threats": [], "opportunities": [], "known_entities": []},
		"current_action": "idle",
		"next_decision_time": 0.0,
	}

	var updated := CrewAISystem._absorb_formation_order(pilot, [])
	assert_eq(updated["orders"]["received"].get("type", ""), "engage",
		"Non-formation received orders must not be consumed by _absorb_formation_order")
