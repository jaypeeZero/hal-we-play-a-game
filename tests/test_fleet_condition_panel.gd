extends GutTest

## Tests for FleetConditionPanel — behavior only.


func _make_hull(ship_type: String, iced: bool = false) -> Dictionary:
	return {
		"hull_id": ship_type + "_1",
		"ship_type": ship_type,
		"iced": iced,
		"ship": {},
		"crew": [
			{"role": CrewData.Role.PILOT, "callsign": "Ace"},
		],
		"complement": [
			{"role": CrewData.Role.PILOT},
		],
	}


func test_refresh_with_multiple_hulls_produces_matching_button_count():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	var hulls := [_make_hull("fighter"), _make_hull("corvette"), _make_hull("heavy_fighter")]
	panel.refresh(500, hulls)
	var buttons := _collect_buttons(panel)
	assert_gte(buttons.size(), hulls.size(),
		"At least one button per hull is present")


func test_refresh_with_no_hulls_shows_no_hull_buttons():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	panel.refresh(100, [])
	# Should have no hull-type buttons (only the no-hulls label)
	var labels := _collect_labels(panel)
	var found_empty := false
	for l in labels:
		if l.text.to_lower().contains("no hull"):
			found_empty = true
	assert_true(found_empty, "Empty fleet shows a no-hulls indicator label")


func test_hull_selected_emits_with_clicked_hull():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	watch_signals(panel)

	var hull := _make_hull("torpedo_boat")
	panel.refresh(200, [hull])

	# Find the hull button (first button in the tree) and click it
	var buttons := _collect_buttons(panel)
	assert_gt(buttons.size(), 0, "At least one hull button exists")
	buttons[0].emit_signal("pressed")

	assert_signal_emitted(panel, "hull_selected")


func test_hull_selected_emits_the_hull_dictionary():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	watch_signals(panel)

	var hull := _make_hull("fighter")
	panel.refresh(0, [hull])

	var buttons := _collect_buttons(panel)
	buttons[0].emit_signal("pressed")

	var params: Array = get_signal_parameters(panel, "hull_selected")
	assert_not_null(params, "hull_selected signal has parameters")
	assert_true(params[0] is Dictionary, "Emitted parameter is a Dictionary")
	assert_eq(params[0].get("ship_type", ""), "fighter",
		"Emitted hull matches the one that was clicked")


# --- helpers ---

func _collect_buttons(root: Node) -> Array:
	var result := []
	for child in root.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_collect_buttons(child))
	return result


func _collect_labels(root: Node) -> Array:
	var result := []
	for child in root.get_children():
		if child is Label:
			result.append(child)
		result.append_array(_collect_labels(child))
	return result
