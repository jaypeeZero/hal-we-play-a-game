class_name TacticalKnowledgeSystem
extends RefCounted

## Pure functional tactical knowledge system
## Provides BM25-style knowledge retrieval for crew decision-making
## Knowledge base can be extended with real battle data later

# ============================================================================
# PERFORMANCE CACHE
# ============================================================================

# PERFORMANCE TOGGLE - Set to false to disable knowledge queries entirely
static var enable_knowledge_queries: bool = false  # DISABLED by default

# Query cache to avoid re-computing same queries
static var _query_cache: Dictionary = {}
const MAX_CACHE_SIZE = 50  # Keep cache small

# ============================================================================
# KNOWLEDGE BASE - Placeholder tactical patterns
# ============================================================================

## Pre-loaded tactical knowledge patterns
## User can replace with real data later
static var knowledge_base = {
	# PILOTING KNOWLEDGE
	"pilot_evasive_close_threat": {
		"role": CrewData.Role.PILOT,
		"tags": ["piloting", "evasion", "combat"],
		"text": "close enemy threat incoming fire evade dodge maneuver threat",
		"content": {
			"action": "evasive_maneuver",
			"maneuver_types": ["zigzag", "perpendicular_burn", "random_jink"],
			"priority": "immediate"
		}
	},

	"pilot_pursuit_damaged": {
		"role": CrewData.Role.PILOT,
		"tags": ["piloting", "pursuit", "opportunity"],
		"text": "damaged enemy disabled pursuit chase intercept opportunity",
		"content": {
			"action": "pursue_target",
			"approach": "direct_intercept",
			"caution": "watch_for_escorts"
		}
	},

	"pilot_maintain_formation": {
		"role": CrewData.Role.PILOT,
		"tags": ["piloting", "formation", "coordination"],
		"text": "formation position squadron maintain spacing coordinate",
		"content": {
			"action": "maintain_formation",
			"adjustments": ["match_speed", "align_heading"],
			"benefits": ["mutual_support", "coordinated_attack"]
		}
	},

	"pilot_obstacle_avoidance": {
		"role": CrewData.Role.PILOT,
		"tags": ["piloting", "navigation", "safety"],
		"text": "obstacle debris asteroid collision avoid navigate",
		"content": {
			"action": "avoid_obstacle",
			"maneuvers": ["lateral_shift", "course_correction"],
			"detection": "sensor_sweep"
		}
	},

	# GUNNER KNOWLEDGE
	"gunner_priority_targets": {
		"role": CrewData.Role.GUNNER,
		"tags": ["gunnery", "targeting", "priority"],
		"text": "target priority damaged disabled threat select",
		"content": {
			"action": "prioritize_targets",
			"priority_order": ["damaged_enemies", "close_threats", "high_value"],
			"reasoning": "finish_weak_first"
		}
	},

	"gunner_lead_target": {
		"role": CrewData.Role.GUNNER,
		"tags": ["gunnery", "targeting", "accuracy"],
		"text": "lead target moving velocity predict intercept aim",
		"content": {
			"action": "calculate_lead",
			"factors": ["target_velocity", "projectile_speed", "distance"],
			"technique": "predictive_fire"
		}
	},

	"gunner_conserve_ammo": {
		"role": CrewData.Role.GUNNER,
		"tags": ["gunnery", "resources", "discipline"],
		"text": "ammo low conserve fire discipline range",
		"content": {
			"action": "fire_discipline",
			"triggers": ["low_ammo", "uncertain_hit"],
			"guidance": "wait_for_clear_shot"
		}
	},

	# CAPTAIN KNOWLEDGE
	"captain_concentrate_fire": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "coordination", "combat"],
		"text": "damaged enemy focus fire concentrate destroy finish",
		"content": {
			"action": "concentrate_fire",
			"reasoning": "eliminate_one_threat_completely",
			"orders": ["all_weapons_one_target"]
		}
	},

	"captain_withdraw_damaged": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "survival", "retreat"],
		"text": "heavy damage disabled critical withdraw retreat",
		"content": {
			"action": "tactical_withdrawal",
			"conditions": ["critical_damage", "outnumbered"],
			"execution": ["evasive_course", "request_cover"]
		}
	},

	"captain_defensive_posture": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "defense", "positioning"],
		"text": "outnumbered superior enemy defensive protect armor",
		"content": {
			"action": "defensive_stance",
			"tactics": ["angle_armor", "limit_exposure"],
			"goal": "survive_until_reinforcements"
		}
	},

	"captain_aggressive_pursuit": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "offense", "pursuit"],
		"text": "fleeing enemy damaged pursuit press attack",
		"content": {
			"action": "aggressive_pursuit",
			"execution": ["full_speed", "continuous_fire"],
			"warning": "watch_for_ambush"
		}
	},

	# SQUADRON LEADER KNOWLEDGE
	"squadron_leader_target_assignment": {
		"role": CrewData.Role.SQUADRON_LEADER,
		"tags": ["squadron", "coordination", "targeting"],
		"text": "multiple targets squadron assign distribute coordinate",
		"content": {
			"action": "assign_targets",
			"strategy": "one_ship_per_target",
			"benefit": "prevent_overkill"
		}
	},

	"squadron_leader_mutual_support": {
		"role": CrewData.Role.SQUADRON_LEADER,
		"tags": ["squadron", "support", "coordination"],
		"text": "ship damaged support cover protect squadron",
		"content": {
			"action": "provide_mutual_support",
			"tactics": ["cover_damaged_ships", "screen_withdrawal"],
			"principle": "no_ship_left_behind"
		}
	},

	"squadron_leader_formation": {
		"role": CrewData.Role.SQUADRON_LEADER,
		"tags": ["squadron", "formation", "tactics"],
		"text": "formation scattered regroup coordinate position",
		"content": {
			"action": "reform_squadron",
			"formations": ["line_abreast", "wedge", "wall"],
			"benefit": "coordinated_firepower"
		}
	},

	# FLEET COMMANDER KNOWLEDGE
	"commander_concentration_force": {
		"role": CrewData.Role.FLEET_COMMANDER,
		"tags": ["strategy", "fleet", "concentration"],
		"text": "fleet concentration superior numbers focus mass",
		"content": {
			"principle": "concentration_of_force",
			"execution": ["mass_at_decisive_point", "defeat_in_detail"],
			"doctrine": "never_divide_fleet"
		}
	},

	"commander_strategic_withdrawal": {
		"role": CrewData.Role.FLEET_COMMANDER,
		"tags": ["strategy", "fleet", "retreat"],
		"text": "losses heavy fleet preserve strategic withdraw",
		"content": {
			"action": "strategic_withdrawal",
			"conditions": ["unsustainable_losses", "objective_failed"],
			"priority": "preserve_combat_power"
		}
	}
}

# ============================================================================
# BM25 IMPLEMENTATION - Lightweight text similarity
# ============================================================================

## Query knowledge base for relevant patterns
## Returns array of matches sorted by relevance
static func query_knowledge(situation: String, role: int, top_k: int = 3) -> Array:
	# PERFORMANCE: Skip if disabled
	if not enable_knowledge_queries:
		return []

	if situation.is_empty():
		return []

	# Check cache first
	var cache_key = str(situation) + "_" + str(role) + "_" + str(top_k)
	if _query_cache.has(cache_key):
		return _query_cache[cache_key]

	var scored_patterns = []

	# Score each pattern
	for pattern_id in knowledge_base:
		var pattern = knowledge_base[pattern_id]

		# Filter by role (or include general patterns)
		if pattern.role != role:
			continue

		var score = calculate_relevance_score(situation, pattern)
		if score > 0.0:
			scored_patterns.append({
				"pattern_id": pattern_id,
				"score": score,
				"content": pattern.content,
				"tags": pattern.tags
			})

	# Sort by score descending
	scored_patterns.sort_custom(func(a, b): return a.score > b.score)

	# Return top K
	var result = scored_patterns.slice(0, min(top_k, scored_patterns.size()))

	# Cache result (limit cache size)
	if _query_cache.size() >= MAX_CACHE_SIZE:
		_query_cache.clear()  # Simple cache eviction
	_query_cache[cache_key] = result

	return result

## Calculate relevance score between query and pattern
## Simple BM25-style scoring: term matching with tag boosting
static func calculate_relevance_score(query: String, pattern: Dictionary) -> float:
	var query_terms = tokenize(query)
	var pattern_terms = tokenize(pattern.text)

	if query_terms.is_empty():
		return 0.0

	# Count matching terms
	var matches = 0
	for term in query_terms:
		if term in pattern_terms:
			matches += 1

	# Base score: match ratio
	var base_score = float(matches) / float(query_terms.size())

	# Tag boost: if query contains pattern tags, boost relevance
	var tag_boost = 1.0
	for tag in pattern.tags:
		if tag in query.to_lower():
			tag_boost += 0.3

	return base_score * tag_boost

## Tokenize text into lowercase words
static func tokenize(text: String) -> Array:
	return text.to_lower().split(" ", false)

# ============================================================================
# CONVENIENCE QUERIES BY ROLE
# ============================================================================

## Query knowledge for pilot situations
static func query_pilot_knowledge(situation: String, top_k: int = 2) -> Array:
	return query_knowledge(situation, CrewData.Role.PILOT, top_k)

## Query knowledge for gunner situations
static func query_gunner_knowledge(situation: String, top_k: int = 2) -> Array:
	return query_knowledge(situation, CrewData.Role.GUNNER, top_k)

## Query knowledge for captain situations
static func query_captain_knowledge(situation: String, top_k: int = 2) -> Array:
	return query_knowledge(situation, CrewData.Role.CAPTAIN, top_k)

## Query knowledge for squadron leader situations
static func query_squadron_knowledge(situation: String, top_k: int = 2) -> Array:
	return query_knowledge(situation, CrewData.Role.SQUADRON_LEADER, top_k)

## Query knowledge for fleet commander situations
static func query_commander_knowledge(situation: String, top_k: int = 2) -> Array:
	return query_knowledge(situation, CrewData.Role.FLEET_COMMANDER, top_k)

# ============================================================================
# KNOWLEDGE BASE EXTENSION (for later use)
# ============================================================================

## Add new knowledge pattern to database
## Returns updated knowledge base
static func add_knowledge_pattern(pattern_id: String, role: int, tags: Array, text: String, content: Dictionary) -> void:
	knowledge_base[pattern_id] = {
		"role": role,
		"tags": tags,
		"text": text,
		"content": content
	}

## Get all patterns for a specific role
static func get_patterns_for_role(role: int) -> Array:
	var patterns = []
	for pattern_id in knowledge_base:
		var pattern = knowledge_base[pattern_id]
		if pattern.role == role:
			patterns.append({
				"id": pattern_id,
				"pattern": pattern
			})
	return patterns

## Get pattern by ID
static func get_pattern(pattern_id: String) -> Dictionary:
	return knowledge_base.get(pattern_id, {})
