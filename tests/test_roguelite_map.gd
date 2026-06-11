extends GutTest

## Tests for RogueliteMap generation - FUNCTIONALITY ONLY
## Star dates label each row and increase semi-randomly; gaps stay within
## the configured bounds and survive the map-state round trip.

var _saved_map_state: Dictionary


func before_each() -> void:
	_saved_map_state = RoguelikeRun.map_state.duplicate(true)


func after_each() -> void:
	RoguelikeRun.map_state = _saved_map_state


func _generate_map_nodes() -> Array:
	var map: RogueliteMap = autofree(RogueliteMap.new())
	map._generate_map()
	return map._map_nodes.duplicate(true)


func test_every_node_carries_a_star_date():
	for row in _generate_map_nodes():
		for node in row:
			assert_true(node.has("star_date"), "Each map node should carry a star date")


func test_star_dates_increase_row_to_row_within_gap_bounds():
	var rows = _generate_map_nodes()
	var previous_date: int = RoguelikeRun.STAR_DATE_RUN_START
	for row in rows:
		var row_date: int = row[0]["star_date"]
		var gap: int = row_date - previous_date
		assert_between(gap, RoguelikeRun.STAR_DATE_GAP_MIN, RoguelikeRun.STAR_DATE_GAP_MAX,
			"Star-date gaps should stay within the configured bounds")
		previous_date = row_date


func test_all_nodes_in_a_row_share_the_star_date():
	for row in _generate_map_nodes():
		for node in row:
			assert_eq(node["star_date"], row[0]["star_date"],
				"A row is one star date; all its nodes share it")


func test_star_dates_survive_map_state_round_trip():
	var rows = _generate_map_nodes()
	RoguelikeRun.save_map_state(rows, [], 0)

	var restored: Array = RoguelikeRun.load_map_state().get("nodes", [])

	assert_eq(restored[0][0]["star_date"], rows[0][0]["star_date"],
		"Star dates should persist through save/load")
