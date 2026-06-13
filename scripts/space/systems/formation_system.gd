class_name FormationSystem
extends RefCounted

## Formation slot resolver — pure per-frame geometry execution.
##
## The squadron leader's crew decision (in CrewAISystem) issues formation_slot
## orders down the command chain.  Each pilot absorbs the order into
## crew["formation_assignment"] and stamps it onto ship.orders.  This system
## then resolves those assignments into live world positions each frame,
## because the lead ship and enemy centroid move continuously.
##
## assign_slots() reads ship.orders.formation_assignment (set by the pilot's
## absorbed order) and writes ship.orders.formation_slot + anchor_position.
## Ships with no formation_assignment get their slot/anchor cleared.
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

# ── Facing axis ───────────────────────────────────────────────────────────────
## Minimum speed for the lead ship's velocity to count as a heading hint.
const MIN_LEAD_SPEED_FOR_HEADING := 10.0


# ── Public API ────────────────────────────────────────────────────────────────

## Resolve formation slots for every ship that has a formation_assignment.
## Reads ship.orders.formation_assignment (stamped by the pilot's absorbed
## formation_slot order) and writes formation_slot + anchor_position.
## Ships with no assignment get their formation_slot/anchor_position cleared.
## Returns a NEW Array of ship dicts; inputs are not mutated.
static func assign_slots(ships: Array) -> Array:
	# Build ship_id → ship lookup for fast lead-ship resolution.
	var ship_lookup: Dictionary = {}
	for ship in ships:
		if ship == null:
			continue
		ship_lookup[ship.get("ship_id", "")] = ship

	var result: Array = []
	for ship in ships:
		if ship == null:
			result.append(ship)
			continue

		var orders: Dictionary = ship.get("orders", {})
		var fa: Variant = orders.get("formation_assignment", null)

		if fa == null or not fa is Dictionary:
			# No assignment — clear stale formation pull and pass through.
			var cleared: Dictionary = ship.duplicate(true)
			var cleared_orders: Dictionary = cleared.get("orders", {}).duplicate(true)
			cleared_orders.erase("formation_slot")
			cleared_orders.erase("anchor_position")
			cleared["orders"] = cleared_orders
			result.append(cleared)
			continue

		var lead_ship: Variant = ship_lookup.get(fa.get("lead_ship_id", ""), null)
		if lead_ship == null:
			result.append(ship)
			continue

		# Facing axis: lead → enemy centroid, or lead velocity heading.
		var axis_angle: float = _compute_facing_axis(lead_ship, ships)
		var axis: Vector2 = Vector2(cos(axis_angle), sin(axis_angle))
		var perp: Vector2 = axis.rotated(PI / 2.0)

		var local_offset: Vector2 = slot_offset(
			fa.get("shape", "line_abreast"),
			fa.get("slot_index", 0),
			fa.get("slot_count", 1),
			fa.get("spacing", 0.5),
			0.5,  # depth — leader may extend this in a future step
			"wingman"
		)

		# Convert to world coordinates: lead_pos + axis*local.y + perp*local.x
		# local.x → spread along perp; local.y → depth along axis
		var lead_pos: Vector2 = lead_ship.get("position", Vector2.ZERO)
		var world_slot: Vector2 = lead_pos + axis * local_offset.y + perp * local_offset.x

		var updated: Dictionary = ship.duplicate(true)
		var updated_orders: Dictionary = updated.get("orders", {}).duplicate(true)
		updated_orders["formation_slot"]  = world_slot
		updated_orders["anchor_position"] = lead_pos
		updated["orders"] = updated_orders
		result.append(updated)

	return result


## Compute the facing angle (radians) from lead ship toward nearest enemy centroid.
## Falls back to lead velocity heading, then to 0.0 if stationary.
static func _compute_facing_axis(lead_ship: Dictionary, all_ships: Array) -> float:
	var lead_team: int = lead_ship.get("team", -1)
	var lead_pos: Vector2 = lead_ship.get("position", Vector2.ZERO)

	# Collect enemy positions.
	var enemy_positions: Array = []
	for ship in all_ships:
		if ship == null:
			continue
		if ship.get("team", -1) == lead_team or ship.get("team", -1) < 0:
			continue
		if ship.get("status", "") != OPERATIONAL_STATUS:
			continue
		enemy_positions.append(ship.get("position", Vector2.ZERO))

	if not enemy_positions.is_empty():
		var centroid: Vector2 = _centroid_of_positions(enemy_positions)
		var to_enemy: Vector2 = centroid - lead_pos
		if to_enemy.length() > 1.0:
			return to_enemy.angle()

	# Fallback: lead ship velocity heading.
	var vel: Vector2 = lead_ship.get("velocity", Vector2.ZERO)
	if vel.length() > MIN_LEAD_SPEED_FOR_HEADING:
		return vel.angle()

	return 0.0


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

## Centroid of a bare list of Vector2 positions.
static func _centroid_of_positions(positions: Array) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for p in positions:
		total += p
	return total / float(positions.size())
