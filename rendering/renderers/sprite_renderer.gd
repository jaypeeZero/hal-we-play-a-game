class_name SpriteRenderer extends IVisualRenderer

## Sprite-based visual renderer using Kenny's Space Shooter sprite sheet
## COMPOSES ships from individual sprite parts to match MatrixRenderer shapes

# Sprite atlas configuration
const SPRITE_SHEET_PATH = "res://assets/kenney_space-shooter-extension/Spritesheet/spaceShooter2_spritesheet.png"
const SPRITE_ATLAS_XML_PATH = "res://assets/kenney_space-shooter-extension/Spritesheet/spaceShooter2_spritesheet.xml"

# Team tint colors
const COLOR_TEAM0_TINT = Color(0.5, 1.0, 0.5)  # Greenish tint for Team 0
const COLOR_TEAM1_TINT = Color(1.0, 0.9, 0.9)  # White/grey for Team 1

var _theme: IVisualTheme = null
var _entity_visuals: Dictionary = {}  # entity_id -> Dictionary of visual nodes
var _component_visuals: Dictionary = {}  # entity_id -> Dictionary[component_id -> Node]
var _sprite_atlas: Dictionary = {}  # sprite_name -> {x, y, width, height}
var _sprite_sheet_texture: Texture2D = null

func initialize(theme: IVisualTheme) -> void:
	_theme = theme
	name = "SpriteRenderer"

	# Load sprite sheet texture
	_sprite_sheet_texture = load(SPRITE_SHEET_PATH)
	if not _sprite_sheet_texture:
		push_error("Failed to load sprite sheet: " + SPRITE_SHEET_PATH)
		return

	# Load and parse sprite atlas XML
	_load_sprite_atlas()

	print("SpriteRenderer initialized - composing ships from sprite parts")

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
		# Fallback
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

	# Update ship health color modulation
	_update_health_modulation(visual.root, state.health_percent)

	# Update component visuals if present
	if state.components.size() > 0:
		_update_components(entity_id, state.components, visual.root, state.is_main_engine_firing, state.maneuvering_thrust_direction)

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
	_component_visuals.clear()

## Load sprite atlas from XML file
func _load_sprite_atlas() -> void:
	var file = FileAccess.open(SPRITE_ATLAS_XML_PATH, FileAccess.READ)
	if not file:
		push_error("Failed to open sprite atlas XML: " + SPRITE_ATLAS_XML_PATH)
		return

	var xml_content = file.get_as_text()
	file.close()

	# Parse XML to extract sprite regions
	var parser = XMLParser.new()
	parser.open_buffer(xml_content.to_utf8_buffer())

	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			if parser.get_node_name() == "SubTexture":
				var sprite_name = parser.get_named_attribute_value("name")
				var x = parser.get_named_attribute_value("x").to_int()
				var y = parser.get_named_attribute_value("y").to_int()
				var width = parser.get_named_attribute_value("width").to_int()
				var height = parser.get_named_attribute_value("height").to_int()

				# Remove .png extension from name
				sprite_name = sprite_name.replace(".png", "")

				_sprite_atlas[sprite_name] = {
					"x": x,
					"y": y,
					"width": width,
					"height": height
				}

	print("Loaded " + str(_sprite_atlas.size()) + " sprites from atlas")

## Create ship visual by composing sprite parts to match MatrixRenderer shapes
func _create_ship_visual(entity: IRenderable, visual_type: String) -> Node2D:
	var container = Node2D.new()
	container.name = "SpriteShipVisual"

	# Get ship data
	var ship_data = {}
	if entity.has_method("get_ship_data"):
		ship_data = entity.get_ship_data()

	# Determine ship type and build from parts
	var ship_type = visual_type.replace("ship_", "")
	var team = ship_data.get("team", 0)
	var tint = COLOR_TEAM0_TINT if team == 0 else COLOR_TEAM1_TINT

	# Store team in metadata
	container.set_meta("team", team)

	# Build ship from sprite parts based on type
	match ship_type:
		"fighter":
			_build_fighter_from_parts(container, tint)
		"corvette":
			_build_corvette_from_parts(container, tint)
		"capital":
			_build_capital_from_parts(container, tint)
		_:
			_build_fighter_from_parts(container, tint)

	return container

## Build fighter - elongated triangle like MatrixRenderer
## Front section: pointy nose, Back section: wider tail
func _build_fighter_from_parts(container: Node2D, tint: Color) -> void:
	# Fighter is small, elongated triangle
	# Use small/medium spaceParts to build pointy front and wider back

	# NOSE (front section) - narrow pointy part
	var nose = _create_sprite("spaceParts_004")  # Narrow long part (26x84)
	if nose:
		nose.position = Vector2(0, -20)  # Forward position
		nose.modulate = tint
		nose.rotation = 0  # Point up
		container.add_child(nose)

	# MID BODY - slightly wider
	var mid = _create_sprite("spaceParts_005")  # Medium part (36x79)
	if mid:
		mid.position = Vector2(0, 5)
		mid.modulate = tint
		container.add_child(mid)

	# TAIL (back section) - wider base
	var tail_left = _create_sprite("spaceParts_057")  # Small wing part
	if tail_left:
		tail_left.position = Vector2(-8, 20)
		tail_left.modulate = tint
		container.add_child(tail_left)

	var tail_right = _create_sprite("spaceParts_057")  # Small wing part
	if tail_right:
		tail_right.position = Vector2(8, 20)
		tail_right.modulate = tint
		container.add_child(tail_right)

## Build corvette - hammerhead front, thin body, thick rear like MatrixRenderer
func _build_corvette_from_parts(container: Node2D, tint: Color) -> void:
	# HAMMERHEAD FRONT - wide horizontal piece
	var hammer_left = _create_sprite("spaceParts_087")  # Wide flat part (36x22)
	if hammer_left:
		hammer_left.position = Vector2(-15, -25)
		hammer_left.modulate = tint
		hammer_left.rotation = PI / 2  # Rotate to horizontal
		container.add_child(hammer_left)

	var hammer_right = _create_sprite("spaceParts_087")  # Wide flat part
	if hammer_right:
		hammer_right.position = Vector2(15, -25)
		hammer_right.modulate = tint
		hammer_right.rotation = PI / 2  # Rotate to horizontal
		container.add_child(hammer_right)

	# THIN BODY - narrow middle section
	var body_upper = _create_sprite("spaceParts_004")  # Narrow part (26x84)
	if body_upper:
		body_upper.position = Vector2(0, -5)
		body_upper.modulate = tint
		container.add_child(body_upper)

	# THICK REAR - wider engine section
	var rear = _create_sprite("spaceParts_014")  # Wider part (50x67)
	if rear:
		rear.position = Vector2(0, 25)
		rear.modulate = tint
		container.add_child(rear)

	# Rear wings
	var rear_left = _create_sprite("spaceParts_061")  # Small accent
	if rear_left:
		rear_left.position = Vector2(-18, 30)
		rear_left.modulate = tint
		container.add_child(rear_left)

	var rear_right = _create_sprite("spaceParts_061")  # Small accent
	if rear_right:
		rear_right.position = Vector2(18, 30)
		rear_right.modulate = tint
		container.add_child(rear_right)

## Build capital - Star Destroyer triangle like MatrixRenderer
func _build_capital_from_parts(container: Node2D, tint: Color) -> void:
	# Capital is 3x longer, builds a triangle from nose to wide back

	# NOSE - single narrow point
	var nose = _create_sprite("spaceParts_004")  # Narrow (26x84)
	if nose:
		nose.position = Vector2(0, -60)
		nose.modulate = tint
		container.add_child(nose)

	# FRONT SECTIONS - narrow widening
	var front_left = _create_sprite("spaceParts_007")  # Medium narrow (32x86)
	if front_left:
		front_left.position = Vector2(-12, -30)
		front_left.modulate = tint
		container.add_child(front_left)

	var front_right = _create_sprite("spaceParts_007")
	if front_right:
		front_right.position = Vector2(12, -30)
		front_right.modulate = tint
		container.add_child(front_right)

	# MIDDLE SECTIONS - wider
	var mid_left = _create_sprite("spaceParts_002")  # Medium (41x71)
	if mid_left:
		mid_left.position = Vector2(-25, 0)
		mid_left.modulate = tint
		container.add_child(mid_left)

	var mid_right = _create_sprite("spaceParts_002")
	if mid_right:
		mid_right.position = Vector2(25, 0)
		mid_right.modulate = tint
		container.add_child(mid_right)

	# BACK SECTIONS - widest parts
	var back_left = _create_sprite("spaceParts_014")  # Wide (50x67)
	if back_left:
		back_left.position = Vector2(-40, 30)
		back_left.modulate = tint
		container.add_child(back_left)

	var back_right = _create_sprite("spaceParts_014")
	if back_right:
		back_right.position = Vector2(40, 30)
		back_right.modulate = tint
		container.add_child(back_right)

	# WING TIPS - outermost edges
	var wing_left = _create_sprite("spaceParts_041")  # Large part (59x66)
	if wing_left:
		wing_left.position = Vector2(-55, 35)
		wing_left.modulate = tint
		container.add_child(wing_left)

	var wing_right = _create_sprite("spaceParts_041")
	if wing_right:
		wing_right.position = Vector2(55, 35)
		wing_right.modulate = tint
		container.add_child(wing_right)

## Create projectile visual using sprite
func _create_projectile_visual(entity: IRenderable) -> Node2D:
	var container = Node2D.new()
	container.name = "SpriteProjectileVisual"

	# Use a missile sprite for projectiles
	var projectile_sprite = _create_sprite("spaceMissiles_001")
	if projectile_sprite:
		projectile_sprite.scale = Vector2(0.6, 0.6)
		container.add_child(projectile_sprite)

	return container

## Create fallback visual
func _create_fallback_visual() -> Node2D:
	var container = Node2D.new()
	container.name = "SpriteFallbackVisual"

	# Use a small part as fallback
	var fallback = _create_sprite("spaceParts_054")
	if fallback:
		container.add_child(fallback)

	return container

## Create a sprite from the sprite sheet using atlas data
func _create_sprite(sprite_name: String) -> Sprite2D:
	if not _sprite_atlas.has(sprite_name):
		return null

	var atlas_data = _sprite_atlas[sprite_name]
	var sprite = Sprite2D.new()
	sprite.texture = _sprite_sheet_texture
	sprite.centered = true

	# Set region to extract specific sprite from sheet
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		atlas_data.x,
		atlas_data.y,
		atlas_data.width,
		atlas_data.height
	)

	return sprite

## Update component visuals based on state
func _update_components(entity_id: String, components: Array[Dictionary], parent_node: Node2D, is_main_engine_firing: bool, maneuvering_thrust_direction: Vector2) -> void:
	# Initialize component visuals dictionary for this entity if needed
	if entity_id not in _component_visuals:
		_component_visuals[entity_id] = {}

	var component_dict: Dictionary = _component_visuals[entity_id]
	var current_component_ids: Array = []

	# Get team from parent (ship)
	var team = 0
	if parent_node.has_meta("team"):
		team = parent_node.get_meta("team")
	var tint = COLOR_TEAM0_TINT if team == 0 else COLOR_TEAM1_TINT

	# Create or update components
	for component_data in components:
		var component_id: String = component_data.component_id
		current_component_ids.append(component_id)

		# Create component visual if it doesn't exist
		if component_id not in component_dict:
			var component_visual = _create_component_visual(component_data, tint)
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
					_update_engine_thrust(component_visual, component_data.status, is_main_engine_firing)
				else:
					_update_component_status(component_visual, component_data.status)

	# Remove components that no longer exist
	var to_remove: Array = []
	for component_id in component_dict.keys():
		if component_id not in current_component_ids:
			to_remove.append(component_id)

	for component_id in to_remove:
		if is_instance_valid(component_dict[component_id]):
			component_dict[component_id].queue_free()
		component_dict.erase(component_id)

## Create visual node for a component
func _create_component_visual(component_data: Dictionary, tint: Color) -> Node2D:
	var visual_type: String = component_data.visual_type
	var component_type: String = component_data.component_type

	var container = Node2D.new()
	container.name = "Component_" + component_data.component_id

	if component_type == "weapon":
		# Weapons: use missile sprites as turret/gun barrels
		_create_weapon_visual(container, visual_type, tint)
	elif component_type == "engine":
		# Engines: show thrust effect sprites
		_create_engine_visual(container, tint)

	return container

## Create weapon visual using missile sprites
func _create_weapon_visual(container: Node2D, visual_type: String, tint: Color) -> void:
	var weapon_sprite_name = _get_weapon_sprite_name(visual_type)
	var weapon_sprite = _create_sprite(weapon_sprite_name)

	if weapon_sprite:
		weapon_sprite.name = "WeaponSprite"
		weapon_sprite.modulate = tint
		weapon_sprite.scale = Vector2(0.7, 0.7)
		container.add_child(weapon_sprite)

## Create engine visual with thrust effect sprites
func _create_engine_visual(container: Node2D, tint: Color) -> void:
	# Engine thrust: use spaceEffects sprites for flame/thrust
	var thrust_sprite = _create_sprite("spaceEffects_005")  # Vertical thrust flame

	if thrust_sprite:
		thrust_sprite.name = "ThrustSprite"
		thrust_sprite.modulate = Color(1.0, 0.6, 0.0)  # Orange thrust
		thrust_sprite.scale = Vector2(0.4, 0.4)
		thrust_sprite.rotation = PI  # Point backward
		thrust_sprite.visible = false  # Hidden by default
		container.add_child(thrust_sprite)

## Map weapon visual type to sprite name
func _get_weapon_sprite_name(visual_type: String) -> String:
	match visual_type:
		"heavy_turret":
			return "spaceMissiles_021"  # Larger missile
		"medium_turret":
			return "spaceMissiles_007"
		"gatling_turret":
			return "spaceMissiles_001"
		"light_weapon":
			return "spaceMissiles_001"
		_:
			return "spaceMissiles_001"

## Update engine thrust visual based on firing state
func _update_engine_thrust(component_visual: Node2D, status: String, is_firing: bool) -> void:
	var thrust = component_visual.get_node_or_null("ThrustSprite")
	if not thrust:
		return

	# Only show thrust when engine is firing
	if is_firing and status != "destroyed":
		thrust.visible = true
		match status:
			"operational":
				thrust.modulate = Color(1.0, 0.6, 0.0)  # Bright orange
			"damaged":
				thrust.modulate = Color(0.8, 0.4, 0.0)  # Dimmer
	else:
		thrust.visible = false

## Update component status
func _update_component_status(component_visual: Node2D, status: String) -> void:
	# Weapons don't have damage status currently
	pass

## Update health color modulation
func _update_health_modulation(root: Node2D, health_percent: float) -> void:
	# Tint all child sprites based on health
	var damage_tint = Color.WHITE.lerp(Color(1.0, 0.3, 0.3), 1.0 - health_percent)

	for child in root.get_children():
		if child is Sprite2D:
			var base_tint = child.modulate
			child.modulate = Color(
				base_tint.r * damage_tint.r,
				base_tint.g * damage_tint.g,
				base_tint.b * damage_tint.b,
				1.0
			)

## Show destruction effect
func _show_destruction_effect(visual: Dictionary) -> void:
	var root = visual.root
	var tween = root.create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 1.0)
