extends GutTest

## Perceived time of `threat_appeared` is strictly ordered by awareness — a
## high-awareness pilot's mailbox releases the event almost immediately, while a
## rookie's stays queued for hundreds of ms. This is the latency layer the
## reaction commit-delay model builds on.

const CREW := "crew_x"

## Compute the same delivery latency space_battle_game._check_spatial_awareness_triggers
## uses. Replicated here so the test doesn't depend on the game node.
func _detection_latency(awareness: float) -> float:
	var clamped = clamp(awareness, 0.0, 1.0)
	return (1.0 - clamped) * WingConstants.MAX_DETECTION_LAG

func _post_threat_for_awareness(mailboxes: Dictionary, awareness: float, post_at: float) -> Dictionary:
	var latency = _detection_latency(awareness)
	var event = {"type": "threat_appeared", "data": {"enemy_id": "e1"}}
	if latency > 0.0:
		event["deliver_at"] = post_at + latency
	return CrewMailboxSystem.post_event(mailboxes, CREW, event)

## Find the earliest game_time at which `has_pending` returns true after
## the event is posted. We sweep with fine resolution so the result is
## tight enough to compare across awareness levels.
func _perceived_time(awareness: float, post_at: float) -> float:
	var mailboxes = _post_threat_for_awareness({}, awareness, post_at)
	var t = post_at
	for i in range(2000):
		if CrewMailboxSystem.has_pending(mailboxes, CREW, t):
			return t
		t += 0.001
	return INF

func test_high_awareness_perceives_threat_almost_immediately():
	var perceived_at = _perceived_time(0.95, 10.0)
	# 0.95 awareness → 0.045s lag — basically the next physics tick.
	assert_lt(perceived_at, 10.1,
		"Elite awareness must perceive the threat well under 100 ms after it appears.")

func test_low_awareness_lags_by_hundreds_of_ms():
	var perceived_at = _perceived_time(0.1, 10.0)
	# 0.1 awareness → 0.81s lag; assert it's clearly in the laggy band.
	assert_gt(perceived_at - 10.0, 0.5,
		"Rookie awareness must lag by at least 500 ms before the event lands.")

func test_perceived_time_is_strictly_ordered_by_awareness():
	# A spread of awareness levels must produce strictly increasing
	# perceived-times as awareness drops. This is the core S1 invariant.
	var levels := [0.95, 0.7, 0.4, 0.1]
	var times: Array = []
	for level in levels:
		times.append(_perceived_time(level, 10.0))
	for i in range(1, times.size()):
		assert_lt(times[i - 1], times[i],
			"Higher awareness must perceive threats earlier than lower (level %s vs %s)" % [levels[i - 1], levels[i]])

func test_elite_vs_rookie_perception_gap_is_at_least_4x():
	# Acceptance criterion #2 from 03_awareness_detection.md: time from
	# threat_appeared to the *crew* receiving it differs by ≥ 4× between
	# elite and rookie crew.
	var elite = _perceived_time(0.95, 10.0) - 10.0
	var rookie = _perceived_time(0.1, 10.0) - 10.0
	assert_gt(rookie, max(elite, 0.001) * 4.0,
		"Rookie perception lag must be ≥4× elite lag (got rookie=%s, elite=%s)." % [rookie, elite])
