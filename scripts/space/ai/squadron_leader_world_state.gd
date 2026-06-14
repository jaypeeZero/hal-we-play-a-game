class_name SquadronLeaderWorldState
extends RefCounted

## Snapshot of a squadron leader's tactical situation, built once per decision tick.
## Coordination-fail roll taken once here so actions are deterministic for the tick.

# Raw inputs
var crew_data: Dictionary
var game_time: float

# Situation flags
var has_threats: bool
var has_opportunities: bool
var threat_count: int
var subordinate_count: int

# Derived context
var damaged_subordinate: Dictionary  # first damaged/critical/disabled subordinate; empty if none
var is_scattered: bool

# Coordination style and knowledge
var coordination_style: int          # CrewIntegrationSystem.CoordinationStyle.*
var knowledge_actions: Array         # suggested actions from query_squadron_knowledge

# INDIVIDUAL-style roll — taken once per decision
var coordination_failed: bool        # true → INDIVIDUAL leader fails to coordinate


static func build(crew_data: Dictionary, game_time: float) -> SquadronLeaderWorldState:
	var ws := SquadronLeaderWorldState.new()
	ws.crew_data = crew_data
	ws.game_time = game_time

	var threats: Array       = crew_data.get("awareness", {}).get("threats", [])
	var opportunities: Array = crew_data.get("awareness", {}).get("opportunities", [])
	var subordinates: Array  = crew_data.get("command_chain", {}).get("subordinates", [])

	ws.has_threats       = not threats.is_empty()
	ws.has_opportunities = not opportunities.is_empty()
	ws.threat_count      = threats.size()
	ws.subordinate_count = subordinates.size()

	var skill: float = CrewAISystem.calculate_effective_skill(crew_data)
	ws.coordination_style = CrewIntegrationSystem._select_coordination_style(skill)

	var situation: String = TacticalMemorySystem.generate_situation_summary(crew_data)
	var raw_knowledge: Array = TacticalKnowledgeSystem.query_squadron_knowledge(
		situation, 3, crew_data.get("known_patterns", [])
	)
	ws.knowledge_actions = []
	for k in raw_knowledge:
		var act: String = k.get("content", {}).get("action", "")
		if act != "":
			ws.knowledge_actions.append(act)

	ws.damaged_subordinate = _find_damaged_subordinate(crew_data)
	ws.is_scattered        = _is_squadron_scattered(crew_data)

	# Roll INDIVIDUAL coordination failure once
	ws.coordination_failed = randf() < SquadronLeaderAction.INDIVIDUAL_COORDINATION_FAIL_CHANCE

	return ws


# --- Private helpers ---

static func _find_damaged_subordinate(crew_data: Dictionary) -> Dictionary:
	var subordinates: Array    = crew_data.get("command_chain", {}).get("subordinates", [])
	var known_entities: Array  = crew_data.get("awareness", {}).get("known_entities", [])
	for sub_id in subordinates:
		for entity in known_entities:
			if entity.get("id", "") == sub_id and entity.get("status", "") in ["damaged", "critical", "disabled"]:
				return entity
	return {}


static func _is_squadron_scattered(crew_data: Dictionary) -> bool:
	var subordinates: Array   = crew_data.get("command_chain", {}).get("subordinates", [])
	if subordinates.size() < 2:
		return false
	var known_entities: Array = crew_data.get("awareness", {}).get("known_entities", [])
	var positions: Array      = []
	for sub_id in subordinates:
		for entity in known_entities:
			if entity.get("id", "") == sub_id:
				positions.append(entity.get("position", Vector2.ZERO))
				break
	if positions.size() < 2:
		return false
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) > SquadronLeaderAction.SCATTERED_THRESHOLD:
				return true
	return false
