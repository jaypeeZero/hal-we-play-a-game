class_name CommanderCommitAction
extends CommanderAction

## Commander strategic commit action — issues a press_attack posture fleet-wide.
## Same two triggers as CaptainPressAttackAction but at fleet scope:
##   1. Few enemies + time elapsed.
##   2. Stalemate on focus target.
##
## Having both captain and commander emit postures means a fleet with or
## without a live commander still escalates.

func action_id() -> String: return "commander_commit"

func cost(_ws: CommanderWorldState) -> float:
	return WingConstants.COMMIT_COST

func precondition(ws: CommanderWorldState) -> bool:
	var few_enemies_trigger: bool = (
		ws.enemy_count > 0
		and ws.enemy_count <= WingConstants.COMMIT_ENEMY_COUNT_THRESHOLD
		and ws.engagement_elapsed >= WingConstants.COMMIT_ENGAGEMENT_SECONDS
	)
	var stalemate_trigger: bool = (
		ws.has_focus_target
		and ws.engagement_elapsed >= WingConstants.COMMIT_STALL_WINDOW_SECONDS
		and ws.focus_target_net_delta <= WingConstants.COMMIT_STALL_NET_DAMAGE_EPSILON
	)
	return few_enemies_trigger or stalemate_trigger


func execute(ws: CommanderWorldState) -> Dictionary:
	var target_id: String = ws.best_target.get("id", "")
	var orders := CommanderAction.orders_to_subordinates(ws, {
		"type": "posture",
		"subtype": "press_attack",
		"target_id": target_id,
		"expires_at": ws.game_time + WingConstants.COMMIT_POSTURE_DURATION,
		"player_override": false,
		"timestamp": ws.game_time,
	})
	return {
		"decision": CommanderAction.make_strategic_decision(ws, "commit_press_attack", {
			"target_id": target_id,
		}),
		"issued_orders": orders,
	}
