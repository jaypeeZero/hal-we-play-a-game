class_name FighterBrain
extends RefCounted

## GOAP-style planner for fighter pilots.
## Builds a world state snapshot, evaluates all actions by precondition + cost,
## then picks the cheapest valid action. A plan lock prevents thrashing:
## once locked, the current action stays unless something dramatically cheaper
## becomes available (< PRIORITY_OVERRIDE_THRESHOLD × locked cost).

const PLAN_LOCK_DURATION          = 1.2    # seconds before re-evaluating freely
const PRIORITY_OVERRIDE_THRESHOLD = 0.5   # new action must cost < 50% of locked to override


static func decide(ws: FighterWorldState, game_time: float) -> Dictionary:
	var actions := _get_actions()
	var candidates: Array = []
	for a in actions:
		if a.precondition(ws):
			candidates.append({ "action": a, "cost": a.cost(ws) })

	if candidates.is_empty():
		return _idle(ws, game_time)

	candidates.sort_custom(func(a, b): return a.cost < b.cost)
	var best: Dictionary = candidates[0]

	# Plan stability lock
	var cs: Dictionary   = ws.crew_data.get("combat_state", {})
	var locked_id: String = cs.get("locked_action_id", "")
	var lock_expires: float = cs.get("plan_lock_expires_at", 0.0)
	if locked_id != "" and game_time < lock_expires:
		for c in candidates:
			if c.action.action_id() == locked_id:
				# Keep locked action unless best is dramatically cheaper
				if not (best.cost < c.cost * PRIORITY_OVERRIDE_THRESHOLD):
					best = c
				break

	cs["locked_action_id"]  = best.action.action_id()
	cs["plan_lock_expires_at"] = game_time + PLAN_LOCK_DURATION

	return best.action.execute(ws)


static func _get_actions() -> Array:
	return [
		EvadeOutnumberedAction.new(),
		RejoinWingAction.new(),
		PatrolReturnAction.new(),
		SupportUnderFireAction.new(),
		CutOffAction.new(),
		FlankAction.new(),
		AttackAction.new(),
	]


static func _idle(ws: FighterWorldState, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "idle",
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.my_ship.get("ship_id", ""),
		"target_id": "",
		"skill_factor": ws.skill,
		"delay": 2.0,
		"timestamp": game_time
	}
