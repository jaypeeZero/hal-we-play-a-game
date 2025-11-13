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

func update_state(entity_id: String, state: EntityState) -> void:
	if not _entity_visuals.has(entity_id):
		return

	var visual = _entity_visuals[entity_id]
	if not visual.root or not is_instance_valid(visual.root):
		return

	# Update color based on health
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

	match ship_type:
		"fighter":
			size = 15.0
			_create_fighter_shape(container, size, color)
		"corvette":
			size = 25.0
			_create_corvette_shape(container, size, color)
		"capital":
			size = 50.0
			_create_capital_shape(container, size, color)
		_:
			_create_generic_ship_shape(container, size, color)

	# Add team indicator
	if ship_data.has("team"):
		_add_team_indicator(container, ship_data.team)

	# Add glow effect
	_add_glow_effect(container)

	return container

## Create fighter shape (small triangle)
func _create_fighter_shape(container: Node2D, size: float, color: Color) -> void:
	var polygon = Polygon2D.new()
	polygon.name = "ShipBody"
	polygon.polygon = PackedVector2Array([
		Vector2(0, -size * 0.8),        # Nose
		Vector2(-size * 0.4, size * 0.6),  # Left wing
		Vector2(size * 0.4, size * 0.6)    # Right wing
	])
	polygon.color = color
	container.add_child(polygon)

	# Add outline
	var line = Line2D.new()
	line.name = "ShipOutline"
	line.add_point(Vector2(0, -size * 0.8))
	line.add_point(Vector2(-size * 0.4, size * 0.6))
	line.add_point(Vector2(size * 0.4, size * 0.6))
	line.add_point(Vector2(0, -size * 0.8))
	line.default_color = COLOR_SOFT_GLOW
	line.width = 2.0
	container.add_child(line)

## Create corvette shape (diamond)
func _create_corvette_shape(container: Node2D, size: float, color: Color) -> void:
	var polygon = Polygon2D.new()
	polygon.name = "ShipBody"
	polygon.polygon = PackedVector2Array([
		Vector2(0, -size),           # Front
		Vector2(-size * 0.5, 0),     # Left
		Vector2(0, size),            # Rear
		Vector2(size * 0.5, 0)       # Right
	])
	polygon.color = color
	container.add_child(polygon)

	# Add outline
	var line = Line2D.new()
	line.name = "ShipOutline"
	line.add_point(Vector2(0, -size))
	line.add_point(Vector2(-size * 0.5, 0))
	line.add_point(Vector2(0, size))
	line.add_point(Vector2(size * 0.5, 0))
	line.add_point(Vector2(0, -size))
	line.default_color = COLOR_SOFT_GLOW
	line.width = 2.5
	container.add_child(line)

## Create capital shape (large hexagon)
func _create_capital_shape(container: Node2D, size: float, color: Color) -> void:
	var polygon = Polygon2D.new()
	polygon.name = "ShipBody"
	polygon.polygon = PackedVector2Array([
		Vector2(0, -size),                    # Front point
		Vector2(-size * 0.4, -size * 0.5),   # Front left
		Vector2(-size * 0.4, size * 0.5),    # Rear left
		Vector2(0, size),                     # Rear point
		Vector2(size * 0.4, size * 0.5),     # Rear right
		Vector2(size * 0.4, -size * 0.5)     # Front right
	])
	polygon.color = color
	container.add_child(polygon)

	# Add outline
	var line = Line2D.new()
	line.name = "ShipOutline"
	line.add_point(Vector2(0, -size))
	line.add_point(Vector2(-size * 0.4, -size * 0.5))
	line.add_point(Vector2(-size * 0.4, size * 0.5))
	line.add_point(Vector2(0, size))
	line.add_point(Vector2(size * 0.4, size * 0.5))
	line.add_point(Vector2(size * 0.4, -size * 0.5))
	line.add_point(Vector2(0, -size))
	line.default_color = COLOR_SOFT_GLOW
	line.width = 3.0
	container.add_child(line)

	# Add internal details
	var detail_line = Line2D.new()
	detail_line.name = "Details"
	detail_line.add_point(Vector2(-size * 0.2, 0))
	detail_line.add_point(Vector2(size * 0.2, 0))
	detail_line.default_color = COLOR_DIM
	detail_line.width = 1.5
	container.add_child(detail_line)

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

## Update visual color based on health
func _update_health_color(visual: Dictionary, health_percent: float) -> void:
	var root = visual.root
	var body = root.get_node_or_null("ShipBody")
	if not body:
		return

	# Interpolate color based on health
	var color: Color
	if health_percent > 0.5:
		color = COLOR_PRIMARY_GLOW
	elif health_percent > 0.25:
		color = COLOR_DIM
	else:
		color = COLOR_ERROR

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
