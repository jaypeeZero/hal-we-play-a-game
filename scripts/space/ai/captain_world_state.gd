class_name CaptainWorldState
extends RefCounted

## Snapshot of a captain's tactical situation, built once per decision tick.
## Probabilistic style rolls are taken once here and consumed as booleans.

# Raw inputs
var crew_data: Dictionary
var game_time: float

# Situation flags
var has_threats: bool
var has_opportunities: bool
var threat_count: int

# Derived situational context
var damaged_friendly: Dictionary   # first damaged/critical friendly; empty if none
var is_critically_damaged: bool

# Command style and knowledge
var command_style: int             # CrewIntegrationSystem.CommandStyle.*
var knowledge_actions: Array       # suggested actions from query_captain_knowledge, in result order

# Target selection (computed once)
var mission_target: Dictionary     # _select_mission_target result
var damaged_target: Dictionary     # first damaged/critical opportunity; empty if none
var top_threat_priority: float     # threats[0]._threat_priority, or 0.0

# REACTIVE style rolls — computed once so actions are deterministic (overview §5)
var panic_withdraw_roll: bool      # REACTIVE captain panics and may withdraw
var hold_instead_roll: bool        # REACTIVE captain holds instead of engaging
var hesitate_roll: bool            # REACTIVE captain hesitates on opportunity

# Commit-decision inputs (Layer B)
var enemy_count: int               # operational enemies known via awareness
var engagement_elapsed: float      # seconds since first contact
var has_focus_target: bool
var focus_target_net_delta: float  # net hull damage over COMMIT_STALL_WINDOW_SECONDS


static func build(crew_data: Dictionary, game_time: float) -> CaptainWorldState:
	var ws := CaptainWorldState.new()
	ws.crew_data         = crew_data
	ws.game_time         = game_time

	var threats: Array      = crew_data.get("awareness", {}).get("threats", [])
	var opportunities: Array = crew_data.get("awareness", {}).get("opportunities", [])
	ws.has_threats       = not threats.is_empty()
	ws.has_opportunities = not opportunities.is_empty()
	ws.threat_count      = threats.size()
	ws.top_threat_priority = threats[0].get("_threat_priority", 0.0) if not threats.is_empty() else 0.0

	var skill: float = CrewAISystem.calculate_effective_skill(crew_data)
	ws.command_style  = CrewIntegrationSystem._select_command_style(skill)

	var situation: String = TacticalMemorySystem.generate_situation_summary(crew_data)
	var raw_knowledge: Array = TacticalKnowledgeSystem.query_captain_knowledge(
		situation, 3, crew_data.get("known_patterns", [])
	)
	ws.knowledge_actions = []
	for k in raw_knowledge:
		var act: String = k.get("content", {}).get("action", "")
		if act != "":
			ws.knowledge_actions.append(act)

	ws.damaged_friendly    = _find_damaged_friendly(crew_data)
	ws.is_critically_damaged = _is_ship_critically_damaged(crew_data)
	ws.mission_target      = _select_mission_target(crew_data)
	ws.damaged_target      = _select_damaged_target(crew_data)

	# Roll probabilistic REACTIVE choices once per decision (overview §5)
	ws.panic_withdraw_roll = randf() < CaptainAction.REACTIVE_PANIC_WITHDRAW_CHANCE
	ws.hold_instead_roll   = randf() < CaptainAction.REACTIVE_HOLD_INSTEAD_OF_ENGAGE_CHANCE
	ws.hesitate_roll       = randf() < CaptainAction.REACTIVE_HESITATE_ON_OPPORTUNITY_CHANCE

	# Commit-decision inputs (Layer B)
	ws.enemy_count         = TacticalProgressSystem.operational_enemy_count(crew_data)
	ws.engagement_elapsed  = TacticalProgressSystem.engagement_elapsed(crew_data, game_time)
	var focus_id: String   = ws.mission_target.get("id", "")
	ws.has_focus_target    = focus_id != ""
	ws.focus_target_net_delta = TacticalProgressSystem.net_hull_delta(
		focus_id, WingConstants.COMMIT_STALL_WINDOW_SECONDS, game_time
	) if ws.has_focus_target else 0.0

	return ws


# --- Private helpers ---

static func _find_damaged_friendly(crew_data: Dictionary) -> Dictionary:
	var known: Array = crew_data.get("awareness", {}).get("known_entities", [])
	for entity in known:
		if entity is Dictionary and entity.get("is_friendly", false):
			if entity.get("status", "") in ["damaged", "critical"]:
				return entity
	return {}


static func _is_ship_critically_damaged(crew_data: Dictionary) -> bool:
	var stress: float      = crew_data.get("stats", {}).get("stress", 0.0)
	var threat_count: int  = crew_data.get("awareness", {}).get("threats", []).size()
	return stress > CaptainAction.CRITICAL_STRESS_THRESHOLD and threat_count >= CaptainAction.CRITICAL_THREAT_COUNT


static func _select_mission_target(crew_data: Dictionary) -> Dictionary:
	var mission: String   = crew_data.get("squadron_mission", SquadronData.Mission.FREE)
	var params: Dictionary = crew_data.get("squadron_mission_params", {})
	if mission == SquadronData.Mission.FREE:
		return CrewAIShared.select_best_tactical_target(crew_data)
	var opportunities: Array = crew_data.get("awareness", {}).get("opportunities", [])
	if opportunities.is_empty():
		return {}
	var best: Dictionary = {}
	var best_score := -1.0
	for opp in opportunities:
		var base_score: float = opp.get("_threat_priority", 1.0)
		var score: float = base_score * MissionTargetingSystem.score_multiplier(mission, params, opp)
		if score > best_score:
			best_score = score
			best = opp
	return best


static func _select_damaged_target(crew_data: Dictionary) -> Dictionary:
	for opp in crew_data.get("awareness", {}).get("opportunities", []):
		if opp.get("status", "") in ["damaged", "disabled", "critical"]:
			return opp
	return {}
