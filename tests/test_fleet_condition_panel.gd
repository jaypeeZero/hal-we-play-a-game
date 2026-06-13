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
	var buttons := _collect_hull_buttons(panel)
	assert_gte(buttons.size(), hulls.size(),
		"At least one button per hull is present")


func test_refresh_with_no_hulls_shows_no_hull_buttons():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	panel.refresh(100, [])
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

	var buttons := _collect_hull_buttons(panel)
	assert_gt(buttons.size(), 0, "At least one hull button exists")
	buttons[0].emit_signal("pressed")

	assert_signal_emitted(panel, "hull_selected")


func test_hull_selected_emits_the_hull_dictionary():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	watch_signals(panel)

	var hull := _make_hull("fighter")
	panel.refresh(0, [hull])

	var buttons := _collect_hull_buttons(panel)
	buttons[0].emit_signal("pressed")

	var params: Array = get_signal_parameters(panel, "hull_selected")
	assert_not_null(params, "hull_selected signal has parameters")
	assert_true(params[0] is Dictionary, "Emitted parameter is a Dictionary")
	assert_eq(params[0].get("ship_type", ""), "fighter",
		"Emitted hull matches the one that was clicked")


# --- Collapsible header ---

func test_toggle_hides_body_but_panel_stays_visible():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	panel.refresh(100, [_make_hull("fighter")])
	assert_true(panel._body.visible, "Body visible before collapse")
	panel._toggle_btn.emit_signal("pressed")
	assert_true(panel.visible, "Panel still visible after collapse")
	assert_false(panel._body.visible, "Body hidden after collapse")


func test_toggle_twice_restores_body():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	panel.refresh(100, [_make_hull("fighter")])
	panel._toggle_btn.emit_signal("pressed")
	panel._toggle_btn.emit_signal("pressed")
	assert_true(panel._body.visible, "Body visible again after two toggles")


func test_collapse_state_survives_refresh_rebuild():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	panel.refresh(100, [_make_hull("fighter")])
	panel._toggle_btn.emit_signal("pressed")
	assert_false(panel._body.visible, "Body hidden after collapse")
	panel.refresh(200, [_make_hull("corvette"), _make_hull("fighter")])
	assert_false(panel._body.visible, "Body still hidden after refresh rebuild")


# --- Scrollable hull list ---

func test_many_hulls_are_inside_scroll_container():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	var hulls: Array = []
	for i in range(20):
		hulls.append(_make_hull("fighter"))
	panel.refresh(999, hulls)
	var scroll := _find_scroll_container(panel)
	assert_not_null(scroll, "A ScrollContainer exists when hull count is large")


func test_scroll_container_height_does_not_exceed_cap():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	var hulls: Array = []
	for i in range(20):
		hulls.append(_make_hull("fighter"))
	panel.refresh(999, hulls)
	var scroll := _find_scroll_container(panel)
	assert_not_null(scroll, "ScrollContainer exists")
	assert_lte(scroll.custom_minimum_size.y, FleetConditionPanel.MAX_LIST_HEIGHT,
		"Scroll area custom_minimum_size does not exceed MAX_LIST_HEIGHT")


func test_hull_selected_emits_from_inside_scroll_container():
	var panel := FleetConditionPanel.new()
	add_child_autofree(panel)
	watch_signals(panel)
	var hulls: Array = []
	for i in range(20):
		hulls.append(_make_hull("fighter"))
	panel.refresh(999, hulls)
	var buttons := _collect_hull_buttons(panel)
	assert_gt(buttons.size(), 0, "Hull buttons exist inside scroll area")
	buttons[0].emit_signal("pressed")
	assert_signal_emitted(panel, "hull_selected")


# --- helpers ---

func _collect_hull_buttons(panel: FleetConditionPanel) -> Array:
	## Collect hull-row buttons from the body only (excludes the toggle button in the header).
	return _collect_buttons(panel._body)


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


func _find_scroll_container(root: Node) -> ScrollContainer:
	for child in root.get_children():
		if child is ScrollContainer:
			return child
		var found := _find_scroll_container(child)
		if found:
			return found
	return null
