extends GutTest

## A pending intent attached at t=0 with commit_at=0.5 must NOT apply at
## t=0.4 and MUST apply at t=0.5. This is the core timing invariant for
## the reaction-latency buffer.

func _make_ship(ship_id: String) -> Dictionary:
	return {
		"ship_id": ship_id,
		"team": 0,
		"position": Vector2.ZERO,
		"velocity": Vector2.ZERO,
		"rotation": 0.0,
		"orders": {
			"current_order": "",
			"target_id": "",
			"threat_id": ""
		},
		"crew_modifiers": {}
	}

func _make_evade_decision(target_id: String) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "evade",
		"crew_id": "crew_x",
		"entity_id": "ship_a",
		"target_id": target_id
	}

func _attach_evade(ship: Dictionary, target_id: String, commit_at: float) -> Dictionary:
	var payload = {
		"decision": _make_evade_decision(target_id),
		"crew_snapshot": {}
	}
	return PendingIntentSystem.attach(ship, "evasive", payload, commit_at)

func test_intent_does_not_apply_before_commit_at():
	var ship = _attach_evade(_make_ship("ship_a"), "enemy_1", 0.5)
	var result = PendingIntentSystem.commit_due([ship], 0.4)
	assert_eq(result.committed.size(), 0, "Nothing committed before commit_at.")
	var ship_after = result.ships[0]
	assert_true(ship_after.has("pending_intent"), "Intent stays buffered.")
	assert_eq(ship_after.orders.threat_id, "", "Orders unchanged before commit.")

func test_intent_applies_at_commit_at():
	var ship = _attach_evade(_make_ship("ship_a"), "enemy_1", 0.5)
	var result = PendingIntentSystem.commit_due([ship], 0.5)
	assert_eq(result.committed.size(), 1, "Exactly one commit recorded.")
	var ship_after = result.ships[0]
	assert_false(ship_after.has("pending_intent"), "Intent cleared after commit.")
	assert_eq(ship_after.orders.threat_id, "enemy_1", "Evade order applied.")
	assert_eq(ship_after.orders.current_order, "evade")

func test_intent_applies_when_time_overshoots_commit_at():
	var ship = _attach_evade(_make_ship("ship_a"), "enemy_1", 0.5)
	# Frame time may overshoot commit_at — apply must still fire on the
	# first tick where game_time >= commit_at.
	var result = PendingIntentSystem.commit_due([ship], 1.2)
	assert_eq(result.committed.size(), 1)
	assert_eq(result.ships[0].orders.threat_id, "enemy_1")

func test_cancel_removes_pending_intent():
	var ship = _attach_evade(_make_ship("ship_a"), "enemy_1", 0.5)
	assert_true(ship.has("pending_intent"))
	var cancelled = PendingIntentSystem.cancel(ship)
	assert_false(cancelled.has("pending_intent"))

func test_committed_metadata_includes_decided_and_commit_at():
	# decided_at travels in payload.decision.decided_at; commit_due lifts it
	# into the metadata so callers can emit decision_committed events.
	var decision = _make_evade_decision("enemy_1")
	decision["decided_at"] = 0.1
	var payload = {"decision": decision, "crew_snapshot": {"crew_id": "crew_x"}}
	var ship = PendingIntentSystem.attach(_make_ship("ship_a"), "evasive", payload, 0.5)
	var result = PendingIntentSystem.commit_due([ship], 0.5)
	var entry = result.committed[0]
	assert_eq(entry.intent_type, "evasive")
	assert_eq(entry.commit_at, 0.5)
	assert_eq(entry.decided_at, 0.1)
	assert_eq(entry.crew_id, "crew_x")
	assert_eq(entry.ship_id, "ship_a")
