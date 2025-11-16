class_name SpriteRenderer extends IVisualRenderer

## Sprite-based visual renderer using Kenny's Space Shooter sprite sheet
## Renders ships and components using pre-made sprite graphics

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

	print("SpriteRenderer initialized with Kenny sprite sheet")

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
		# Fallback to simple placeholder
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
	# Format: <SubTexture name="spaceShips_001.png" x="480" y="1045" width="106" height="80"/>
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

## Create ship visual using sprite sheet
func _create_ship_visual(entity: IRenderable, visual_type: String) -> Node2D:
	var container = Node2D.new()
	container.name = "SpriteShipVisual"

	# Get ship data
	var ship_data = {}
	if entity.has_method("get_ship_data"):
		ship_data = entity.get_ship_data()

	# Determine sprite based on ship type
	var ship_type = visual_type.replace("ship_", "")
	var sprite_name = _get_ship_sprite_name(ship_type)

	# Create sprite
	var ship_sprite = _create_sprite(sprite_name)
	if ship_sprite:
		# Store team in metadata for later use
		if ship_data.has("team"):
			container.set_meta("team", ship_data.team)
			# Apply team color tint
			var tint = COLOR_TEAM0_TINT if ship_data.team == 0 else COLOR_TEAM1_TINT
			ship_sprite.modulate = tint

		container.add_child(ship_sprite)
	else:
		# Fallback to simple shape if sprite not found
		push_warning("Sprite not found: " + sprite_name + ", using fallback")
		var fallback = ColorRect.new()
		fallback.size = Vector2(20, 20)
		fallback.position = Vector2(-10, -10)
		fallback.color = Color.GRAY
		container.add_child(fallback)

	return container

## Create projectile visual using sprite
func _create_projectile_visual(entity: IRenderable) -> Node2D:
	var container = Node2D.new()
	container.name = "SpriteProjectileVisual"

	# Use a missile sprite for projectiles
	var projectile_sprite = _create_sprite("spaceMissiles_001")
	if projectile_sprite:
		projectile_sprite.scale = Vector2(0.6, 0.6)  # Scale down a bit
		container.add_child(projectile_sprite)
	else:
		# Fallback
		var fallback = ColorRect.new()
		fallback.size = Vector2(4, 8)
		fallback.position = Vector2(-2, -4)
		fallback.color = Color.YELLOW
		container.add_child(fallback)

	return container

## Create fallback visual for unknown types
func _create_fallback_visual() -> Node2D:
	var container = Node2D.new()
	container.name = "SpriteFallbackVisual"

	var fallback = ColorRect.new()
	fallback.size = Vector2(16, 16)
	fallback.position = Vector2(-8, -8)
	fallback.color = Color.MAGENTA
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

## Map ship type to sprite name
func _get_ship_sprite_name(ship_type: String) -> String:
	match ship_type:
		"fighter":
			return "spaceShips_001"  # Small fighter
		"corvette":
			return "spaceShips_004"  # Medium ship
		"capital":
			return "spaceShips_007"  # Large capital ship
		_:
			return "spaceShips_002"  # Default ship

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

	# Create or update components
	for component_data in components:
		var component_id: String = component_data.component_id
		current_component_ids.append(component_id)

		# Create component visual if it doesn't exist
		if component_id not in component_dict:
			var component_visual = _create_component_visual(component_data, team)
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
func _create_component_visual(component_data: Dictionary, team: int) -> Node2D:
	var visual_type: String = component_data.visual_type
	var component_type: String = component_data.component_type

	var container = Node2D.new()
	container.name = "Component_" + component_data.component_id

	if component_type == "weapon":
		# Weapons: use missile sprites as turret/gun barrels
		_create_weapon_visual(container, visual_type, team)
	elif component_type == "engine":
		# Engines: show thrust effect sprites
		_create_engine_visual(container, team)

	return container

## Create weapon visual using sprite
func _create_weapon_visual(container: Node2D, visual_type: String, team: int) -> void:
	var weapon_sprite_name = _get_weapon_sprite_name(visual_type)
	var weapon_sprite = _create_sprite(weapon_sprite_name)

	if weapon_sprite:
		weapon_sprite.name = "WeaponSprite"
		# Apply team tint
		var tint = COLOR_TEAM0_TINT if team == 0 else COLOR_TEAM1_TINT
		weapon_sprite.modulate = tint
		weapon_sprite.scale = Vector2(0.8, 0.8)  # Scale appropriately
		container.add_child(weapon_sprite)
	else:
		# Fallback: simple rectangle
		var fallback = ColorRect.new()
		fallback.size = Vector2(4, 12)
		fallback.position = Vector2(-2, -12)
		fallback.color = Color.DARK_GRAY
		container.add_child(fallback)

## Create engine visual with thrust effect sprites
func _create_engine_visual(container: Node2D, team: int) -> void:
	# Engine thrust: use spaceEffects sprites for flame/thrust
	var thrust_sprite = _create_sprite("spaceEffects_005")  # Vertical thrust flame

	if thrust_sprite:
		thrust_sprite.name = "ThrustSprite"
		thrust_sprite.modulate = Color(1.0, 0.6, 0.0)  # Orange thrust color
		thrust_sprite.scale = Vector2(0.4, 0.4)
		thrust_sprite.rotation = PI  # Point backward
		thrust_sprite.visible = false  # Hidden by default, shown when firing
		container.add_child(thrust_sprite)
	else:
		# Fallback: simple polygon thrust
		var thrust = Polygon2D.new()
		thrust.name = "ThrustSprite"
		var thrust_size = 12.0
		thrust.polygon = PackedVector2Array([
			Vector2(0, 0),
			Vector2(-thrust_size * 0.5, thrust_size * 0.8),
			Vector2(0, thrust_size * 1.8),
			Vector2(thrust_size * 0.5, thrust_size * 0.8)
		])
		thrust.color = Color("FF8C00")
		thrust.visible = false
		container.add_child(thrust)

## Map weapon visual type to sprite name
func _get_weapon_sprite_name(visual_type: String) -> String:
	match visual_type:
		"heavy_turret":
			return "spaceMissiles_021"  # Larger missile for heavy turret
		"medium_turret":
			return "spaceMissiles_007"  # Medium missile
		"gatling_turret":
			return "spaceMissiles_001"  # Small missile
		"light_weapon":
			return "spaceMissiles_001"  # Small missile for light weapon
		_:
			return "spaceMissiles_001"

## Update engine thrust visual based on firing state and status
func _update_engine_thrust(component_visual: Node2D, status: String, is_firing: bool) -> void:
	var thrust = component_visual.get_node_or_null("ThrustSprite")
	if not thrust:
		return

	# Only show thrust when engine is firing
	if is_firing and status != "destroyed":
		thrust.visible = true

		# Modify thrust color/intensity based on engine status
		match status:
			"operational":
				thrust.modulate = Color(1.0, 0.6, 0.0)  # Bright orange
			"damaged":
				thrust.modulate = Color(0.8, 0.4, 0.0)  # Dimmer orange for damaged
	else:
		# Hide thrust when not firing or destroyed
		thrust.visible = false

## Update component visual based on status
func _update_component_status(component_visual: Node2D, status: String) -> void:
	# Currently weapons don't have damage status, so this is a no-op
	pass

## Update health color modulation
func _update_health_modulation(root: Node2D, health_percent: float) -> void:
	# Tint sprite based on health
	var ship_sprite = root.get_child(0) if root.get_child_count() > 0 else null
	if not ship_sprite:
		return

	# Calculate damage tint (red overlay as health decreases)
	var damage_tint = Color.WHITE.lerp(Color(1.0, 0.3, 0.3), 1.0 - health_percent)

	# Preserve team tint and combine with damage
	var base_tint = ship_sprite.modulate
	ship_sprite.modulate = Color(
		base_tint.r * damage_tint.r,
		base_tint.g * damage_tint.g,
		base_tint.b * damage_tint.b,
		1.0
	)

## Show destruction effect
func _show_destruction_effect(visual: Dictionary) -> void:
	var root = visual.root

	# Fade out
	var tween = root.create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 1.0)
