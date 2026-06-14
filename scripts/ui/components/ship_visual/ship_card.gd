class_name ShipCard
extends PanelContainer

## Reusable ship card control: ship sprite + optional name label and badge.
## Code-built (no .tscn) matching the pattern of CrewPortrait and other
## components in scripts/ui/components/.
##
## Usage:
##   var card := ShipCard.new()
##   card.setup("fighter", {label = "HAL-7", team = 0})
##   add_child(card)

const CARD_SIZE := Vector2(96, 120)
const SPRITE_SIZE := Vector2(80, 96)
const LABEL_FONT_SIZE := 11

## Internal nodes (read-only after setup).
var _sprite: TextureRect
var _label: Label


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL, UiKit.LINE))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = SPRITE_SIZE
	_sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sprite.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_sprite)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	_label.add_theme_color_override("font_color", UiKit.DIM)
	_label.visible = false
	vbox.add_child(_label)


## Configure the card. `opts` keys (all optional):
##   label    : String — ship name or call-sign shown below sprite
##   team     : int    — 0 or 1; tints sprite with ShipSprite.team_color()
##   modulate : Color  — explicit modulate override (takes precedence over team)
func setup(ship_type: String, opts: Dictionary = {}) -> void:
	_sprite.texture = ShipSprite.texture_for_type(ship_type)

	if opts.has("modulate"):
		_sprite.modulate = opts["modulate"] as Color
	elif opts.has("team"):
		_sprite.modulate = ShipSprite.team_color(opts["team"] as int)
	else:
		_sprite.modulate = Color.WHITE

	if opts.has("label"):
		_label.text = opts["label"] as String
		_label.visible = true
	else:
		_label.visible = false
