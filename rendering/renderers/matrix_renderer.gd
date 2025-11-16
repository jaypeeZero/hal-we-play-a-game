class_name MatrixRenderer extends IVisualRenderer

## Matrix-themed visual renderer for space combat
## Renders ships as geometric shapes with Matrix green aesthetic

# Matrix color palette
const COLOR_PRIMARY_GLOW = Color("00FF41")  # Signature Matrix green - Team 0
const COLOR_SOFT_GLOW = Color("36BA01")     # Edge highlights
const COLOR_DIM = Color("009A22")           # Inactive elements
const COLOR_HIGHLIGHT = Color("80CE87")     # Cursor/sparks
const COLOR_ERROR = Color("FF003C")         # Damage/warning
const COLOR_BACKGROUND = Color("0D0D0D")    # Deep black
const COLOR_TEAM1 = Color("CCCCCC")         # Grey/White - Team 1

var _theme: IVisualTheme = null
var _entity_visuals: Dictionary = {}  # entity_id -> Dictionary of visual nodes

func initialize(theme: IVisualTheme) -> void:
	_theme = theme
	name = "MatrixRenderer"
	print("MatrixRenderer initialized with Matrix color scheme")

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
		# Fallback to simple shape
		visual_node = _create_fallback_visual()

	# Add as child of entity
	entity.add_child(visual_node)

	# Retrieve sections from metadata if available
	var sections = {}
	if visual_node.has_meta("sections"):
		sections = visual_node.get_meta("sections")

	# Store reference
	_entity_visuals[entity_id] = {
		"root": visual_node,
		"entity": entity,
		"sections": sections
	}

func detach_from_entity(entity: IRenderable) -> void:
	var entity_id = entity.get_entity_id()
	if _entity_visuals.has(entity_id):
		var visual = _entity_visuals[entity_id]
		if visual.root and is_instance_valid(visual.root):
			visual.root.queue_free()
		_entity_visuals.erase(entity_id)

func update_state(entity_id: String, state: EntityState) -> void:
	if not _entity_visuals.has(entity_id):
		return

	var visual = _entity_visuals[entity_id]
	if not visual.root or not is_instance_valid(visual.root):
		return

	# Update section colors based on per-section damage
	if state.section_damage.size() > 0:
		_update_section_colors(visual, state.section_damage)
	else:
		# Fallback to overall health color
		_update_health_color(visual, state.health_percent)

	# Update based on state flags
	if state.has_flag("destroyed"):
		_show_destruction_effect(visual)

func play_animation(entity_id: String, request: AnimationRequest) -> void:
	# Animations handled by state changes in this renderer
	pass

func cleanup() -> void:
	for entity_id in _entity_visuals:
		detach_from_entity(_entity_visuals[entity_id].entity)
	_entity_visuals.clear()

## Create ship visual
func _create_ship_visual(entity: IRenderable, visual_type: String) -> Node2D:
	var container = Node2D.new()
	container.name = "MatrixShipVisual"

	# Get ship data
	var ship_data = {}
	if entity.has_method("get_ship_data"):
		ship_data = entity.get_ship_data()

	# Determine size and shape based on ship type
	var ship_type = visual_type.replace("ship_", "")
	var size = 20.0
	# Set color based on team: Green for Team 0, Grey/White for Team 1
	var color = COLOR_PRIMARY_GLOW if ship_data.get("team", 0) == 0 else COLOR_TEAM1
	var sections = {}

	match ship_type:
		"fighter":
			size = 15.0
			sections = _create_fighter_shape(container, size, color)
		"corvette":
			size = 25.0
			sections = _create_corvette_shape(container, size, color)
		"capital":
			size = 50.0
			sections = _create_capital_shape(container, size, color)
		_:
			_create_generic_ship_shape(container, size, color)

	# Store sections in container metadata for later retrieval
	container.set_meta("sections", sections)

	# Add team indicator
	if ship_data.has("team"):
		_add_team_indicator(container, ship_data.team)

	# Add glow effect with team-appropriate color
	_add_glow_effect(container, color)

	return container

## Create a wedge-shaped section polygon based on angle arc
func _create_section_wedge(start_angle_deg: float, end_angle_deg: float, outer_radius: float, inner_radius: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var segments = 8  # Resolution for the arc

	# Convert to radians (0 degrees = up/north in Godot)
	var start_rad = deg_to_rad(start_angle_deg - 90)  # Adjust for Godot's coordinate system
	var end_rad = deg_to_rad(end_angle_deg - 90)

	# Handle wrapping arcs (e.g., 300 to 60 wraps around 360)
	if end_angle_deg < start_angle_deg:
		end_rad += TAU

	var arc_length = end_rad - start_rad
	var step = arc_length / segments

	# Outer arc
	for i in range(segments + 1):
		var angle = start_rad + (i * step)
		points.append(Vector2(cos(angle), sin(angle)) * outer_radius)

	# Inner arc (reverse direction)
	for i in range(segments + 1):
		var angle = end_rad - (i * step)
		points.append(Vector2(cos(angle), sin(angle)) * inner_radius)

	return points

## Create fighter shape - elongated triangle, pointy front (2 sections: front, back)
func _create_fighter_shape(container: Node2D, size: float, color: Color) -> Dictionary:
	var sections = {}

	# Fighter dimensions - elongated triangle
	var length = size * 1.6  # Make it elongated
	var width = size * 0.8
	var nose_y = -length
	var tail_y = length * 0.3
	var mid_y = 0  # Split point between front and back sections

	# Front section (pointy nose to middle)
	var front_armor = Polygon2D.new()
	front_armor.name = "Armor"
	front_armor.polygon = PackedVector2Array([
		Vector2(0, nose_y),              # Nose point
		Vector2(-width * 0.5, mid_y),    # Left mid
		Vector2(width * 0.5, mid_y)      # Right mid
	])
	front_armor.color = color

	var front_internal = Polygon2D.new()
	front_internal.name = "Internal"
	front_internal.polygon = PackedVector2Array([
		Vector2(0, nose_y * 0.7),        # Nose (scaled inward)
		Vector2(-width * 0.3, mid_y),    # Left mid (narrower)
		Vector2(width * 0.3, mid_y)      # Right mid (narrower)
	])
	front_internal.color = color.darkened(0.3)

	var front_container = Node2D.new()
	front_container.name = "Section_front"
	front_container.add_child(front_armor)
	front_container.add_child(front_internal)
	container.add_child(front_container)

	sections["front"] = {
		"armor": front_armor,
		"internal": front_internal
	}

	# Back section (middle to tail)
	var back_armor = Polygon2D.new()
	back_armor.name = "Armor"
	back_armor.polygon = PackedVector2Array([
		Vector2(-width * 0.5, mid_y),    # Left mid
		Vector2(-width * 0.4, tail_y),   # Left tail
		Vector2(width * 0.4, tail_y),    # Right tail
		Vector2(width * 0.5, mid_y)      # Right mid
	])
	back_armor.color = color

	var back_internal = Polygon2D.new()
	back_internal.name = "Internal"
	back_internal.polygon = PackedVector2Array([
		Vector2(-width * 0.3, mid_y),    # Left mid (narrower)
		Vector2(-width * 0.2, tail_y * 0.8),  # Left tail (scaled inward)
		Vector2(width * 0.2, tail_y * 0.8),   # Right tail (scaled inward)
		Vector2(width * 0.3, mid_y)      # Right mid (narrower)
	])
	back_internal.color = color.darkened(0.3)

	var back_container = Node2D.new()
	back_container.name = "Section_back"
	back_container.add_child(back_armor)
	back_container.add_child(back_internal)
	container.add_child(back_container)

	sections["back"] = {
		"armor": back_armor,
		"internal": back_internal
	}

	# Add outline for the whole ship
	var line = Line2D.new()
	line.name = "ShipOutline"
	line.add_point(Vector2(0, nose_y))
	line.add_point(Vector2(-width * 0.5, mid_y))
	line.add_point(Vector2(-width * 0.4, tail_y))
	line.add_point(Vector2(width * 0.4, tail_y))
	line.add_point(Vector2(width * 0.5, mid_y))
	line.add_point(Vector2(0, nose_y))
	line.default_color = COLOR_SOFT_GLOW
	line.width = 2.0
	container.add_child(line)

	return sections

## Create corvette shape - hammerhead front, thin body, thick oval rear (3 sections)
func _create_corvette_shape(container: Node2D, size: float, color: Color) -> Dictionary:
	var sections = {}

	# Corvette dimensions
	var body_width = size * 0.4  # Thin body
	var hammer_width = size * 0.9  # Wide hammerhead
	var rear_width = size * 0.7  # Thick rear
	var front_y = -size * 1.2
	var front_mid_y = -size * 0.4
	var rear_mid_y = size * 0.4
	var rear_y = size * 1.2

	# FRONT SECTION - Hammerhead
	var front_armor = Polygon2D.new()
	front_armor.name = "Armor"
	front_armor.polygon = PackedVector2Array([
		Vector2(-hammer_width * 0.5, front_y),      # Left hammerhead edge
		Vector2(hammer_width * 0.5, front_y),       # Right hammerhead edge
		Vector2(body_width * 0.5, front_mid_y),     # Right body connection
		Vector2(-body_width * 0.5, front_mid_y)     # Left body connection
	])
	front_armor.color = color

	var front_internal = Polygon2D.new()
	front_internal.name = "Internal"
	front_internal.polygon = PackedVector2Array([
		Vector2(-hammer_width * 0.35, front_y * 0.85),  # Left (scaled inward)
		Vector2(hammer_width * 0.35, front_y * 0.85),   # Right (scaled inward)
		Vector2(body_width * 0.3, front_mid_y),         # Right body
		Vector2(-body_width * 0.3, front_mid_y)         # Left body
	])
	front_internal.color = color.darkened(0.3)

	var front_container = Node2D.new()
	front_container.name = "Section_front"
	front_container.add_child(front_armor)
	front_container.add_child(front_internal)
	container.add_child(front_container)

	sections["front"] = {
		"armor": front_armor,
		"internal": front_internal
	}

	# MIDDLE SECTION - Thin rectangle body
	var middle_armor = Polygon2D.new()
	middle_armor.name = "Armor"
	middle_armor.polygon = PackedVector2Array([
		Vector2(-body_width * 0.5, front_mid_y),    # Left front
		Vector2(body_width * 0.5, front_mid_y),     # Right front
		Vector2(body_width * 0.5, rear_mid_y),      # Right rear
		Vector2(-body_width * 0.5, rear_mid_y)      # Left rear
	])
	middle_armor.color = color

	var middle_internal = Polygon2D.new()
	middle_internal.name = "Internal"
	middle_internal.polygon = PackedVector2Array([
		Vector2(-body_width * 0.3, front_mid_y),    # Left front (narrower)
		Vector2(body_width * 0.3, front_mid_y),     # Right front (narrower)
		Vector2(body_width * 0.3, rear_mid_y),      # Right rear (narrower)
		Vector2(-body_width * 0.3, rear_mid_y)      # Left rear (narrower)
	])
	middle_internal.color = color.darkened(0.3)

	var middle_container = Node2D.new()
	middle_container.name = "Section_middle"
	middle_container.add_child(middle_armor)
	middle_container.add_child(middle_internal)
	container.add_child(middle_container)

	sections["middle"] = {
		"armor": middle_armor,
		"internal": middle_internal
	}

	# BACK SECTION - Thick oval rear
	var back_armor = Polygon2D.new()
	back_armor.name = "Armor"
	# Create rounded rear with multiple points
	var back_points = PackedVector2Array([
		Vector2(-body_width * 0.5, rear_mid_y),     # Left body connection
		Vector2(-rear_width * 0.5, rear_mid_y + (rear_y - rear_mid_y) * 0.3),  # Left side bulge
		Vector2(-rear_width * 0.4, rear_y * 0.85),  # Left rear curve
		Vector2(0, rear_y),                          # Rear center point
		Vector2(rear_width * 0.4, rear_y * 0.85),   # Right rear curve
		Vector2(rear_width * 0.5, rear_mid_y + (rear_y - rear_mid_y) * 0.3),  # Right side bulge
		Vector2(body_width * 0.5, rear_mid_y)       # Right body connection
	])
	back_armor.polygon = back_points
	back_armor.color = color

	var back_internal = Polygon2D.new()
	back_internal.name = "Internal"
	var back_internal_points = PackedVector2Array([
		Vector2(-body_width * 0.3, rear_mid_y),     # Left body (narrower)
		Vector2(-rear_width * 0.35, rear_mid_y + (rear_y - rear_mid_y) * 0.3),  # Left side (scaled)
		Vector2(-rear_width * 0.25, rear_y * 0.75), # Left rear (scaled)
		Vector2(0, rear_y * 0.8),                    # Rear center (scaled)
		Vector2(rear_width * 0.25, rear_y * 0.75),  # Right rear (scaled)
		Vector2(rear_width * 0.35, rear_mid_y + (rear_y - rear_mid_y) * 0.3),  # Right side (scaled)
		Vector2(body_width * 0.3, rear_mid_y)       # Right body (narrower)
	])
	back_internal.polygon = back_internal_points
	back_internal.color = color.darkened(0.3)

	var back_container = Node2D.new()
	back_container.name = "Section_back"
	back_container.add_child(back_armor)
	back_container.add_child(back_internal)
	container.add_child(back_container)

	sections["back"] = {
		"armor": back_armor,
		"internal": back_internal
	}

	# Add outline for the whole ship
	var line = Line2D.new()
	line.name = "ShipOutline"
	line.add_point(Vector2(-hammer_width * 0.5, front_y))
	line.add_point(Vector2(hammer_width * 0.5, front_y))
	line.add_point(Vector2(body_width * 0.5, front_mid_y))
	line.add_point(Vector2(body_width * 0.5, rear_mid_y))
	for point in back_points.slice(1, back_points.size() - 1):  # Add rear curve
		line.add_point(point)
	line.add_point(Vector2(-body_width * 0.5, rear_mid_y))
	line.add_point(Vector2(-body_width * 0.5, front_mid_y))
	line.add_point(Vector2(-hammer_width * 0.5, front_y))
	line.default_color = COLOR_SOFT_GLOW
	line.width = 2.5
	container.add_child(line)

	return sections

## Create capital shape - Star Destroyer triangle (6 sections, 3x corvette length)
func _create_capital_shape(container: Node2D, size: float, color: Color) -> Dictionary:
	var sections = {}

	# Capital dimensions - Star Destroyer (3x corvette length)
	var length = size * 3.6  # 3x corvette length (corvette is 2.4 * size)
	var max_width = size * 1.8  # Wide at the back
	var nose_y = -length
	var front_split_y = -length * 0.5
	var middle_split_y = 0
	var back_y = length * 0.2

	# Calculate widths at each split
	# Star Destroyer is a triangle, so width increases linearly from nose to back
	var width_at_front = max_width * 0.2
	var width_at_middle = max_width * 0.6
	var width_at_back = max_width

	# Helper to create a section polygon
	var create_section = func(left_front: Vector2, right_front: Vector2, right_back: Vector2, left_back: Vector2, section_id: String, container_node: Node2D):
		# Armor polygon
		var armor = Polygon2D.new()
		armor.name = "Armor"
		armor.polygon = PackedVector2Array([left_front, right_front, right_back, left_back])
		armor.color = color

		# Internal polygon (scaled inward)
		var internal = Polygon2D.new()
		internal.name = "Internal"
		var center = (left_front + right_front + right_back + left_back) / 4.0
		var scale_factor = 0.6
		internal.polygon = PackedVector2Array([
			center + (left_front - center) * scale_factor,
			center + (right_front - center) * scale_factor,
			center + (right_back - center) * scale_factor,
			center + (left_back - center) * scale_factor
		])
		internal.color = color.darkened(0.3)

		var section_container = Node2D.new()
		section_container.name = "Section_" + section_id
		section_container.add_child(armor)
		section_container.add_child(internal)
		container_node.add_child(section_container)

		return {"armor": armor, "internal": internal}

	# FRONT LEFT SECTION (nose to front split, left side)
	sections["front_left"] = create_section.call(
		Vector2(0, nose_y),  # Nose point (shared between left and right)
		Vector2(0, nose_y),  # Nose point again (triangle tip)
		Vector2(-width_at_front * 0.5, front_split_y),  # Left at front split
		Vector2(0, front_split_y),  # Center at front split
		"front_left",
		container
	)

	# FRONT RIGHT SECTION (nose to front split, right side)
	sections["front_right"] = create_section.call(
		Vector2(0, nose_y),  # Nose point
		Vector2(0, nose_y),  # Nose point again
		Vector2(0, front_split_y),  # Center at front split
		Vector2(width_at_front * 0.5, front_split_y),  # Right at front split
		"front_right",
		container
	)

	# MIDDLE LEFT SECTION (front split to middle split, left side)
	sections["middle_left"] = create_section.call(
		Vector2(0, front_split_y),  # Center at front split
		Vector2(-width_at_front * 0.5, front_split_y),  # Left at front split
		Vector2(-width_at_middle * 0.5, middle_split_y),  # Left at middle split
		Vector2(0, middle_split_y),  # Center at middle split
		"middle_left",
		container
	)

	# MIDDLE RIGHT SECTION (front split to middle split, right side)
	sections["middle_right"] = create_section.call(
		Vector2(width_at_front * 0.5, front_split_y),  # Right at front split
		Vector2(0, front_split_y),  # Center at front split
		Vector2(0, middle_split_y),  # Center at middle split
		Vector2(width_at_middle * 0.5, middle_split_y),  # Right at middle split
		"middle_right",
		container
	)

	# BACK LEFT SECTION (middle split to back, left side)
	sections["back_left"] = create_section.call(
		Vector2(0, middle_split_y),  # Center at middle split
		Vector2(-width_at_middle * 0.5, middle_split_y),  # Left at middle split
		Vector2(-width_at_back * 0.5, back_y),  # Left at back
		Vector2(0, back_y),  # Center at back
		"back_left",
		container
	)

	# BACK RIGHT SECTION (middle split to back, right side)
	sections["back_right"] = create_section.call(
		Vector2(width_at_middle * 0.5, middle_split_y),  # Right at middle split
		Vector2(0, middle_split_y),  # Center at middle split
		Vector2(0, back_y),  # Center at back
		Vector2(width_at_back * 0.5, back_y),  # Right at back
		"back_right",
		container
	)

	# Add outline for the whole ship (Star Destroyer triangle)
	var line = Line2D.new()
	line.name = "ShipOutline"
	line.add_point(Vector2(0, nose_y))  # Nose
	line.add_point(Vector2(width_at_back * 0.5, back_y))  # Right wing
	line.add_point(Vector2(-width_at_back * 0.5, back_y))  # Left wing
	line.add_point(Vector2(0, nose_y))  # Back to nose
	line.default_color = COLOR_SOFT_GLOW
	line.width = 3.0
	container.add_child(line)

	# Add internal detail lines (section dividers)
	var add_detail_line = func(from: Vector2, to: Vector2, container_node: Node2D):
		var detail = Line2D.new()
		detail.add_point(from)
		detail.add_point(to)
		detail.default_color = COLOR_DIM
		detail.width = 1.5
		container_node.add_child(detail)

	# Centerline
	add_detail_line.call(Vector2(0, nose_y), Vector2(0, back_y), container)
	# Front split line
	add_detail_line.call(Vector2(-width_at_front * 0.5, front_split_y), Vector2(width_at_front * 0.5, front_split_y), container)
	# Middle split line
	add_detail_line.call(Vector2(-width_at_middle * 0.5, middle_split_y), Vector2(width_at_middle * 0.5, middle_split_y), container)

	return sections

## Create generic ship shape
func _create_generic_ship_shape(container: Node2D, size: float, color: Color) -> void:
	var polygon = Polygon2D.new()
	polygon.name = "ShipBody"
	polygon.polygon = PackedVector2Array([
		Vector2(0, -size),
		Vector2(-size * 0.5, size * 0.5),
		Vector2(size * 0.5, size * 0.5)
	])
	polygon.color = color
	container.add_child(polygon)

## Add team indicator (color dot)
func _add_team_indicator(container: Node2D, team: int) -> void:
	var indicator = Polygon2D.new()
	indicator.name = "TeamIndicator"

	# Small circle
	var points = PackedVector2Array()
	var segments = 8
	var radius = 4.0
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	indicator.polygon = points
	indicator.position = Vector2(0, -20)

	# Team colors: Green for Team 0, Grey/White for Team 1
	indicator.color = COLOR_PRIMARY_GLOW if team == 0 else COLOR_TEAM1

	container.add_child(indicator)

## Add glow effect
func _add_glow_effect(container: Node2D, glow_color: Color = COLOR_PRIMARY_GLOW) -> void:
	# Add a PointLight2D for glow
	var light = PointLight2D.new()
	light.name = "Glow"
	light.enabled = true
	light.texture_scale = 0.5
	light.energy = 0.5
	light.color = glow_color
	container.add_child(light)

## Create projectile visual
func _create_projectile_visual(entity: IRenderable) -> Node2D:
	var container = Node2D.new()
	container.name = "MatrixProjectileVisual"

	# Small glowing circle
	var polygon = Polygon2D.new()
	polygon.name = "ProjectileBody"

	var points = PackedVector2Array()
	var segments = 6
	var radius = 3.0
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	polygon.polygon = points
	polygon.color = COLOR_HIGHLIGHT

	container.add_child(polygon)

	# Add trail effect
	var trail = Line2D.new()
	trail.name = "Trail"
	trail.add_point(Vector2.ZERO)
	trail.add_point(Vector2(-10, 0))  # Trail behind
	trail.default_color = Color(COLOR_HIGHLIGHT, 0.5)
	trail.width = 2.0
	container.add_child(trail)

	# Add glow
	var light = PointLight2D.new()
	light.name = "Glow"
	light.enabled = true
	light.texture_scale = 0.3
	light.energy = 0.8
	light.color = COLOR_HIGHLIGHT
	container.add_child(light)

	return container

## Create fallback visual
func _create_fallback_visual() -> Node2D:
	var container = Node2D.new()
	container.name = "MatrixFallbackVisual"

	var polygon = Polygon2D.new()
	polygon.polygon = PackedVector2Array([
		Vector2(-10, -10),
		Vector2(10, -10),
		Vector2(10, 10),
		Vector2(-10, 10)
	])
	polygon.color = COLOR_DIM

	container.add_child(polygon)

	return container

## Get color based on damage percent
func _get_damage_color(percent: float) -> Color:
	if percent > 0.75:
		return COLOR_PRIMARY_GLOW  # Green - healthy
	elif percent > 0.5:
		return COLOR_SOFT_GLOW     # Dim green - slightly damaged
	elif percent > 0.25:
		return Color("FFA500")     # Orange - heavily damaged
	else:
		return COLOR_ERROR         # Red - critical

## Update section colors based on per-section damage
func _update_section_colors(visual: Dictionary, section_damage: Array[Dictionary]) -> void:
	if not visual.has("sections"):
		return

	for section_data in section_damage:
		var section_id = section_data.section_id
		if not visual.sections.has(section_id):
			continue

		var section_visual = visual.sections[section_id]

		# Update armor color
		if section_visual.has("armor"):
			var armor_node = section_visual.armor
			if armor_node and is_instance_valid(armor_node):
				armor_node.color = _get_damage_color(section_data.armor_percent)

		# Update internal color
		if section_visual.has("internal"):
			var internal_node = section_visual.internal
			if internal_node and is_instance_valid(internal_node):
				internal_node.color = _get_damage_color(section_data.internal_percent)

## Update visual color based on health (fallback for non-sectioned entities)
func _update_health_color(visual: Dictionary, health_percent: float) -> void:
	var root = visual.root
	var body = root.get_node_or_null("ShipBody")
	if not body:
		return

	# Interpolate color based on health
	var color = _get_damage_color(health_percent)
	body.color = color

	# Update outline too
	var outline = root.get_node_or_null("ShipOutline")
	if outline:
		outline.default_color = color

## Show destruction effect
func _show_destruction_effect(visual: Dictionary) -> void:
	var root = visual.root

	# Flash red
	var body = root.get_node_or_null("ShipBody")
	if body:
		body.color = COLOR_ERROR

	# Fade out
	var tween = root.create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 1.0)
