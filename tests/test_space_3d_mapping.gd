extends GutTest

## Tests for the pure 2D->3D coordinate mapping used by Renderer3D.
## The invariant: a 3D point (x, z) must land on screen exactly where
## the 2D point (x, y) does, and a yawed Node3D must face where the
## 2D entity faces.

const ANGLE_TOLERANCE: float = 0.0001

func test_position_maps_x_to_x_and_y_to_z() -> void:
	var mapped := Space3DMapping.to_3d_position(Vector2(120.0, -45.0))
	assert_eq(mapped.x, 120.0, "2D X must map to 3D X")
	assert_eq(mapped.z, -45.0, "2D Y must map to 3D Z")
	assert_eq(mapped.y, Space3DMapping.BATTLE_PLANE_Y, "Entities sit on the battle plane")

func test_position_respects_height_override() -> void:
	var mapped := Space3DMapping.to_3d_position(Vector2.ZERO, 50.0)
	assert_eq(mapped.y, 50.0)

func test_yaw_makes_3d_forward_match_2d_facing() -> void:
	# 2D facing at rotation r is Vector2(sin(r), -cos(r)) (rotation 0 = north)
	for rotation_2d in [0.0, PI / 4.0, PI / 2.0, PI, -PI / 3.0, 2.7]:
		var facing_2d := Vector2(sin(rotation_2d), -cos(rotation_2d))
		var forward_2d := Space3DMapping.yaw_forward_2d(Space3DMapping.to_3d_yaw(rotation_2d))
		assert_almost_eq(forward_2d.x, facing_2d.x, ANGLE_TOLERANCE,
			"forward X mismatch at rotation %f" % rotation_2d)
		assert_almost_eq(forward_2d.y, facing_2d.y, ANGLE_TOLERANCE,
			"forward Y mismatch at rotation %f" % rotation_2d)

func test_local_offset_preserves_lateral_and_forward_axes() -> void:
	# A point ahead of the ship (-Y in 2D local space) must be ahead in 3D (-Z)
	var ahead := Space3DMapping.to_3d_local_offset(Vector2(0.0, -10.0))
	assert_eq(ahead.z, -10.0)
	# A point to the right (+X) stays to the right
	var right := Space3DMapping.to_3d_local_offset(Vector2(7.0, 0.0))
	assert_eq(right.x, 7.0)

func test_ortho_size_matches_camera2d_zoom() -> void:
	# Camera2D shows viewport_height / zoom world units vertically;
	# the ortho camera size must equal that for a 1:1 screen match.
	var viewport_height := 1080.0
	assert_eq(Space3DMapping.ortho_size_for_zoom(viewport_height, 1.0), viewport_height)
	assert_eq(Space3DMapping.ortho_size_for_zoom(viewport_height, 2.0), viewport_height / 2.0)

func test_ortho_size_inversely_proportional_to_zoom() -> void:
	var zoomed_out := Space3DMapping.ortho_size_for_zoom(1000.0, 0.05)
	var zoomed_in := Space3DMapping.ortho_size_for_zoom(1000.0, 2.0)
	assert_gt(zoomed_out, zoomed_in, "Zooming out must widen the 3D view")
