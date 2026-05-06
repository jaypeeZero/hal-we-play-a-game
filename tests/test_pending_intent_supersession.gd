extends GutTest

## A fresh decision replaces a waiting one — the older intent never
## applies. This protects against stale evasions firing after the threat
## geometry has changed.

func _make_ship() -> Dictionary:
	return {
		"ship_id": "ship_a",
		"team": 0,
		"position": Vector2.ZERO,
		"orders": {
			"current_order": "",
			"target_id": "",
			"threat_id": ""
		},
		"crew_modifiers": {}
	}

func _make_decision(target_id: String) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "evade",
		"crew_id": "crew_x",
		"entity_id": "ship_a",
		"target_id": target_id
	}

func _attach(ship: Dictionary, target_id: String, commit_at: float) -> Dictionary:
	var payload = {"decision": _make_decision(target_id), "crew_snapshot": {}}
	return PendingIntentSystem.attach(ship, "evasive", payload, commit_at)

func test_fresh_attach_replaces_waiting_intent():
	var ship = _attach(_make_ship(), "enemy_old", 0.5)
	ship = _attach(ship, "enemy_new", 0.6)
	assert_true(ship.has("pending_intent"))
	assert_eq(ship.pending_intent.commit_at, 0.6,
		"Fresh attach overwrites the older intent.")
	assert_eq(ship.pending_intent.payload.decision.target_id, "enemy_new")

func test_old_intent_never_applies_after_supersession():
	# Old intent commit_at=0.5, new intent commit_at=0.6 attached at t=0.1.
	# At t=0.5, neither should apply (the new one isn't due yet, the old
	# one was overwritten). At t=0.6, only the new intent applies.
	var ship = _attach(_make_ship(), "enemy_old", 0.5)
	ship = _attach(ship, "enemy_new", 0.6)

	var mid = PendingIntentSystem.commit_due([ship], 0.5)
	assert_eq(mid.committed.size(), 0, "Old intent's commit_at must not fire it once superseded.")
	assert_true(mid.ships[0].has("pending_intent"), "New intent stays buffered.")

	var late = PendingIntentSystem.commit_due(mid.ships, 0.6)
	assert_eq(late.committed.size(), 1)
	assert_eq(late.ships[0].orders.threat_id, "enemy_new",
		"Only the most recent intent's effect lands on the ship.")

func test_supersession_to_earlier_commit_at_still_replaces():
	# Reattaching with a SOONER commit_at is also valid — represents a more
	# urgent reaction overtaking a previously decided one.
	var ship = _attach(_make_ship(), "enemy_old", 0.6)
	ship = _attach(ship, "enemy_new", 0.4)
	assert_eq(ship.pending_intent.commit_at, 0.4)
	var result = PendingIntentSystem.commit_due([ship], 0.4)
	assert_eq(result.committed.size(), 1)
	assert_eq(result.ships[0].orders.threat_id, "enemy_new")
