class_name FleeBoundarySystem
extends RefCounted

## The escape boundary: a large ovoid (ellipse) centered on the battlefield.
## Ships that commit to fleeing run for the edge and leave the battle when they
## cross it; ships that don't must turn back inward.
##
## Pure geometry — no state. Sized to ~3x the inter-fleet spawn distance across,
## with the vertical axis scaled to the battlefield's aspect so it reads as an
## ovoid rather than a circle.

## Horizontal span of the boundary as a multiple of the inter-fleet spawn distance.
const BOUNDARY_SPAWN_MULTIPLE := 3.0
## Normalized ellipse distance at which a ship's flee decision fires.
const NEAR_EDGE_FRACTION := 0.85
## A "returning" ship's flee lock clears once it is back inside this fraction.
const RETURN_CLEAR_FRACTION := 0.6
## How far past the boundary an outward exit point sits (world units).
const EXIT_OVERSHOOT := 200.0
## Fallback arena size for any ship that has not been stamped with its own
## battlefield_size at spawn. Matches SpaceBattleGame._battlefield_size.
const DEFAULT_BATTLEFIELD_SIZE := Vector2(5000, 3500)


static func center(battlefield_size: Vector2) -> Vector2:
	return battlefield_size * 0.5


## Horizontal/vertical semi-axes of the ovoid. Horizontal span = the spawn
## multiple times the inter-fleet spawn distance; vertical keeps the
## battlefield's aspect ratio.
static func semi_axes(battlefield_size: Vector2) -> Vector2:
	var spawn_distance: float = battlefield_size.x - 2.0 * BattlePlanner.MARGIN
	var a: float = 0.5 * BOUNDARY_SPAWN_MULTIPLE * spawn_distance
	var b: float = a * (battlefield_size.y / battlefield_size.x)
	return Vector2(a, b)


## Normalized ellipse distance: <1 inside, =1 on the boundary, >1 outside.
static func normalized_distance(pos: Vector2, battlefield_size: Vector2) -> float:
	var c: Vector2 = center(battlefield_size)
	var ax: Vector2 = semi_axes(battlefield_size)
	var dx: float = (pos.x - c.x) / ax.x
	var dy: float = (pos.y - c.y) / ax.y
	return sqrt(dx * dx + dy * dy)


static func is_near_edge(pos: Vector2, battlefield_size: Vector2) -> bool:
	return normalized_distance(pos, battlefield_size) >= NEAR_EDGE_FRACTION


static func is_outside(pos: Vector2, battlefield_size: Vector2) -> bool:
	return normalized_distance(pos, battlefield_size) >= 1.0


static func is_clear_inside(pos: Vector2, battlefield_size: Vector2) -> bool:
	return normalized_distance(pos, battlefield_size) < RETURN_CLEAR_FRACTION


## A point just outside the boundary along the ship's outward radial — the exit
## a committed-to-flee ship runs for.
static func outward_exit_point(pos: Vector2, battlefield_size: Vector2) -> Vector2:
	var c: Vector2 = center(battlefield_size)
	var dir: Vector2 = pos - c
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	return c + dir.normalized() * (semi_axes(battlefield_size).length() + EXIT_OVERSHOOT)


## The battlefield center — where a "turn back" ship heads.
static func inward_point(battlefield_size: Vector2) -> Vector2:
	return center(battlefield_size)
