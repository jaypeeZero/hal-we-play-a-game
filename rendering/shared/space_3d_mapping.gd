class_name Space3DMapping
extends RefCounted

## Pure conversion functions between the 2D game world and the 3D visual world.
##
## 2D game world: +X right, +Y down, rotation 0 faces -Y (north),
## positive rotation turns clockwise on screen.
## 3D visual world: battle plane at Y = BATTLE_PLANE_Y, +X right,
## +Z is screen-down. The camera looks straight down -Y, so 3D (x, z)
## lands on screen exactly where 2D (x, y) does.

const BATTLE_PLANE_Y: float = 0.0

## Map a 2D world position onto the 3D battle plane.
static func to_3d_position(position_2d: Vector2, height: float = BATTLE_PLANE_Y) -> Vector3:
	return Vector3(position_2d.x, height, position_2d.y)

## Map a 2D rotation to a Node3D yaw so the node's -Z forward points
## where the 2D entity faces (2D facing = Vector2(sin(r), -cos(r))).
static func to_3d_yaw(rotation_2d: float) -> float:
	return -rotation_2d

## Map an entity-local 2D offset (e.g. component position_offset) to an
## offset local to a yaw-rotated Node3D on the battle plane.
static func to_3d_local_offset(offset_2d: Vector2) -> Vector3:
	return Vector3(offset_2d.x, 0.0, offset_2d.y)

## Forward direction of a Node3D with the given yaw, projected to 2D.
## Exists so tests can verify yaw mapping against 2D facing.
static func yaw_forward_2d(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))

## Orthographic camera size (vertical world-units in view) that matches
## a Camera2D at the given zoom in a viewport of the given pixel height.
static func ortho_size_for_zoom(viewport_height_px: float, zoom: float) -> float:
	return viewport_height_px / zoom
