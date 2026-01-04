## LargeShipPilotAI - Corvette and Capital ship pilot behavior
##
## Distance ranges (larger than fighters):
## - FAR_RANGE: > 3000 units - approach at full speed
## - MID_RANGE: 1500-3000 units - tactical positioning
## - CLOSE_RANGE: < 1500 units - maintain range, present broadside
##
## Core behaviors:
## - Present broadside to maximize turret coverage
## - Maintain safe distance from fighters (kite them)
## - Use lateral thrust to strafe while keeping turrets on target

extends RefCounted
class_name LargeShipPilotAI

const FAR_RANGE = 3000.0
const MID_RANGE = 1500.0
const CLOSE_RANGE = 800.0
const SAFE_RANGE_VS_FIGHTERS = 2000.0

## Main decision function - called by CrewAISystem
static func make_decision(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float) -> Dictionary:
	var ship_type = ship_data.get("type", "corvette")
	var target = _find_best_target(crew_data, ship_data, all_ships)

	if target.is_empty():
		return _make_idle_decision(crew_data, game_time)

	var target_type = target.get("type", "fighter")
	var distance = ship_data.get("position", Vector2.ZERO).distance_to(target.get("position", Vector2.ZERO))

	# Generate situation string for knowledge query
	var situation = _generate_situation(ship_type, target_type, distance, crew_data, ship_data, target)

	# Query knowledge system
	var maneuver = _query_large_ship_knowledge(situation, crew_data)

	if maneuver == "":
		maneuver = _get_default_maneuver(ship_type, target_type, distance)

	return _create_maneuver_decision(crew_data, ship_data, target, maneuver, game_time)

## Generate situation string for knowledge query
## Format: "{ship_type} vs {target_type} {distance_category} {position_advantage}"
static func _generate_situation(ship_type: String, target_type: String, distance: float, crew_data: Dictionary, ship_data: Dictionary, target: Dictionary) -> String:
	var parts = [ship_type]

	# Target type category
	if FleetDataManager.is_fighter_class(target_type):
		parts.append("fighters")
	elif target_type == "corvette":
		parts.append("corvette")
	else:
		parts.append("capital")

	# Distance category
	if distance > FAR_RANGE:
		parts.append("far")
	elif distance > MID_RANGE:
		parts.append("mid")
	else:
		parts.append("close")

	# Broadside status
	if _is_presenting_broadside(ship_data, target):
		parts.append("broadside")
	else:
		parts.append("not_broadside")

	return " ".join(parts)

## Check if ship is presenting broadside to target (perpendicular)
static func _is_presenting_broadside(ship_data: Dictionary, target: Dictionary) -> bool:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var my_rotation = ship_data.get("rotation", 0.0)
	var target_pos = target.get("position", Vector2.ZERO)

	var to_target = (target_pos - my_pos).normalized()
	var my_facing = Vector2(cos(my_rotation), sin(my_rotation))

	# Broadside = perpendicular = angle ~90 degrees
	var angle = abs(my_facing.angle_to(to_target))
	return abs(angle - PI/2) < deg_to_rad(30.0)  # Within 30 degrees of perpendicular

## Get default maneuver when knowledge query returns empty
static func _get_default_maneuver(ship_type: String, target_type: String, distance: float) -> String:
	if FleetDataManager.is_fighter_class(target_type):
		if distance < SAFE_RANGE_VS_FIGHTERS:
			return "large_ship_kite"  # Back away from fighters
		else:
			return "large_ship_broadside"  # Present broadside at safe range
	else:
		# vs corvette/capital
		if distance > FAR_RANGE:
			return "large_ship_approach"
		else:
			return "large_ship_broadside"

## Query knowledge system for large ship tactics
static func _query_large_ship_knowledge(situation: String, crew_data: Dictionary) -> String:
	var knowledge = TacticalKnowledgeSystem.query_pilot_knowledge(situation, 3)
	if knowledge.is_empty():
		return ""

	# Select maneuver based on skill (same pattern as FighterPilotAI)
	var skill = crew_data.get("stats", {}).get("skill", 0.5)
	var content = knowledge[0].get("content", {})
	var maneuvers = content.get("maneuvers", [])
	var skill_requirements = content.get("skill_requirements", {})

	for m in maneuvers:
		var required = skill_requirements.get(m, 0.0)
		if skill >= required:
			return m

	return maneuvers[-1] if maneuvers.size() > 0 else ""

static func _find_best_target(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array) -> Dictionary:
	var my_team = ship_data.get("team", -1)
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var best_target = {}
	var best_score = -1.0

	for ship in all_ships:
		if ship.get("team", -1) == my_team:
			continue
		if ship.get("status", "") == "destroyed":
			continue

		var distance = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		var score = 10000.0 - distance  # Prefer closer targets

		# Prefer damaged targets
		if ship.get("status", "") == "damaged":
			score += 5000.0

		if score > best_score:
			best_score = score
			best_target = ship

	return best_target

static func _make_idle_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)
	updated.next_decision_time = game_time + randf_range(1.0, 2.0)
	return {"crew_data": updated}

static func _create_maneuver_decision(crew_data: Dictionary, ship_data: Dictionary, target: Dictionary, maneuver: String, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)

	var decision = {
		"type": "maneuver",
		"subtype": maneuver,
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": crew_data.get("assigned_to", ""),
		"target_id": target.get("ship_id", ""),
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"timestamp": game_time
	}

	updated.next_decision_time = game_time + randf_range(0.5, 1.0)
	return {"crew_data": updated, "decision": decision}
