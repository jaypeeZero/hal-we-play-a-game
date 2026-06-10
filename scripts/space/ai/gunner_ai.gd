extends RefCounted
class_name GunnerAI

## Pure functional gunner role AI.
## Knowledge-driven target selection with hold/standard/suppressive/precision modes.

# Re-decision delays per fire mode
const SUPPRESSIVE_REDECIDE_DELAY = 0.05
const PRECISION_REDECIDE_MIN = 0.8
const PRECISION_REDECIDE_MAX = 1.2
const STANDARD_REDECIDE_AFTER_ORDER = 0.1
const HOLD_REDECIDE_MIN = 0.5
const HOLD_REDECIDE_MAX = 1.0
const NO_TARGETS_REDECIDE_MIN = 1.0
const NO_TARGETS_REDECIDE_MAX = 2.0
const MULTI_TARGET_REDECIDE_DELAY = 0.1
const MULTI_TARGET_THRESHOLD = 2

# Gunner-knowledge thresholds
const SUPPRESSIVE_TARGET_COUNT_THRESHOLD = 3

# Target scoring weights
const DAMAGED_TARGET_BONUS = 50.0
const HIGH_VALUE_TARGET_BONUS = 30.0
const DISTANCE_SCORE_MAX = 100.0
const DISTANCE_SCORE_DIVISOR = 10.0
const DEFAULT_TARGET_DISTANCE = 1000.0


## Public entry point - called by CrewAISystem dispatcher.
static func make_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	# Check for specific target order from captain
	if crew_data.orders.received != null:
		return _execute_order(crew_data, game_time)

	# Select target from opportunities
	if not crew_data.awareness.opportunities.is_empty():
		return _select_target(crew_data, game_time)

	# No targets available - schedule next decision check
	var updated = crew_data.duplicate(true)
	updated.next_decision_time = game_time + randf_range(NO_TARGETS_REDECIDE_MIN, NO_TARGETS_REDECIDE_MAX)
	return {"crew_data": updated}


## Execute target order from captain
static func _execute_order(crew_data: Dictionary, game_time: float) -> Dictionary:
	var order = crew_data.orders.received
	var updated = crew_data.duplicate(true)

	updated.orders.current = order
	updated.orders.received = null

	# Determine fire mode based on order
	var fire_subtype = order.get("subtype", "fire")
	var decision = _create_fire_decision_with_mode(updated, order.get("target_id", ""), fire_subtype, game_time)

	# Re-decide frequency based on fire mode
	match fire_subtype:
		"suppressive_fire":
			updated.next_decision_time = game_time + SUPPRESSIVE_REDECIDE_DELAY
		"precision_shot":
			updated.next_decision_time = game_time + randf_range(PRECISION_REDECIDE_MIN, PRECISION_REDECIDE_MAX)
		_:
			updated.next_decision_time = game_time + STANDARD_REDECIDE_AFTER_ORDER

	return {"crew_data": updated, "decision": decision}


## Make target selection decision - KNOWLEDGE-DRIVEN
static func _select_target(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Query knowledge for firing guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_gunner_knowledge(situation, 3, crew_data.get("known_patterns", []))

	# Select fire action from knowledge
	var fire_action = _select_action_from_knowledge(knowledge, crew_data)

	# Default: pick first target
	var target = crew_data.awareness.opportunities[0]
	var decision = null

	match fire_action:
		"hold_fire":
			# Don't fire - wait for better opportunity
			decision = _create_hold_fire_decision(updated, game_time)
			updated.next_decision_time = game_time + randf_range(HOLD_REDECIDE_MIN, HOLD_REDECIDE_MAX)

		"suppressive_fire":
			# Rapid fire, cycle between targets
			decision = _create_fire_decision_with_mode(updated, target.id, "suppressive_fire", game_time)
			updated.next_decision_time = game_time + SUPPRESSIVE_REDECIDE_DELAY

		"precision_shot":
			# Select best target and aim carefully
			target = _select_best_target(crew_data)
			decision = _create_fire_decision_with_mode(updated, target.id, "precision_shot", game_time)
			updated.next_decision_time = game_time + randf_range(PRECISION_REDECIDE_MIN, PRECISION_REDECIDE_MAX)

		"fire", _:
			# Standard fire mode
			# Use knowledge to inform target selection
			if knowledge.size() > 0:
				var priority_order = knowledge[0].get("content", {}).get("priority_order", [])
				if "damaged_enemies" in priority_order:
					for opp in crew_data.awareness.opportunities:
						if opp.get("status", "") in ["damaged", "disabled"]:
							target = opp
							break

			decision = _create_fire_decision_with_mode(updated, target.id, "fire", game_time)

			# Gatling gun behavior: if multiple targets in range, fire frequently
			var target_count = crew_data.awareness.opportunities.size()
			if target_count >= MULTI_TARGET_THRESHOLD:
				updated.next_decision_time = game_time + MULTI_TARGET_REDECIDE_DELAY
			else:
				updated.next_decision_time = game_time + randf_range(HOLD_REDECIDE_MIN, HOLD_REDECIDE_MAX)

	updated.orders.current = decision
	return {"crew_data": updated, "decision": decision}


## Select gunner action from knowledge
static func _select_action_from_knowledge(knowledge: Array, crew_data: Dictionary) -> String:
	var action = "fire"  # Default

	if knowledge.is_empty():
		return action

	# Check ammo status (TODO: get from ship data)
	var is_low_ammo = false

	# Check target count
	var target_count = crew_data.awareness.opportunities.size()

	for k in knowledge:
		var suggested_action = k.get("content", {}).get("action", "")
		var subtype = k.get("content", {}).get("subtype", "")

		if suggested_action == "hold_fire":
			if is_low_ammo:
				return "hold_fire"

		elif suggested_action == "fire":
			if subtype == "suppressive_fire" and target_count >= SUPPRESSIVE_TARGET_COUNT_THRESHOLD:
				return "suppressive_fire"
			elif subtype == "precision_shot":
				return "precision_shot"

	return action


## Select best target for precision shooting
static func _select_best_target(crew_data: Dictionary) -> Dictionary:
	var best_target = {}
	var best_score = -1.0

	for opp in crew_data.awareness.opportunities:
		var score = 0.0

		# Prefer damaged targets
		if opp.get("status", "") in ["damaged", "disabled", "critical"]:
			score += DAMAGED_TARGET_BONUS

		# Prefer closer targets
		var distance = opp.get("distance", DEFAULT_TARGET_DISTANCE)
		score += max(0, DISTANCE_SCORE_MAX - distance / DISTANCE_SCORE_DIVISOR)

		# Prefer high-value targets
		var target_type = opp.get("type", "")
		if target_type in ["capital", "corvette"]:
			score += HIGH_VALUE_TARGET_BONUS

		if score > best_score:
			best_score = score
			best_target = opp

	return best_target if not best_target.is_empty() else crew_data.awareness.opportunities[0]


## Create fire decision with mode
static func _create_fire_decision_with_mode(crew_data: Dictionary, target_id: String, mode: String, game_time: float) -> Dictionary:
	return {
		"type": "fire",
		"subtype": mode,
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": target_id,
		"skill_factor": CrewAISystem.calculate_effective_skill(crew_data),
		"delay": crew_data.stats.reaction_time,
		"timestamp": game_time
	}


## Create hold fire decision
static func _create_hold_fire_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "fire",
		"subtype": "hold_fire",
		"crew_id": crew_data.crew_id,
		"entity_id": crew_data.assigned_to,
		"target_id": "",
		"skill_factor": CrewAISystem.calculate_effective_skill(crew_data),
		"delay": 0.0,
		"timestamp": game_time
	}
