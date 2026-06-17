class_name StandardFireAction
extends GunnerAction

## Standard fire — the default when opportunities exist and no specific mode
## was suggested by knowledge. Highest base cost so knowledge-driven actions win.

const BASE_COST = 1.0

func action_id() -> String: return "standard_fire"
func cost(_ws: GunnerWorldState) -> float: return BASE_COST

func precondition(ws: GunnerWorldState) -> bool:
	return not ws.opportunities.is_empty()

func execute(ws: GunnerWorldState) -> Dictionary:
	# Default: leave target_id empty so each weapon self-selects the best in-arc
	# target via WeaponSystem.find_best_target_for_weapon.
	# Only force a target when fleet command has designated an explicit focus.
	var focus: String = ws.crew_data.get("focus_assignment", "")
	var target_id: String = focus if focus != "" else ""
	return GunnerAction.make_fire_decision(ws, target_id, "fire")
