class_name CaptainBrain
extends RefCounted

## GOAP-style planner for captains.
## Plan lock damps order churn — captains re-decide every 1–2s and knowledge queries are noisy.

const PLAN_LOCK_DURATION          = 1.2
const PRIORITY_OVERRIDE_THRESHOLD = 0.5


static func decide(ws: CaptainWorldState, game_time: float) -> Dictionary:
	var actions := _get_actions()
	var candidates: Array = []
	for a in actions:
		if a.precondition(ws):
			candidates.append({ "action": a, "cost": a.cost(ws) })

	if candidates.is_empty():
		return {}

	candidates.sort_custom(func(a, b): return a.cost < b.cost)
	var best: Dictionary = candidates[0]

	# Plan stability lock
	var cs: Dictionary      = ws.crew_data.get("combat_state", {})
	var locked_id: String   = cs.get("locked_action_id", "")
	var lock_expires: float = cs.get("plan_lock_expires_at", 0.0)
	if locked_id != "" and game_time < lock_expires:
		for c in candidates:
			if c.action.action_id() == locked_id:
				if not (best.cost < c.cost * PRIORITY_OVERRIDE_THRESHOLD):
					best = c
				break

	cs["locked_action_id"]    = best.action.action_id()
	cs["plan_lock_expires_at"] = game_time + PLAN_LOCK_DURATION

	return best.action.execute(ws)


static func _get_actions() -> Array:
	return [
		CaptainWithdrawAction.new(),
		DefensivePostureAction.new(),
		CaptainPressAttackAction.new(),   # commit-to-press escalation
		ConcentrateFireAction.new(),
		AggressivePursuitAction.new(),
		SupportAllyAction.new(),
		CaptainFlankAction.new(),
		CaptainEngageAction.new(),
		CaptainHoldAction.new(),
	]
