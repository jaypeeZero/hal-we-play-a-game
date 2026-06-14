extends GutTest

## Mailbox supports per-event delivery latency.
##
## Events whose `deliver_at` is in the future are not eligible — drain
## leaves them queued and has_pending reports false until time catches up.
## This is the foundation for skill-gated perception lag.

const CREW := "crew_x"

func test_no_deliver_at_means_immediately_eligible():
	# Backwards-compatible path: events without deliver_at drain right away.
	var mailboxes = CrewMailboxSystem.post_event({}, CREW, {
		"type": "threat_appeared",
		"data": {}
	})
	assert_true(CrewMailboxSystem.has_pending(mailboxes, CREW, 0.0),
		"Event without deliver_at must be pending at any game_time.")

	var drained = CrewMailboxSystem.drain_events(mailboxes, CREW, 0.0)
	assert_eq(drained.events.size(), 1, "Legacy event drains on first tick.")

func test_future_deliver_at_is_held_back():
	var mailboxes = CrewMailboxSystem.post_event({}, CREW, {
		"type": "threat_appeared",
		"deliver_at": 1.5,
		"data": {}
	})

	assert_false(CrewMailboxSystem.has_pending(mailboxes, CREW, 1.0),
		"Event with deliver_at > game_time must not be pending yet.")

	var drained = CrewMailboxSystem.drain_events(mailboxes, CREW, 1.0)
	assert_eq(drained.events.size(), 0, "Drain skips not-yet-deliverable events.")
	# And the event must still be in the queue, waiting.
	assert_eq(drained.mailboxes[CREW].size(), 1,
		"Future-dated event stays queued for later delivery.")

func test_event_becomes_eligible_once_game_time_passes():
	var mailboxes = CrewMailboxSystem.post_event({}, CREW, {
		"type": "threat_appeared",
		"deliver_at": 1.5,
		"data": {}
	})

	# Before the threshold: still hidden.
	assert_false(CrewMailboxSystem.has_pending(mailboxes, CREW, 1.0))

	# At/after the threshold: visible.
	assert_true(CrewMailboxSystem.has_pending(mailboxes, CREW, 1.5),
		"deliver_at == game_time should be eligible (not strictly greater).")

	var drained = CrewMailboxSystem.drain_events(mailboxes, CREW, 1.6)
	assert_eq(drained.events.size(), 1, "Drained once time passed.")
	assert_eq(drained.mailboxes[CREW].size(), 0, "Queue empty after drain.")

func test_mixed_eligibility_drains_only_eligible():
	# Two events with different deliver_at; at t=1.0 only the first should
	# drain, the second waits.
	var step1 = CrewMailboxSystem.post_event({}, CREW, {
		"type": "threat_appeared", "deliver_at": 0.5, "data": {"id": "a"}
	})
	var step2 = CrewMailboxSystem.post_event(step1, CREW, {
		"type": "threat_appeared", "deliver_at": 2.0, "data": {"id": "b"}
	})

	var drained = CrewMailboxSystem.drain_events(step2, CREW, 1.0)
	assert_eq(drained.events.size(), 1, "Only the eligible event drains.")
	assert_eq(drained.events[0].data.id, "a", "The right event drains.")
	assert_eq(drained.mailboxes[CREW].size(), 1, "The held event stays queued.")
