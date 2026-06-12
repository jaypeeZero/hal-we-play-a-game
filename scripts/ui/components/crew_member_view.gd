class_name CrewMemberView
extends PanelContainer

## Football-Manager-style crew member sheet: silhouette portrait, identity,
## skill radar chart, derived stats, and the seven skill values. ONE component
## serves both display and editing — `setup(entry, editable)` decides which
## control each row gets; the layout is shared so the two modes cannot drift.
##
## Operates on the roster-entry shape ({id, callsign, role, skills}); adapt
## live crew dicts with CrewData.entry_from_crew. Derived stats (reaction,
## decision, awareness range) are recomputed for display on every change and
## never stored on the entry.

signal entry_changed(entry: Dictionary)

const SECTION_GAP := 10
const TOP_ROW_GAP := 14
const CALLSIGN_FONT_SIZE := 18
const SKILL_STEP := 0.01
const SKILL_TITLE_WIDTH := 86
const SKILL_VALUE_WIDTH := 36
const DERIVED_TITLES := {
	"reaction_time": "REACTION",
	"decision_time": "DECISION",
	"awareness_range": "AWARENESS",
}

var _entry: Dictionary = {}
var _editable := false
var _radar: SkillRadarChart
var _derived_labels: Dictionary = {}
var _skill_value_labels: Dictionary = {}


func setup(entry: Dictionary, editable: bool) -> void:
	_entry = entry.duplicate(true)
	_editable = editable
	_rebuild()


## The entry as currently shown, including any edits. A copy — callers own it.
func current_entry() -> Dictionary:
	return _entry.duplicate(true)


func _rebuild() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL, UiKit.LINE))
	for child in get_children():
		remove_child(child)
		child.free()
	_derived_labels = {}
	_skill_value_labels = {}

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SECTION_GAP)
	add_child(box)
	box.add_child(_top_row())
	box.add_child(UiKit.separator())
	box.add_child(_derived_row())
	box.add_child(UiKit.separator())
	for skill_name in CrewData.SKILL_NAMES:
		box.add_child(_skill_row(str(skill_name)))
	_refresh_radar()
	_refresh_derived()


# LAYOUT

func _top_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", TOP_ROW_GAP)
	row.add_child(HeadshotSilhouette.new())

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	if _editable:
		var name_edit := LineEdit.new()
		name_edit.text = str(_entry.get("callsign", ""))
		name_edit.text_changed.connect(_on_callsign_changed)
		identity.add_child(name_edit)
		identity.add_child(_role_picker())
	else:
		identity.add_child(UiKit.label(
			str(_entry.get("callsign", "")), UiKit.INK, CALLSIGN_FONT_SIZE))
		identity.add_child(UiKit.label(
			CrewData.get_role_name(_entry_role()), UiKit.DIM, 12))
	row.add_child(identity)

	_radar = SkillRadarChart.new()
	var axis_labels: Array = []
	for skill_name in CrewData.SKILL_NAMES:
		axis_labels.append(str(skill_name).capitalize())
	_radar.set_axis_labels(axis_labels)
	row.add_child(_radar)
	return row


func _role_picker() -> OptionButton:
	var picker := OptionButton.new()
	for role in CrewData.ROLE_NAMES:
		picker.add_item(CrewData.get_role_name(role), role)
	picker.select(picker.get_item_index(_entry_role()))
	picker.item_selected.connect(
		func(index: int): _on_role_selected(picker.get_item_id(index)))
	return picker


func _derived_row() -> Control:
	var row := HBoxContainer.new()
	for key in DERIVED_TITLES:
		var block := VBoxContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := UiKit.label("", UiKit.INK, 14)
		_derived_labels[key] = value
		block.add_child(value)
		block.add_child(UiKit.label(DERIVED_TITLES[key], UiKit.DIM, 10))
		row.add_child(block)
	return row


func _skill_row(skill_name: String) -> Control:
	var value: float = clampf(
		float(_entry.get("skills", {}).get(skill_name, 0.0)), 0.0, 1.0)
	if not _editable:
		var meter := UiKit.meter_bar(skill_name, value, UiKit.ACCENT)
		meter.get_child(0).custom_minimum_size = Vector2(SKILL_TITLE_WIDTH, 0)
		return meter

	var row := HBoxContainer.new()
	var title := UiKit.label(skill_name.capitalize(), UiKit.DIM, 11)
	title.custom_minimum_size = Vector2(SKILL_TITLE_WIDTH, 0)
	row.add_child(title)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = SKILL_STEP
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(
		func(new_value: float): _on_skill_changed(skill_name, new_value))
	row.add_child(slider)

	var value_label := UiKit.label(_format_skill(value), UiKit.INK, 11)
	value_label.custom_minimum_size = Vector2(SKILL_VALUE_WIDTH, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skill_value_labels[skill_name] = value_label
	row.add_child(value_label)
	return row


# EDIT HANDLERS

func _on_callsign_changed(text: String) -> void:
	_entry["callsign"] = text
	entry_changed.emit(current_entry())


func _on_role_selected(role: int) -> void:
	_entry["role"] = CrewData.role_to_name(role)
	_refresh_derived()
	entry_changed.emit(current_entry())


func _on_skill_changed(skill_name: String, value: float) -> void:
	_entry["skills"][skill_name] = value
	if _skill_value_labels.has(skill_name):
		_skill_value_labels[skill_name].text = _format_skill(value)
	_refresh_radar()
	_refresh_derived()
	entry_changed.emit(current_entry())


# REFRESH

func _refresh_radar() -> void:
	var values: Array = []
	var skills: Dictionary = _entry.get("skills", {})
	for skill_name in CrewData.SKILL_NAMES:
		values.append(clampf(float(skills.get(skill_name, 0.0)), 0.0, 1.0))
	_radar.set_values(values)


func _refresh_derived() -> void:
	var stats := CrewData.recompute_derived_stats(
		{"skills": _entry.get("skills", {})}, _entry_role())
	_derived_labels["reaction_time"].text = "%.2fs" % stats.reaction_time
	_derived_labels["decision_time"].text = "%.2fs" % stats.decision_time
	_derived_labels["awareness_range"].text = "%d" % int(stats.awareness_range)


func _entry_role() -> int:
	return CrewData.role_from_name(str(_entry.get("role", "")))


func _format_skill(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))
