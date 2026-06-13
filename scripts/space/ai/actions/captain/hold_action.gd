class_name CaptainHoldAction
extends CaptainAction

## Hold position — the safe default. REACTIVE hesitation rolls raise its effective priority.

func action_id() -> String: return "hold"

func cost(ws: CaptainWorldState) -> float:
	# REACTIVE captains that rolled hesitate/hold pay a lower cost, making hold win
	if ws.command_style == CrewIntegrationSystem.CommandStyle.REACTIVE:
		if ws.hold_instead_roll or ws.hesitate_roll:
			return CaptainAction.COST_KNOWLEDGE  # beats engage/standard actions
	return CaptainAction.COST_HOLD

func precondition(_ws: CaptainWorldState) -> bool:
	return true  # always available as a fallback

func execute(ws: CaptainWorldState) -> Dictionary:
	var orders := CaptainAction.orders_to_subordinates(ws, {"type": "hold", "subtype": "maintain_position"})
	return {
		"decision": CaptainAction.make_captain_decision(ws, "hold", null),
		"issued_orders": orders,
	}
