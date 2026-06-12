extends GutTest

## Tests for Renderer3D - FUNCTIONALITY ONLY
## Exercises renderer lifecycle and the auto-fit sizing without a display.

## Minimal IRenderable stand-in so tests don't depend on ShipEntity internals.
class FakeShip extends IRenderable:
	var _id: String
	var _visual_type: String
	var _team: int

	func _init(id: String, visual_type: String, team: int = 0) -> void:
		_id = id
		_visual_type = visual_type
		_team = team

	func get_entity_id() -> String:
		return _id

	func get_visual_type() -> String:
		return _visual_type

	func get_ship_data() -> Dictionary:
		return {"team": _team, "ship_type": _visual_type.trim_prefix("ship_")}

var _renderer: Renderer3D

func before_each() -> void:
	_renderer = Renderer3D.new()
	add_child_autofree(_renderer)
	_renderer.initialize()

func _attach(id: String, visual_type: String, pos: Vector2 = Vector2.ZERO) -> FakeShip:
	var ship := FakeShip.new(id, visual_type)
	ship.global_position = pos
	add_child_autofree(ship)
	_renderer.attach_to_entity(ship)
	return ship

# ============================================================================
# LIFECYCLE
# ============================================================================

func test_initialize_builds_a_world_and_camera():
	assert_true(is_instance_valid(_renderer._world), "Renderer should build a 3D world")
	assert_true(is_instance_valid(_renderer._camera_3d), "Renderer should build a camera")
	assert_eq(_renderer._camera_3d.projection, Camera3D.PROJECTION_ORTHOGONAL,
		"Top-down camera must be orthographic")

func test_attaching_a_ship_loads_the_model():
	_attach("a", "ship_fighter")
	assert_true(_renderer._visuals.has("a"), "Attached ship should be tracked")
	var root: Node3D = _renderer._visuals["a"].root
	assert_true(is_instance_valid(root.get_node_or_null("Model")),
		"A real model should load for a configured ship type")

func test_detach_removes_the_visual():
	_attach("b", "ship_fighter")
	_renderer.detach_from_entity(_renderer._visuals["b"].entity)
	assert_false(_renderer._visuals.has("b"), "Detached ship should be untracked")

# ============================================================================
# AUTO-FIT SIZING
# ============================================================================

func test_model_is_fit_to_ship_footprint():
	# Auto-fit should size any model to the ship's footprint regardless of the
	# model's authored scale.
	_attach("c", "ship_fighter")
	var model: Node3D = _renderer._visuals["c"].root.get_node("Model")
	var aabb: AABB = _renderer._merged_aabb(model, model.transform)
	var extent: float = maxf(aabb.size.x, aabb.size.z)
	var expected: float = HullShapes.get_base_size("fighter")
	assert_almost_eq(extent, expected, expected * 0.05,
		"Fitted model footprint should match the fighter's base size")

func test_capital_fits_larger_than_fighter():
	_attach("fig", "ship_fighter")
	_attach("cap", "ship_capital")
	var fig_model: Node3D = _renderer._visuals["fig"].root.get_node("Model")
	var cap_model: Node3D = _renderer._visuals["cap"].root.get_node("Model")
	var fig_extent: float = maxf(_renderer._merged_aabb(fig_model, fig_model.transform).size.x,
		_renderer._merged_aabb(fig_model, fig_model.transform).size.z)
	var cap_extent: float = maxf(_renderer._merged_aabb(cap_model, cap_model.transform).size.x,
		_renderer._merged_aabb(cap_model, cap_model.transform).size.z)
	assert_gt(cap_extent, fig_extent, "Capital should fit larger than a fighter")
