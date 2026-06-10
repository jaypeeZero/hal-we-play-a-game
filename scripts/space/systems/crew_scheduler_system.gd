class_name CrewSchedulerSystem
extends RefCounted

## Event-driven scheduler for crew decisions.
##
## A crew is processed this tick if:
##   - their next_decision_time has been reached, OR
##   - they have pending events in their mailbox.
##
## Pure functions; the caller passes in crew_list and mailboxes, and gets back
## an updated copy of each.  No internal state.

## Missile lock is not a real game mechanic — reaction-latency triggers off
## `threat_appeared` and `ship_damaged` only.
const URGENT_EVENT_TYPES = ["threat_appeared", "ship_damaged"]

## Process all due crew this tick.
## Returns {crew_list, decisions, mailboxes}.
static func tick(
	crew_list: Array,
	game_time: float,
	mailboxes: Dictionary,
	ships: Array = [],
	wings: Array = []
) -> Dictionary:
	var updated_crew: Array = []
	var decisions: Array = []
	var current_mailboxes = mailboxes

	for crew in crew_list:
		var crew_id = crew.crew_id
		var has_events = CrewMailboxSystem.has_pending(current_mailboxes, crew_id, game_time)
		var is_due = game_time >= crew.get("next_decision_time", 0.0)

		if not has_events and not is_due:
			updated_crew.append(crew)
			continue

		var events: Array = []
		var working_crew = crew
		if has_events:
			var drained = CrewMailboxSystem.drain_events(current_mailboxes, crew_id, game_time)
			events = drained.events
			current_mailboxes = drained.mailboxes
			working_crew = apply_event_side_effects(working_crew, events, game_time)

		var result = update_crew_with_events(working_crew, game_time, events, ships, crew_list, wings)
		var stamped = result.crew_data.duplicate(true)
		stamped["last_state_update_time"] = game_time
		updated_crew.append(stamped)
		if result.has("decision") and result.decision != null and not result.decision.is_empty():
			decisions.append(result.decision)

	return {
		"crew_list": updated_crew,
		"decisions": decisions,
		"mailboxes": current_mailboxes
	}

## Same as tick(), plus a per-crew awareness refresh on wake.
##
## Sleeping crew keep their last awareness snapshot; only crew that wake
## (timer due or events pending) get their threat / opportunity / known
## entity lists rebuilt against the current world.
##
## Optional ship_grid / projectile_grid turn the per-crew O(n) entity scan
## into an O(cells) range query inside InformationSystem.
static func tick_with_awareness(
	crew_list: Array,
	game_time: float,
	mailboxes: Dictionary,
	ships: Array = [],
	projectiles: Array = [],
	wings: Array = [],
	ship_grid: Dictionary = {},
	projectile_grid: Dictionary = {}
) -> Dictionary:
	var updated_crew: Array = []
	var decisions: Array = []
	var current_mailboxes = mailboxes

	for crew in crew_list:
		var crew_id = crew.crew_id
		var has_events = CrewMailboxSystem.has_pending(current_mailboxes, crew_id, game_time)
		var is_due = game_time >= crew.get("next_decision_time", 0.0)

		if not has_events and not is_due:
			updated_crew.append(crew)
			continue

		var aware_crew = InformationSystem.update_crew_awareness(
			crew, ships, projectiles, game_time, ship_grid, projectile_grid)

		var events: Array = []
		if has_events:
			var drained = CrewMailboxSystem.drain_events(current_mailboxes, crew_id, game_time)
			events = drained.events
			current_mailboxes = drained.mailboxes
			aware_crew = apply_event_side_effects(aware_crew, events, game_time)

		var result = update_crew_with_events(aware_crew, game_time, events, ships, crew_list, wings)
		var stamped = result.crew_data.duplicate(true)
		stamped["last_state_update_time"] = game_time
		updated_crew.append(stamped)
		if result.has("decision") and result.decision != null and not result.decision.is_empty():
			decisions.append(result.decision)

	return {
		"crew_list": updated_crew,
		"decisions": decisions,
		"mailboxes": current_mailboxes
	}

## Apply event-driven state mutations to a crew before deciding.
##
## Each event type carries its own side effect on crew state (tactical memory,
## current target, received orders).  Lives in the scheduler so the entire
## event flow goes through one path.  Returns a new crew dict.
static func apply_event_side_effects(crew: Dictionary, events: Array, game_time: float) -> Dictionary:
	var updated = crew
	for event in events:
		_log_urgent_trigger(crew, event)
		updated = _apply_one_event(updated, event, game_time)
	return updated

## Record urgent wake-ups in the battle log so a reactive decision is always
## preceded by the event that caused it.
static func _log_urgent_trigger(crew: Dictionary, event: Dictionary) -> void:
	var event_type: String = event.get("type", "")
	if event_type not in URGENT_EVENT_TYPES:
		return
	var data: Dictionary = event.get("data", {})
	var source_id: String = str(data.get("enemy_id", data.get("attacker", "")))
	if BattleEventLoggerAutoload.service:
		BattleEventLoggerAutoload.log_ai_trigger(crew.get("crew_id", ""), event_type, source_id)

static func _apply_one_event(crew: Dictionary, event: Dictionary, game_time: float) -> Dictionary:
	match event.get("type", ""):
		"threat_appeared":
			return TacticalMemorySystem.record_event(crew, {
				"type": "threat_detected",
				"entity_id": event.get("data", {}).get("enemy_id", ""),
				"timestamp": game_time
			})
		"target_lost":
			var updated = crew.duplicate(true)
			updated.awareness["current_target"] = ""
			return updated
		"ship_damaged":
			return TacticalMemorySystem.record_event(crew, {
				"type": "ship_damaged",
				"damage": event.get("data", {}),
				"timestamp": game_time
			})
		"order_received":
			var order = event.get("data", {}).get("order", {})
			if order.is_empty():
				return crew
			return CommandChainSystem.process_single_order(crew, order)
		_:
			return crew

## Make a single crew member's decision, considering pending events.
## URGENT events (threat_appeared, ship_damaged) for pilots with known
## threats short-circuit to an evasive maneuver. Other events fall through
## to the standard role-based decision path.
##
## State (stress, fatigue) catches up lazily: dt is the time since this crew's
## last state update, not the engine frame's delta.
static func update_crew_with_events(
	crew: Dictionary,
	game_time: float,
	events: Array,
	ships: Array = [],
	crew_list: Array = [],
	wings: Array = []
) -> Dictionary:
	var dt = max(0.0, game_time - crew.get("last_state_update_time", game_time))

	if crew.role == CrewData.Role.PILOT and _has_urgent_event(events) and not crew.awareness.threats.is_empty():
		var aged = CrewAISystem.update_crew_state(crew, dt)
		return CrewAISystem.make_evasive_decision(aged, game_time)

	return CrewAISystem.update_crew_member(crew, dt, game_time, ships, crew_list, wings)

static func _has_urgent_event(events: Array) -> bool:
	for event in events:
		if event.get("type", "") in URGENT_EVENT_TYPES:
			return true
	return false
