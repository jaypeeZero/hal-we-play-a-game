extends GutTest

## Tests for DestinationPanel — behavior only.


func _make_battle_node(accessible: bool, visited: bool = false) -> Dictionary:
	return {
		"id": "node_battle_1",
		"name": "Epsilon Outpost",
		"type": "battle",
		"star_date_gap": 3,
		"visited": visited,
		"accessible": accessible,
		"enemy_fleet": {"fighter": 4, "corvette": 1},
	}


func _make_shop_node(accessible: bool) -> Dictionary:
	return {
		"id": "node_shop_1",
		"name": "Trading Station",
		"type": "shop",
		"star_date_gap": 2,
		"visited": false,
		"accessible": accessible,
	}


func _make_randr_node() -> Dictionary:
	return {
		"id": "node_randr_1",
		"name": "Haven Station",
		"type": "randr",
		"star_date_gap": 1,
		"visited": false,
		"accessible": true,
	}


# --- Launch button state ---

func test_launch_disabled_for_inaccessible_node():
	var panel := DestinationPanel.new()
	add_child_autofree(panel)
	panel.show_node(_make_battle_node(false), false)
	assert_true(panel._launch_button.disabled,
		"Launch is disabled when node is inaccessible")


func test_launch_disabled_for_visited_node():
	var panel := DestinationPanel.new()
	add_child_autofree(panel)
	panel.show_node(_make_battle_node(false, true), false)
	assert_true(panel._launch_button.disabled,
		"Launch is disabled when node was visited but is not accessible")


func test_launch_enabled_for_accessible_node():
	var panel := DestinationPanel.new()
	add_child_autofree(panel)
	panel.show_node(_make_battle_node(true), false)
	assert_false(panel._launch_button.disabled,
		"Launch is enabled when node is accessible")


# --- Signal emission ---

func test_launch_emits_launch_requested_with_node_id():
	var panel := DestinationPanel.new()
	add_child_autofree(panel)
	watch_signals(panel)
	panel.show_node(_make_battle_node(true), false)
	panel._launch_button.emit_signal("pressed")
	assert_signal_emitted_with_parameters(panel, "launch_requested", ["node_battle_1"])


# --- Battle nodes render scout report ---

func test_battle_node_contains_scout_report_content():
	var panel := DestinationPanel.new()
	add_child_autofree(panel)
	panel.show_node(_make_battle_node(true), false)

	# Scout report lines should appear somewhere in the tree
	var found := _find_label_containing(panel, "contacts") or _find_label_containing(panel, "long-range")
	assert_true(found, "Battle node renders scout report content")


func test_shop_node_does_not_render_scout_report():
	var panel := DestinationPanel.new()
	add_child_autofree(panel)
	panel.show_node(_make_shop_node(true), false)

	assert_false(_find_label_containing(panel, "contacts"),
		"Shop node does not render scout report contact line")


func test_randr_node_does_not_render_scout_report():
	var panel := DestinationPanel.new()
	add_child_autofree(panel)
	panel.show_node(_make_randr_node(), false)

	assert_false(_find_label_containing(panel, "contacts"),
		"R&R node does not render scout report contact line")


# --- Dismiss ---

func test_dismiss_hides_panel():
	var panel := DestinationPanel.new()
	add_child_autofree(panel)
	panel.show_node(_make_battle_node(true), false)
	assert_true(panel.visible, "Panel is visible after show_node")
	panel.dismiss()
	assert_false(panel.visible, "Panel is hidden after dismiss")


# --- helpers ---

func _find_label_containing(root: Node, text: String) -> bool:
	## Recursively search for a Label whose text contains `text` (case-insensitive).
	for child in root.get_children():
		if child is Label and child.text.to_lower().contains(text.to_lower()):
			return true
		if _find_label_containing(child, text):
			return true
	return false
