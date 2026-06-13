class_name SquadronLeaderAction
extends RefCounted

## Base class for GOAP squadron leader actions.
## execute() returns {"decision": ..., "issued_orders": [...]}

# Coordination thresholds
const COORDINATED_ATTACK_MIN_SUBORDINATES = 3
const SCATTERED_THRESHOLD                 = 2000.0
const INDIVIDUAL_COORDINATION_FAIL_CHANCE = 0.4

# Skill-based assignment quality thresholds
const HIGH_SKILL_THRESHOLD   = 0.7
const MEDIUM_SKILL_THRESHOLD = 0.5

# Target priority scoring weights
const DAMAGED_TARGET_BONUS    = 50.0
const THREATENING_TARGET_BONUS = 30.0
const DISTANCE_SCORE_MAX      = 100.0
const DISTANCE_SCORE_DIVISOR  = 20.0
const DEFAULT_TARGET_DISTANCE = 1000.0

# Cost bands
const COST_MUTUAL_SUPPORT = 0.2   # protect damaged subordinate
const COST_REFORM         = 0.3   # reform scattered formation
const COST_SCREEN         = 0.35  # screen withdrawal
const COST_COORDINATE     = 0.4   # coordinated attack run (ORCHESTRATED)
const COST_ASSIGN         = 0.5   # standard target assignment


# Virtual interface

func action_id() -> String:
	return ""

func cost(_ws: SquadronLeaderWorldState) -> float:
	return 1.0

func precondition(_ws: SquadronLeaderWorldState) -> bool:
	return false

func execute(_ws: SquadronLeaderWorldState) -> Dictionary:
	return {}


# Shared static helpers

static func make_squadron_decision(
	ws: SquadronLeaderWorldState,
	subtype: String,
	extra: Dictionary = {}
) -> Dictionary:
	var d := {
		"type": "squadron_command",
		"subtype": subtype,
		"crew_id": ws.crew_data.get("crew_id", ""),
		"delay": CrewAISystem.calculate_decision_delay(ws.crew_data),
		"timestamp": ws.game_time,
	}
	for k in extra:
		d[k] = extra[k]
	return d


static func orders_to_subordinates(ws: SquadronLeaderWorldState, template: Dictionary) -> Array:
	var result: Array = []
	for sub_id in ws.crew_data.get("command_chain", {}).get("subordinates", []):
		var order: Dictionary = template.duplicate(true)
		order["to"] = sub_id
		result.append(order)
	return result


## Score a target for assignment quality (moved here from SquadronLeaderAI).
static func calculate_target_priority_score(
	target: Dictionary, mission: String = "", params: Dictionary = {}
) -> float:
	var score := 0.0
	if target.get("status", "") in ["damaged", "critical", "disabled"]:
		score += DAMAGED_TARGET_BONUS
	var distance: float = target.get("distance", DEFAULT_TARGET_DISTANCE)
	score += maxf(0.0, DISTANCE_SCORE_MAX - distance / DISTANCE_SCORE_DIVISOR)
	if target.get("is_threat", false):
		score += THREATENING_TARGET_BONUS
	score *= MissionTargetingSystem.score_multiplier(mission, params, target)
	return score
