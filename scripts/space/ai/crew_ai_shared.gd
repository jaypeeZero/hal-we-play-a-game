extends RefCounted
class_name CrewAIShared

## Shared helpers used across multiple role AIs (captain, squadron leader, commander).


## Select best tactical target - prioritize threats, then opportunities.
static func select_best_tactical_target(crew_data: Dictionary) -> Dictionary:
	if not crew_data.awareness.threats.is_empty():
		return crew_data.awareness.threats[0]
	if not crew_data.awareness.opportunities.is_empty():
		return crew_data.awareness.opportunities[0]
	return {}
