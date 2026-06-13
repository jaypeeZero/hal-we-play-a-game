class_name FleetConditionPanel
extends PanelContainer

## Top-left fleet status panel for the campaign map. Shows credits and
## one row per hull with condition meters and crew count.

signal hull_selected(hull: Dictionary)

const MARGIN_LEFT := 20
const MARGIN_TOP := 80
const MIN_WIDTH := 300
const CONDITION_LOW_RATIO := 0.4


func _ready() -> void:
	custom_minimum_size = Vector2(MIN_WIDTH, 0)
	add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL, UiKit.LINE))
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = MARGIN_LEFT
	offset_top = MARGIN_TOP


## Rebuild the panel contents for the given credits and hull list.
func refresh(money: int, hulls: Array) -> void:
	for child in get_children():
		child.queue_free()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	box.add_child(UiKit.section_title("Fleet"))
	box.add_child(UiKit.label("Credits: %d" % money, UiKit.GOLD))

	if hulls.is_empty():
		box.add_child(UiKit.label("No hulls", UiKit.DIM))
		return

	for hull in hulls:
		box.add_child(_hull_row(hull))


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
