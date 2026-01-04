class_name InformationSystem
extends RefCounted

## Pure functional information gathering system
## Handles crew awareness, sensor data, and information flow up command chain
## Following functional programming principles - all data is immutable

# ============================================================================
# MAIN API - Update crew awareness
# ============================================================================

## Update all crew awareness based on game state
static func update_all_crew_awareness(crew_list: Array, ships: Array, projectiles: Array, game_time: float) -> Array:
	return crew_list.map(func(crew):
		return update_crew_awareness(crew, ships, projectiles, game_time))

## Update single crew member's awareness
static func update_crew_awareness(crew_data: Dictionary, ships: Array, projectiles: Array, game_time: float) -> Dictionary:
	if crew_data.assigned_to == null:
		return crew_data  # Can't sense without being assigned to an entity

	var own_ship = find_ship_by_id(ships, crew_data.assigned_to)
	if own_ship.is_empty():
		return crew_data

	var visible_entities = gather_visible_entities(own_ship, crew_data, ships, projectiles)
	var threats = identify_threats(visible_entities, own_ship, crew_data, ships)
	var opportunities = identify_opportunities(visible_entities, own_ship, crew_data, ships)

	return update_crew_awareness_data(crew_data, visible_entities, threats, opportunities, game_time)

# ============================================================================
# AWARENESS GATHERING
# ============================================================================

## Gather all entities visible to this crew member
static func gather_visible_entities(own_ship: Dictionary, crew_data: Dictionary, ships: Array, projectiles: Array) -> Array:
	var base_range = crew_data.stats.awareness_range

	# Awareness skill modifies effective detection range
	# 0.0 awareness = 70% range
	# 0.5 awareness = 100% range
	# 1.0 awareness = 130% range
	var awareness = crew_data.get("stats", {}).get("skills", {}).get("situational_awareness", 0.5)
	var effective_range = base_range * (0.7 + awareness * 0.6)
	var range_sq = effective_range * effective_range

	var position = own_ship.position

	var visible = []

	# Check ships
	for ship in ships:
		if ship.ship_id != own_ship.ship_id and is_ship_visible(ship):
			if position.distance_squared_to(ship.position) <= range_sq:
				visible.append(create_entity_info(ship, "ship"))

	# Check projectiles (if role cares about them)
	if should_track_projectiles(crew_data.role):
		for projectile in projectiles:
			if projectile.team != own_ship.team:
				if position.distance_squared_to(projectile.position) <= range_sq:
					visible.append(create_entity_info(projectile, "projectile"))

	return visible

## Check if ship should be visible (not destroyed)
static func is_ship_visible(ship: Dictionary) -> bool:
	return ship.status != "destroyed"

## Check if role should track projectiles
static func should_track_projectiles(role: int) -> bool:
	# Pilots care about incoming fire, commanders don't need that detail
	return role in [CrewData.Role.PILOT, CrewData.Role.GUNNER]

## Create entity info snapshot
static func create_entity_info(entity: Dictionary, entity_type: String) -> Dictionary:
	var info = {
		"id": entity.get("ship_id", entity.get("projectile_id", "unknown")),
		"type": entity_type,
		"position": entity.position,
		"team": entity.team
	}

	# Add ship-specific info
	if entity_type == "ship":
		info.ship_type = entity.type
		info.status = entity.status
		info.velocity = entity.velocity

	# Add projectile-specific info
	if entity_type == "projectile":
		info.velocity = entity.velocity
		info.damage = entity.get("damage", 0)

	return info

# ============================================================================
# THREAT IDENTIFICATION
# ============================================================================

## Identify and prioritize threats
static func identify_threats(visible_entities: Array, own_ship: Dictionary, crew_data: Dictionary, all_ships: Array) -> Array:
	var enemies = visible_entities.filter(func(e): return e.team != own_ship.team)

	# All enemies are potential threats (weapons can damage any target, just at reduced effectiveness)
	# Prioritization happens at the weapon system level
	var threats = enemies \
		.map(func(e): return add_threat_priority(e, own_ship, crew_data)) \
		.filter(func(e): return e._threat_priority > 0.0)
	threats.sort_custom(func(a, b): return a._threat_priority > b._threat_priority)

	# Limit number of threats tracked based on situational awareness
	var awareness = crew_data.get("stats", {}).get("skills", {}).get("situational_awareness", 0.5)
	# Max threats scales with awareness
	# 0.0 awareness = 1 threat
	# 0.5 awareness = 2-3 threats
	# 1.0 awareness = 4+ threats
	var max_threats = int(1 + awareness * 4)
	return threats.slice(0, min(max_threats, threats.size()))

## Calculate threat priority for an entity
static func add_threat_priority(entity: Dictionary, own_ship: Dictionary, crew_data: Dictionary) -> Dictionary:
	var priority = calculate_threat_priority(entity, own_ship, crew_data)
	var result = entity.duplicate(true)
	result._threat_priority = priority
	return result

## Calculate threat priority score
static func calculate_threat_priority(entity: Dictionary, own_ship: Dictionary, crew_data: Dictionary) -> float:
	var priority = 0.0

	# Distance factor (closer = higher threat)
	var distance = own_ship.position.distance_to(entity.position)
	priority += calculate_distance_threat(distance, crew_data.stats.awareness_range)

	# Type factor
	if entity.get("type") == "projectile":
		priority += calculate_projectile_threat(entity, own_ship)
	elif entity.get("type") == "ship":
		priority += calculate_ship_threat(entity)

	return priority

## Calculate threat from distance
static func calculate_distance_threat(distance: float, max_range: float) -> float:
	# Closer = higher threat (0-100 points)
	return (1.0 - (distance / max_range)) * 100.0

## Calculate projectile threat
static func calculate_projectile_threat(projectile: Dictionary, own_ship: Dictionary) -> float:
	# Check if projectile is heading toward us
	var to_ship = own_ship.position - projectile.position
	var projectile_dir = projectile.velocity.normalized()

	var heading_toward = to_ship.normalized().dot(projectile_dir)
	if heading_toward > 0.7:  # Heading toward us
		return 200.0  # Very high threat
	return 10.0  # Low threat

## Calculate ship threat
static func calculate_ship_threat(ship: Dictionary) -> float:
	var threat = 50.0  # Base threat

	# Type-based threat
	match ship.get("ship_type", ""):
		"fighter":
			threat += 30.0  # Fast and aggressive
		"heavy_fighter":
			threat += 45.0  # Between fighter (30) and corvette (50)
		"torpedo_boat":
			threat += 55.0  # Higher threat due to AOE torpedoes
		"corvette":
			threat += 50.0  # Moderate threat
		"capital":
			threat += 70.0  # High threat

	# Status modifiers
	if ship.get("status") == "disabled":
		threat *= 0.1  # Low threat

	return threat

# ============================================================================
# OPPORTUNITY IDENTIFICATION
# ============================================================================

## Identify tactical opportunities
static func identify_opportunities(visible_entities: Array, own_ship: Dictionary, crew_data: Dictionary, all_ships: Array) -> Array:
	var enemies = visible_entities.filter(func(e): return e.get("team") != own_ship.get("team") and e.get("type") == "ship")

	# All enemy ships are potential opportunities (can damage any target at some effectiveness)
	# Prioritization of good targets happens at the weapon system level
	var opportunities = enemies \
		.map(func(e): return add_opportunity_score(e, own_ship, crew_data)) \
		.filter(func(e): return e._opportunity_score > 0.0)
	opportunities.sort_custom(func(a, b): return a._opportunity_score > b._opportunity_score)

	# Limit number of opportunities tracked (same as threats)
	var awareness = crew_data.get("stats", {}).get("skills", {}).get("situational_awareness", 0.5)
	var max_opportunities = int(1 + awareness * 4)
	return opportunities.slice(0, min(max_opportunities, opportunities.size()))

## Add opportunity score to entity
static func add_opportunity_score(entity: Dictionary, own_ship: Dictionary, crew_data: Dictionary) -> Dictionary:
	var score = calculate_opportunity_score(entity, own_ship, crew_data)
	var result = entity.duplicate(true)
	result._opportunity_score = score
	return result

## Calculate opportunity score (good targets)
static func calculate_opportunity_score(entity: Dictionary, own_ship: Dictionary, crew_data: Dictionary) -> float:
	if entity.get("type") != "ship":
		return 0.0

	var score = 50.0  # Base score

	# Damaged/disabled ships are good targets
	if entity.get("status") == "disabled":
		score += 100.0
	elif entity.get("status") == "damaged":
		score += 50.0

	# Distance factor (prefer closer targets for opportunities)
	var distance = own_ship.position.distance_to(entity.position)
	score += (1.0 - (distance / crew_data.stats.awareness_range)) * 30.0

	return score

# ============================================================================
# AWARENESS UPDATE
# ============================================================================

## Update crew awareness data with new information
static func update_crew_awareness_data(crew_data: Dictionary, entities: Array, threats: Array, opportunities: Array, game_time: float) -> Dictionary:
	var updated = crew_data.duplicate(true)
	updated.awareness.known_entities = entities
	updated.awareness.threats = threats
	updated.awareness.opportunities = opportunities
	updated.awareness.last_update = game_time
	return updated

# ============================================================================
# INFORMATION SHARING (UP THE CHAIN)
# ============================================================================

## Share information from subordinate to superior
static func share_information_up_chain(superior: Dictionary, subordinate: Dictionary) -> Dictionary:
	# Subordinates share their top threats and opportunities with superior
	var updated_superior = superior.duplicate(true)

	# Merge threat lists (superior gets broader view)
	var combined_threats = combine_threat_lists(
		superior.awareness.threats,
		subordinate.awareness.threats
	)
	updated_superior.awareness.threats = combined_threats

	# Merge opportunity lists
	var combined_opportunities = combine_opportunity_lists(
		superior.awareness.opportunities,
		subordinate.awareness.opportunities
	)
	updated_superior.awareness.opportunities = combined_opportunities

	return updated_superior

## Combine threat lists from multiple sources
static func combine_threat_lists(list1: Array, list2: Array) -> Array:
	var combined = {}

	# Add all from list1
	for threat in list1:
		combined[threat.id] = threat

	# Merge from list2 (keep higher priority)
	for threat in list2:
		if not combined.has(threat.id) or combined[threat.id]._threat_priority < threat._threat_priority:
			combined[threat.id] = threat

	# Convert back to array and sort
	var result = combined.values()
	result.sort_custom(func(a, b): return a._threat_priority > b._threat_priority)
	return result

## Combine opportunity lists from multiple sources
static func combine_opportunity_lists(list1: Array, list2: Array) -> Array:
	var combined = {}

	# Add all from list1
	for opp in list1:
		combined[opp.id] = opp

	# Merge from list2 (keep higher score)
	for opp in list2:
		if not combined.has(opp.id) or combined[opp.id]._opportunity_score < opp._opportunity_score:
			combined[opp.id] = opp

	# Convert back to array and sort
	var result = combined.values()
	result.sort_custom(func(a, b): return a._opportunity_score > b._opportunity_score)
	return result

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

## Find ship by ID
static func find_ship_by_id(ships: Array, ship_id: String) -> Dictionary:
	for ship in ships:
		if ship.ship_id == ship_id:
			return ship
	return {}
