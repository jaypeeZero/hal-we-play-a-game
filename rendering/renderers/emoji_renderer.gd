class_name EmojiRenderer extends IVisualRenderer

## Implements IVisualRenderer interface
## Renders entities as emoji Labels or geometric shapes

var _theme: IVisualTheme = null
var _entity_visuals: Dictionary = {}  # entity_id -> Node (Label or Control)
var _component_visuals: Dictionary = {}  # entity_id -> Dictionary[component_id -> Node]

func initialize(theme: IVisualTheme) -> void:
	_theme = theme
	name = "EmojiRenderer"
	print("EmojiRenderer initialized")

func attach_to_entity(entity: IRenderable) -> void:
	var entity_id: String = entity.get_entity_id()
	var visual_type: String = entity.get_visual_type()

	# Query theme for visual data
	var visual_data: VisualData = _theme.get_visual_data(visual_type)

	# Override shape radius if entity has collision_radius property (for variable-sized shapes)
	if visual_data.renderer_type == "shape" and "collision_radius" in entity:
		visual_data.shape_radius = entity.get("collision_radius")

	var visual_node: Node = null

	# Create visual based on renderer type
	if visual_data.renderer_type == "shape":
		visual_node = _create_shape_visual(visual_data)
	else:
		# Default to label/emoji
		visual_node = _create_label_visual(visual_data)

	# Add as child of entity
	entity.add_child(visual_node)

	# Store reference
	_entity_visuals[entity_id] = visual_node

func _create_label_visual(visual_data: VisualData) -> Label:
	var label: Label = Label.new()
	label.name = "EmojiVisual"
	label.text = visual_data.emoji
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Apply styling from theme
	var settings: LabelSettings = LabelSettings.new()
	settings.font_size = visual_data.font_size
	label.label_settings = settings

	# Position/size from theme
	label.position = -visual_data.bounds / 2
	label.size = visual_data.bounds

	return label

func _create_shape_visual(visual_data: VisualData) -> Control:
	if visual_data.shape_type == "circle":
		return _create_circle_shape(visual_data)
	else:
		# Fallback to basic colored rectangle
		var rect: ColorRect = ColorRect.new()
		rect.name = "ShapeVisual"
		rect.color = visual_data.shape_color
		rect.size = visual_data.bounds
		rect.position = -visual_data.bounds / 2
		return rect

func _create_circle_shape(visual_data: VisualData) -> Control:
	# Create a Control node with a circular shader/drawing
	var circle: Control = Control.new()
	circle.name = "CircleVisual"

	var radius: float = visual_data.shape_radius
	var diameter: float = radius * 2.0

	# Set size and position
	circle.custom_minimum_size = Vector2(diameter, diameter)
	circle.size = Vector2(diameter, diameter)
	circle.position = Vector2(-radius, -radius)

	# Create a ColorRect as child for the actual visual
	var color_rect: ColorRect = ColorRect.new()
	color_rect.color = visual_data.shape_color
	color_rect.size = Vector2(diameter, diameter)

	# Use a shader to make it circular
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 circle_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);

	if (dist > 0.5) {
		discard;
	} else {
		COLOR = circle_color;
	}
}
"""
	shader_material.shader = shader
	shader_material.set_shader_parameter("circle_color", visual_data.shape_color)
	color_rect.material = shader_material

	circle.add_child(color_rect)

	return circle


func detach_from_entity(entity: IRenderable) -> void:
	var entity_id: String = entity.get_entity_id()

	if entity_id in _entity_visuals:
		var visual_node: Node = _entity_visuals[entity_id]
		if is_instance_valid(visual_node):
			visual_node.queue_free()
		_entity_visuals.erase(entity_id)


func update_state(entity_id: String, state: EntityState) -> void:
	# Update component visuals if present
	if state.components.size() > 0:
		_update_components(entity_id, state.components)

	# Could add simple effects here (color tint based on health, etc.)
	pass

func play_animation(entity_id: String, request: AnimationRequest) -> void:
	# Emojis can't animate, but we can do simple effects
	if entity_id not in _entity_visuals:
		return

	match request.animation_name:
		"attack", "cast":
			_play_pulse_effect(entity_id)
		"damaged":
			_play_flash_effect(entity_id)
		"death":
			_play_fade_out_effect(entity_id)
		_:
			# Unknown animation, ignore
			pass

func cleanup() -> void:
	# Remove all visual nodes
	for entity_id in _entity_visuals:
		if is_instance_valid(_entity_visuals[entity_id]):
			_entity_visuals[entity_id].queue_free()

	_entity_visuals.clear()
	_component_visuals.clear()
	print("EmojiRenderer cleaned up")

## Update component visuals based on state
func _update_components(entity_id: String, components: Array[Dictionary]) -> void:
	if entity_id not in _entity_visuals:
		return

	var entity_node: Node = _entity_visuals[entity_id]
	if not is_instance_valid(entity_node):
		return

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
				entity_node.add_child(component_visual)
				component_dict[component_id] = component_visual

		# Update component position and rotation
		if component_id in component_dict:
			var component_visual: Node = component_dict[component_id]
			if is_instance_valid(component_visual):
				component_visual.position = component_data.position_offset
				component_visual.rotation = component_data.rotation

				# Update visual based on status
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
func _create_component_visual(component_data: Dictionary) -> Node:
	var visual_type: String = component_data.visual_type
	var visual_data: VisualData = _theme.get_visual_data("component_" + visual_type)

	# If no specific theme data, create a simple colored circle
	if visual_data == null or visual_data.emoji.is_empty():
		return _create_default_component_visual(component_data)

	# Create label-based visual
	var label: Label = Label.new()
	label.name = "Component_" + component_data.component_id
	label.text = visual_data.emoji
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var settings: LabelSettings = LabelSettings.new()
	settings.font_size = visual_data.font_size
	label.label_settings = settings

	label.position = -visual_data.bounds / 2
	label.size = visual_data.bounds

	return label

## Create a default component visual when no theme data exists
func _create_default_component_visual(component_data: Dictionary) -> Control:
	var color: Color = _get_component_color(component_data.visual_type)
	var size: float = _get_component_size(component_data.component_type)

	var circle: Control = Control.new()
	circle.name = "Component_" + component_data.component_id

	var radius: float = size
	var diameter: float = radius * 2.0

	circle.custom_minimum_size = Vector2(diameter, diameter)
	circle.size = Vector2(diameter, diameter)
	circle.position = Vector2(-radius, -radius)

	var color_rect: ColorRect = ColorRect.new()
	color_rect.color = color
	color_rect.size = Vector2(diameter, diameter)

	var shader_material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 circle_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);

	if (dist > 0.5) {
		discard;
	} else {
		COLOR = circle_color;
	}
}
"""
	shader_material.shader = shader
	shader_material.set_shader_parameter("circle_color", color)
	color_rect.material = shader_material

	circle.add_child(color_rect)

	return circle

## Get color for component type
func _get_component_color(visual_type: String) -> Color:
	match visual_type:
		"engine":
			return Color(0.3, 0.6, 1.0)  # Blue for engines
		"control":
			return Color(0.9, 0.9, 0.2)  # Yellow for control
		"power_core":
			return Color(1.0, 0.4, 0.2)  # Orange for power
		"light_weapon":
			return Color(0.6, 0.6, 0.6)  # Gray for light weapons
		"medium_turret":
			return Color(0.7, 0.7, 0.7)  # Light gray for medium turrets
		"heavy_turret":
			return Color(0.8, 0.8, 0.8)  # Lighter gray for heavy turrets
		"gatling_turret":
			return Color(0.5, 0.5, 0.5)  # Dark gray for gatling
		_:
			return Color(0.5, 0.5, 0.5)  # Default gray

## Get size for component type
func _get_component_size(component_type: String) -> float:
	match component_type:
		"engine":
			return 3.0
		"control":
			return 2.0
		"power":
			return 2.5
		"weapon":
			return 2.5
		_:
			return 2.0

## Update component visual based on status
func _update_component_status(component_visual: Node, status: String) -> void:
	match status:
		"operational":
			component_visual.modulate = Color.WHITE
		"damaged":
			component_visual.modulate = Color(1.0, 0.6, 0.0)  # Orange for damaged
		"destroyed":
			component_visual.modulate = Color(0.3, 0.3, 0.3)  # Dark gray for destroyed

## Simple pulse effect (scale up and down)
func _play_pulse_effect(entity_id: String) -> void:
	if entity_id not in _entity_visuals:
		return

	var visual_node: Node = _entity_visuals[entity_id]
	if not is_instance_valid(visual_node):
		return

	var tween: Tween = create_tween()
	tween.tween_property(visual_node, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(visual_node, "scale", Vector2.ONE, 0.1)

## Flash red briefly
func _play_flash_effect(entity_id: String) -> void:
	if entity_id not in _entity_visuals:
		return

	var visual_node: Node = _entity_visuals[entity_id]
	if not is_instance_valid(visual_node):
		return

	var original_color: Color = visual_node.modulate
	visual_node.modulate = Color(1.0, 0.3, 0.3, 1.0)

	var tween: Tween = create_tween()
	tween.tween_property(visual_node, "modulate", original_color, 0.15)

## Fade out to transparent
func _play_fade_out_effect(entity_id: String) -> void:
	if entity_id not in _entity_visuals:
		return

	var visual_node: Node = _entity_visuals[entity_id]
	if not is_instance_valid(visual_node):
		return

	var tween: Tween = create_tween()
	tween.tween_property(visual_node, "modulate:a", 0.0, 0.5)
