class_name CrewSchedulerSystem
extends RefCounted

## Event-driven scheduler for crew decisions.
##
## Replaces the per-frame "iterate every crew" loop with a wake-on-time-or-event
## model.  A crew is processed this tick if:
##   - their next_decision_time has been reached, OR
##   - they have pending events in their mailbox.
##
## Pure functions; the caller passes in crew_list and mailboxes, and gets back
## an updated copy of each.  No internal state.

const URGENT_EVENT_TYPES = ["missile_locked", "threat_appeared", "ship_damaged"]

## Process all due crew this tick.
## Returns {crew_list, decisions, mailboxes}.
##
## ships, all_crew, wings are forwarded to CrewAISystem.update_crew_member for
## decision context — same shape as the legacy update_all_crew API.
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
		var has_events = CrewMailboxSystem.has_pending(current_mailboxes, crew_id)
		var is_due = game_time >= crew.get("next_decision_time", 0.0)

		if not has_events and not is_due:
			# Sleeping with nothing to react to: no work
			updated_crew.append(crew)
			continue

		# Drain events (if any) and pass them as decision context
		var events: Array = []
		if has_events:
			var drained = CrewMailboxSystem.drain_events(current_mailboxes, crew_id)
			events = drained.events
			current_mailboxes = drained.mailboxes

		var result = update_crew_with_events(crew, game_time, events, ships, crew_list, wings)
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

## Make a single crew member's decision, considering pending events.
## URGENT events (missile_locked, threat_appeared, ship_damaged) for pilots
## with known threats short-circuit to an evasive maneuver.  Other events fall
## through to the standard role-based decision path.
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

	# Urgent-event handling: pilot with threats reacts evasively
	if crew.role == CrewData.Role.PILOT and _has_urgent_event(events) and not crew.awareness.threats.is_empty():
		var aged = CrewAISystem.update_crew_state(crew, dt)
		return CrewAISystem.make_evasive_decision(aged, game_time)

	# Default: hand off to role-based decision logic with lazy dt
	return CrewAISystem.update_crew_member(crew, dt, game_time, ships, crew_list, wings)

static func _has_urgent_event(events: Array) -> bool:
	for event in events:
		if event.get("type", "") in URGENT_EVENT_TYPES:
			return true
	return false
