class_name WingFormationSystem
extends RefCounted

## WingFormationSystem - Dynamically forms and manages wings.
##
## Wings form when 2+ same-team fighters are alive and within proximity.
## The highest-skilled pilot becomes Lead. Lead makes all decisions.
## Wingmen's job: stick with Lead, fire at Lead's target.
##
## Wing Types (by size, lead + wingmen):
##   solo, pair, three, four, five, six
## A wing can grow up to 1 lead + 5 wingmen so a squadron spawned together
## can fly under one commander. Use the WingConstants/MAX_WINGMEN cap.
##
## All constants defined in WingConstants

## Distinct colors for wing visualization (high saturation, good visibility)
const WING_COLORS: Array[Color] = [
	Color(1.0, 0.4, 0.4),    # Red
	Color(0.4, 0.6, 1.0),    # Blue
	Color(1.0, 0.8, 0.2),    # Yellow
	Color(0.6, 0.4, 1.0),    # Purple
	Color(1.0, 0.5, 0.2),    # Orange
	Color(0.4, 1.0, 0.8),    # Cyan
	Color(1.0, 0.4, 0.8),    # Pink
	Color(0.5, 1.0, 0.5),    # Lime
]

## Track next color index for assignment
static var _next_color_index: int = 0

## Max wingmen a single lead can run. With one lead + 5 wingmen a 6-pack
## squadron flies as a single wing, matching the doctrine of a real flight.
const MAX_WINGMEN = 5

## Map a wingman count to a human-readable wing type string.
static func _wing_type_for_size(wingman_count: int) -> String:
	match wingman_count:
		0: return "solo"
		1: return "pair"
		2: return "three"
		3: return "four"
		4: return "five"
		_: return "six"

## Form wings from available fighters on a team
## Returns array of wing dictionaries
## Previous wings are used to preserve existing memberships
static func form_wings(all_ships: Array, all_crew: Array, previous_wings: Array = []) -> Array:
	var wings = []
	var assigned_ship_ids = {}  # Track which ships are already in a wing

	# Get all operational fighters grouped by team
	var fighters_by_team = _group_fighters_by_team(all_ships, all_crew)

	# First pass: Keep existing valid wings (that haven't broken)
	for old_wing in previous_wings:
		if not should_wing_break(old_wing, all_ships):
			# Wing is still valid - keep all members
			wings.append(old_wing)
			assigned_ship_ids[old_wing.get("lead_ship_id", "")] = true
			for wingman in old_wing.get("wingmen", []):
				assigned_ship_ids[wingman.get("ship_id", "")] = true

	# Second pass: Allow solo fighters to join nearby existing wings
	for team in fighters_by_team.keys():
		var team_fighters = fighters_by_team[team]
		var solo_fighters = team_fighters.filter(func(f): return not assigned_ship_ids.has(f.ship.get("ship_id", "")))

		# Try to add solo fighters to nearby existing wings
		var remaining_solo = []
		for solo_fighter in solo_fighters:
			var added_to_wing = false

			# Look for a nearby existing wing that can accept this fighter
			for wing in wings:
				if wing.get("team", -1) != team:
					continue  # Different team

				# Check if wing can accept more wingmen
				if wing.get("wingmen", []).size() >= MAX_WINGMEN:
					continue  # Already at max

				# Check distance to lead
				var lead_pos = _get_ship_by_id(wing.get("lead_ship_id", ""), all_ships).get("position", Vector2.ZERO)
				var solo_pos = solo_fighter.ship.get("position", Vector2.ZERO)
				if lead_pos.distance_to(solo_pos) <= WingConstants.FORMATION_RANGE:
					# Position alternates side so wingmen fan out around the lead.
					var existing_count = wing.get("wingmen", []).size()
					var on_right = existing_count % 2 == 0
					var rank = 0
					for w in wing.get("wingmen", []):
						if w.get("position_side", 1) == (1 if on_right else -1):
							rank += 1
					wing.wingmen.append({
						"ship_id": solo_fighter.ship.get("ship_id", ""),
						"crew_id": solo_fighter.crew.get("crew_id", ""),
						"skill": solo_fighter.crew.get("stats", {}).get("skill", 0.5),
						"position_side": 1 if on_right else -1,
						"slot_rank": rank
					})
					assigned_ship_ids[solo_fighter.ship.get("ship_id", "")] = true
					wing["wing_type"] = _wing_type_for_size(wing.wingmen.size())

					added_to_wing = true
					break

			if not added_to_wing:
				remaining_solo.append(solo_fighter)

		# Third pass: Form new wings only from remaining solo fighters
		var team_wings = _form_team_wings(remaining_solo, assigned_ship_ids)
		wings.append_array(team_wings)

	return wings

## Group operational fighters by team
static func _group_fighters_by_team(all_ships: Array, all_crew: Array) -> Dictionary:
	var grouped = {}

	for ship in all_ships:
		var ship_type = ship.get("type", "")
		if not FleetDataManager.is_fighter_class(ship_type):
			continue
		if ship.get("status", "") != "operational":
			continue

		var team = ship.get("team", -1)
		if team < 0:
			continue

		# Find the crew for this ship
		var ship_crew = _find_crew_for_ship(ship.get("ship_id", ""), all_crew)
		if ship_crew.is_empty():
			continue

		if not grouped.has(team):
			grouped[team] = []

		grouped[team].append({
			"ship": ship,
			"crew": ship_crew
		})

	return grouped

## Find crew assigned to a ship
static func _find_crew_for_ship(ship_id: String, all_crew: Array) -> Dictionary:
	for crew in all_crew:
		if crew.get("assigned_to", "") == ship_id:
			return crew
	return {}

## Form wings for a single team's fighters
static func _form_team_wings(team_fighters: Array, assigned_ship_ids: Dictionary) -> Array:
	var wings = []

	# Sort by skill (highest first) - high skill pilots become leads
	var sorted_fighters = team_fighters.duplicate()
	sorted_fighters.sort_custom(func(a, b):
		var skill_a = a.crew.get("stats", {}).get("skill", 0.5)
		var skill_b = b.crew.get("stats", {}).get("skill", 0.5)
		return skill_a > skill_b  # Descending
	)

	# Form wings starting with highest-skilled pilots
	for fighter in sorted_fighters:
		var ship_id = fighter.ship.get("ship_id", "")
		if assigned_ship_ids.has(ship_id):
			continue  # Already in a wing

		# Find nearby unassigned fighters to form a wing with
		var potential_wingmen = _find_nearby_unassigned(fighter, sorted_fighters, assigned_ship_ids)

		if potential_wingmen.is_empty():
			# Solo fighter - no wing
			continue

		# Form wing: Lead + up to MAX_WINGMEN wingmen
		var wing = {
			"lead_ship_id": ship_id,
			"lead_crew_id": fighter.crew.get("crew_id", ""),
			"lead_skill": fighter.crew.get("stats", {}).get("skill", 0.5),
			"wingmen": [],
			"wing_type": "solo",  # Reclassified below as wingmen are added
			"team": fighter.ship.get("team", -1),
			"wing_color": _get_next_wing_color()
		}
		assigned_ship_ids[ship_id] = true

		# Add up to MAX_WINGMEN wingmen (already sorted by skill, highest first).
		# position_side alternates so wingmen fan out symmetrically around the lead.
		# slot_rank is the index within their own side (0 = innermost slot).
		var right_count = 0
		var left_count = 0
		for wingman in potential_wingmen:
			if wing.wingmen.size() >= MAX_WINGMEN:
				break

			var on_right = (wing.wingmen.size() % 2 == 0)
			var slot_rank = right_count if on_right else left_count
			if on_right:
				right_count += 1
			else:
				left_count += 1

			var wm_ship_id = wingman.ship.get("ship_id", "")
			wing.wingmen.append({
				"ship_id": wm_ship_id,
				"crew_id": wingman.crew.get("crew_id", ""),
				"skill": wingman.crew.get("stats", {}).get("skill", 0.5),
				"position_side": 1 if on_right else -1,
				"slot_rank": slot_rank
			})
			assigned_ship_ids[wm_ship_id] = true

		wing.wing_type = _wing_type_for_size(wing.wingmen.size())
		wings.append(wing)

	return wings

## Find nearby fighters not yet assigned to a wing
static func _find_nearby_unassigned(lead_fighter: Dictionary, all_fighters: Array, assigned_ship_ids: Dictionary) -> Array:
	var nearby = []
	var lead_pos = lead_fighter.ship.get("position", Vector2.ZERO)
	var lead_ship_id = lead_fighter.ship.get("ship_id", "")

	for fighter in all_fighters:
		var ship_id = fighter.ship.get("ship_id", "")
		if ship_id == lead_ship_id:
			continue
		if assigned_ship_ids.has(ship_id):
			continue

		var pos = fighter.ship.get("position", Vector2.ZERO)
		var distance = lead_pos.distance_to(pos)

		if distance <= WingConstants.FORMATION_RANGE:
			nearby.append(fighter)

	# Sort by skill (prefer higher-skilled wingmen)
	nearby.sort_custom(func(a, b):
		var skill_a = a.crew.get("stats", {}).get("skill", 0.5)
		var skill_b = b.crew.get("stats", {}).get("skill", 0.5)
		return skill_a > skill_b
	)

	return nearby

## Check if a wing should break (members too far apart)
static func should_wing_break(wing: Dictionary, all_ships: Array) -> bool:
	var lead_ship = _get_ship_by_id(wing.get("lead_ship_id", ""), all_ships)
	if lead_ship.is_empty() or lead_ship.get("status", "") != "operational":
		return true  # Lead destroyed

	var lead_pos = lead_ship.get("position", Vector2.ZERO)

	for wingman in wing.get("wingmen", []):
		var wm_ship = _get_ship_by_id(wingman.get("ship_id", ""), all_ships)
		if wm_ship.is_empty() or wm_ship.get("status", "") != "operational":
			continue  # This wingman is gone, check others

		var wm_pos = wm_ship.get("position", Vector2.ZERO)
		if lead_pos.distance_to(wm_pos) > WingConstants.BREAK_RANGE:
			return true  # Wingman too far

	return false

## Get wing information for a specific crew member
## Returns the wing they're in and their role (lead/wingman)
static func get_wing_info(crew_id: String, wings: Array) -> Dictionary:
	for wing in wings:
		if wing.get("lead_crew_id", "") == crew_id:
			return {
				"wing": wing,
				"role": "lead",
				"position_side": 0
			}

		for wingman in wing.get("wingmen", []):
			if wingman.get("crew_id", "") == crew_id:
				return {
					"wing": wing,
					"role": "wingman",
					"position_side": wingman.get("position_side", 1),
					"slot_rank": wingman.get("slot_rank", 0)
				}

	return {}  # Not in a wing

## Calculate ideal formation position for a wingman.
## position_side: 1 = right, -1 = left
## slot_rank: 0-based index of this wingman among same-side wingmen — used to
##            fan multiple wingmen out at distinct angles/distances. Default 0
##            keeps prior pair/three behavior unchanged.
static func calculate_wing_position(lead_ship: Dictionary, position_side: int, wingman_skill: float, slot_rank: int = 0) -> Vector2:
	var lead_pos = lead_ship.get("position", Vector2.ZERO)
	var lead_velocity = lead_ship.get("velocity", Vector2.ZERO)

	# Use velocity direction if moving, otherwise use rotation
	var lead_heading: float
	if lead_velocity.length() > 10.0:
		lead_heading = lead_velocity.angle()
	else:
		lead_heading = lead_ship.get("rotation", 0.0)

	# Calculate position behind and to the side. Each additional slot rank
	# on the same side adds a step of angle and distance, so 4-6 ship wings
	# fan out into a "finger six" rather than piling onto the same point.
	var base_angle = deg_to_rad(WingConstants.POSITION_ANGLE) * position_side
	var rank_angle = deg_to_rad(WingConstants.POSITION_ANGLE * 0.6) * position_side * slot_rank
	var formation_angle = lead_heading + PI + base_angle + rank_angle

	# Distance varies by skill - high skill stays closer. Outer slots sit
	# slightly further out so they're not stacked on the inner pair.
	var skill_distance_modifier = lerp(WingConstants.POSITION_SKILL_FAR_MODIFIER, WingConstants.POSITION_SKILL_CLOSE_MODIFIER, wingman_skill)
	var rank_distance_modifier = 1.0 + 0.35 * float(slot_rank)
	var actual_distance = WingConstants.POSITION_DISTANCE * skill_distance_modifier * rank_distance_modifier

	var formation_offset = Vector2(cos(formation_angle), sin(formation_angle)) * actual_distance

	# Predict lead's future position based on velocity
	# High skill wingman anticipates better
	var prediction_time = lerp(WingConstants.POSITION_PREDICTION_MIN, WingConstants.POSITION_PREDICTION_MAX, wingman_skill)
	var predicted_lead_pos = lead_pos + lead_velocity * prediction_time

	# Add some error for low-skill wingmen (they don't anticipate as well)
	var error_magnitude = (1.0 - wingman_skill) * WingConstants.POSITION_ERROR_MAX
	var error_angle = randf_range(0, TAU)
	var error_offset = Vector2(cos(error_angle), sin(error_angle)) * error_magnitude

	return predicted_lead_pos + formation_offset + error_offset

## Check if a wingman is in formation with their lead
static func is_in_formation(wingman_ship: Dictionary, lead_ship: Dictionary, wingman_skill: float) -> bool:
	var ideal_pos = calculate_wing_position(lead_ship, 1, wingman_skill)  # Side doesn't matter for distance check
	var actual_pos = wingman_ship.get("position", Vector2.ZERO)

	# Tolerance is higher for low-skill wingmen
	var tolerance = lerp(WingConstants.IN_FORMATION_TOLERANCE_LOW_SKILL, WingConstants.IN_FORMATION_TOLERANCE_HIGH_SKILL, wingman_skill)

	var lead_pos = lead_ship.get("position", Vector2.ZERO)
	var distance_to_lead = actual_pos.distance_to(lead_pos)

	return distance_to_lead <= tolerance + WingConstants.POSITION_DISTANCE

## Get ship by ID helper
static func _get_ship_by_id(ship_id: String, all_ships: Array) -> Dictionary:
	for ship in all_ships:
		if ship.get("ship_id", "") == ship_id:
			return ship
	return {}

## Get Lead's current target (for wingmen to follow)
static func get_lead_target(wing: Dictionary, all_crew: Array) -> String:
	var lead_crew_id = wing.get("lead_crew_id", "")

	for crew in all_crew:
		if crew.get("crew_id", "") == lead_crew_id:
			var orders = crew.get("orders", {}).get("current", {})
			return orders.get("target_id", "")

	return ""

## Get Lead's current maneuver (for wingmen to coordinate)
static func get_lead_maneuver(wing: Dictionary, all_crew: Array) -> String:
	var lead_crew_id = wing.get("lead_crew_id", "")

	for crew in all_crew:
		if crew.get("crew_id", "") == lead_crew_id:
			var orders = crew.get("orders", {}).get("current", {})
			return orders.get("subtype", "")

	return ""

## Get next wing color (cycles through available colors)
static func _get_next_wing_color() -> Color:
	var color = WING_COLORS[_next_color_index % WING_COLORS.size()]
	_next_color_index += 1
	return color

## Get all ship IDs in a wing (lead + wingmen)
static func get_wing_ship_ids(wing: Dictionary) -> Array:
	var ship_ids = [wing.get("lead_ship_id", "")]
	for wingman in wing.get("wingmen", []):
		ship_ids.append(wingman.get("ship_id", ""))
	return ship_ids
