extends RefCounted
class_name SquadronLeaderAI

## Pure functional squadron leader role AI.
## Coordinates multiple ships - target assignment, mutual support, formation reform.

const REDECIDE_MIN = 1.5
const REDECIDE_MAX = 3.0

# Coordination thresholds
const COORDINATED_ATTACK_MIN_SUBORDINATES = 3
const SCATTERED_THRESHOLD = 2000.0  # Units between ships before squadron is "scattered"

# Failure rates by coordination style
const INDIVIDUAL_COORDINATION_FAIL_CHANCE = 0.4

# Skill-based assignment quality thresholds (mapped from WingConstants)
const HIGH_SKILL_THRESHOLD = 0.7
const MEDIUM_SKILL_THRESHOLD = 0.5

# Target priority scoring
const DAMAGED_TARGET_BONUS = 50.0
const THREATENING_TARGET_BONUS = 30.0
const DISTANCE_SCORE_MAX = 100.0
const DISTANCE_SCORE_DIVISOR = 20.0
const DEFAULT_TARGET_DISTANCE = 1000.0


## Public entry point - called by CrewAISystem dispatcher.
static func make_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	# SQUADRON PLAYS — try a coordinated multi-fighter maneuver before
	# falling through to the legacy assign-targets / mutual-support flow.
	# A play stays in flight across decisions; tick_squadron_play handles
	# selection, advancement, and replanning. If no play qualifies (rookie
	# leader, undersized wing, no target), we drop through unchanged.
	var play_result := _try_run_squadron_play(updated, game_time)
	if not play_result.is_empty():
		return play_result

	# Query knowledge for squadron guidance
	var situation = TacticalMemorySystem.generate_situation_summary(crew_data)
	var knowledge = TacticalKnowledgeSystem.query_squadron_knowledge(situation, 3, crew_data.get("known_patterns", []))

	# Analyze squadron situation
	var has_threats = not crew_data.awareness.threats.is_empty()
	var has_opportunities = not crew_data.awareness.opportunities.is_empty()
	var damaged_subordinate = _find_damaged_subordinate(crew_data)
	var is_scattered = _is_squadron_scattered(crew_data)

	# Select action based on knowledge
	var squadron_action = _select_action_from_knowledge(knowledge, crew_data, has_threats, has_opportunities, damaged_subordinate != null, is_scattered)

	var decision = null
	var orders = []

	match squadron_action:
		"assign_targets":
			orders = _assign_squadron_targets(crew_data)
			decision = {
				"type": "squadron_command",
				"subtype": "assign_targets",
				"crew_id": crew_data.crew_id,
				"assignments": orders,
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"call_mutual_support":
			orders = _create_mutual_support_orders(crew_data, damaged_subordinate)
			decision = {
				"type": "squadron_command",
				"subtype": "call_mutual_support",
				"crew_id": crew_data.crew_id,
				"protected_ship": damaged_subordinate.get("id", "") if damaged_subordinate else "",
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"reform_formation":
			orders = _create_reform_formation_orders(crew_data)
			decision = {
				"type": "squadron_command",
				"subtype": "reform_formation",
				"crew_id": crew_data.crew_id,
				"formation": "wedge",
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"coordinate_attack_run":
			var target = CrewAIShared.select_best_tactical_target(crew_data)
			orders = _create_coordinated_attack_orders(crew_data, target)
			decision = {
				"type": "squadron_command",
				"subtype": "coordinate_attack_run",
				"crew_id": crew_data.crew_id,
				"target_id": target.get("id", ""),
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

		"screen_withdrawal":
			orders = _create_screen_withdrawal_orders(crew_data)
			decision = {
				"type": "squadron_command",
				"subtype": "screen_withdrawal",
				"crew_id": crew_data.crew_id,
				"delay": CrewAISystem.calculate_decision_delay(crew_data),
				"timestamp": game_time
			}

	if decision:
		updated.orders.issued = orders
		updated.orders.current = decision
		updated.next_decision_time = game_time + randf_range(REDECIDE_MIN, REDECIDE_MAX)
		return {"crew_data": updated, "decision": decision}

	return {"crew_data": updated}


## Select squadron action from knowledge and COORDINATION STYLE
## INDIVIDUAL: Ships fight independently, no coordination
## LOOSE: Wingman pairing, mutual support, focus fire, tactical retreats
## ORCHESTRATED: Play-driven coordinated maneuvers (handled separately by
##               _try_run_squadron_play before this function runs)
static func _select_action_from_knowledge(knowledge: Array, crew_data: Dictionary, has_threats: bool, has_opportunities: bool, has_damaged_subordinate: bool, is_scattered: bool) -> String:
	var skill = CrewAISystem.calculate_effective_skill(crew_data)
	var coordination_style = CrewIntegrationSystem._select_coordination_style(skill)

	# Default action based on coordination level
	var action = "assign_targets" if has_opportunities else ""

	# INDIVIDUAL style (low skill) - ships fight on their own
	if coordination_style == CrewIntegrationSystem.CoordinationStyle.INDIVIDUAL:
		# Can only do basic target assignment, and poorly at that
		if has_opportunities:
			# Poor target assignment - may not even assign targets
			if randf() < INDIVIDUAL_COORDINATION_FAIL_CHANCE:
				return ""  # Fails to coordinate at all
			return "assign_targets"
		return ""

	# LOOSE style - mutual support, focus fire, retreats; everything short of
	# play-driven orchestration.
	if coordination_style == CrewIntegrationSystem.CoordinationStyle.LOOSE:
		if has_damaged_subordinate:
			return "call_mutual_support"
		if is_scattered and not has_threats:
			return "reform_formation"
		if has_threats and crew_data.awareness.threats.size() > crew_data.command_chain.subordinates.size():
			return "screen_withdrawal"
		if has_opportunities:
			return "assign_targets"
		return action

	# ORCHESTRATED style (elite) - uses all tactics from knowledge
	if knowledge.is_empty():
		# Even without knowledge, orchestrated leaders make good choices
		if has_damaged_subordinate:
			return "call_mutual_support"
		if has_opportunities and crew_data.command_chain.subordinates.size() >= COORDINATED_ATTACK_MIN_SUBORDINATES:
			return "coordinate_attack_run"
		return action

	for k in knowledge:
		var suggested_action = k.get("content", {}).get("action", "")
		if suggested_action == "":
			continue

		match suggested_action:
			"call_mutual_support":
				if has_damaged_subordinate:
					return "call_mutual_support"

			"reform_formation":
				if is_scattered and not has_threats:
					return "reform_formation"

			"coordinate_attack_run":
				# Only ORCHESTRATED leaders can pull off coordinated attacks
				if has_opportunities and crew_data.command_chain.subordinates.size() >= COORDINATED_ATTACK_MIN_SUBORDINATES:
					return "coordinate_attack_run"

			"screen_withdrawal":
				if has_threats and crew_data.awareness.threats.size() > crew_data.command_chain.subordinates.size():
					return "screen_withdrawal"

			"assign_targets":
				if has_opportunities:
					return "assign_targets"

	return action


## Find damaged subordinate ship
static func _find_damaged_subordinate(crew_data: Dictionary) -> Variant:
	var subordinates = crew_data.get("command_chain", {}).get("subordinates", [])
	var known_entities = crew_data.get("awareness", {}).get("known_entities", [])

	for sub_id in subordinates:
		for entity in known_entities:
			if entity.get("id", "") == sub_id:
				var status = entity.get("status", "")
				if status in ["damaged", "critical", "disabled"]:
					return entity

	return null


## Check if squadron is scattered
static func _is_squadron_scattered(crew_data: Dictionary) -> bool:
	var subordinates = crew_data.get("command_chain", {}).get("subordinates", [])
	if subordinates.size() < 2:
		return false

	var known_entities = crew_data.get("awareness", {}).get("known_entities", [])
	var positions = []

	for sub_id in subordinates:
		for entity in known_entities:
			if entity.get("id", "") == sub_id:
				positions.append(entity.get("position", Vector2.ZERO))
				break

	if positions.size() < 2:
		return false

	# Check if any pair is too far apart
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) > SCATTERED_THRESHOLD:
				return true

	return false


## Assign targets to squadron ships
## Skill affects assignment quality: low skill = poor matching, high skill = optimal
static func _assign_squadron_targets(crew_data: Dictionary) -> Array:
	var orders = []
	var skill = CrewAISystem.calculate_effective_skill(crew_data)
	var subordinates = crew_data.command_chain.subordinates
	var targets = crew_data.awareness.opportunities.duplicate()
	var mission: String = crew_data.get("squadron_mission", SquadronData.Mission.FREE)
	var mission_params: Dictionary = crew_data.get("squadron_mission_params", {})

	# Assignment quality based on skill (using constants)
	var assignment_quality = lerp(WingConstants.SQUADRON_ASSIGNMENT_QUALITY_MIN,
								  WingConstants.SQUADRON_ASSIGNMENT_QUALITY_MAX, skill)

	# High skill: Sort targets by priority (damaged, close, threatening)
	if assignment_quality > HIGH_SKILL_THRESHOLD:
		targets.sort_custom(func(a, b):
			var score_a = _calculate_target_priority_score(a, mission, mission_params)
			var score_b = _calculate_target_priority_score(b, mission, mission_params)
			return score_a > score_b
		)
	# Medium skill: Partial sorting (top half sorted)
	elif assignment_quality > MEDIUM_SKILL_THRESHOLD:
		var half = targets.size() / 2
		if half > 0:
			var top_half = targets.slice(0, half)
			top_half.sort_custom(func(a, b):
				return _calculate_target_priority_score(a, mission, mission_params) > _calculate_target_priority_score(b, mission, mission_params)
			)
			for i in half:
				targets[i] = top_half[i]
	# Low skill: Random order (poor assessment)
	else:
		targets.shuffle()

	# Assign targets to subordinates
	for i in subordinates.size():
		if i < targets.size():
			orders.append({
				"to": subordinates[i],
				"type": "engage",
				"target_id": targets[i].id
			})

	return orders


## Calculate priority score for target assignment, biased by the leader's
## squadron mission when one is active.
static func _calculate_target_priority_score(target: Dictionary, mission: String = "", params: Dictionary = {}) -> float:
	var score = 0.0

	# Damaged targets are higher priority
	var status = target.get("status", "")
	if status in ["damaged", "critical", "disabled"]:
		score += DAMAGED_TARGET_BONUS

	# Closer targets are higher priority
	var distance = target.get("distance", DEFAULT_TARGET_DISTANCE)
	score += max(0, DISTANCE_SCORE_MAX - distance / DISTANCE_SCORE_DIVISOR)

	# Threatening targets (facing us) are higher priority
	if target.get("is_threat", false):
		score += THREATENING_TARGET_BONUS

	score *= MissionTargetingSystem.score_multiplier(mission, params, target)
	return score


## Create mutual support orders - protect damaged ship
static func _create_mutual_support_orders(crew_data: Dictionary, damaged_ship: Variant) -> Array:
	var orders = []
	var ship_id = damaged_ship.get("id", "") if damaged_ship is Dictionary else ""

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "support_ally",
			"ally_id": ship_id,
			"priority": "protect"
		})

	return orders


## Create reform formation orders
static func _create_reform_formation_orders(crew_data: Dictionary) -> Array:
	var orders = []

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "formation",
			"subtype": "reform",
			"formation": "wedge"
		})

	return orders


## Create coordinated attack orders
static func _create_coordinated_attack_orders(crew_data: Dictionary, target: Dictionary) -> Array:
	var orders = []
	var target_id = target.get("id", "")

	for sub_id in crew_data.command_chain.subordinates:
		orders.append({
			"to": sub_id,
			"type": "engage",
			"subtype": "coordinated_attack",
			"target_id": target_id,
			"timing": "synchronized"
		})

	return orders


## Drive the squadron play system. Returns the standard {crew_data,
## decision} envelope when a play is active, or {} to indicate the legacy
## flow should run.
static func _try_run_squadron_play(crew_data: Dictionary, game_time: float) -> Dictionary:
	var subordinates: Array = crew_data.get("command_chain", {}).get("subordinates", [])
	if subordinates.size() < 2:
		return {}

	var geometry := _build_play_geometry(crew_data)
	if geometry.is_empty():
		return {}

	var wing_state := {"fighters": subordinates}
	var result := SquadronPlaySystem.tick_squadron_play(crew_data, wing_state, geometry, game_time)
	if not result.get("selected", false):
		return {}

	var updated: Dictionary = result.get("crew_data", crew_data)
	var orders: Array = result.get("orders", [])
	var active_play: Dictionary = updated.get("squadron_state", {}).get("active_play", {})

	updated.orders.issued = orders
	var decision := {
		"type": "squadron_command",
		"subtype": "execute_play",
		"crew_id": updated.crew_id,
		"play_id": active_play.get("play_id", ""),
		"phase": active_play.get("phase_index", 0),
		"target_id": active_play.get("target_id", ""),
		"delay": CrewAISystem.calculate_decision_delay(updated),
		"timestamp": game_time,
	}
	updated.orders.current = decision
	# Tick more frequently than the replan interval so phases advance smoothly.
	updated.next_decision_time = game_time + randf_range(REDECIDE_MIN, REDECIDE_MAX)

	# Emit observability event so post-hoc analysis can correlate plays with
	# tactics and outcomes (see plan §05.5 / overview.md observability).
	_log_play_executed(updated, active_play)

	return {"crew_data": updated, "decision": decision}


## Build geometry for the play system from leader awareness. Picks the top
## opportunity as the target and infers facing from its velocity.
static func _build_play_geometry(crew_data: Dictionary) -> Dictionary:
	var opportunities: Array = crew_data.get("awareness", {}).get("opportunities", [])
	if opportunities.is_empty():
		return {}
	var top = opportunities[0]
	var target_id: String = top.get("id", "")
	if target_id == "":
		return {}
	var pos: Vector2 = top.get("position", Vector2.ZERO)
	var vel: Vector2 = top.get("velocity", Vector2.ZERO)
	var facing := vel.normalized() if vel.length() > 1.0 else Vector2.RIGHT
	return {
		"target_id": target_id,
		"target_position": pos,
		"target_facing": facing,
	}


static func _log_play_executed(leader_crew: Dictionary, active_play: Dictionary) -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not loop is SceneTree:
		return
	var root := (loop as SceneTree).root
	if root == null or not root.has_node("BattleEventLoggerAutoload"):
		return
	var logger := root.get_node("BattleEventLoggerAutoload")
	var fighters: Array = active_play.get("role_assignments", {}).keys()
	logger.log_event("play_executed", {
		"leader_crew_id": leader_crew.get("crew_id", ""),
		"play_id": active_play.get("play_id", ""),
		"phase": active_play.get("phase_index", 0),
		"fighters": fighters.size(),
		"target_id": active_play.get("target_id", ""),
	})


## Create screen withdrawal orders - rearguard action
static func _create_screen_withdrawal_orders(crew_data: Dictionary) -> Array:
	var orders = []
	var subordinates = crew_data.command_chain.subordinates

	for i in subordinates.size():
		var role = "rearguard" if i < subordinates.size() / 2 else "withdraw"
		orders.append({
			"to": subordinates[i],
			"type": "withdraw" if role == "withdraw" else "engage",
			"subtype": role,
			"priority": "cover_retreat"
		})

	return orders
