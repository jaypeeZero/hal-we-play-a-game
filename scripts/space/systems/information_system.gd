class_name InformationSystem
extends RefCounted

## Pure functional information gathering system
## Handles crew awareness, sensor data, and information flow up command chain
## Following functional programming principles - all data is immutable

# ============================================================================
# MAIN API - Update crew awareness
# ============================================================================

## Update single crew member's awareness.
##
## Optional ship_grid / projectile_grid let gather_visible_entities skip the
## O(n) fleet scan and query a candidate set instead. Empty grids fall back
## to the full scan (test-friendly).
static func update_crew_awareness(
	crew_data: Dictionary,
	ships: Array,
	projectiles: Array,
	game_time: float,
	ship_grid: Dictionary = {},
	projectile_grid: Dictionary = {}
) -> Dictionary:
	if crew_data.assigned_to == null:
		return crew_data  # Can't sense without being assigned to an entity

	var own_ship = find_ship_by_id(ships, crew_data.assigned_to)
	if own_ship.is_empty():
		return crew_data

	var visible_entities = gather_visible_entities(
		own_ship, crew_data, ships, projectiles, ship_grid, projectile_grid)
	var threats = identify_threats(visible_entities, own_ship, crew_data, ships)
	var opportunities = identify_opportunities(visible_entities, own_ship, crew_data, ships)

	return update_crew_awareness_data(crew_data, visible_entities, threats, opportunities, game_time)

# ============================================================================
# AWARENESS GATHERING
# ============================================================================

## Gather all entities visible to this crew member
static func gather_visible_entities(
	own_ship: Dictionary,
	crew_data: Dictionary,
	ships: Array,
	projectiles: Array,
	ship_grid: Dictionary = {},
	projectile_grid: Dictionary = {}
) -> Array:
	var base_range = crew_data.stats.awareness_range

	# Awareness skill modifies effective detection range
	# 0.0 awareness = 70% range
	# 0.5 awareness = 100% range
	# 1.0 awareness = 130% range
	var awareness = crew_data.get("stats", {}).get("skills", {}).get("awareness", 0.5)
	var effective_range = base_range * (0.7 + awareness * 0.6)
	var range_sq = effective_range * effective_range

	var position = own_ship.position

	var visible = []

	# When the grid is supplied, query the candidate set; otherwise scan the
	# full fleet (test path).  Per-entity filters below are unchanged.
	var ship_candidates = ships if ship_grid.is_empty() \
		else SpatialGridSystem.query_radius(ship_grid, position, effective_range)
	for ship in ship_candidates:
		if ship.ship_id != own_ship.ship_id and is_ship_visible(ship):
			if position.distance_squared_to(ship.position) <= range_sq:
				visible.append(create_entity_info(ship, "ship"))

	# Check projectiles (if role cares about them)
	if should_track_projectiles(crew_data.role):
		var projectile_candidates = projectiles if projectile_grid.is_empty() \
			else SpatialGridSystem.query_radius(projectile_grid, position, effective_range)
		for projectile in projectile_candidates:
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

## Identify and prioritize threats. Awareness gates how many threats appear
## on the crew's list at all; tactics shapes whether they are *correctly*
## ordered by urgency (high-tactics: clean ranking; low-tactics: noisy).
static func identify_threats(visible_entities: Array, own_ship: Dictionary, crew_data: Dictionary, all_ships: Array) -> Array:
	var enemies = visible_entities.filter(func(e): return e.team != own_ship.team)

	# All enemies are potential threats (weapons can damage any target, just at reduced effectiveness)
	var scored: Array = enemies \
		.map(func(e): return add_threat_priority(e, own_ship, crew_data, all_ships)) \
		.filter(func(e): return e._threat_priority > 0.0)

	return prioritize_threats(scored, crew_data, own_ship)

## Order threats by urgency and clip the visible set by awareness.
##
## - High-tactics crew: low noise, clean ordering by urgency (closing speed,
##   weapon threat, aspect bias).
## - Low-tactics crew: noisy ordering — sometimes mis-prioritises which
##   threat to react to first.
## - Awareness sets how many threats appear on the list at all
##   (`floor(awareness * MAX_VISIBLE_THREATS)`, minimum 1).
static func prioritize_threats(threats: Array, crew_data: Dictionary, own_ship: Dictionary) -> Array:
	var skills: Dictionary = crew_data.get("stats", {}).get("skills", {})
	var tactics: float = clamp(float(skills.get("tactics", 0.5)), 0.0, 1.0)
	var awareness: float = clamp(float(skills.get("awareness", 0.5)), 0.0, 1.0)

	var ranked: Array = []
	for threat in threats:
		var entry = threat.duplicate(true)
		var urgency: float = _compute_urgency(entry, own_ship)
		if tactics < WingConstants.HIGH_TACTICS_THRESHOLD:
			# Below the threshold, ranking gets noisy. Noise scales with the
			# gap between this crew's tactics and the clean-ranking floor.
			var noise_scale: float = 1.0 - (tactics / WingConstants.HIGH_TACTICS_THRESHOLD)
			var noise: float = WingConstants.TACTICS_NOISE * noise_scale
			urgency *= randf_range(1.0 - noise, 1.0 + noise)
		entry["_threat_urgency"] = urgency
		ranked.append(entry)

	ranked.sort_custom(func(a, b): return a._threat_urgency > b._threat_urgency)

	# Awareness caps how many threats the crew can hold in their head.
	var max_visible: int = max(1, int(floor(awareness * WingConstants.MAX_VISIBLE_THREATS)))
	if max_visible > ranked.size():
		max_visible = ranked.size()
	return ranked.slice(0, max_visible)

## Pure urgency score from threat geometry — higher means "react first".
## Combines closing speed, weapon-threat heuristic, and aspect (are they
## pointing at us?). Uses small EPSILON to avoid div-by-zero on stationary
## threats; result then gets noisy-multiplied for low-tactics crew.
static func _compute_urgency(threat: Dictionary, own_ship: Dictionary) -> float:
	const EPSILON: float = 0.001

	var threat_pos: Vector2 = threat.get("position", Vector2.ZERO)
	var threat_vel: Vector2 = threat.get("velocity", Vector2.ZERO)
	var own_pos: Vector2 = own_ship.get("position", Vector2.ZERO)

	var to_own: Vector2 = own_pos - threat_pos
	var distance: float = max(to_own.length(), EPSILON)
	var to_own_dir: Vector2 = to_own / distance

	# Closing speed: positive when the threat is approaching.
	var closing_speed: float = max(threat_vel.dot(to_own_dir), 0.0)
	var time_to_intercept: float = distance / max(closing_speed, EPSILON)

	# Threat priority already encodes weapon/type danger.
	var weapon_threat: float = max(float(threat.get("_threat_priority", 1.0)), 1.0)

	# Aspect bias: a threat with their nose on us is far more dangerous than
	# one we're tailing. `velocity` direction stands in for facing — fighters
	# point where they're going and ships point near where they're going.
	# `to_own_dir` is FROM threat TO own; when their heading matches that
	# direction, dot is +1 (heading straight at us); -1 when fleeing.
	var aspect_bias: float = 1.0
	if threat_vel.length() > EPSILON:
		var heading: Vector2 = threat_vel.normalized()
		var dot: float = heading.dot(to_own_dir)
		aspect_bias = 1.0 + dot  # range: 0..2

	return (closing_speed / time_to_intercept) * weapon_threat * aspect_bias

## Calculate threat priority for an entity
static func add_threat_priority(entity: Dictionary, own_ship: Dictionary, crew_data: Dictionary, all_ships: Array = []) -> Dictionary:
	var priority = calculate_threat_priority(entity, own_ship, crew_data, all_ships)
	var result = entity.duplicate(true)
	result._threat_priority = priority
	return result

## Calculate threat priority score
static func calculate_threat_priority(entity: Dictionary, own_ship: Dictionary, crew_data: Dictionary, all_ships: Array = []) -> float:
	var priority = 0.0

	# Distance factor (closer = higher threat)
	var distance = own_ship.position.distance_to(entity.position)
	priority += calculate_distance_threat(distance, crew_data.stats.awareness_range)

	# Type factor
	if entity.get("type") == "projectile":
		priority += calculate_projectile_threat(entity, own_ship)
	elif entity.get("type") == "ship":
		priority += calculate_ship_threat(entity)

	# Tactics multiplier: doctrine shapes which enemies rank highest (applied
	# before skill-gated noise so noise still perturbs the doctrine-weighted order).
	# Thread focus_assignment + concentration so 3b focus-fire boost is applied here.
	var tactics: Dictionary = crew_data.get("tactics", {})
	if not tactics.is_empty():
		var focus_assignment: String = crew_data.get("focus_assignment", "")
		var concentration: float = float(tactics.get("concentration", 0.0))
		priority *= targeting_weight(entity, own_ship, tactics, all_ships, focus_assignment, concentration)

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
		.map(func(e): return add_opportunity_score(e, own_ship, crew_data, all_ships)) \
		.filter(func(e): return e._opportunity_score > 0.0)
	opportunities.sort_custom(func(a, b): return a._opportunity_score > b._opportunity_score)

	# Limit number of opportunities tracked (same as threats)
	var awareness = crew_data.get("stats", {}).get("skills", {}).get("awareness", 0.5)
	var max_opportunities = int(1 + awareness * 4)
	return opportunities.slice(0, min(max_opportunities, opportunities.size()))

## Add opportunity score to entity
static func add_opportunity_score(entity: Dictionary, own_ship: Dictionary, crew_data: Dictionary, all_ships: Array = []) -> Dictionary:
	var score = calculate_opportunity_score(entity, own_ship, crew_data, all_ships)
	var result = entity.duplicate(true)
	result._opportunity_score = score
	return result

## Calculate opportunity score (good targets)
static func calculate_opportunity_score(entity: Dictionary, own_ship: Dictionary, crew_data: Dictionary, all_ships: Array = []) -> float:
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

	# Tactics multiplier: doctrine shapes which enemies rank highest (applied
	# before awareness cap so doctrine is visible across the whole ranked set).
	# Thread focus_assignment + concentration so 3b focus-fire boost is applied here.
	var tactics: Dictionary = crew_data.get("tactics", {})
	if not tactics.is_empty():
		var focus_assignment: String = crew_data.get("focus_assignment", "")
		var concentration: float = float(tactics.get("concentration", 0.0))
		score *= targeting_weight(entity, own_ship, tactics, all_ships, focus_assignment, concentration)

	return score

# ============================================================================
# TACTICS-DRIVEN TARGETING WEIGHT
# ============================================================================

## Boost magnitudes for priority dials. Named constants so tuning is one-place.
## A multiplier of 1.0 = neutral (no change). Values > 1.0 push that class up.
const PRIORITY_BOOST          := 2.5  # Preferred class gets this multiplier
const PRIORITY_PENALTY        := 0.6  # Non-preferred class gets this multiplier
const SECTOR_BOOST            := 2.0  # Enemy in the focused sector gets this multiplier
const NEAREST_DISTANCE_SCALE  := 2000.0  # Reference distance for nearest priority (units)

## Maximum weight multiplier applied to the focus-designated target.
## At concentration=1.0 the focused enemy gets this boost; at concentration=0.0
## the boost is 1.0 (neutral), so low-concentration leaders produce no effect.
const FOCUS_MAX_BOOST         := 3.0

## Half-width of the "center" lateral sector (mirrors TacticsTelemetry).
const SECTOR_CENTER_HALF_WIDTH := 100.0

## Ship types that count as "capital-class" for priority matching.
const CAPITAL_CLASS_TYPES: Array = ["capital", "corvette"]

## Ship types that count as "fighter-class" for priority matching.
const FIGHTER_CLASS_TYPES: Array = ["fighter", "heavy_fighter", "torpedo_boat"]

## Pure function: returns a multiplier (1.0 = neutral) that scales a raw
## threat/opportunity score according to the crew's resolved tactics dict.
##
## entity           — entity_info snapshot (has ship_type, position, id)
## own_ship         — the observing ship (position, team)
## tactics          — crew_data["tactics"] (resolved by TacticsSystem.compile_for_crew)
## all_ships        — full fleet snapshot for centroid computation; may be []
## focus_assignment — ship_id of the designated focus target (crew["focus_assignment"]);
##                    "" means no active focus (3a behaviour, no change)
## concentration    — crew tactics concentration dial (0..1); scales the focus boost
##
## Application order inside priority/opportunity scorers:
##   base_score  →  × targeting_weight  →  skill-gated noise in prioritize_threats
## So tactics shapes the pre-noise order; skill still adds mis-prioritization for rookies.
static func targeting_weight(
	entity: Dictionary,
	own_ship: Dictionary,
	tactics: Dictionary,
	all_ships: Array,
	focus_assignment: String = "",
	concentration: float = 0.0
) -> float:
	var weight := 1.0

	# --- Priority dial ---
	var priority: String = tactics.get("priority", "nearest")
	var ship_type: String = entity.get("ship_type", "")

	match priority:
		"capitals_first":
			# Boost capital/corvette; penalise fighters so doctrine is visible
			# even when a fighter happens to be closer.
			if ship_type in CAPITAL_CLASS_TYPES:
				weight *= PRIORITY_BOOST
			elif ship_type in FIGHTER_CLASS_TYPES:
				weight *= PRIORITY_PENALTY

		"fighters_first":
			if ship_type in FIGHTER_CLASS_TYPES:
				weight *= PRIORITY_BOOST
			elif ship_type in CAPITAL_CLASS_TYPES:
				weight *= PRIORITY_PENALTY

		"weakest_first":
			# Prefer low-health targets. We read current/max armor directly from
			# the original ship dict (health not copied into entity_info snapshot).
			var health_ratio := _entity_health_ratio(entity, all_ships)
			# health_ratio 0→1: invert so weak=high weight, then scale into boost range.
			# At ratio 0.0: weight = PRIORITY_BOOST; at 1.0: weight = PRIORITY_PENALTY.
			weight *= lerp(PRIORITY_BOOST, PRIORITY_PENALTY, health_ratio)

		"command_first":
			# Capitals are always command targets. Ships carrying a command hat
			# (commander / squadron_leader role tag) would also qualify, but that
			# requires scanning crew which is not available at this scope — we
			# treat all capital-class ships as command targets (simple, correct
			# for the vast majority of battles where the capital IS the command ship).
			if ship_type in CAPITAL_CLASS_TYPES:
				weight *= PRIORITY_BOOST
			elif ship_type in FIGHTER_CLASS_TYPES:
				weight *= PRIORITY_PENALTY

		"nearest":
			# Closer = higher weight. Normalised so a ship at distance 0 gets
			# PRIORITY_BOOST and one at NEAREST_DISTANCE_SCALE gets PRIORITY_PENALTY.
			var dist: float = own_ship.get("position", Vector2.ZERO).distance_to(
				entity.get("position", Vector2.ZERO))
			var t: float = clamp(dist / NEAREST_DISTANCE_SCALE, 0.0, 1.0)
			weight *= lerp(PRIORITY_BOOST, PRIORITY_PENALTY, t)

	# --- Sector-focus dial ---
	var sector_focus: String = tactics.get("sector_focus", "none")
	if sector_focus != "none":
		var lateral_sector := _lateral_sector(entity, own_ship, all_ships)
		if lateral_sector == sector_focus:
			weight *= SECTOR_BOOST

	# --- Focus-fire boost ---
	# When the leader has designated a focus target, multiply its weight by
	# lerp(1.0, FOCUS_MAX_BOOST, concentration). crew with no focus_assignment
	# or concentration=0 are unaffected (multiplier stays 1.0 exactly).
	if focus_assignment != "" and entity.get("id", "") == focus_assignment:
		weight *= lerp(1.0, FOCUS_MAX_BOOST, clampf(concentration, 0.0, 1.0))

	return weight


## Compute the entity's lateral sector ("left"/"center"/"right") relative to
## the own-team-centroid → enemy-centroid axis (same geometry as TacticsTelemetry).
## Falls back to "center" when the axis is degenerate or all_ships is empty.
static func _lateral_sector(entity: Dictionary, own_ship: Dictionary, all_ships: Array) -> String:
	if all_ships.is_empty():
		return "center"

	var own_team: int = own_ship.get("team", 0)
	# Own-team centroid
	var own_sum := Vector2.ZERO
	var own_count := 0
	for s in all_ships:
		if s.get("team", -1) == own_team and s.get("status", "") not in ["destroyed", "fled"]:
			own_sum += s.position
			own_count += 1
	if own_count == 0:
		return "center"
	var own_centroid := own_sum / float(own_count)

	# Enemy centroid (anchor)
	var enemy_sum := Vector2.ZERO
	var enemy_count := 0
	for s in all_ships:
		if s.get("team", -1) != own_team and s.get("status", "") not in ["destroyed", "fled"]:
			enemy_sum += s.position
			enemy_count += 1
	if enemy_count == 0:
		return "center"
	var enemy_centroid := enemy_sum / float(enemy_count)

	var axis := enemy_centroid - own_centroid
	if axis.length_squared() < 0.001:
		return "center"

	# Rightward direction from own team's perspective facing the enemy.
	var right_dir := Vector2(-axis.y, axis.x).normalized()
	var offset: Vector2 = entity.get("position", Vector2.ZERO) - own_centroid
	var lateral: float = offset.dot(right_dir)

	if lateral > SECTOR_CENTER_HALF_WIDTH:
		return "right"
	elif lateral < -SECTOR_CENTER_HALF_WIDTH:
		return "left"
	return "center"


## Returns a 0..1 health ratio for the entity identified by entity_info.
## Reads current_armor/max_armor from armor_sections in the original ship dict.
## Falls back to 1.0 (full health) when the ship cannot be found or has no
## armor sections — so an unarmored ship is not mistakenly prioritised as weak.
static func _entity_health_ratio(entity_info: Dictionary, all_ships: Array) -> float:
	var entity_id: String = entity_info.get("id", "")
	for ship in all_ships:
		if ship.get("ship_id", "") != entity_id:
			continue
		var sections: Array = ship.get("armor_sections", [])
		if sections.is_empty():
			return 1.0  # No armor data → treat as full health
		var current := 0.0
		var maximum := 0.0
		for section in sections:
			current += float(section.get("current_armor", 0))
			maximum += float(section.get("max_armor", 0))
		return current / maximum if maximum > 0.0 else 1.0
	return 1.0  # Ship not found → neutral


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
