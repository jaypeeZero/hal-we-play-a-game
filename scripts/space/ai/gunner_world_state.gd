class_name GunnerWorldState
extends RefCounted

## Snapshot of a gunner's tactical situation, built once per decision tick.
## Actions read from this; they never rebuild it.

# Raw inputs
var crew_data: Dictionary
var game_time: float

# Targeting
var opportunities: Array       # from crew_data.awareness.opportunities
var target_count: int

# Knowledge-driven intent
var knowledge: Array           # TacticalKnowledgeSystem.query_gunner_knowledge results
var knowledge_action: String   # "fire" | "hold_fire" | "suppressive_fire" | "precision_shot"

# Ammo state
var is_low_ammo: bool          # TODO: derive from ship data; false for now

# Skill
var effective_skill: float

# Pre-scored targets (computed once)
var best_target: Dictionary    # highest-scoring target for precision shots
var priority_target: Dictionary  # damaged/disabled opp if knowledge wants it, else opp[0]


static func build(crew_data: Dictionary, game_time: float) -> GunnerWorldState:
	var ws := GunnerWorldState.new()
	ws.crew_data    = crew_data
	ws.game_time    = game_time
	ws.opportunities = crew_data.get("awareness", {}).get("opportunities", [])
	ws.target_count  = ws.opportunities.size()
	ws.is_low_ammo   = false  # TODO: query ship ammo when mechanic exists

	ws.effective_skill = CrewAISystem.calculate_effective_skill(crew_data)

	# Knowledge query — one call per decision
	var situation := TacticalMemorySystem.generate_situation_summary(crew_data)
	ws.knowledge = TacticalKnowledgeSystem.query_gunner_knowledge(
		situation, 3, crew_data.get("known_patterns", [])
	)
	ws.knowledge_action = _select_action_from_knowledge(ws.knowledge, ws.target_count, ws.is_low_ammo)

	# Best target for precision shots
	ws.best_target = _select_best_target(ws.opportunities)

	# Priority target for standard fire — prefer damaged when knowledge says so
	ws.priority_target = _select_priority_target(ws.knowledge, ws.opportunities)

	return ws


# --- Private helpers ---

static func _select_action_from_knowledge(
	knowledge: Array, target_count: int, is_low_ammo: bool
) -> String:
	if knowledge.is_empty():
		return "fire"
	for k in knowledge:
		var suggested_action: String = k.get("content", {}).get("action", "")
		var subtype: String          = k.get("content", {}).get("subtype", "")
		if suggested_action == "hold_fire" and is_low_ammo:
			return "hold_fire"
		elif suggested_action == "fire":
			if subtype == "suppressive_fire" and target_count >= GunnerAction.SUPPRESSIVE_TARGET_COUNT_THRESHOLD:
				return "suppressive_fire"
			elif subtype == "precision_shot":
				return "precision_shot"
	return "fire"


static func _select_best_target(opportunities: Array) -> Dictionary:
	if opportunities.is_empty():
		return {}
	var best: Dictionary = opportunities[0]
	var best_score := -1.0
	for opp in opportunities:
		var score := 0.0
		if opp.get("status", "") in ["damaged", "disabled", "critical"]:
			score += GunnerAction.DAMAGED_TARGET_BONUS
		var dist: float = opp.get("distance", GunnerAction.DEFAULT_TARGET_DISTANCE)
		score += maxf(0.0, GunnerAction.DISTANCE_SCORE_MAX - dist / GunnerAction.DISTANCE_SCORE_DIVISOR)
		var ttype: String = opp.get("type", "")
		if ttype in ["capital", "corvette"]:
			score += GunnerAction.HIGH_VALUE_TARGET_BONUS
		if score > best_score:
			best_score = score
			best = opp
	return best


static func _select_priority_target(knowledge: Array, opportunities: Array) -> Dictionary:
	if opportunities.is_empty():
		return {}
	# Use knowledge priority_order to prefer damaged enemies when indicated
	if not knowledge.is_empty():
		var priority_order: Array = knowledge[0].get("content", {}).get("priority_order", [])
		if "damaged_enemies" in priority_order:
			for opp in opportunities:
				if opp.get("status", "") in ["damaged", "disabled"]:
					return opp
	return opportunities[0]
