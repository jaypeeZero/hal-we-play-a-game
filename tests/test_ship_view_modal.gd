extends GutTest

## Tests for ShipViewModal — behavior only.


func _make_crew_member(role: CrewData.Role, callsign: String) -> Dictionary:
	return CrewData.create_crew_member(role, 0.5)


func _make_hull(crew_count: int, complement_count: int) -> Dictionary:
	var crew := []
	for i in range(crew_count):
		var member := CrewData.create_crew_member(CrewData.Role.PILOT, 0.5)
		member["callsign"] = "Pilot_%d" % i
		crew.append(member)

	var complement := []
	for i in range(complement_count):
		complement.append({"role": CrewData.Role.PILOT})

	return {
		"hull_id": "test_hull",
		"ship_type": "fighter",
		"iced": false,
		"ship": {},
		"crew": crew,
		"complement": complement,
	}


func test_crew_rows_match_crew_count():
	var hull := _make_hull(2, 2)
	var modal := ShipViewModal.new()
	add_child_autofree(modal)
	modal.setup(hull)

	# Count ghost buttons (callsign buttons per crew member)
	var buttons := _collect_buttons_by_text_pattern(modal, "Pilot_")
	assert_eq(buttons.size(), 2, "Two crew rows for two crew members")


func test_vacant_slot_note_appears_when_complement_exceeds_crew():
	var hull := _make_hull(1, 3)  # 2 vacant slots
	var modal := ShipViewModal.new()
	add_child_autofree(modal)
	modal.setup(hull)

	var found := _find_label_containing(modal, "vacant")
	assert_true(found, "Vacant slot note appears when complement > crew")


func test_vacant_slot_note_absent_when_crew_equals_complement():
	var hull := _make_hull(2, 2)
	var modal := ShipViewModal.new()
	add_child_autofree(modal)
	modal.setup(hull)

	var found := _find_label_containing(modal, "vacant")
	assert_false(found, "No vacant slot note when crew equals complement")


func test_closed_signal_emits_on_close():
	var modal := ShipViewModal.new()
	add_child_autofree(modal)
	watch_signals(modal)
	modal.setup(_make_hull(1, 1))

	# Find the Close button and press it
	var close_btn := _find_button_with_text(modal, "Close")
	assert_not_null(close_btn, "Close button exists")
	close_btn.emit_signal("pressed")

	assert_signal_emitted(modal, "closed")


func test_open_static_attaches_modal_to_parent():
	var parent := Control.new()
	add_child_autofree(parent)
	var hull := _make_hull(0, 0)
	var modal := ShipViewModal.open(parent, hull)
	assert_not_null(modal, "open() returns a modal")
	assert_eq(modal.get_parent(), parent, "Modal is attached to parent")
	# Cleanup: modal will be freed by parent since parent is autofree'd
	# but modal.queue_free just in case it persists
	if is_instance_valid(modal):
		modal.queue_free()


# --- helpers ---

func _collect_buttons_by_text_pattern(root: Node, pattern: String) -> Array:
	var result := []
	for child in root.get_children():
		if child is Button and child.text.begins_with(pattern):
			result.append(child)
		result.append_array(_collect_buttons_by_text_pattern(child, pattern))
	return result


func _find_label_containing(root: Node, text: String) -> bool:
	for child in root.get_children():
		if child is Label and child.text.to_lower().contains(text.to_lower()):
			return true
		if _find_label_containing(child, text):
			return true
	return false


func _find_button_with_text(root: Node, text: String) -> Button:
	for child in root.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button_with_text(child, text)
		if found:
			return found
	return null
