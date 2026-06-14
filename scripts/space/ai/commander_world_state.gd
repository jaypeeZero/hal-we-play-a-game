class_name CommanderWorldState
extends RefCounted

## Snapshot of a commander's strategic situation, built once per decision tick.

# Raw inputs
var crew_data: Dictionary
var game_time: float

# Situation
var has_threats: bool
var has_opportunities: bool
var threat_count: int
var subordinate_count: int

# Knowledge and target
var knowledge_actions: Array     # suggested actions from query_commander_knowledge
var best_target: Dictionary      # CrewAIShared.select_best_tactical_target result

# Commit-decision inputs (Layer B)
var enemy_count: int
var engagement_elapsed: float
var fleet_aggression: float  # resolved doctrine mentality 0..1 — gates commit-to-press
var has_focus_target: bool
var focus_target_net_delta: float


static func build(crew_data: Dictionary, game_time: float) -> CommanderWorldState:
	var ws := CommanderWorldState.new()
	ws.crew_data = crew_data
	ws.game_time = game_time

	var threats: Array       = crew_data.get("awareness", {}).get("threats", [])
	var opportunities: Array = crew_data.get("awareness", {}).get("opportunities", [])
	var subordinates: Array  = crew_data.get("command_chain", {}).get("subordinates", [])

	ws.has_threats       = not threats.is_empty()
	ws.has_opportunities = not opportunities.is_empty()
	ws.threat_count      = threats.size()
	ws.subordinate_count = subordinates.size()

	var situation: String = TacticalMemorySystem.generate_situation_summary(crew_data)
	var raw_knowledge: Array = TacticalKnowledgeSystem.query_commander_knowledge(
		situation, 3, crew_data.get("known_patterns", [])
	)
	ws.knowledge_actions = []
	for k in raw_knowledge:
		var act: String = k.get("content", {}).get("action", "")
		if act != "":
			ws.knowledge_actions.append(act)

	ws.best_target = CrewAIShared.select_best_tactical_target(crew_data)

	# Commit-decision inputs (Layer B)
	ws.enemy_count        = TacticalProgressSystem.operational_enemy_count(crew_data)
	ws.engagement_elapsed = TacticalProgressSystem.engagement_elapsed(crew_data, game_time)
	# Only aggressive doctrines escalate to a fleet-wide press; defensive hold.
	ws.fleet_aggression   = float(crew_data.get("tactics", {}).get("mentality_scalar", 0.5))
	var focus_id: String  = ws.best_target.get("id", "")
	ws.has_focus_target   = focus_id != ""
	ws.focus_target_net_delta = TacticalProgressSystem.net_hull_delta(
		focus_id, WingConstants.COMMIT_STALL_WINDOW_SECONDS, game_time
	) if ws.has_focus_target else 0.0

	return ws
