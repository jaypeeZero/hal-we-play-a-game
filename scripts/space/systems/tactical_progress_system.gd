class_name TacticalProgressSystem
extends RefCounted

## Pure helper: measures damage progress against a focus target over a time window.
## Uses the BattleEventLogger event stream (already records damage_dealt and
## repair_applied). Pure static functions — no state.


## Net hull delta for `target_id` over [now - window, now].
## Positive = we are netting damage (good). Zero/negative = stalemate/regen.
## Returns 0.0 if the logger has no service (e.g. unit tests without a battle).
static func net_hull_delta(target_id: String, window: float, now: float) -> float:
	if not BattleEventLoggerAutoload.service:
		return 0.0
	var start: float = now - window
	var events: Array = BattleEventLoggerAutoload.service.get_events_in_timerange(start, now)

	var damage_dealt: float = 0.0
	var repaired: float     = 0.0

	for ev in events:
		var data: Dictionary = ev.get("data", {})
		match ev.get("type", ""):
			"damage_dealt":
				if data.get("victim_id", "") == target_id:
					damage_dealt += float(data.get("amount", 0))
			"repair_applied":
				if data.get("ship_id", "") == target_id:
					repaired += float(data.get("amount", 0))

	return damage_dealt - repaired


## Count operational enemies known to a crew member via awareness threats.
static func operational_enemy_count(crew_data: Dictionary) -> int:
	var threats: Array = crew_data.get("awareness", {}).get("threats", [])
	var count := 0
	for t in threats:
		if t.get("status", "operational") == "operational":
			count += 1
	return count


## Seconds since first threat contact for this crew member.
## Stamped into combat_state.engagement_started_at on first threat.
## Returns 0.0 when no engagement has been recorded.
static func engagement_elapsed(crew_data: Dictionary, game_time: float) -> float:
	var started_at: float = crew_data.get("combat_state", {}).get("engagement_started_at", -1.0)
	if started_at < 0.0:
		return 0.0
	return game_time - started_at


## Stamp engagement_started_at on first threat contact (call from game tick
## that populates awareness). No-op if already stamped. Returns updated crew.
static func maybe_stamp_engagement_start(crew_data: Dictionary, game_time: float) -> Dictionary:
	if crew_data.get("combat_state", {}).get("engagement_started_at", -1.0) >= 0.0:
		return crew_data
	var threats: Array = crew_data.get("awareness", {}).get("threats", [])
	if threats.is_empty():
		return crew_data
	var updated := crew_data.duplicate(true)
	if not updated.has("combat_state"):
		updated["combat_state"] = {}
	updated["combat_state"]["engagement_started_at"] = game_time
	return updated
