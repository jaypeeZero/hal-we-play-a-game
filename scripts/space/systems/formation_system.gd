class_name FormationSystem
extends RefCounted

## Per-frame formation slot stamper.
##
## Owns formation_slot (absolute world position) and anchor_position on
## ship.orders. Called once per frame before MovementSystem so the formation
## goal is always live, even though crew decisions are event-driven.
##
## All functions are static pure: inputs are never mutated; the returned
## Array contains duplicate ships with updated orders.

# ── Spacing constants ────────────────────────────────────────────────────────

## Base distance between adjacent slots in world units.
## spacing dial (0..1) scales between SPACING_TIGHT and SPACING_LOOSE.
const SPACING_UNIT := 300.0
const SPACING_TIGHT_FACTOR := 0.4   # spacing=0 → 0.4 × SPACING_UNIT apart
const SPACING_LOOSE_FACTOR := 2.0   # spacing=1 → 2.0 × SPACING_UNIT apart

# ── Wall / line_abreast geometry ─────────────────────────────────────────────

## Wall sits this far behind the team centroid along the −axis (toward own rear).
## Keeps the wall shape visually distinct from wedge (which leads forward).
const WALL_REAR_OFFSET := 80.0

# ── Wedge geometry ───────────────────────────────────────────────────────────

## Half-angle of the wedge arms from the axis, in radians.
## 35° makes the V clearly visible and distinct from a wall.
const WEDGE_ARM_ANGLE := deg_to_rad(35.0)

## Lead ship is this far ahead along +axis.
const WEDGE_LEAD_FORWARD := 200.0

## Each successive arm ship steps this far back along −axis per arm rank.
const WEDGE_ARM_DEPTH_STEP := 220.0

# ── Layered geometry ─────────────────────────────────────────────────────────

## Maximum depth displacement along −axis for the rearmost row when depth=1.
## depth dial (0..1) scales this.
const LAYER_MAX_DEPTH := 800.0

## Number of perp columns in a layered formation.
const LAYER_COLUMNS := 3

# ── Vanguard / reserve geometry ───────────────────────────────────────────────

## Forward group is pushed this far along +axis (toward enemy).
const VANGUARD_FORWARD := 350.0

## Rear group is pushed this far along −axis (away from enemy).
const RESERVE_REAR := 350.0

# ── Operational status filter ─────────────────────────────────────────────────

const OPERATIONAL_STATUS := "operational"


# ── Public API ────────────────────────────────────────────────────────────────

## Stamp formation_slot (absolute world pos) and anchor_position onto each
## ship's orders. Returns a NEW Array of ship dicts; inputs are not mutated.
##
## Steps:
##   1. Group operational ships by team.
##   2. Compute enemy centroid for each team (the anchor — formation faces it).
##   3. Compute own centroid; build axis (toward enemy) and perp.
##   4. Read shape/spacing/depth from the first ship's crew["tactics"] if present.
##   5. Sort ships by ship_id for deterministic slot assignment.
##   6. Stamp each ship's orders with formation_slot and anchor_position.
static func assign_slots(ships: Array) -> Array:
	# Group by team (operational only)
	var by_team: Dictionary = _group_by_team(ships)
	var team_centroids: Dictionary = {}
	for team in by_team:
		team_centroids[team] = _centroid(by_team[team])

	# Pre-build updated orders dict keyed by ship_id
	var slot_map: Dictionary = {}   # ship_id -> {formation_slot, anchor_position}

	for team in by_team:
		var own_ships: Array = by_team[team]
		if own_ships.is_empty():
			continue

		# Anchor = centroid of ALL enemy teams (operational)
		var enemy_positions: Array = []
		for other_team in by_team:
			if other_team != team:
				for s in by_team[other_team]:
					enemy_positions.append(s.get("position", Vector2.ZERO))
		if enemy_positions.is_empty():
			# No enemies — leave existing slots untouched for this team
			continue

		var anchor: Vector2 = _centroid_of_positions(enemy_positions)
		var own_centroid: Vector2 = team_centroids[team]

		# Axis toward enemy; perp is the lateral spread axis.
		var axis: Vector2  = Vector2.ZERO
		var to_enemy: Vector2 = anchor - own_centroid
		if to_enemy.length() > 1.0:
			axis = to_enemy.normalized()
		else:
			axis = Vector2(1.0, 0.0)   # arbitrary when fleets overlap
		var perp: Vector2 = axis.rotated(PI / 2.0)

		# Read formation dials from the first ship's tactics block.
		var tactics: Dictionary = _read_tactics(own_ships[0])
		var shape:   String  = tactics.get("shape",   "line_abreast")
		var spacing: float   = tactics.get("spacing", 0.5)
		var depth:   float   = tactics.get("depth",   0.5)

		# Sort ships by ship_id for deterministic assignment.
		var sorted_ships: Array = own_ships.duplicate()
		sorted_ships.sort_custom(func(a, b): return a.get("ship_id", "") < b.get("ship_id", ""))
		var count: int = sorted_ships.count(sorted_ships[0]) if false else sorted_ships.size()

		for i in range(sorted_ships.size()):
			var s: Dictionary = sorted_ships[i]
			var role: String  = _read_tactics(s).get("role", "brawler")

			# Offset in axis/perp basis
			var local_offset: Vector2 = slot_offset(shape, i, sorted_ships.size(), spacing, depth, role)

			# Convert to world coordinates: centroid + axis*local.y + perp*local.x
			# local.x → spread along perp; local.y → depth along axis
			var world_slot: Vector2 = own_centroid + axis * local_offset.y + perp * local_offset.x

			slot_map[s.get("ship_id", "")] = {
				"formation_slot":  world_slot,
				"anchor_position": anchor,
			}

	# Rebuild the array with stamped orders; non-operational ships pass through unchanged.
	var result: Array = []
	for ship in ships:
		if ship == null:
			result.append(ship)
			continue
		var sid: String = ship.get("ship_id", "")
		if slot_map.has(sid):
			var updated: Dictionary = ship.duplicate(true)
			var orders: Dictionary  = updated.get("orders", {}).duplicate(true)
			orders["formation_slot"]  = slot_map[sid]["formation_slot"]
			orders["anchor_position"] = slot_map[sid]["anchor_position"]
			updated["orders"] = orders
			result.append(updated)
		else:
			result.append(ship)
	return result


## Return a 2D offset for a ship's formation slot in the (perp, axis) basis.
##   x → spread along perp (lateral)
##   y → depth along axis (+y = forward toward enemy, -y = rearward)
##
## All distances in world units, derived from named consts + dial scalars.
static func slot_offset(
	shape: String,
	index: int,
	count: int,
	spacing: float,
	depth: float,
	_role: String
) -> Vector2:
	var sep: float = SPACING_UNIT * lerp(SPACING_TIGHT_FACTOR, SPACING_LOOSE_FACTOR, spacing)

	match shape:
		"wall", "line_abreast":
			return _wall_offset(index, count, sep)
		"wedge":
			return _wedge_offset(index, count, sep)
		"layered":
			return _layered_offset(index, count, sep, depth)
		"vanguard_reserve":
			return _vanguard_reserve_offset(index, count, sep)
		"globe":
			# Globe falls back to wall for 2D; true sphere needs 3D.
			return _wall_offset(index, count, sep)
		_:
			return _wall_offset(index, count, sep)


# ── Shape geometry ────────────────────────────────────────────────────────────

## Wall / line_abreast: ships spread evenly along perp, centered.
## The line sits WALL_REAR_OFFSET behind the centroid so it is visually
## distinct from the wedge's lead ship which is ahead.
static func _wall_offset(index: int, count: int, sep: float) -> Vector2:
	# Center the line: index 0 at -(count-1)/2 * sep, last at +(count-1)/2 * sep
	var center: float = float(count - 1) / 2.0
	var lateral: float = (float(index) - center) * sep
	return Vector2(lateral, -WALL_REAR_OFFSET)   # slight rear bias, flat line


## Wedge: V/arrow shape pointing toward enemy.
##   index 0  → lead ship, furthest forward along +axis
##   remaining → split into left/right arms, stepping back and outward
static func _wedge_offset(index: int, count: int, sep: float) -> Vector2:
	if index == 0:
		return Vector2(0.0, WEDGE_LEAD_FORWARD)   # lead ship: ahead of centroid

	# Remaining ships fill the arms alternating left/right.
	var arm_rank: int  = (index - 1) / 2 + 1   # 1, 1, 2, 2, 3, 3, ...
	var side: int      = 1 if (index % 2 == 1) else -1   # odd→right, even→left

	var lateral: float = side * arm_rank * sep * cos(WEDGE_ARM_ANGLE)
	var forward: float = -arm_rank * WEDGE_ARM_DEPTH_STEP   # step back from centroid

	# Clamp lateral so wide wedges don't degenerate on small counts
	lateral = clampf(lateral, -sep * count * 0.5, sep * count * 0.5)
	return Vector2(lateral, forward)


## Layered: rows stacked along axis; ships within each row spread along perp.
## Row 0 is closest to the enemy (+axis); higher rows step back by depth.
static func _layered_offset(index: int, count: int, sep: float, depth: float) -> Vector2:
	var cols: int    = maxi(1, mini(LAYER_COLUMNS, count))
	var col: int     = index % cols
	var row: int     = index / cols

	var total_rows: int = (count + cols - 1) / cols   # ceil division
	var row_step: float = LAYER_MAX_DEPTH * depth / maxf(1.0, float(total_rows - 1))

	# Center the column spread
	var col_center: float = float(cols - 1) / 2.0
	var lateral: float    = (float(col) - col_center) * sep

	# Row 0 forward (closer to enemy), higher rows step back
	var forward: float = -float(row) * row_step

	return Vector2(lateral, forward)


## Vanguard/Reserve: front half pushed forward, rear half pushed back.
static func _vanguard_reserve_offset(index: int, count: int, sep: float) -> Vector2:
	var half: int = count / 2
	var in_vanguard: bool = index < half + (count % 2)   # lead group gets the odd one

	var group_index: int
	var group_count: int
	var axis_offset: float

	if in_vanguard:
		group_index = index
		group_count = half + (count % 2)
		axis_offset = VANGUARD_FORWARD
	else:
		group_index = index - (half + (count % 2))
		group_count = maxi(1, half)
		axis_offset = -RESERVE_REAR

	# Spread within the group along perp
	var center: float  = float(group_count - 1) / 2.0
	var lateral: float = (float(group_index) - center) * sep

	return Vector2(lateral, axis_offset)


# ── Helpers ───────────────────────────────────────────────────────────────────

## Group operational ships by team int.
static func _group_by_team(ships: Array) -> Dictionary:
	var result: Dictionary = {}
	for s in ships:
		if s == null:
			continue
		if s.get("status", "") != OPERATIONAL_STATUS:
			continue
		var team: int = s.get("team", -1)
		if not result.has(team):
			result[team] = []
		result[team].append(s)
	return result


## Centroid (average position) of a list of ship dicts.
static func _centroid(ship_list: Array) -> Vector2:
	if ship_list.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for s in ship_list:
		total += s.get("position", Vector2.ZERO)
	return total / float(ship_list.size())


## Centroid of a bare list of Vector2 positions.
static func _centroid_of_positions(positions: Array) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for p in positions:
		total += p
	return total / float(positions.size())


## Read the tactics dict from the first crew member of a ship, if present.
## Returns {} when no crew or no tactics block exists.
static func _read_tactics(ship: Dictionary) -> Dictionary:
	var crew: Array = ship.get("crew", [])
	if crew.is_empty():
		return {}
	return crew[0].get("tactics", {})
