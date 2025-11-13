class_name VisualData extends RefCounted

## Base collision radius at size 1.0 (used for automatic collision calculation)
const BASE_COLLISION_RADIUS: float = 30.0

## Renderer type to use ("label", "sprite_2d", "sprite_3d", "shape")
var renderer_type: String = "label"

## Size multiplier (affects both visual scale and collision radius)
var size: float = 1.0

## Explicit collision radius override (if -1, uses BASE_COLLISION_RADIUS * size)
var collision_radius_override: float = -1.0

## Sprite sheet path (if using sprites)
var sprite_sheet_path: String = ""

## Frame dimensions in pixels
var frame_size: Vector2 = Vector2.ZERO

## Visual offset from entity position
var sprite_offset: Vector2 = Vector2.ZERO

## Bounding box size
var bounds: Vector2 = Vector2.ZERO

## Shadow configuration
var shadow_enabled: bool = false
var shadow_texture_path: String = ""
var shadow_opacity: float = 0.3

## Emoji configuration (if using labels)
var emoji: String = ""
var font_size: int = 16

## Shape configuration (if using shapes)
var shape_type: String = "circle"  # "circle", "rectangle", etc.
var shape_color: Color = Color.BLACK
var shape_radius: float = 30.0  # For circles

## Animation specs (anim_name -> AnimationSpec)
var animations: Dictionary = {}

## Get collision radius (uses override if set, otherwise BASE_COLLISION_RADIUS * size)
func get_collision_radius() -> float:
	if collision_radius_override > 0:
		return collision_radius_override
	return BASE_COLLISION_RADIUS * size

## Get visual scale for sprite rendering
func get_sprite_scale() -> float:
	return size

## Deserialize from theme JSON
static func from_dict(data: Dictionary) -> VisualData:
	var vd = VisualData.new()

	vd.renderer_type = data.get("renderer_type", "label")
	vd.sprite_sheet_path = data.get("sprite_sheet", "")

	# Parse size and collision
	vd.size = data.get("size", 1.0)
	vd.collision_radius_override = data.get("collision_radius_override", -1.0)

	# Parse arrays to Vector2
	var frame_arr = data.get("frame_size", [0, 0])
	vd.frame_size = Vector2(frame_arr[0], frame_arr[1]) if frame_arr.size() >= 2 else Vector2.ZERO

	var offset_arr = data.get("sprite_offset", [0, 0])
	vd.sprite_offset = Vector2(offset_arr[0], offset_arr[1]) if offset_arr.size() >= 2 else Vector2.ZERO

	var bounds_arr = data.get("bounds", [0, 0])
	vd.bounds = Vector2(bounds_arr[0], bounds_arr[1]) if bounds_arr.size() >= 2 else Vector2.ZERO

	# Parse shadow config
	var shadow_data = data.get("shadow", {})
	vd.shadow_enabled = shadow_data.get("enabled", false)
	vd.shadow_texture_path = shadow_data.get("texture", "")
	vd.shadow_opacity = shadow_data.get("opacity", 0.3)

	# Parse emoji config
	vd.emoji = data.get("emoji", "")
	vd.font_size = data.get("font_size", 16)

	# Parse shape config
	var shape_data = data.get("shape", {})
	vd.shape_type = shape_data.get("type", "circle")
	vd.shape_radius = shape_data.get("radius", 30.0)

	# Parse color from hex string or array
	var color_data = shape_data.get("color", "#000000")
	if color_data is String:
		vd.shape_color = Color(color_data)
	elif color_data is Array and color_data.size() >= 3:
		vd.shape_color = Color(color_data[0], color_data[1], color_data[2], color_data[3] if color_data.size() > 3 else 1.0)
	else:
		vd.shape_color = Color.BLACK

	# Parse animations
	var anim_data = data.get("animations", {})
	for anim_name in anim_data:
		vd.animations[anim_name] = AnimationSpec.from_dict(anim_data[anim_name])

	return vd
