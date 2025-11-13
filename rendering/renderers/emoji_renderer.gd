class_name EmojiRenderer extends IVisualRenderer

## Implements IVisualRenderer interface
## Renders entities as emoji Labels or geometric shapes

var _theme: IVisualTheme = null
var _entity_visuals: Dictionary = {}  # entity_id -> Node (Label or Control)

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
	# Emoji visuals are static, no state-based updates needed
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
	print("EmojiRenderer cleaned up")

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
