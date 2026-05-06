class_name PendingIntentSystem
extends RefCounted

## Pending-intent / reaction-latency buffer.
##
## Reactive decisions (evasion, brace, break-off) don't apply immediately.
## They are stashed on `ship_data.pending_intent` with a commit_at, and
## applied to the ship's orders only once game_time crosses commit_at.
## Combined with detection latency in InformationSystem this produces the
## ~80 ms (elite) vs ~700 ms (rookie) reaction-time spread that drives S1.
##
## A fresh attach replaces any waiting intent — supersession is desired
## behavior: a more recent decision is always better than an older one.

## Stash a pending intent on the ship. Replaces any prior pending intent.
static func attach(ship_data: Dictionary, intent_type: String, payload: Dictionary, commit_at: float) -> Dictionary:
	var updated = ship_data.duplicate(true)
	updated["pending_intent"] = {
		"intent_type": intent_type,
		"payload": payload,
		"commit_at": commit_at
	}
	return updated

## Drop any waiting pending intent. Used when a fresh decision supersedes.
static func cancel(ship_data: Dictionary) -> Dictionary:
	if not ship_data.has("pending_intent"):
		return ship_data
	var updated = ship_data.duplicate(true)
	updated.erase("pending_intent")
	return updated

## Apply all pending intents whose commit_at has passed.
## Returns {ships, committed} — committed is metadata for the caller to
## log (decision_committed events). One O(ships) array scan per frame.
static func commit_due(ships: Array, game_time: float) -> Dictionary:
	var updated: Array = []
	var committed: Array = []
	for ship in ships:
		if ship.has("pending_intent") and game_time >= ship.pending_intent.commit_at:
			var pi: Dictionary = ship.pending_intent
			var applied = _apply_intent(ship, pi)
			updated.append(applied)
			var decision: Dictionary = pi.get("payload", {}).get("decision", {})
			committed.append({
				"ship_id": ship.get("ship_id", ""),
				"intent_type": pi.get("intent_type", ""),
				"decided_at": decision.get("decided_at", pi.get("commit_at", game_time)),
				"commit_at": pi.get("commit_at", game_time),
				"crew_id": decision.get("crew_id", "")
			})
		else:
			updated.append(ship)
	return {"ships": updated, "committed": committed}

static func _apply_intent(ship: Dictionary, pi: Dictionary) -> Dictionary:
	var payload: Dictionary = pi.get("payload", {})
	var decision: Dictionary = payload.get("decision", {})
	var crew_snapshot: Dictionary = payload.get("crew_snapshot", {})
	var applied = CrewIntegrationSystem.apply_decision_to_ship(ship, decision, crew_snapshot)
	if applied.has("pending_intent"):
		applied.erase("pending_intent")
	return applied
