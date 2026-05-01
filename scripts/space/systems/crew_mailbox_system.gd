class_name CrewMailboxSystem
extends RefCounted

## Per-crew event mailbox.  Pure functions; the caller owns the mailbox state.
##
## A "mailbox" here is a Dictionary[crew_id -> Array[event_dict]].  Event
## sources (WeaponSystem, InformationSystem, ProjectileSystem, ...) call
## post_event() when something happens that an NPC should react to.  The
## scheduler drains a crew's mailbox when it wakes them, and the decision
## function reads the events to know WHY it woke without rescanning the world.
##
## Cap: 10 events per crew.  Newest is retained on overflow; oldest is dropped.
## This is bounded so a noisy event source can't unbounded-grow memory.

const MAX_EVENTS_PER_CREW: int = 10

## Add an event to a crew's mailbox.  Returns a new mailboxes dict (immutable).
static func post_event(mailboxes: Dictionary, crew_id: String, event: Dictionary) -> Dictionary:
	var result = mailboxes.duplicate()
	var queue: Array = []
	if result.has(crew_id):
		queue = result[crew_id].duplicate()
	queue.append(event)
	if queue.size() > MAX_EVENTS_PER_CREW:
		# Drop oldest; keep the newest MAX_EVENTS_PER_CREW
		queue = queue.slice(queue.size() - MAX_EVENTS_PER_CREW, queue.size())
	result[crew_id] = queue
	return result

## True if the crew has any pending events.
static func has_pending(mailboxes: Dictionary, crew_id: String) -> bool:
	if not mailboxes.has(crew_id):
		return false
	return not mailboxes[crew_id].is_empty()

## Pop all events for a crew.  Returns {events, mailboxes} where the returned
## mailboxes has that crew's queue cleared.
static func drain_events(mailboxes: Dictionary, crew_id: String) -> Dictionary:
	var events: Array = []
	if mailboxes.has(crew_id):
		events = mailboxes[crew_id].duplicate()
	var new_mailboxes = mailboxes.duplicate()
	new_mailboxes[crew_id] = []
	return {"events": events, "mailboxes": new_mailboxes}

## Peek at events without draining.  Useful for read-only checks.
static func peek_events(mailboxes: Dictionary, crew_id: String) -> Array:
	if not mailboxes.has(crew_id):
		return []
	return mailboxes[crew_id]
