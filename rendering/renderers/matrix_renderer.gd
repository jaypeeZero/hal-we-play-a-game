class_name MatrixRenderer extends IVisualRenderer

## Matrix-themed visual renderer for space combat
## Renders ships as geometric shapes with Matrix green aesthetic

# Matrix color palette
const COLOR_PRIMARY_GLOW = Color("00FF41")  # Signature Matrix green
const COLOR_SOFT_GLOW = Color("36BA01")     # Edge highlights
const COLOR_DIM = Color("009A22")           # Inactive elements
const COLOR_HIGHLIGHT = Color("80CE87")     # Cursor/sparks
const COLOR_ERROR = Color("FF003C")         # Damage/warning
const COLOR_BACKGROUND = Color("0D0D0D")    # Deep black

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
	var color = COLOR_PRIMARY_GLOW
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

	# Add glow effect
	_add_glow_effect(container)

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

## Create fighter shape with sections (front, back)
func _create_fighter_shape(container: Node2D, size: float, color: Color) -> Dictionary:
	var sections = {}

	# Fighter sections: front (-90 to 90), back (90 to 270)
	var section_configs = [
		{"id": "front", "start": -90, "end": 90},
		{"id": "back", "start": 90, "end": 270}
	]

	for config in section_configs:
		var section_container = Node2D.new()
		section_container.name = "Section_" + config.id
		container.add_child(section_container)

		# Armor layer (outer)
		var armor = Polygon2D.new()
		armor.name = "Armor"
		armor.polygon = _create_section_wedge(config.start, config.end, size, size * 0.7)
		armor.color = color
		section_container.add_child(armor)

		# Internal layer (inner)
		var internal = Polygon2D.new()
		internal.name = "Internal"
		internal.polygon = _create_section_wedge(config.start, config.end, size * 0.6, 0)
		internal.color = color.darkened(0.3)
		section_container.add_child(internal)

		# Store references
		sections[config.id] = {
			"armor": armor,
			"internal": internal
		}

	# Add outline for the whole ship
	var line = Line2D.new()
	line.name = "ShipOutline"
	var outline_segments = 16
	for i in range(outline_segments + 1):
		var angle = (float(i) / outline_segments) * TAU
		line.add_point(Vector2(cos(angle), sin(angle)) * size)
	line.default_color = COLOR_SOFT_GLOW
	line.width = 2.0
	container.add_child(line)

	return sections

## Create corvette shape with sections (front, middle, back)
func _create_corvette_shape(container: Node2D, size: float, color: Color) -> Dictionary:
	var sections = {}

	# Corvette sections: front (-60 to 60), middle (60 to 300), back (300 to 420/60)
	var section_configs = [
		{"id": "front", "start": -60, "end": 60},
		{"id": "middle", "start": 60, "end": 300},
		{"id": "back", "start": 300, "end": 420}  # Wraps around
	]

	for config in section_configs:
		var section_container = Node2D.new()
		section_container.name = "Section_" + config.id
		container.add_child(section_container)

		# Armor layer (outer)
		var armor = Polygon2D.new()
		armor.name = "Armor"
		armor.polygon = _create_section_wedge(config.start, config.end, size, size * 0.7)
		armor.color = color
		section_container.add_child(armor)

		# Internal layer (inner)
		var internal = Polygon2D.new()
		internal.name = "Internal"
		internal.polygon = _create_section_wedge(config.start, config.end, size * 0.6, 0)
		internal.color = color.darkened(0.3)
		section_container.add_child(internal)

		# Store references
		sections[config.id] = {
			"armor": armor,
			"internal": internal
		}

	# Add outline for the whole ship
	var line = Line2D.new()
	line.name = "ShipOutline"
	var outline_segments = 16
	for i in range(outline_segments + 1):
		var angle = (float(i) / outline_segments) * TAU
		line.add_point(Vector2(cos(angle), sin(angle)) * size)
	line.default_color = COLOR_SOFT_GLOW
	line.width = 2.5
	container.add_child(line)

	return sections

## Create capital shape with sections (6 sections)
func _create_capital_shape(container: Node2D, size: float, color: Color) -> Dictionary:
	var sections = {}

	# Capital sections: 6 sections of 60 degrees each
	var section_configs = [
		{"id": "front_left", "start": 300, "end": 360},
		{"id": "front_right", "start": 0, "end": 60},
		{"id": "middle_right", "start": 60, "end": 120},
		{"id": "back_right", "start": 120, "end": 180},
		{"id": "back_left", "start": 180, "end": 240},
		{"id": "middle_left", "start": 240, "end": 300}
	]

	for config in section_configs:
		var section_container = Node2D.new()
		section_container.name = "Section_" + config.id
		container.add_child(section_container)

		# Armor layer (outer)
		var armor = Polygon2D.new()
		armor.name = "Armor"
		armor.polygon = _create_section_wedge(config.start, config.end, size, size * 0.75)
		armor.color = color
		section_container.add_child(armor)

		# Internal layer (inner)
		var internal = Polygon2D.new()
		internal.name = "Internal"
		internal.polygon = _create_section_wedge(config.start, config.end, size * 0.65, 0)
		internal.color = color.darkened(0.3)
		section_container.add_child(internal)

		# Store references
		sections[config.id] = {
			"armor": armor,
			"internal": internal
		}

	# Add outline for the whole ship
	var line = Line2D.new()
	line.name = "ShipOutline"
	var outline_segments = 24
	for i in range(outline_segments + 1):
		var angle = (float(i) / outline_segments) * TAU
		line.add_point(Vector2(cos(angle), sin(angle)) * size)
	line.default_color = COLOR_SOFT_GLOW
	line.width = 3.0
	container.add_child(line)

	# Add internal detail lines
	for i in range(6):
		var detail_line = Line2D.new()
		detail_line.name = "Detail_" + str(i)
		var angle = (float(i) / 6.0) * TAU
		detail_line.add_point(Vector2.ZERO)
		detail_line.add_point(Vector2(cos(angle), sin(angle)) * size * 0.8)
		detail_line.default_color = COLOR_DIM
		detail_line.width = 1.5
		container.add_child(detail_line)

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

	# Team colors
	indicator.color = COLOR_PRIMARY_GLOW if team == 0 else COLOR_ERROR

	container.add_child(indicator)

## Add glow effect
func _add_glow_effect(container: Node2D) -> void:
	# Add a PointLight2D for glow
	var light = PointLight2D.new()
	light.name = "Glow"
	light.enabled = true
	light.texture_scale = 0.5
	light.energy = 0.5
	light.color = COLOR_PRIMARY_GLOW
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
