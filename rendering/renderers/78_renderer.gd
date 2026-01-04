class_name Renderer78 extends IVisualRenderer

## 78 Renderer - Uses HullShapes data for ship visualization
## Same visual style as the Ship Editor - line-based outlines with semi-transparent fills

var _theme: IVisualTheme = null
var _entity_visuals: Dictionary = {}  # entity_id -> Dictionary of visual nodes
var _component_visuals: Dictionary = {}  # entity_id -> Dictionary[component_id -> Node]

func initialize(theme: IVisualTheme) -> void:
	_theme = theme
	name = "Renderer78"
	print("Renderer78 initialized - using HullShapes data")

func attach_to_entity(entity: IRenderable) -> void:
	var entity_id: String = entity.get_entity_id()
	var visual_type: String = entity.get_visual_type()

	var visual_node: Node2D = null

	# Create visuals based on type
	if visual_type.begins_with("ship_"):
		visual_node = _create_ship_visual(entity, visual_type)
	elif visual_type == "space_projectile":
		visual_node = _create_projectile_visual(entity)
	else:
		visual_node = _create_fallback_visual()

	# Add as child of entity
	entity.add_child(visual_node)

	# Store reference
	_entity_visuals[entity_id] = {
		"root": visual_node,
		"entity": entity
	}

func detach_from_entity(entity: IRenderable) -> void:
	var entity_id = entity.get_entity_id()
	if _entity_visuals.has(entity_id):
		var visual = _entity_visuals[entity_id]
		if visual.root and is_instance_valid(visual.root):
			visual.root.queue_free()
		_entity_visuals.erase(entity_id)

	# Clean up component visuals
	if _component_visuals.has(entity_id):
		_component_visuals.erase(entity_id)

func update_state(entity_id: String, state: EntityState) -> void:
	if not _entity_visuals.has(entity_id):
		return

	var visual = _entity_visuals[entity_id]
	if not visual.root or not is_instance_valid(visual.root):
		return

	# Update section colors based on per-section damage
	if state.section_damage.size() > 0:
		HullShapeDrawer.update_section_damage(visual.root, state.section_damage)

	# Update component visuals if present
	if state.components.size() > 0:
		_update_components(entity_id, state.components, visual.root, state.is_main_engine_firing, state.maneuvering_thrust_direction)

	# Update based on state flags
	if state.has_flag("destroyed"):
		_show_destruction_effect(visual)

	# Update wing circle visual
	_update_wing_circle(visual.root, state.wing_color)

	# Update debug visuals
	_update_pilot_direction_line(visual.root, state.debug_pilot_direction)
	_update_leader_number(visual.root, state.debug_leader_number)

func play_animation(entity_id: String, request: AnimationRequest) -> void:
	# Animations handled by state changes in this renderer
	pass

func cleanup() -> void:
	for entity_id in _entity_visuals:
		detach_from_entity(_entity_visuals[entity_id].entity)
	_entity_visuals.clear()
	_component_visuals.clear()

## Create ship visual using HullShapeDrawer
func _create_ship_visual(entity: IRenderable, visual_type: String) -> Node2D:
	# Get ship data
	var ship_data = {}
	if entity.has_method("get_ship_data"):
		ship_data = entity.get_ship_data()

	var ship_type = visual_type.replace("ship_", "")
	var team = ship_data.get("team", 0)

	# Create ship using shared HullShapeDrawer
	# Don't rotate for display - ships face up (north) in game
	var container = HullShapeDrawer.create_ship_visual(ship_type, team, 1.0, false)
	container.name = "78ShipVisual"

	# Store team in metadata
	container.set_meta("team", team)

	return container

## Create projectile visual
func _create_projectile_visual(entity: IRenderable) -> Node2D:
	var container = Node2D.new()
	container.name = "78ProjectileVisual"

	# Small glowing circle in armor color
	var radius = 3.0
	var circle = Polygon2D.new()
	circle.name = "ProjectileBody"

	var points = PackedVector2Array()
	var segments = 6
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	circle.polygon = points
	circle.color = HullShapeDrawer.COLOR_ARMOR.lightened(0.3)
	container.add_child(circle)

	# Outline
	var outline = Line2D.new()
	outline.name = "Outline"
	for i in range(segments + 1):
		var angle = (float(i) / segments) * TAU
		outline.add_point(Vector2(cos(angle), sin(angle)) * radius)
	outline.default_color = HullShapeDrawer.COLOR_ARMOR
	outline.width = 1.5
	container.add_child(outline)

	# Trail
	var trail = Line2D.new()
	trail.name = "Trail"
	trail.add_point(Vector2.ZERO)
	trail.add_point(Vector2(0, 10))  # Trail behind (ships face up/-Y)
	trail.default_color = Color(HullShapeDrawer.COLOR_ARMOR, 0.5)
	trail.width = 2.0
	container.add_child(trail)

	return container

## Create fallback visual
func _create_fallback_visual() -> Node2D:
	var container = Node2D.new()
	container.name = "78FallbackVisual"

	var polygon = Polygon2D.new()
	polygon.polygon = PackedVector2Array([
		Vector2(-10, -10),
		Vector2(10, -10),
		Vector2(10, 10),
		Vector2(-10, 10)
	])
	polygon.color = HullShapeDrawer.COLOR_ARMOR.darkened(0.5)
	container.add_child(polygon)

	return container

## Update component visuals based on state
func _update_components(entity_id: String, components: Array[Dictionary], parent_node: Node2D, is_main_engine_firing: bool, maneuvering_thrust_direction: Vector2) -> void:
	# Initialize component visuals dictionary for this entity if needed
	if entity_id not in _component_visuals:
		_component_visuals[entity_id] = {}

	var component_dict: Dictionary = _component_visuals[entity_id]
	var current_component_ids: Array = []

	# Create or update components
	for component_data in components:
		var component_id: String = component_data.component_id
		current_component_ids.append(component_id)

		# Create component visual if it doesn't exist
		if component_id not in component_dict:
			var component_visual = _create_component_visual(component_data)
			if component_visual:
				parent_node.add_child(component_visual)
				component_dict[component_id] = component_visual

		# Update component position and rotation
		if component_id in component_dict:
			var component_visual: Node2D = component_dict[component_id]
			if is_instance_valid(component_visual):
				component_visual.position = component_data.position_offset
				component_visual.rotation = component_data.rotation

				# Update visual based on status and thrust state
				if component_data.component_type == "engine":
					HullShapeDrawer.set_engine_thrust(component_visual, is_main_engine_firing, component_data.status)

	# Remove components that no longer exist
	var to_remove: Array = []
	for component_id in component_dict.keys():
		if component_id not in current_component_ids:
			to_remove.append(component_id)

	for component_id in to_remove:
		if is_instance_valid(component_dict[component_id]):
			component_dict[component_id].queue_free()
		component_dict.erase(component_id)

## Create visual node for a component using HullShapeDrawer
func _create_component_visual(component_data: Dictionary) -> Node2D:
	var component_type: String = component_data.component_type
	var position_offset: Vector2 = component_data.position_offset
	var rotation: float = component_data.rotation

	if component_type == "weapon":
		var visual = HullShapeDrawer.create_weapon_visual(Vector2.ZERO, 0.0, 1.0, false)
		visual.name = "Component_" + component_data.component_id
		return visual
	elif component_type == "engine":
		var visual = HullShapeDrawer.create_engine_visual(Vector2.ZERO, 1.0, false)
		visual.name = "Component_" + component_data.component_id
		return visual

	return null

## Show destruction effect
func _show_destruction_effect(visual: Dictionary) -> void:
	var root = visual.root
	if not root or not is_instance_valid(root):
		return

	# Flash red and fade out
	var tween = root.create_tween()
	tween.tween_property(root, "modulate", Color.RED, 0.1)
	tween.tween_property(root, "modulate:a", 0.0, 0.9)

## Update wing circle visual based on wing color
func _update_wing_circle(parent_node: Node2D, wing_color: Color) -> void:
	var wing_circle = parent_node.get_node_or_null("WingCircle")

	# If no wing (transparent color), hide/remove circle
	if wing_color.a < 0.01:
		if wing_circle:
			wing_circle.visible = false
		return

	# Create wing circle if it doesn't exist
	if not wing_circle:
		wing_circle = Line2D.new()
		wing_circle.name = "WingCircle"
		wing_circle.width = 2.0
		wing_circle.closed = true

		# Create circle points
		var points = PackedVector2Array()
		var segments = 24
		for i in range(segments):
			var angle = (float(i) / segments) * TAU
			points.append(Vector2(cos(angle), sin(angle)) * 35.0)
		wing_circle.points = points

		# Add behind other visuals (z_index or add first)
		wing_circle.z_index = -1
		parent_node.add_child(wing_circle)

	# Update color and visibility
	wing_circle.default_color = wing_color
	wing_circle.visible = true

## Update pilot direction line debug visual
func _update_pilot_direction_line(parent_node: Node2D, direction: Vector2) -> void:
	const DEBUG_LINE_LENGTH: float = 60.0
	const DEBUG_LINE_COLOR: Color = Color(1.0, 1.0, 0.0, 0.8)  # Yellow
	const DEBUG_LINE_WIDTH: float = 2.0

	var direction_line = parent_node.get_node_or_null("DebugDirectionLine")

	# If no direction (zero vector), hide/remove line
	if direction.length_squared() < 0.001:
		if direction_line:
			direction_line.visible = false
		return

	# Create direction line if it doesn't exist
	if not direction_line:
		direction_line = Line2D.new()
		direction_line.name = "DebugDirectionLine"
		direction_line.width = DEBUG_LINE_WIDTH
		direction_line.default_color = DEBUG_LINE_COLOR
		direction_line.z_index = 10  # Draw above other elements
		parent_node.add_child(direction_line)

	# Update line points - line goes from ship center in the direction
	# Need to account for ship rotation since the line is a child of the ship
	var ship_rotation = parent_node.get_parent().rotation if parent_node.get_parent() else 0.0
	var local_direction = direction.rotated(-ship_rotation)

	direction_line.clear_points()
	direction_line.add_point(Vector2.ZERO)
	direction_line.add_point(local_direction * DEBUG_LINE_LENGTH)
	direction_line.visible = true

## Update leader number debug visual
func _update_leader_number(parent_node: Node2D, leader_number: int) -> void:
	const LABEL_OFFSET: Vector2 = Vector2(0, -50)  # Above the ship
	const LABEL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)  # White
	const LABEL_FONT_SIZE: int = 16

	var leader_label = parent_node.get_node_or_null("DebugLeaderLabel")

	# If not a leader (0), hide label
	if leader_number <= 0:
		if leader_label:
			leader_label.visible = false
		return

	# Create label if it doesn't exist
	if not leader_label:
		leader_label = Label.new()
		leader_label.name = "DebugLeaderLabel"
		leader_label.add_theme_color_override("font_color", LABEL_COLOR)
		leader_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		leader_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		leader_label.z_index = 10  # Draw above other elements
		parent_node.add_child(leader_label)

	# Update label text and position
	# Counter-rotate to keep text upright (since it's a child of rotating ship)
	var ship_rotation = parent_node.get_parent().rotation if parent_node.get_parent() else 0.0
	leader_label.rotation = -ship_rotation
	leader_label.position = LABEL_OFFSET.rotated(-ship_rotation)
	leader_label.text = str(leader_number)
	leader_label.visible = true
