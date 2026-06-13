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

	return ws
