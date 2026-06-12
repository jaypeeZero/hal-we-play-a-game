extends GutTest

## Tests for CrewMemberView (the dual-mode crew sheet) and CrewViewModal -
## FUNCTIONALITY ONLY. Read-only mode exposes no editing controls, editable
## mode does, edits flow out through entry_changed/current_entry, and the
## modal closes cleanly.

const EDIT_SKILL := 0.9


func _entry(role_names: Array = ["pilot"], skill: float = 0.5) -> Dictionary:
	var skills := {}
	for skill_name in CrewData.SKILL_NAMES:
		skills[skill_name] = skill
	return {"id": "view_test", "callsign": "Testy", "roles": role_names, "skills": skills}


func _view(editable: bool, entry: Dictionary = _entry()) -> CrewMemberView:
	var view := CrewMemberView.new()
	add_child_autofree(view)
	view.setup(entry, editable)
	return view


func _find_by_class(node: Node, klass: String, acc: Array) -> Array:
	for child in node.get_children():
		if child.is_class(klass):
			acc.append(child)
		_find_by_class(child, klass, acc)
	return acc


## is_class only knows engine classes; script classes are found by script.
func _find_by_script(node: Node, script: Script, acc: Array) -> Array:
	for child in node.get_children():
		if child.get_script() == script:
			acc.append(child)
		_find_by_script(child, script, acc)
	return acc


# MODES

func test_read_only_mode_has_no_editing_controls():
	var view := _view(false)
	for klass in ["HSlider", "LineEdit", "CheckBox"]:
		assert_eq(_find_by_class(view, klass, []).size(), 0,
			"Read-only mode contains no %s" % klass)


func test_editable_mode_has_a_control_per_editable_field():
	var view := _view(true)
	assert_eq(_find_by_class(view, "HSlider", []).size(), CrewData.SKILL_NAMES.size(),
		"One slider per skill")
	assert_eq(_find_by_class(view, "LineEdit", []).size(), 1, "One callsign field")
	assert_eq(_find_by_class(view, "CheckBox", []).size(), CrewData.ROLE_NAMES.size(),
		"One qualification checkbox per role")


func test_both_modes_share_the_same_visual_anatomy():
	for editable in [false, true]:
		var view := _view(editable)
		assert_eq(_find_by_script(view, SkillRadarChart, []).size(), 1,
			"A radar chart renders in both modes")
		assert_eq(_find_by_script(view, HeadshotSilhouette, []).size(), 1,
			"A portrait renders in both modes")


# EDITS

func test_moving_a_skill_slider_updates_the_entry_and_signals():
	var view := _view(true)
	watch_signals(view)

	var slider: HSlider = _find_by_class(view, "HSlider", [])[0]
	slider.value = EDIT_SKILL

	assert_signal_emitted(view, "entry_changed", "Edits announce themselves")
	assert_eq(view.current_entry().skills[CrewData.SKILL_NAMES[0]], EDIT_SKILL,
		"The first slider edits the first skill in canonical order")


func test_editing_the_callsign_updates_the_entry():
	var view := _view(true)
	var name_edit: LineEdit = _find_by_class(view, "LineEdit", [])[0]

	name_edit.text = "Renamed"
	name_edit.text_changed.emit("Renamed")

	assert_eq(view.current_entry().callsign, "Renamed",
		"Typing a callsign lands on the entry")


func _role_checkbox(view: CrewMemberView, role: int) -> CheckBox:
	for check in _find_by_class(view, "CheckBox", []):
		if check.text == CrewData.get_role_name(role):
			return check
	return null


func test_checking_a_role_adds_a_qualification():
	var view := _view(true, _entry(["pilot"]))
	var check := _role_checkbox(view, CrewData.Role.ENGINEER)

	check.button_pressed = true

	assert_eq(view.current_entry().roles, ["pilot", "engineer"],
		"Checking a role appends it, keeping the original primary first")


func test_unchecking_a_role_removes_the_qualification():
	var view := _view(true, _entry(["pilot", "engineer"]))
	var check := _role_checkbox(view, CrewData.Role.PILOT)

	check.button_pressed = false

	assert_eq(view.current_entry().roles, ["engineer"],
		"Unchecking removes the qualification")


func test_the_last_qualification_cannot_be_unchecked():
	var view := _view(true, _entry(["pilot"]))
	var check := _role_checkbox(view, CrewData.Role.PILOT)
	watch_signals(view)

	check.button_pressed = false

	assert_eq(view.current_entry().roles, ["pilot"],
		"A crew member always keeps at least one qualified role")
	assert_true(check.button_pressed, "The checkbox snaps back on")
	assert_signal_not_emitted(view, "entry_changed",
		"A reverted uncheck is not an edit")


func test_current_entry_is_a_copy_not_a_live_reference():
	var view := _view(true)
	var taken := view.current_entry()
	taken["callsign"] = "Mutated"

	assert_eq(view.current_entry().callsign, "Testy",
		"Mutating a returned entry never reaches the view's state")


func test_setup_does_not_mutate_the_callers_entry():
	var original := _entry()
	var view := _view(true, original)
	var slider: HSlider = _find_by_class(view, "HSlider", [])[0]

	slider.value = EDIT_SKILL

	assert_eq(original.skills[CrewData.SKILL_NAMES[0]], 0.5,
		"The caller's dict is untouched by edits inside the view")


# MODAL

func test_modal_hosts_a_read_only_view():
	var host := Control.new()
	add_child_autofree(host)
	var modal := CrewViewModal.open(host, _entry())

	assert_eq(_find_by_script(modal, CrewMemberView, []).size(), 1,
		"The modal shows one crew sheet")
	assert_eq(_find_by_class(modal, "HSlider", []).size(), 0,
		"...in read-only mode")


func test_modal_close_signals_and_frees():
	var host := Control.new()
	add_child_autofree(host)
	var modal := CrewViewModal.open(host, _entry())
	watch_signals(modal)

	var close: Button = _find_by_class(modal, "Button", [])[0]
	close.pressed.emit()

	assert_signal_emitted(modal, "closed", "Closing announces itself")
	assert_true(modal.is_queued_for_deletion(), "The modal cleans itself up")
