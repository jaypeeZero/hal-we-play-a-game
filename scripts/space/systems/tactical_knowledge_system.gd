class_name TacticalKnowledgeSystem
extends RefCounted

## Pure functional tactical knowledge system
## Provides BM25-style knowledge retrieval for crew decision-making
## Knowledge base can be extended with real battle data later

# ============================================================================
# PERFORMANCE CACHE
# ============================================================================

# PERFORMANCE TOGGLE - Set to false to disable knowledge queries entirely
static var enable_knowledge_queries: bool = true  # Enabled for testing

# Query cache to avoid re-computing same queries
static var _query_cache: Dictionary = {}
const MAX_CACHE_SIZE = 50  # Keep cache small

# ============================================================================
# KNOWLEDGE BASE - Placeholder tactical patterns
# ============================================================================

## Pre-loaded tactical knowledge patterns
## User can replace with real data later
static var knowledge_base = {
	# ============================================================================
	# FIGHTER-SPECIFIC KNOWLEDGE - Maps directly to FighterPilotAI maneuvers
	# ============================================================================

	# Fighter vs Fighter - Far Range
	"fighter_approach_far": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "approach", "far", "pursuit"],
		"text": "fighter fighter far range approach closing pursuit intercept distance solo neutral",
		"content": {
			"maneuvers": ["fight_pursue_full_speed"],
			"skill_requirements": {"fight_pursue_full_speed": 0.0},
			"priority": "normal",
			"context": "Close distance quickly at far range vs fighter"
		}
	},

	# Fighter vs Fighter - Mid Range, Not Behind
	"fighter_flank_mid": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "flank", "mid", "tactical", "positioning"],
		"text": "fighter mid range flank behind position tactical maneuver angle",
		"content": {
			"maneuvers": ["fight_flank_behind", "fight_pursue_tactical", "fight_pursue_full_speed"],
			"skill_requirements": {"fight_flank_behind": 0.6, "fight_pursue_tactical": 0.3, "fight_pursue_full_speed": 0.0},
			"priority": "tactical",
			"context": "Get behind enemy at mid range"
		}
	},

	# Fighter vs Fighter - Mid Range, Behind Enemy
	"fighter_tactical_pursuit_mid": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "pursuit", "mid", "behind", "advantage"],
		"text": "fighter mid range behind advantage pursuit tactical closing",
		"content": {
			"maneuvers": ["fight_pursue_tactical", "fight_pursue_full_speed"],
			"skill_requirements": {"fight_pursue_tactical": 0.3, "fight_pursue_full_speed": 0.0},
			"priority": "aggressive",
			"context": "Press advantage when behind at mid range"
		}
	},

	# Fighter vs Fighter - Close Range, Behind Enemy
	"fighter_dogfight_close_behind": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "dogfight", "close", "behind", "advantage", "engage"],
		"text": "fighter close range behind advantage dogfight tight pursuit engage kill",
		"content": {
			"maneuvers": ["fight_tight_pursuit", "fight_dogfight_maneuver"],
			"skill_requirements": {"fight_tight_pursuit": 0.3, "fight_dogfight_maneuver": 0.0},
			"priority": "aggressive",
			"context": "Maintain firing position when behind at close range"
		}
	},

	# Fighter vs Fighter - Close Range, Not Behind
	"fighter_dogfight_close_neutral": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "dogfight", "close", "neutral", "maneuver"],
		"text": "fighter close range dogfight maneuver turning fight neutral",
		"content": {
			"maneuvers": ["fight_dogfight_maneuver", "fight_flank_behind"],
			"skill_requirements": {"fight_dogfight_maneuver": 0.0, "fight_flank_behind": 0.6},
			"priority": "tactical",
			"context": "Outmaneuver enemy to gain advantage"
		}
	},

	# Fighter vs Fighter - Disadvantaged (Enemy Behind Me)
	"fighter_evasive_disadvantaged": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "evasion", "disadvantaged", "defensive", "threat", "behind"],
		"text": "fighter enemy behind disadvantaged evade defensive break threat danger",
		"content": {
			"maneuvers": ["fight_defensive_break", "fight_evasive_turn", "fight_pursue_full_speed"],
			"skill_requirements": {"fight_defensive_break": 0.6, "fight_evasive_turn": 0.3, "fight_pursue_full_speed": 0.0},
			"composure_requirements": {"fight_defensive_break": 0.6, "fight_evasive_turn": 0.3, "fight_pursue_full_speed": 0.0},
			"priority": "immediate",
			"context": "Shake enemy from your tail"
		}
	},

	# Fighter vs Fighter - Collision Course
	"fighter_collision_avoidance": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "collision", "head_on", "break", "avoidance"],
		"text": "fighter collision head on break lateral avoid crash closing fast",
		"content": {
			"maneuvers": ["fight_lateral_break", "fight_evasive_turn"],
			"skill_requirements": {"fight_lateral_break": 0.6, "fight_evasive_turn": 0.0},
			"priority": "immediate",
			"context": "Avoid head-on collision"
		}
	},

	# Fighter vs Capital - Solo/Small Group, Far
	"fighter_capital_cautious_approach": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "capital", "corvette", "approach", "cautious", "far"],
		"text": "fighter capital corvette far approach cautious careful bigship",
		"content": {
			"maneuvers": ["fight_cautious_approach"],
			"skill_requirements": {"fight_cautious_approach": 0.0},
			"priority": "tactical",
			"context": "Careful approach to capital ship"
		}
	},

	# Fighter vs Capital - Solo/Small Group, At Range
	"fighter_capital_harass": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "capital", "corvette", "harass", "dodge", "weave"],
		"text": "fighter capital corvette harass dodge weave range potshot",
		"content": {
			"maneuvers": ["fight_dodge_and_weave"],
			"skill_requirements": {"fight_dodge_and_weave": 0.0},
			"priority": "tactical",
			"context": "Harass capital ship from safe distance"
		}
	},

	# Fighter vs Capital - Solo/Small Group, Too Close
	"fighter_capital_retreat": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "capital", "corvette", "retreat", "evade", "close", "danger"],
		"text": "fighter capital corvette too close retreat evade danger escape",
		"content": {
			"maneuvers": ["fight_evasive_retreat"],
			"skill_requirements": {"fight_evasive_retreat": 0.0},
			"priority": "immediate",
			"context": "Get away from capital ship"
		}
	},

	# Fighter vs Capital - Group Attack Approach
	"fighter_capital_group_approach": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "capital", "group", "coordinated", "approach", "run"],
		"text": "fighter capital group coordinated approach attack run formation",
		"content": {
			"maneuvers": ["fight_group_run_approach"],
			"skill_requirements": {"fight_group_run_approach": 0.0},
			"context_requirements": {"nearby_fighters": 4},
			"priority": "tactical",
			"context": "Coordinate group attack run on capital"
		}
	},

	# Fighter vs Capital - Group Attack Execute
	"fighter_capital_group_attack": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "capital", "group", "attack", "run", "strike"],
		"text": "fighter capital group attack run strike execute fire",
		"content": {
			"maneuvers": ["fight_group_run_attack"],
			"skill_requirements": {"fight_group_run_attack": 0.0},
			"context_requirements": {"nearby_fighters": 4},
			"priority": "aggressive",
			"context": "Execute attack run on capital"
		}
	},

	# Fighter vs Capital - Group Swing Around
	"fighter_capital_group_reposition": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "capital", "group", "reposition", "swing", "around"],
		"text": "fighter capital group swing around reposition another run",
		"content": {
			"maneuvers": ["fight_group_run_swing_around"],
			"skill_requirements": {"fight_group_run_swing_around": 0.0},
			"context_requirements": {"nearby_fighters": 4},
			"priority": "tactical",
			"context": "Reposition for another attack run"
		}
	},

	# Wing Formation - Rejoin Lead
	"fighter_wing_rejoin": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "wing", "formation", "rejoin", "lead"],
		"text": "fighter wing formation rejoin lead broken separated",
		"content": {
			"maneuvers": ["fight_wing_rejoin"],
			"skill_requirements": {"fight_wing_rejoin": 0.0},
			"priority": "high",
			"context": "Rejoin wing lead when separated"
		}
	},

	# Wing Formation - Follow Lead
	"fighter_wing_follow": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "wing", "formation", "follow", "maintain"],
		"text": "fighter wing formation follow lead maintain position",
		"content": {
			"maneuvers": ["fight_wing_follow"],
			"skill_requirements": {"fight_wing_follow": 0.0},
			"priority": "normal",
			"context": "Maintain formation with wing lead"
		}
	},

	# Wing Formation - Engage with Lead
	"fighter_wing_engage": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "wing", "formation", "engage", "target", "coordinated"],
		"text": "fighter wing formation engage target lead coordinated attack",
		"content": {
			"maneuvers": ["fight_wing_engage"],
			"skill_requirements": {"fight_wing_engage": 0.0},
			"priority": "aggressive",
			"context": "Engage target while maintaining wing formation"
		}
	},

	# Legacy Wingman Rejoin
	"fighter_rejoin_wingman": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "wingman", "rejoin", "formation", "pair"],
		"text": "fighter wingman rejoin formation pair broken separated",
		"content": {
			"maneuvers": ["fight_rejoin_wingman"],
			"skill_requirements": {"fight_rejoin_wingman": 0.0},
			"priority": "high",
			"context": "Rejoin wingman pair"
		}
	},

	# Idle/Patrol
	"fighter_idle_patrol": {
		"role": CrewData.Role.PILOT,
		"tags": ["fighter", "idle", "patrol", "scan", "no_target"],
		"text": "fighter idle patrol scan no target waiting",
		"content": {
			"maneuvers": ["idle"],
			"skill_requirements": {"idle": 0.0},
			"priority": "low",
			"context": "No targets, patrol and scan"
		}
	},

	# ============================================================================
	# LARGE SHIP PILOT KNOWLEDGE - Corvette and Capital tactics
	# ============================================================================

	"large_ship_vs_fighters_close": {
		"role": CrewData.Role.PILOT,
		"tags": ["corvette", "capital", "fighters", "close", "kite"],
		"text": "corvette capital fighters close kite back away maintain distance",
		"content": {
			"maneuvers": ["large_ship_kite", "large_ship_broadside"],
			"skill_requirements": {"large_ship_kite": 0.3, "large_ship_broadside": 0.0},
			"priority": "defensive",
			"context": "Back away from fighters, maintain turret range"
		}
	},

	"large_ship_vs_fighters_mid": {
		"role": CrewData.Role.PILOT,
		"tags": ["corvette", "capital", "fighters", "mid", "broadside"],
		"text": "corvette capital fighters mid range broadside turrets",
		"content": {
			"maneuvers": ["large_ship_broadside", "large_ship_kite"],
			"skill_requirements": {"large_ship_broadside": 0.0, "large_ship_kite": 0.3},
			"priority": "tactical",
			"context": "Present broadside for maximum turret coverage"
		}
	},

	"large_ship_vs_fighters_far": {
		"role": CrewData.Role.PILOT,
		"tags": ["corvette", "capital", "fighters", "far", "approach"],
		"text": "corvette capital fighters far approach close distance",
		"content": {
			"maneuvers": ["large_ship_approach"],
			"skill_requirements": {"large_ship_approach": 0.0},
			"priority": "normal",
			"context": "Close distance to engagement range"
		}
	},

	"large_ship_vs_capital_close": {
		"role": CrewData.Role.PILOT,
		"tags": ["corvette", "capital", "close", "broadside", "firing"],
		"text": "corvette capital close range broadside firing solution",
		"content": {
			"maneuvers": ["large_ship_broadside", "large_ship_orbit"],
			"skill_requirements": {"large_ship_broadside": 0.0, "large_ship_orbit": 0.5},
			"priority": "aggressive",
			"context": "Maintain broadside firing position"
		}
	},

	"large_ship_vs_capital_far": {
		"role": CrewData.Role.PILOT,
		"tags": ["corvette", "capital", "far", "approach"],
		"text": "corvette capital far approach closing",
		"content": {
			"maneuvers": ["large_ship_approach"],
			"skill_requirements": {"large_ship_approach": 0.0},
			"priority": "normal",
			"context": "Close to engagement range"
		}
	},

	# ============================================================================
	# GENERAL PILOTING KNOWLEDGE (non-fighter specific)
	# ============================================================================

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

	# ============================================================================
	# GUNNER KNOWLEDGE - Expanded with specific actions
	# ============================================================================

	"gunner_priority_targets": {
		"role": CrewData.Role.GUNNER,
		"tags": ["gunnery", "targeting", "priority"],
		"text": "target priority damaged disabled threat select",
		"content": {
			"action": "fire",
			"subtype": "precision_shot",
			"priority_order": ["damaged_enemies", "close_threats", "high_value"],
			"reasoning": "finish_weak_first"
		}
	},

	"gunner_lead_target": {
		"role": CrewData.Role.GUNNER,
		"tags": ["gunnery", "targeting", "accuracy", "moving"],
		"text": "lead target moving velocity predict intercept aim",
		"content": {
			"action": "fire",
			"subtype": "precision_shot",
			"factors": ["target_velocity", "projectile_speed", "distance"],
			"technique": "predictive_fire"
		}
	},

	"gunner_conserve_ammo": {
		"role": CrewData.Role.GUNNER,
		"tags": ["gunnery", "resources", "discipline", "ammo", "low"],
		"text": "ammo low conserve fire discipline range wait",
		"content": {
			"action": "hold_fire",
			"triggers": ["low_ammo", "uncertain_hit"],
			"guidance": "wait_for_clear_shot"
		}
	},

	"gunner_suppressive_fire": {
		"role": CrewData.Role.GUNNER,
		"tags": ["gunnery", "suppression", "area", "multiple", "threats"],
		"text": "multiple targets suppressive fire area deny cover",
		"content": {
			"action": "fire",
			"subtype": "suppressive_fire",
			"reasoning": "area_denial",
			"rate": "high"
		}
	},

	"gunner_precision_shot": {
		"role": CrewData.Role.GUNNER,
		"tags": ["gunnery", "precision", "aim", "careful", "weak_point"],
		"text": "precision aim careful shot weak point critical",
		"content": {
			"action": "fire",
			"subtype": "precision_shot",
			"technique": "aimed_fire",
			"target": "weak_points"
		}
	},

	# ============================================================================
	# CAPTAIN KNOWLEDGE - Expanded with specific actions
	# ============================================================================

	"captain_concentrate_fire": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "coordination", "combat", "focus", "damage"],
		"text": "damaged enemy focus fire concentrate destroy finish",
		"content": {
			"action": "concentrate_fire",
			"reasoning": "eliminate_one_threat_completely",
			"orders": ["all_weapons_one_target"]
		}
	},

	"captain_withdraw_damaged": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "survival", "retreat", "damage", "critical"],
		"text": "heavy damage disabled critical withdraw retreat escape",
		"content": {
			"action": "withdraw",
			"conditions": ["critical_damage", "outnumbered"],
			"execution": ["evasive_course", "request_cover"]
		}
	},

	"captain_defensive_posture": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "defense", "positioning", "outnumbered"],
		"text": "outnumbered superior enemy defensive protect armor angle",
		"content": {
			"action": "defensive_posture",
			"tactics": ["angle_armor", "limit_exposure"],
			"goal": "survive_until_reinforcements"
		}
	},

	"captain_aggressive_pursuit": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "offense", "pursuit", "fleeing", "press"],
		"text": "fleeing enemy damaged pursuit press attack chase",
		"content": {
			"action": "aggressive_pursuit",
			"execution": ["full_speed", "continuous_fire"],
			"warning": "watch_for_ambush"
		}
	},

	"captain_support_ally": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "support", "ally", "cover", "protect"],
		"text": "ally damaged support cover protect friendly help",
		"content": {
			"action": "support_ally",
			"tactics": ["interpose", "draw_fire", "escort"],
			"priority": "protect_damaged_friendlies"
		}
	},

	"captain_flank_maneuver": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "flank", "maneuver", "positioning", "angle"],
		"text": "flank maneuver position angle weak side attack",
		"content": {
			"action": "flank",
			"goal": "attack_weak_arc",
			"execution": ["lateral_movement", "maintain_fire"]
		}
	},

	"captain_hold_position": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "hold", "position", "defensive", "wait"],
		"text": "hold position defensive wait maintain standby",
		"content": {
			"action": "hold",
			"conditions": ["awaiting_orders", "defensive_position"],
			"stance": "ready_to_engage"
		}
	},

	"captain_engage_target": {
		"role": CrewData.Role.CAPTAIN,
		"tags": ["tactics", "engage", "attack", "target", "combat"],
		"text": "engage attack target enemy combat pursue",
		"content": {
			"action": "engage",
			"execution": ["close_range", "weapons_free"],
			"priority": "destroy_target"
		}
	},

	# ============================================================================
	# SQUADRON LEADER KNOWLEDGE - Expanded with specific actions
	# ============================================================================

	"squadron_leader_target_assignment": {
		"role": CrewData.Role.SQUADRON_LEADER,
		"tags": ["squadron", "coordination", "targeting", "distribute"],
		"text": "multiple targets squadron assign distribute coordinate",
		"content": {
			"action": "assign_targets",
			"strategy": "one_ship_per_target",
			"benefit": "prevent_overkill"
		}
	},

	"squadron_leader_mutual_support": {
		"role": CrewData.Role.SQUADRON_LEADER,
		"tags": ["squadron", "support", "coordination", "protect", "damaged"],
		"text": "ship damaged support cover protect squadron help",
		"content": {
			"action": "call_mutual_support",
			"tactics": ["cover_damaged_ships", "screen_withdrawal"],
			"principle": "no_ship_left_behind"
		}
	},

	"squadron_leader_formation": {
		"role": CrewData.Role.SQUADRON_LEADER,
		"tags": ["squadron", "formation", "tactics", "regroup", "scattered"],
		"text": "formation scattered regroup coordinate position reform",
		"content": {
			"action": "reform_formation",
			"formations": ["line_abreast", "wedge", "wall"],
			"benefit": "coordinated_firepower"
		}
	},

	"squadron_leader_attack_run": {
		"role": CrewData.Role.SQUADRON_LEADER,
		"tags": ["squadron", "attack", "run", "coordinated", "strike"],
		"text": "coordinated attack run strike capital target synchronized",
		"content": {
			"action": "coordinate_attack_run",
			"target_type": "capital_ship",
			"execution": ["simultaneous_approach", "overwhelming_force"]
		}
	},

	"squadron_leader_screen_withdrawal": {
		"role": CrewData.Role.SQUADRON_LEADER,
		"tags": ["squadron", "screen", "withdrawal", "retreat", "cover"],
		"text": "screen withdrawal retreat cover escape protect",
		"content": {
			"action": "screen_withdrawal",
			"tactics": ["rearguard", "suppressive_fire"],
			"goal": "orderly_retreat"
		}
	},

	# ============================================================================
	# FLEET COMMANDER KNOWLEDGE - Expanded with specific actions
	# ============================================================================

	"commander_concentration_force": {
		"role": CrewData.Role.FLEET_COMMANDER,
		"tags": ["strategy", "fleet", "concentration", "mass", "decisive"],
		"text": "fleet concentration superior numbers focus mass decisive",
		"content": {
			"action": "concentrate_force",
			"execution": ["mass_at_decisive_point", "defeat_in_detail"],
			"doctrine": "never_divide_fleet"
		}
	},

	"commander_strategic_withdrawal": {
		"role": CrewData.Role.FLEET_COMMANDER,
		"tags": ["strategy", "fleet", "retreat", "preserve", "losses"],
		"text": "losses heavy fleet preserve strategic withdraw retreat",
		"content": {
			"action": "strategic_withdrawal",
			"conditions": ["unsustainable_losses", "objective_failed"],
			"priority": "preserve_combat_power"
		}
	},

	"commander_commit_reserves": {
		"role": CrewData.Role.FLEET_COMMANDER,
		"tags": ["strategy", "reserves", "commit", "reinforce", "decisive"],
		"text": "reserves commit reinforce decisive moment breakthrough",
		"content": {
			"action": "commit_reserves",
			"timing": "decisive_moment",
			"goal": "overwhelming_force"
		}
	},

	"commander_shift_focus": {
		"role": CrewData.Role.FLEET_COMMANDER,
		"tags": ["strategy", "focus", "shift", "priority", "redirect"],
		"text": "shift focus priority redirect fleet new target",
		"content": {
			"action": "shift_focus",
			"reasoning": "exploit_weakness",
			"execution": "redirect_squadrons"
		}
	},

	"commander_hold_line": {
		"role": CrewData.Role.FLEET_COMMANDER,
		"tags": ["strategy", "hold", "line", "defensive", "position"],
		"text": "hold line defensive position maintain fleet stand",
		"content": {
			"action": "hold_line",
			"conditions": ["defensive_battle", "awaiting_reinforcements"],
			"stance": "no_retreat"
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

	# Tag boost: if query contains pattern tags, add bonus (additive not multiplicative)
	var tag_bonus = 0.0
	for tag in pattern.tags:
		if tag in query.to_lower():
			tag_bonus += 0.2  # Each matching tag adds 0.2 to score

	return base_score + tag_bonus

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
