## Interface: Provides visual configuration data
## Implementations: JsonTheme (loads from JSON files)
class_name IVisualTheme extends RefCounted

## Get visual configuration for entity type
## Returns: VisualData struct with all visual properties
func get_visual_data(entity_type: String) -> VisualData:
	assert(false, "IVisualTheme.get_visual_data() must be implemented")
	return VisualData.new()

## Get UI icon for medallion
## Returns: String (emoji) or Texture2D (sprite)
func get_ui_icon(medallion_id: String) -> Variant:
	assert(false, "IVisualTheme.get_ui_icon() must be implemented")
	return null

## Get animation specification
## Returns: AnimationSpec with frame data, timing, looping
func get_animation_spec(entity_type: String, anim_name: String) -> AnimationSpec:
	assert(false, "IVisualTheme.get_animation_spec() must be implemented")
	return AnimationSpec.new()
