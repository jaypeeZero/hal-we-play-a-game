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
## ## Detection latency
##
## Each event MAY carry a `deliver_at` (game-time seconds). Events whose
## deliver_at is in the future are not eligible: drain_events leaves them
## queued, and has_pending reports false until their time arrives. This is
## the foundation for skill-based perception lag — a low-awareness pilot
## "sees" a threat several hundred ms after it actually appears.
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

## True if the crew has any event eligible to deliver at `game_time`.
## Events with `deliver_at` in the future are invisible until their time.
static func has_pending(mailboxes: Dictionary, crew_id: String, game_time: float = INF) -> bool:
	if not mailboxes.has(crew_id):
		return false
	for event in mailboxes[crew_id]:
		if _is_eligible(event, game_time):
			return true
	return false

## Drain all events eligible at `game_time`. Returns `{events, mailboxes}`
## with eligible events removed and any future-`deliver_at` events kept in
## the queue for later. Calling without `game_time` drains every event
## (legacy/test path).
static func drain_events(mailboxes: Dictionary, crew_id: String, game_time: float = INF) -> Dictionary:
	var events: Array = []
	var remaining: Array = []
	if mailboxes.has(crew_id):
		for event in mailboxes[crew_id]:
			if _is_eligible(event, game_time):
				events.append(event)
			else:
				remaining.append(event)
	var new_mailboxes = mailboxes.duplicate()
	new_mailboxes[crew_id] = remaining
	return {"events": events, "mailboxes": new_mailboxes}

## Peek at events without draining.  Useful for read-only checks.
static func peek_events(mailboxes: Dictionary, crew_id: String) -> Array:
	if not mailboxes.has(crew_id):
		return []
	return mailboxes[crew_id]

static func _is_eligible(event: Dictionary, game_time: float) -> bool:
	if not event.has("deliver_at"):
		return true
	return float(event["deliver_at"]) <= game_time
