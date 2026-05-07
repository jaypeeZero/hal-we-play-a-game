class_name BattlePlanner
extends RefCounted

## Pure planner that builds a BattlePlan-compatible Array of ship entries
## from the two team fleets and a battlefield size. Encapsulates the
## per-team base_x, per-squadron quadrant, and patrol-center/radius math
## that used to live inline in space_battle_game.gd.

const PATROL_ZONE_RADIUS: float = 700.0
# Large ships need a wider operating zone — broadside warfare requires room
# to maneuver at range. A capital fenced into 700u can't actually orbit a
# target without being yanked home by the area leash.
const LARGE_SHIP_PATROL_ZONE_RADIUS: float = 1500.0
# Cardinal offsets used to spread squadrons into distinct quadrants
const PATROL_QUADRANT_DIRS: Array = [
	Vector2(0, -1),  # North
	Vector2(0,  1),  # South
	Vector2(1,  0),  # East
	Vector2(-1, 0),  # West
]
const MARGIN: float = 200.0
# Teams stagger their starting quadrant so squadrons don't all converge on
# the same area; team 0 begins at North, team 1 at South.
const TEAM0_QUADRANT_OFFSET: int = 0
const TEAM1_QUADRANT_OFFSET: int = 1
# Step between squadron quadrants within a team — 2 keeps squadrons on
# opposite sides of the battlefield (N↔S, E↔W).
const QUADRANT_STEP: int = 2


static func build_default_plan(team0_fleet: Dictionary, team1_fleet: Dictionary, battlefield_size: Vector2) -> Array:
	var entries: Array = []
	entries.append_array(_plan_team(team0_fleet, 0, MARGIN, TEAM0_QUADRANT_OFFSET, battlefield_size))
	entries.append_array(_plan_team(team1_fleet, 1, battlefield_size.x - MARGIN, TEAM1_QUADRANT_OFFSET, battlefield_size))
	return entries


static func _plan_team(fleet: Dictionary, team: int, base_x: float, quadrant_offset: int, battlefield_size: Vector2) -> Array:
	var spawn_positions := ShipData.calculate_fleet_spawn_positions(fleet, base_x, battlefield_size.y)
	var battlefield_center := battlefield_size * 0.5
	var squadron_quadrant: Dictionary = {}
	var squadron_count: int = 0
	var entries: Array = []

	for spawn_info in spawn_positions:
		var ship_type: String = spawn_info["type"]
		if not squadron_quadrant.has(ship_type):
			var idx := (quadrant_offset + squadron_count * QUADRANT_STEP) % PATROL_QUADRANT_DIRS.size()
			squadron_quadrant[ship_type] = idx
			squadron_count += 1
		var dir: Vector2 = PATROL_QUADRANT_DIRS[squadron_quadrant[ship_type]]
		var patrol_center: Vector2 = battlefield_center + dir * PATROL_ZONE_RADIUS
		var patrol_radius: float = LARGE_SHIP_PATROL_ZONE_RADIUS if FleetDataManager.is_large_ship(ship_type) else PATROL_ZONE_RADIUS
		entries.append({
			"ship_type": ship_type,
			"team": team,
			"position": spawn_info["position"],
			"patrol_center": patrol_center,
			"patrol_radius": patrol_radius,
			"hull_length": ShipData.get_hull_length(ship_type),
		})

	return entries
