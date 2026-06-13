class_name AssessAction
extends CommanderAction

## Assess the situation — always available, highest cost, the default fallback.
## The commander always emits a decision because this action always qualifies.

func action_id() -> String: return "assess"
func cost(_ws: CommanderWorldState) -> float: return CommanderAction.COST_ASSESS

func precondition(_ws: CommanderWorldState) -> bool:
	return true  # unconditional default

func execute(ws: CommanderWorldState) -> Dictionary:
	return {
		"decision": CommanderAction.make_strategic_decision(ws, "assess"),
		"issued_orders": [],
	}
