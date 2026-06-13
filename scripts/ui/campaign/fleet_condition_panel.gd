class_name FleetConditionPanel
extends PanelContainer

## Top-left fleet status panel for the campaign map. Shows credits and
## one row per hull with condition meters and crew count.
## The hull list is scrollable; a persistent collapsible header survives rebuilds.

signal hull_selected(hull: Dictionary)

const MARGIN_LEFT := 20
const MARGIN_TOP := 80
const MIN_WIDTH := 300
const CONDITION_LOW_RATIO := 0.4

const COLLAPSE_GLYPH := "▾"
const EXPAND_GLYPH := "▸"

## Maximum visible height for the hull list before it scrolls.
const MAX_LIST_HEIGHT := 380.0
## Estimated row height used to size the scroll area to content when short.
const HULL_ROW_HEIGHT_ESTIMATE := 32.0

var _body: VBoxContainer
var _toggle_btn: Button
var _collapsed := false


func _ready() -> void:
	custom_minimum_size = Vector2(MIN_WIDTH, 0)
	add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL, UiKit.LINE))
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = MARGIN_LEFT
	offset_top = MARGIN_TOP

	# Permanent outer container
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	# Permanent header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	outer.add_child(header)

	_toggle_btn = Button.new()
	_toggle_btn.text = COLLAPSE_GLYPH
	UiKit.style_button(_toggle_btn, "ghost")
	_toggle_btn.pressed.connect(_on_toggle)
	header.add_child(_toggle_btn)

	header.add_child(UiKit.label("Fleet", UiKit.INK))

	# Permanent body container — cleared and refilled on each refresh
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	outer.add_child(_body)


## Rebuild the panel contents for the given credits and hull list.
func refresh(money: int, hulls: Array) -> void:
	for child in _body.get_children():
		child.queue_free()

	_body.add_child(UiKit.label("Credits: %d" % money, UiKit.GOLD))

	if hulls.is_empty():
		_body.add_child(UiKit.label("No hulls", UiKit.DIM))
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var list_height := minf(HULL_ROW_HEIGHT_ESTIMATE * hulls.size(), MAX_LIST_HEIGHT)
		scroll.custom_minimum_size = Vector2(0.0, list_height)
		scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		scroll.add_child(list)

		for hull in hulls:
			list.add_child(_hull_row(hull))

		_body.add_child(scroll)

	# Apply current collapse state
	_body.visible = not _collapsed
	_toggle_btn.text = EXPAND_GLYPH if _collapsed else COLLAPSE_GLYPH


func _hull_row(hull: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	# Ship type button
	var ship_type: String = str(hull.get("ship_type", "unknown"))
	var btn := Button.new()
	btn.text = ship_type.capitalize()
	UiKit.style_button(btn, "ghost")
	btn.pressed.connect(func(): hull_selected.emit(hull))
	row.add_child(btn)

	# On ice badge
	if hull.get("iced", false):
		row.add_child(UiKit.badge("On ice"))

	# Condition meters
	var cond := HullConditionSystem.condition(hull)
	row.add_child(UiKit.mini_meter("Arm", cond.armor, UiKit.ACCENT,
		cond.armor < CONDITION_LOW_RATIO))
	row.add_child(UiKit.mini_meter("Sys", cond.systems, UiKit.GOLD,
		cond.systems < CONDITION_LOW_RATIO))

	# Crew count
	var crew_count: int = hull.get("crew", []).size()
	var complement_count: int = hull.get("complement", []).size()
	row.add_child(UiKit.label("crew %d/%d" % [crew_count, complement_count], UiKit.DIM))

	return row


func _on_toggle() -> void:
	_collapsed = not _collapsed
	_body.visible = not _collapsed
	_toggle_btn.text = EXPAND_GLYPH if _collapsed else COLLAPSE_GLYPH
