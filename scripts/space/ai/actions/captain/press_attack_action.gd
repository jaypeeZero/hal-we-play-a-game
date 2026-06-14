class_name CaptainPressAttackAction
extends CaptainAction

## Captain commit action — issues a press_attack posture to all subordinates.
## Fires on two triggers (OR'd into one action to keep the action list small):
##   1. Few enemies + long engagement: few operational enemies remain and the
##      fight has dragged on without resolution.
##   2. Stalemate: our fire is not netting damage on the focus target over a
##      sampling window (DPS ≤ target's regen).
##
## Cost is low (COMMIT_COST) so it beats hold/standoff once its condition is met.

func action_id() -> String: return "captain_press_attack"

func cost(_ws: CaptainWorldState) -> float:
	return WingConstants.COMMIT_COST

func precondition(ws: CaptainWorldState) -> bool:
	# Trigger 1: few enemies + time elapsed.
	var few_enemies_trigger: bool = (
		ws.enemy_count > 0
		and ws.enemy_count <= WingConstants.COMMIT_ENEMY_COUNT_THRESHOLD
		and ws.engagement_elapsed >= WingConstants.COMMIT_ENGAGEMENT_SECONDS
	)
	# Trigger 2: stalemate — focus target not losing net health.
	var stalemate_trigger: bool = (
		ws.has_focus_target
		and ws.engagement_elapsed >= WingConstants.COMMIT_STALL_WINDOW_SECONDS
		and ws.focus_target_net_delta <= WingConstants.COMMIT_STALL_NET_DAMAGE_EPSILON
	)
	# Doctrine gate: only aggressive fleets commit to an all-out press. Defensive
	# or balanced doctrines hold their tactics — this keeps a kiting fleet from
	# devolving into a charge once the stalemate/elapsed timer fires.
	if ws.fleet_aggression < WingConstants.COMMIT_MIN_AGGRESSION:
		return false
	return few_enemies_trigger or stalemate_trigger


func execute(ws: CaptainWorldState) -> Dictionary:
	var target_id: String = ws.mission_target.get("id", "")
	var orders := CaptainAction.orders_to_subordinates(ws, {
		"type": "posture",
		"subtype": "press_attack",
		"target_id": target_id,
		"expires_at": ws.game_time + WingConstants.COMMIT_POSTURE_DURATION,
		"player_override": false,
		"timestamp": ws.game_time,
	})
	return {
		"decision": CaptainAction.make_captain_decision(ws, "press_attack", target_id),
		"issued_orders": orders,
	}
