class_name HullShapeDrawer
extends RefCounted

## Shared utility for drawing ships from HullShapes data
## Used by both 78Renderer (game) and Ship Editor (tool)

# Default colors for ship sections (same as Ship Editor)
const COLOR_ARMOR = Color(0.3, 0.6, 1.0)       # Blue - armor sections
const COLOR_INTERNAL = Color(1.0, 0.5, 0.2)   # Orange - internal components
const COLOR_WEAPON = Color(1.0, 0.3, 0.3)     # Red - weapons
const COLOR_ENGINE = Color(0.3, 1.0, 0.5)     # Green - engines

## Draw a complete ship visual using HullShapes data
## Returns a Node2D container with all visual elements
## If rotate_for_display is true, rotates 90 degrees (for horizontal ship display)
static func create_ship_visual(ship_type: String, team: int = 0, scale: float = 1.0, rotate_for_display: bool = false) -> Node2D:
	var container = Node2D.new()
	container.name = "HullShapeVisual"

	# Get hull sections from HullShapes
	var sections = HullShapes.get_sections(ship_type)

	if sections.is_empty():
		push_warning("No hull shape data found for " + ship_type)
		return container

	var section_dict = {}
	var section_index = 0

	for section in sections:
		var section_id = section.section_id
		var points: Array = section.points

		if points.is_empty():
			continue

		# Transform points (scale and optionally rotate)
		var transformed_points = _transform_points(points, scale, rotate_for_display)

		# Create section container
		var section_container = Node2D.new()
		section_container.name = "Section_" + section_id

		# Draw armor outline (polyline)
		var armor_line = Line2D.new()
		armor_line.name = "ArmorOutline"
		for point in transformed_points:
			armor_line.add_point(point)
		# Close the polygon
		if transformed_points.size() > 0:
			armor_line.add_point(transformed_points[0])

		# Color shade based on section index for visual variety
		var shade = section_index * 0.15
		armor_line.default_color = COLOR_ARMOR.lightened(shade)
		armor_line.width = 1.5
		section_container.add_child(armor_line)

		# Create filled armor polygon
		var armor_fill = Polygon2D.new()
		armor_fill.name = "ArmorFill"
		armor_fill.polygon = PackedVector2Array(transformed_points)
		armor_fill.color = COLOR_ARMOR.lightened(shade).darkened(0.7)
		armor_fill.color.a = 0.3  # Semi-transparent fill
		section_container.add_child(armor_fill)

		# Move outline to front
		section_container.move_child(armor_line, section_container.get_child_count() - 1)

		container.add_child(section_container)

		section_dict[section_id] = {
			"container": section_container,
			"outline": armor_line,
			"fill": armor_fill
		}

		section_index += 1

	# Store section references in metadata
	container.set_meta("sections", section_dict)
	container.set_meta("team", team)
	container.set_meta("ship_type", ship_type)

	return container

## Create engine visual (circle)
## Returns a Node2D for the engine
static func create_engine_visual(position_offset: Vector2, scale: float = 1.0, rotate_for_display: bool = false) -> Node2D:
	var container = Node2D.new()
	container.name = "Engine"

	# Transform position
	var pos = position_offset * scale
	if rotate_for_display:
		pos = HullShapes.rotate_90(pos)
	container.position = pos

	# Engine circle
	var radius = 5.0 * scale
	var circle = _create_circle_polygon(radius, 12, COLOR_ENGINE.darkened(0.3))
	circle.name = "EngineBody"
	container.add_child(circle)

	# Engine outline
	var outline = _create_circle_line(radius, 12, COLOR_ENGINE.lightened(0.3), 1.5)
	outline.name = "EngineOutline"
	container.add_child(outline)

	# Thrust effect (hidden by default)
	var thrust = _create_thrust_visual(scale)
	thrust.name = "Thrust"
	thrust.visible = false
	container.add_child(thrust)

	return container

## Create weapon visual (rectangle)
## Returns a Node2D for the weapon
static func create_weapon_visual(position_offset: Vector2, facing: float = 0.0, scale: float = 1.0, rotate_for_display: bool = false) -> Node2D:
	var container = Node2D.new()
	container.name = "Weapon"

	# Transform position
	var pos = position_offset * scale
	if rotate_for_display:
		pos = HullShapes.rotate_90(pos)
	container.position = pos
	container.rotation = facing

	# Weapon barrel (elongated rectangle)
	var width = 4.0 * scale
	var height = 8.0 * scale

	var barrel = Polygon2D.new()
	barrel.name = "WeaponBarrel"
	barrel.polygon = PackedVector2Array([
		Vector2(-width/2, 0),
		Vector2(width/2, 0),
		Vector2(width/2, -height),
		Vector2(-width/2, -height)
	])
	barrel.color = COLOR_WEAPON.darkened(0.3)
	container.add_child(barrel)

	# Weapon outline
	var outline = Line2D.new()
	outline.name = "WeaponOutline"
	outline.add_point(Vector2(-width/2, 0))
	outline.add_point(Vector2(width/2, 0))
	outline.add_point(Vector2(width/2, -height))
	outline.add_point(Vector2(-width/2, -height))
	outline.add_point(Vector2(-width/2, 0))
	outline.default_color = COLOR_WEAPON.lightened(0.3)
	outline.width = 1.5
	container.add_child(outline)

	return container

## Create internal component visual (small circle)
static func create_internal_visual(position_offset: Vector2, component_type: String, scale: float = 1.0, rotate_for_display: bool = false) -> Node2D:
	var container = Node2D.new()
	container.name = "Internal_" + component_type

	# Transform position
	var pos = position_offset * scale
	if rotate_for_display:
		pos = HullShapes.rotate_90(pos)
	container.position = pos

	var radius = 5.0 * scale

	# Internal body
	var circle = _create_circle_polygon(radius, 12, COLOR_INTERNAL.darkened(0.3))
	circle.name = "InternalBody"
	container.add_child(circle)

	# Internal outline
	var outline = _create_circle_line(radius, 12, COLOR_INTERNAL.lightened(0.3), 1.5)
	outline.name = "InternalOutline"
	container.add_child(outline)

	return container

## Update section colors based on damage
static func update_section_damage(container: Node2D, section_damage: Array[Dictionary]) -> void:
	if not container.has_meta("sections"):
		return

	var sections: Dictionary = container.get_meta("sections")

	for damage_data in section_damage:
		var section_id = damage_data.section_id
		if not sections.has(section_id):
			continue

		var section = sections[section_id]
		var armor_percent = damage_data.armor_percent

		# Calculate damage color
		var color = _get_damage_color(armor_percent)

		# Update outline color
		if section.has("outline"):
			var outline: Line2D = section.outline
			if is_instance_valid(outline):
				outline.default_color = color

		# Update fill color
		if section.has("fill"):
			var fill: Polygon2D = section.fill
			if is_instance_valid(fill):
				fill.color = color.darkened(0.7)
				fill.color.a = 0.3

## Set thrust visibility for an engine
static func set_engine_thrust(engine_container: Node2D, is_firing: bool, status: String = "operational") -> void:
	var thrust = engine_container.get_node_or_null("Thrust")
	if not thrust:
		return

	thrust.visible = is_firing and status != "destroyed"

	if thrust.visible:
		match status:
			"operational":
				thrust.modulate = Color.WHITE
			"damaged":
				thrust.modulate = Color(1.0, 0.6, 0.0)

## Transform points based on scale and rotation
static func _transform_points(points: Array, scale: float, rotate: bool) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in points:
		var p: Vector2 = point * scale
		if rotate:
			p = HullShapes.rotate_90(p)
		result.append(p)
	return result

## Create a circle polygon
static func _create_circle_polygon(radius: float, segments: int, color: Color) -> Polygon2D:
	var polygon = Polygon2D.new()
	var points = PackedVector2Array()

	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	polygon.polygon = points
	polygon.color = color
	return polygon

## Create a circle outline
static func _create_circle_line(radius: float, segments: int, color: Color, width: float) -> Line2D:
	var line = Line2D.new()

	for i in range(segments + 1):
		var angle = (float(i) / segments) * TAU
		line.add_point(Vector2(cos(angle), sin(angle)) * radius)

	line.default_color = color
	line.width = width
	return line

## Create thrust visual effect
static func _create_thrust_visual(scale: float) -> Node2D:
	var container = Node2D.new()

	var thrust_size = 12.0 * scale
	var thrust = Polygon2D.new()
	thrust.name = "ThrustFlame"
	thrust.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(-thrust_size * 0.5, thrust_size * 0.8),
		Vector2(0, thrust_size * 1.8),
		Vector2(thrust_size * 0.5, thrust_size * 0.8)
	])
	thrust.color = Color("FF8C00")  # Orange
	container.add_child(thrust)

	# Add glow
	var light = PointLight2D.new()
	light.name = "ThrustGlow"
	light.position = Vector2(0, thrust_size)
	light.enabled = true
	light.texture_scale = 0.3 * scale
	light.energy = 0.6
	light.color = Color("FF8C00")
	container.add_child(light)

	return container

## Get color based on damage percent
static func _get_damage_color(percent: float) -> Color:
	if percent > 0.75:
		return COLOR_ARMOR  # Full health
	elif percent > 0.5:
		return COLOR_ARMOR.darkened(0.2)  # Light damage
	elif percent > 0.25:
		return Color("FFA500")  # Heavy damage (orange)
	else:
		return Color("FF003C")  # Critical (red)
