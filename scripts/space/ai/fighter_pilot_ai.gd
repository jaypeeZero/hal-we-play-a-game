extends RefCounted
class_name FighterPilotAI

## FighterPilotAI - Simple, straightforward fighter pilot behavior
##
## Distance-based speed control:
## - Far away (>500): full speed approach
## - Mid range (150-500): slow approach, try to get behind enemy
## - Close range (<150): tight maneuvering (orbits, weaves, loops)
##
## Combat behavior:
## - vs Fighters: get behind enemy, adjust for movement, formation flying
## - vs Corvettes/Capitals: stay at distance, dodge/weave, pot-shots
## - vs Corvettes/Capitals (many fighters): coordinated group runs

## Configuration constants
const FAR_RANGE = 500.0  # Distance beyond which we use full speed approach
const MID_RANGE = 300.0  # Mid range threshold for tactical maneuvering
const CLOSE_RANGE = 150.0  # Distance for tight maneuvering
const SAFE_DISTANCE_VS_CAPITAL = 400.0  # Stay at distance vs big ships
const GROUP_RUN_THRESHOLD = 4  # Number of fighters needed for coordinated runs
const FORMATION_SPACING = 100.0  # Distance to maintain from wingmates
const BEHIND_ANGLE_TOLERANCE = 30.0  # Degrees - "behind" the enemy

## Wingmate formation constants
const FORMATION_DISTANCE = 80.0  # Ideal distance between wingmates
const FORMATION_BROKEN_DISTANCE = 150.0  # Distance at which formation is considered broken
const FORMATION_ANGLE_OFFSET = 45.0  # Degrees - wingman stays at 45° behind and to the side

## Main decision function - called by CrewAISystem
static func make_decision(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	# WINGMATE FORMATION: Check formation status FIRST - TOP PRIORITY
	# If we're a wingman and formation is broken, rejoin before engaging targets
	var is_wingman = _is_wingman_role(crew_data, all_crew)
	if is_wingman:
		var partner = _find_wingman_partner(crew_data, all_crew, all_ships)
		if not partner.is_empty():
			var partner_ship = partner.get("ship", {})
			if _is_formation_broken(ship_data, partner_ship):
				# Formation broken! Priority #1 is to rejoin
				return _make_rejoin_wingman_decision(crew_data, ship_data, partner_ship, game_time)

	# SQUADRON STRUCTURE: Check if we have a squadron leader to follow
	var target_id = ""
	var is_leader = crew_data.get("is_squadron_leader", false)

	if is_leader:
		# Squadron Leader picks target for the whole squadron
		target_id = _find_best_target(crew_data, all_ships)
	else:
		# Non-leaders follow squadron leader's target
		target_id = _get_squadron_leader_target(crew_data, all_crew)

		# Fallback to own target if leader has no target
		if target_id == "":
			target_id = _find_best_target(crew_data, all_ships)

	if target_id == "":
		return _make_idle_decision(crew_data, game_time)

	var target_ship = _get_ship_by_id(target_id, all_ships)
	if target_ship == null:
		return _make_idle_decision(crew_data, game_time)

	# Determine combat behavior based on target type
	var target_type = target_ship.get("type", "fighter")
	var decision = {}

	if target_type == "fighter":
		decision = _make_fighter_vs_fighter_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	elif target_type == "corvette" or target_type == "capital":
		decision = _make_fighter_vs_capital_decision(crew_data, ship_data, target_ship, all_ships, all_crew, game_time)
	else:
		decision = _make_pursuit_decision(crew_data, ship_data, target_ship, game_time)

	return decision

## Fighter vs Fighter combat
static func _make_fighter_vs_fighter_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(target_pos)

	# Try to get behind the enemy
	var behind_position = _calculate_behind_position(target_ship)
	var is_behind = _am_i_behind_target(ship_data, target_ship)

	# Check formation status with wingmates
	var wingmates = _find_wingmates(crew_data, all_crew, all_ships)
	var formation_offset = _calculate_formation_offset(crew_data, wingmates, all_ships)

	# Decide maneuver based on distance and position
	var maneuver_type = ""
	var target_id = target_ship.get("ship_id", "")

	if distance > FAR_RANGE:
		# Far away - approach at full speed
		maneuver_type = "pursue_full_speed"
	elif distance > CLOSE_RANGE:
		# Mid range - slow approach, try to get behind
		if is_behind:
			maneuver_type = "pursue_tactical"
		else:
			maneuver_type = "flank_behind"
	else:
		# Close range - tight maneuvering
		if is_behind:
			maneuver_type = "tight_pursuit"
		else:
			maneuver_type = "dogfight_maneuver"

	# Apply formation offset if we have wingmates
	var decision = {
		"type": "maneuver",
		"subtype": maneuver_type,
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_id,
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": game_time,
		"formation_offset": formation_offset,
		"behind_position": behind_position
	}

	return decision

## Fighter vs Corvette/Capital combat
static func _make_fighter_vs_capital_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
	var my_pos = ship_data.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(target_pos)

	# Count friendly fighters nearby
	var nearby_fighters = _count_nearby_friendly_fighters(ship_data, all_ships)

	var maneuver_type = ""
	var target_id = target_ship.get("ship_id", "")

	# If we have enough fighters, coordinate group runs
	if nearby_fighters >= GROUP_RUN_THRESHOLD:
		# Group run tactics
		if distance > SAFE_DISTANCE_VS_CAPITAL:
			# Approach for run
			maneuver_type = "group_run_approach"
		elif distance > CLOSE_RANGE:
			# Execute attack run
			maneuver_type = "group_run_attack"
		else:
			# Too close, swing around
			maneuver_type = "group_run_swing_around"
	else:
		# Solo/small group tactics - stay at distance, pot-shots
		if distance < SAFE_DISTANCE_VS_CAPITAL * 0.7:
			# Too close, evade
			maneuver_type = "evasive_retreat"
		elif distance > SAFE_DISTANCE_VS_CAPITAL * 1.3:
			# Too far, close in
			maneuver_type = "cautious_approach"
		else:
			# Good range, dodge and weave
			maneuver_type = "dodge_and_weave"

	var decision = {
		"type": "maneuver",
		"subtype": maneuver_type,
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_id,
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": game_time,
		"nearby_fighters": nearby_fighters
	}

	return decision

## Check if we're behind the target
static func _am_i_behind_target(my_ship: Dictionary, target_ship: Dictionary) -> bool:
	var my_pos = my_ship.get("position", Vector2.ZERO)
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var target_rotation = target_ship.get("rotation", 0.0)

	# Vector from target to me
	var to_me = (my_pos - target_pos).normalized()

	# Target's facing direction
	var target_facing = Vector2(cos(target_rotation), sin(target_rotation))

	# If I'm behind, angle between target's facing and vector to me should be ~180 degrees
	var angle_diff = rad_to_deg(target_facing.angle_to(to_me))

	# Behind is 180 degrees +/- tolerance
	return abs(abs(angle_diff) - 180.0) < BEHIND_ANGLE_TOLERANCE

## Calculate position behind target (for pursuit)
static func _calculate_behind_position(target_ship: Dictionary) -> Vector2:
	var target_pos = target_ship.get("position", Vector2.ZERO)
	var target_rotation = target_ship.get("rotation", 0.0)
	var target_velocity = target_ship.get("velocity", Vector2.ZERO)

	# Position behind target, accounting for velocity
	var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * CLOSE_RANGE

	# Lead the position if target is moving
	var predicted_pos = target_pos + target_velocity * 0.5

	return predicted_pos + behind_offset

## Get squadron leader's target
static func _get_squadron_leader_target(crew_data: Dictionary, all_crew: Array) -> String:
	# Find squadron leader via command chain
	var leader_id = crew_data.get("command_chain", {}).get("superior", "")
	if leader_id == "":
		return ""

	# Find leader in crew list
	for crew in all_crew:
		if crew.get("crew_id", "") == leader_id:
			# Get leader's current target from their orders
			var leader_orders = crew.get("orders", {}).get("current", {})
			return leader_orders.get("target_id", "")

	return ""

## Find wingmates (other fighters on same team)
static func _find_wingmates(crew_data: Dictionary, all_crew: Array, all_ships: Array) -> Array:
	var wingmates = []
	var my_ship_id = crew_data.get("assigned_ship_id", "")
	var my_ship = _get_ship_by_id(my_ship_id, all_ships)
	if my_ship == null:
		return wingmates

	var my_team = my_ship.get("team", -1)
	var my_pair = crew_data.get("wingman_pair", -1)

	# Prioritize wingman pair first
	if my_pair >= 0:
		# Find specific wingman in same pair
		for crew in all_crew:
			if crew.get("crew_id", "") == crew_data.get("crew_id", ""):
				continue
			if crew.get("wingman_pair", -1) != my_pair:
				continue

			var crew_ship_id = crew.get("assigned_ship_id", "")
			var crew_ship = _get_ship_by_id(crew_ship_id, all_ships)
			if crew_ship != null and crew_ship.get("status", "") == "operational":
				wingmates.append(crew_ship)

	# Then add other squadron members
	for ship in all_ships:
		if ship.get("ship_id", "") == my_ship_id:
			continue
		if ship.get("team", -1) != my_team:
			continue
		if ship.get("type", "") != "fighter":
			continue
		if ship.get("status", "") != "operational":
			continue

		# Don't duplicate wingman pair
		var already_added = false
		for wingmate in wingmates:
			if wingmate.get("ship_id", "") == ship.get("ship_id", ""):
				already_added = true
				break

		if not already_added:
			wingmates.append(ship)

	return wingmates

## Calculate formation offset to maintain spacing
static func _calculate_formation_offset(crew_data: Dictionary, wingmates: Array, all_ships: Array) -> Vector2:
	if wingmates.is_empty():
		return Vector2.ZERO

	var my_ship_id = crew_data.get("assigned_ship_id", "")
	var my_ship = _get_ship_by_id(my_ship_id, all_ships)
	if my_ship == null:
		return Vector2.ZERO

	var my_pos = my_ship.get("position", Vector2.ZERO)
	var my_pair = crew_data.get("wingman_pair", -1)
	var offset = Vector2.ZERO

	# WINGMAN PAIR FORMATION: Maintain tight spacing with your wingman
	# wingmates[0] is your wingman pair partner (if they exist)
	# Others are squadron members to avoid

	for i in range(wingmates.size()):
		var wingmate = wingmates[i]
		var wingmate_pos = wingmate.get("position", Vector2.ZERO)
		var distance = my_pos.distance_to(wingmate_pos)

		# First wingmate is your pair partner - maintain closer formation
		if i == 0 and my_pair >= 0:
			# Maintain 80 unit spacing with wingman (tighter than others)
			var desired_spacing = 80.0
			if distance > desired_spacing * 1.3:
				# Too far from wingman, pull closer
				var direction = (wingmate_pos - my_pos).normalized()
				var strength = (distance - desired_spacing) / desired_spacing
				offset += direction * strength * 50.0
			elif distance < desired_spacing * 0.7 and distance > 0:
				# Too close to wingman, push away slightly
				var direction = (my_pos - wingmate_pos).normalized()
				var strength = (desired_spacing - distance) / desired_spacing
				offset += direction * strength * 30.0
		else:
			# Other squadron members - maintain standard spacing
			if distance < FORMATION_SPACING and distance > 0:
				# Push away from other fighters
				var direction = (my_pos - wingmate_pos).normalized()
				var strength = (FORMATION_SPACING - distance) / FORMATION_SPACING
				offset += direction * strength * 100.0

	return offset

## Count nearby friendly fighters
static func _count_nearby_friendly_fighters(my_ship: Dictionary, all_ships: Array) -> int:
	var my_pos = my_ship.get("position", Vector2.ZERO)
	var my_team = my_ship.get("team", -1)
	var my_id = my_ship.get("ship_id", "")
	var count = 0

	for ship in all_ships:
		if ship.get("ship_id", "") == my_id:
			continue
		if ship.get("team", -1) != my_team:
			continue
		if ship.get("type", "") != "fighter":
			continue
		if ship.get("status", "") != "operational":
			continue

		var distance = my_pos.distance_to(ship.get("position", Vector2.ZERO))
		if distance < SAFE_DISTANCE_VS_CAPITAL * 1.5:
			count += 1

	return count

## Find best target from awareness
static func _find_best_target(crew_data: Dictionary, all_ships: Array) -> String:
	var awareness = crew_data.get("awareness", {})
	var threats = awareness.get("threats", [])
	var opportunities = awareness.get("opportunities", [])

	# Prefer threats (enemy fighters)
	if not threats.is_empty():
		var threat = threats[0]
		if threat is Dictionary:
			return threat.get("id", "")
		return threat

	# Fall back to opportunities
	if not opportunities.is_empty():
		var opportunity = opportunities[0]
		if opportunity is Dictionary:
			return opportunity.get("id", "")
		return opportunity

	return ""

## Get ship by ID
static func _get_ship_by_id(ship_id: String, all_ships: Array) -> Dictionary:
	for ship in all_ships:
		if ship.get("ship_id", "") == ship_id:
			return ship
	return {}

## Make idle decision
static func _make_idle_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "idle",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": crew_data.get("assigned_ship_id", ""),
		"target_id": "",
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": 2.0,  # Check again in 2 seconds
		"timestamp": game_time
	}

## Make basic pursuit decision
static func _make_pursuit_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, game_time: float) -> Dictionary:
	return {
		"type": "maneuver",
		"subtype": "pursue",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": target_ship.get("ship_id", ""),
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": crew_data.get("stats", {}).get("reaction_time", 0.1),
		"timestamp": game_time
	}

# ============================================================================
# WINGMATE FORMATION SYSTEM
# ============================================================================

## Find wingman partner (the other member of the wingman pair)
static func _find_wingman_partner(crew_data: Dictionary, all_crew: Array, all_ships: Array) -> Dictionary:
	var my_pair = crew_data.get("wingman_pair", -1)
	if my_pair < 0:
		return {}  # Not in a wingman pair

	var my_crew_id = crew_data.get("crew_id", "")

	# Find the other pilot in the same wingman pair
	for crew in all_crew:
		if crew.get("crew_id", "") == my_crew_id:
			continue
		if crew.get("wingman_pair", -1) != my_pair:
			continue

		# Found our wingman partner - get their ship
		var partner_ship_id = crew.get("assigned_ship_id", "")
		var partner_ship = _get_ship_by_id(partner_ship_id, all_ships)

		if partner_ship != null and partner_ship.get("status", "") == "operational":
			return {
				"crew": crew,
				"ship": partner_ship
			}

	return {}  # Partner not found or not operational

## Check if this pilot is the wingman (not the lead) in their pair
## In each pair, the pilot with the lower squadron_rank is the lead
static func _is_wingman_role(crew_data: Dictionary, all_crew: Array) -> bool:
	var my_pair = crew_data.get("wingman_pair", -1)
	if my_pair < 0:
		return false  # Not in a wingman pair

	var my_rank = crew_data.get("squadron_rank", 999)
	var my_crew_id = crew_data.get("crew_id", "")

	# Find partner's rank
	for crew in all_crew:
		if crew.get("crew_id", "") == my_crew_id:
			continue
		if crew.get("wingman_pair", -1) != my_pair:
			continue

		var partner_rank = crew.get("squadron_rank", 999)
		# If partner has lower rank, they are the lead, so we are the wingman
		return partner_rank < my_rank

	return false  # No partner found, default to not wingman

## Check if formation with wingman is broken
static func _is_formation_broken(ship_data: Dictionary, partner_ship: Dictionary) -> bool:
	if partner_ship.is_empty():
		return false  # No partner, no formation to break

	var my_pos = ship_data.get("position", Vector2.ZERO)
	var partner_pos = partner_ship.get("position", Vector2.ZERO)
	var distance = my_pos.distance_to(partner_pos)

	return distance > FORMATION_BROKEN_DISTANCE

## Calculate ideal formation position relative to lead
## Wingman should be behind and to the side of the lead
static func _calculate_formation_position(lead_ship: Dictionary, offset_side: int = 1) -> Vector2:
	var lead_pos = lead_ship.get("position", Vector2.ZERO)
	var lead_velocity = lead_ship.get("velocity", Vector2.ZERO)

	# Use velocity direction if moving, otherwise use rotation
	var lead_heading: float
	if lead_velocity.length() > 10.0:
		lead_heading = lead_velocity.angle()
	else:
		lead_heading = lead_ship.get("rotation", 0.0)

	# Calculate position behind and to the side
	# offset_side: 1 = right, -1 = left
	var angle_offset = deg_to_rad(FORMATION_ANGLE_OFFSET) * offset_side
	var formation_angle = lead_heading + PI + angle_offset  # Behind and to the side

	var formation_offset = Vector2(cos(formation_angle), sin(formation_angle)) * FORMATION_DISTANCE

	# Predict lead's future position based on velocity
	var predicted_lead_pos = lead_pos + lead_velocity * 0.5

	return predicted_lead_pos + formation_offset

## Make rejoin wingman decision - TOP PRIORITY when formation is broken
static func _make_rejoin_wingman_decision(crew_data: Dictionary, ship_data: Dictionary, partner_ship: Dictionary, game_time: float) -> Dictionary:
	# Calculate formation position
	var formation_pos = _calculate_formation_position(partner_ship)

	return {
		"type": "maneuver",
		"subtype": "rejoin_wingman",
		"crew_id": crew_data.get("crew_id", ""),
		"entity_id": ship_data.get("ship_id", ""),
		"target_id": partner_ship.get("ship_id", ""),  # Target is the lead ship
		"formation_position": formation_pos,
		"skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
		"delay": 0.3,  # Check frequently when rejoining
		"timestamp": game_time
	}
