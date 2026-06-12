class_name RejoinWingAction
extends FighterAction

## Wingman rejoins lead when out of formation.
## Takes priority over combat so the wing stays coherent.

func action_id() -> String: return "rejoin_wing"
func cost(_ws: FighterWorldState) -> float: return 0.6


func precondition(ws: FighterWorldState) -> bool:
	return (
		ws.in_wing
		and ws.wing_role == "wingman"
		and not ws.is_in_formation
		and not ws.lead_ship.is_empty()
	)


func execute(ws: FighterWorldState) -> Dictionary:
	var wing: Dictionary = ws.wing_info.get("wing", {})
	var position_side: int = ws.wing_info.get("position_side", 1)
	var slot_rank: int = ws.wing_info.get("slot_rank", 0)
	var formation_pos := WingFormationSystem.calculate_wing_position(
		ws.lead_ship, position_side, ws.skill, slot_rank
	)
	return {
		"type": "maneuver",
		"subtype": "fight_wing_rejoin",
		"crew_id": ws.crew_data.get("crew_id", ""),
		"entity_id": ws.my_ship.get("ship_id", ""),
		"target_id": ws.lead_ship.get("ship_id", ""),
		"formation_position": formation_pos,
		"position_side": position_side,
		"skill_factor": ws.skill,
		"delay": lerp(0.5, 0.2, ws.skill),
		"timestamp": ws.game_time,
		"is_wingman": true,
	}
