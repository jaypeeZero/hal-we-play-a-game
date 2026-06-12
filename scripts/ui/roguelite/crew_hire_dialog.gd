class_name CrewHireDialog
extends Control

## Candidate-picker modal for hiring: the roster pool's candidates for one
## role on the left, the selected candidate's full CrewMemberView on the
## right, Hire/Cancel in the footer. Candidates are passed in (the shop
## queries the pool) so the dialog stays pure and testable.
##
## Frees itself after either signal; openers only react to `hired`.

signal hired(roster_id: String)
signal cancelled

const MODAL_WIDTH := 880
const LIST_WIDTH := 280
const LIST_HEIGHT := 430
const SECTION_GAP := 12
const BACKDROP_ALPHA := 0.85

var _candidates: Array = []
var _selected_index := -1
var _detail: CrewMemberView
var _hire_button: Button
var _row_buttons: Array = []


func setup(role: int, candidates: Array) -> void:
	_candidates = candidates.duplicate(true)
	_build_chrome(role)
	if not _candidates.is_empty():
		_select(0)


func _build_chrome(role: int) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := UiKit.BG
	dim.a = BACKDROP_ALPHA
	add_child(UiKit.backdrop(dim))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(MODAL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", UiKit.panel_box(UiKit.PANEL_2, UiKit.LINE))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SECTION_GAP)
	panel.add_child(box)

	box.add_child(UiKit.section_title("Hire %s" % CrewData.get_role_name(role),
		"%d candidate%s" % [_candidates.size(), "" if _candidates.size() == 1 else "s"]))
	box.add_child(_body(role))
	box.add_child(_footer())


func _body(role: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SECTION_GAP)

	if _candidates.is_empty():
		var empty := UiKit.label(
			"No %s candidates available." % CrewData.get_role_name(role), UiKit.DIM)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(empty)
		return row

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, LIST_HEIGHT)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_row_buttons = []
	for i in _candidates.size():
		var entry: Dictionary = _candidates[i]
		var btn := UiKit.style_button(
			_make_button("%s · %s" % [entry.callsign, _top_skill_summary(entry)]), "ghost")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var index := i
		btn.pressed.connect(func(): _select(index))
		_row_buttons.append(btn)
		list.add_child(btn)
	row.add_child(scroll)

	_detail = CrewMemberView.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_detail)
	return row


func _footer() -> Control:
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", SECTION_GAP)

	var cancel := UiKit.style_button(_make_button("Cancel"), "ghost")
	cancel.pressed.connect(_on_cancel)
	footer.add_child(cancel)

	_hire_button = UiKit.style_button(_make_button("Hire"), "primary")
	_hire_button.disabled = true
	_hire_button.pressed.connect(_on_hire)
	footer.add_child(_hire_button)
	return footer


func _select(index: int) -> void:
	_selected_index = index
	var entry: Dictionary = _candidates[index]
	_detail.setup(entry, false)
	_hire_button.disabled = false
	_hire_button.text = "Hire %s" % entry.callsign
	for i in _row_buttons.size():
		UiKit.style_button(_row_buttons[i], "primary" if i == index else "ghost")


func _on_hire() -> void:
	if _selected_index < 0:
		return
	hired.emit(str(_candidates[_selected_index].id))
	queue_free()


func _on_cancel() -> void:
	cancelled.emit()
	queue_free()


## The candidate's strongest competence skill, for the list row
## (aggression is personality, not a qualification).
func _top_skill_summary(entry: Dictionary) -> String:
	var best_name := ""
	var best := -1.0
	var skills: Dictionary = entry.get("skills", {})
	for skill_name in CrewData.SKILL_NAMES:
		if skill_name == CrewData.PERSONALITY_SKILL:
			continue
		var value := float(skills.get(skill_name, 0.0))
		if value > best:
			best = value
			best_name = str(skill_name)
	return "%s %d%%" % [best_name.capitalize(), int(round(best * 100.0))]


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	return btn
