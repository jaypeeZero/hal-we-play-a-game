class_name TacticalMemorySystem
extends RefCounted

## Pure functional tactical memory system
## Manages crew learning from battle events and decision outcomes
## Updates tactical memory and generates situation summaries for knowledge queries

# ============================================================================
# CONFIGURATION
# ============================================================================

const MAX_RECENT_EVENTS = 10  # How many events to track per crew
const SITUATION_UPDATE_INTERVAL = 1.0  # Seconds between situation updates

# ============================================================================
# MEMORY UPDATE - Main API
# ============================================================================

## Update all crew tactical memory with recent events
static func update_all_crew_memory(crew_list: Array, recent_events: Array, game_time: float) -> Array:
	return crew_list.map(func(crew):
		return update_crew_memory(crew, recent_events, game_time))

## Update single crew member's tactical memory
static func update_crew_memory(crew_data: Dictionary, recent_events: Array, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Filter events relevant to this crew
	var relevant_events = filter_relevant_events(crew_data, recent_events)

	# Update recent events list (keep last N)
	updated.awareness.tactical_memory.recent_events = add_to_recent_events(
		crew_data.awareness.tactical_memory.recent_events,
		relevant_events
	)

	# Generate current situation summary
	updated.awareness.tactical_memory.current_situation = generate_situation_summary(updated)

	return updated

## Record a single event to crew memory (EVENT-DRIVEN)
static func record_event(crew_data: Dictionary, event: Dictionary) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Add event to recent events
	updated.awareness.tactical_memory.recent_events.append(event)

	# Keep only last N events
	if updated.awareness.tactical_memory.recent_events.size() > MAX_RECENT_EVENTS:
		updated.awareness.tactical_memory.recent_events = \
			updated.awareness.tactical_memory.recent_events.slice(-MAX_RECENT_EVENTS, \
			updated.awareness.tactical_memory.recent_events.size())

	# Update situation summary
	updated.awareness.tactical_memory.current_situation = generate_situation_summary(updated)

	return updated

# ============================================================================
# DECISION OUTCOME TRACKING
# ============================================================================

## Record the outcome of a decision (success or failure)
static func record_decision_outcome(crew_data: Dictionary, decision: Dictionary, success: bool) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# Extract tactic identifier from decision
	var tactic_id = get_tactic_id_from_decision(decision)
	if tactic_id.is_empty():
		return updated  # No identifiable tactic

	# Update success/failure counters
	if success:
		var current = updated.awareness.tactical_memory.successful_tactics.get(tactic_id, 0)
		updated.awareness.tactical_memory.successful_tactics[tactic_id] = current + 1
	else:
		var current = updated.awareness.tactical_memory.failed_tactics.get(tactic_id, 0)
		updated.awareness.tactical_memory.failed_tactics[tactic_id] = current + 1

	return updated

## Get success rate for a specific tactic
static func get_tactic_success_rate(crew_data: Dictionary, tactic_id: String) -> float:
	var successes = crew_data.awareness.tactical_memory.successful_tactics.get(tactic_id, 0)
	var failures = crew_data.awareness.tactical_memory.failed_tactics.get(tactic_id, 0)

	var total = successes + failures
	if total == 0:
		return 0.5  # Unknown tactic, assume 50% success rate

	return float(successes) / float(total)

## Check if a tactic has been tried before
static func has_tried_tactic(crew_data: Dictionary, tactic_id: String) -> bool:
	return crew_data.awareness.tactical_memory.successful_tactics.has(tactic_id) or \
		   crew_data.awareness.tactical_memory.failed_tactics.has(tactic_id)

# ============================================================================
# SITUATION SUMMARY GENERATION
# ============================================================================

## Generate text summary of current situation for knowledge queries
static func generate_situation_summary(crew_data: Dictionary) -> String:
	var parts = []

	# Role-specific context
	parts.append(_get_role_context(crew_data.role))

	# Threat assessment
	if not crew_data.awareness.threats.is_empty():
		parts.append(_generate_threat_summary(crew_data.awareness.threats))

	# Opportunity assessment
	if not crew_data.awareness.opportunities.is_empty():
		parts.append(_generate_opportunity_summary(crew_data.awareness.opportunities))

	# Recent events context
	if not crew_data.awareness.tactical_memory.recent_events.is_empty():
		parts.append(_generate_event_summary(crew_data.awareness.tactical_memory.recent_events))

	# Current orders context
	if crew_data.orders.current != null:
		parts.append(_generate_order_summary(crew_data.orders.current))

	return " ".join(parts)

## Get role-specific context keywords
static func _get_role_context(role: int) -> String:
	match role:
		CrewData.Role.PILOT:
			return "piloting navigation"
		CrewData.Role.GUNNER:
			return "gunnery targeting"
		CrewData.Role.CAPTAIN:
			return "tactics coordination"
		CrewData.Role.SQUADRON_LEADER:
			return "squadron formation"
		CrewData.Role.FLEET_COMMANDER:
			return "strategy fleet"
		_:
			return ""

## Generate summary of threats
static func _generate_threat_summary(threats: Array) -> String:
	if threats.is_empty():
		return ""

	var parts = []

	# Count threats
	if threats.size() > 3:
		parts.append("multiple threats")
	elif threats.size() > 1:
		parts.append("threats")
	else:
		parts.append("threat")

	# Check for close threats (high priority)
	var top_threat = threats[0]
	if top_threat.get("_threat_priority", 0.0) > 150.0:
		parts.append("close enemy")
		parts.append("immediate danger")
	elif top_threat.get("_threat_priority", 0.0) > 100.0:
		parts.append("incoming")

	# Threat types
	if top_threat.get("type") == "projectile":
		parts.append("incoming fire")
	elif top_threat.get("type") == "ship":
		parts.append("enemy ship")

	return " ".join(parts)

## Generate summary of opportunities
static func _generate_opportunity_summary(opportunities: Array) -> String:
	if opportunities.is_empty():
		return ""

	var parts = []

	# Check for high-value opportunities
	var top_opp = opportunities[0]
	if top_opp.get("status") == "disabled":
		parts.append("disabled enemy")
		parts.append("opportunity")
	elif top_opp.get("status") == "damaged":
		parts.append("damaged enemy")
		parts.append("target")
	else:
		parts.append("enemy")
		parts.append("target")

	return " ".join(parts)

## Generate summary of recent events
static func _generate_event_summary(events: Array) -> String:
	if events.is_empty():
		return ""

	var parts = []
	var event_types = {}

	# Count event types
	for event in events:
		var etype = event.get("type", "")
		event_types[etype] = event_types.get(etype, 0) + 1

	# Summarize dominant event types
	if event_types.get("damage_dealt", 0) > 2:
		parts.append("under fire")
	if event_types.get("projectile_fired", 0) > 2:
		parts.append("combat")

	return " ".join(parts)

## Generate summary of current orders
static func _generate_order_summary(order: Dictionary) -> String:
	var order_type = order.get("type", "")
	var subtype = order.get("subtype", "")

	match order_type:
		"maneuver":
			if subtype == "evade":
				return "evasion"
			elif subtype == "pursue":
				return "pursuit"
		"fire":
			return "engaging"
		"tactical":
			if subtype == "engage":
				return "attack"
			elif subtype == "withdraw":
				return "retreat"

	return ""

# ============================================================================
# EVENT FILTERING
# ============================================================================

## Filter events relevant to this crew member
static func filter_relevant_events(crew_data: Dictionary, all_events: Array) -> Array:
	# For now, include all events
	# Later can filter by: events involving their ship, nearby events, etc.
	return all_events

## Add new events to recent events list (keep last N)
static func add_to_recent_events(current_events: Array, new_events: Array) -> Array:
	var combined = current_events + new_events

	# Keep only last N events
	if combined.size() > MAX_RECENT_EVENTS:
		return combined.slice(combined.size() - MAX_RECENT_EVENTS, combined.size())

	return combined

# ============================================================================
# DECISION TACTIC EXTRACTION
# ============================================================================

## Extract tactic identifier from decision
static func get_tactic_id_from_decision(decision: Dictionary) -> String:
	var decision_type = decision.get("type", "")
	var subtype = decision.get("subtype", "")

	# Build tactic ID from decision type and subtype
	if not subtype.is_empty():
		return decision_type + "_" + subtype
	else:
		return decision_type

# ============================================================================
# MEMORY QUERIES
# ============================================================================

## Get most successful tactics for this crew
static func get_top_successful_tactics(crew_data: Dictionary, top_k: int = 3) -> Array:
	var tactics = []

	for tactic_id in crew_data.awareness.tactical_memory.successful_tactics:
		var success_count = crew_data.awareness.tactical_memory.successful_tactics[tactic_id]
		var success_rate = get_tactic_success_rate(crew_data, tactic_id)

		tactics.append({
			"tactic_id": tactic_id,
			"success_count": success_count,
			"success_rate": success_rate
		})

	# Sort by success rate, then by count
	tactics.sort_custom(func(a, b):
		if abs(a.success_rate - b.success_rate) < 0.1:
			return a.success_count > b.success_count
		return a.success_rate > b.success_rate
	)

	return tactics.slice(0, min(top_k, tactics.size()))

## Get tactics to avoid (low success rate)
static func get_tactics_to_avoid(crew_data: Dictionary, threshold: float = 0.3) -> Array:
	var bad_tactics = []

	# Check all tactics tried
	var all_tactics = {}
	for tactic in crew_data.awareness.tactical_memory.successful_tactics:
		all_tactics[tactic] = true
	for tactic in crew_data.awareness.tactical_memory.failed_tactics:
		all_tactics[tactic] = true

	# Find low success rate tactics
	for tactic_id in all_tactics:
		var success_rate = get_tactic_success_rate(crew_data, tactic_id)
		if success_rate < threshold:
			bad_tactics.append({
				"tactic_id": tactic_id,
				"success_rate": success_rate
			})

	return bad_tactics

## Check if crew has enough experience to trust their memory
static func has_sufficient_experience(crew_data: Dictionary, min_decisions: int = 5) -> bool:
	var total_decisions = 0

	for tactic_id in crew_data.awareness.tactical_memory.successful_tactics:
		total_decisions += crew_data.awareness.tactical_memory.successful_tactics[tactic_id]

	for tactic_id in crew_data.awareness.tactical_memory.failed_tactics:
		total_decisions += crew_data.awareness.tactical_memory.failed_tactics[tactic_id]

	return total_decisions >= min_decisions

# ============================================================================
# DEBUGGING / ANALYSIS
# ============================================================================

## Get memory statistics for crew member
static func get_memory_stats(crew_data: Dictionary) -> Dictionary:
	var total_successes = 0
	var total_failures = 0
	var unique_tactics = {}

	for tactic in crew_data.awareness.tactical_memory.successful_tactics:
		total_successes += crew_data.awareness.tactical_memory.successful_tactics[tactic]
		unique_tactics[tactic] = true

	for tactic in crew_data.awareness.tactical_memory.failed_tactics:
		total_failures += crew_data.awareness.tactical_memory.failed_tactics[tactic]
		unique_tactics[tactic] = true

	var total = total_successes + total_failures
	var overall_success_rate = 0.0
	if total > 0:
		overall_success_rate = float(total_successes) / float(total)

	return {
		"total_decisions": total,
		"total_successes": total_successes,
		"total_failures": total_failures,
		"overall_success_rate": overall_success_rate,
		"unique_tactics_tried": unique_tactics.size(),
		"recent_events_count": crew_data.awareness.tactical_memory.recent_events.size()
	}
