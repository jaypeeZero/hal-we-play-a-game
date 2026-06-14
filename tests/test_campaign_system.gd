extends GutTest

## Tests for CampaignSystem state transitions - FUNCTIONALITY ONLY
## Row-based reachability, promotion, reset_sector_to_shop.

const TEST_SEED := 99


func _campaign() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = TEST_SEED
	return CampaignGenerator.generate(rng)


func _sector_node_with_flag(campaign: Dictionary, sector: String, flag: String) -> Dictionary:
	for node in campaign["nodes"].values():
		if node["sector"] == sector and node.get(flag, false):
			return node
	return {}


func _entry(campaign: Dictionary, sector: String) -> Dictionary:
	return _sector_node_with_flag(campaign, sector, "is_sector_entry")


func _exit(campaign: Dictionary, sector: String) -> Dictionary:
	return _sector_node_with_flag(campaign, sector, "is_sector_exit")



func test_visit_marks_visited_and_sets_current():
	var campaign := _campaign()
	var entry := _entry(campaign, CampaignSystem.SECTORS[0])

	CampaignSystem.visit_node(campaign, entry["id"])

	assert_true(entry["visited"], "Visiting a node marks it visited")
	assert_eq(campaign["current_node_id"], entry["id"],
		"Visiting a node makes it the player's position")


func test_sector_complete_when_exit_is_visited():
	var campaign := _campaign()
	assert_false(CampaignSystem.is_sector_complete(campaign),
		"A fresh campaign has no completed sector")

	CampaignSystem.visit_node(campaign, _exit(campaign, CampaignSystem.SECTORS[0])["id"])

	assert_true(CampaignSystem.is_sector_complete(campaign),
		"Sitting on the visited sector exit completes the sector")


func test_promote_moves_one_sector_up_and_opens_entry():
	var campaign := _campaign()
	CampaignSystem.visit_node(campaign, _exit(campaign, CampaignSystem.SECTORS[0])["id"])

	CampaignSystem.promote(campaign)

	assert_eq(campaign["current_sector"], CampaignSystem.SECTORS[1],
		"Winning a sector promotes one sector up")
	var accessible := CampaignSystem.accessible_node_ids(campaign)
	var entry := _entry(campaign, CampaignSystem.SECTORS[1])
	assert_true(accessible.has(entry["id"]),
		"After promotion the new sector's entry is accessible")
	for node in campaign["nodes"].values():
		if node["sector"] != CampaignSystem.SECTORS[1]:
			assert_false(node["accessible"],
				"Only the new sector has accessible nodes after promotion")


func test_top_sector_detection():
	var campaign := _campaign()
	assert_false(CampaignSystem.is_top_sector(campaign), "The start is not the top")

	campaign["current_sector"] = CampaignSystem.SECTORS[CampaignSystem.SECTORS.size() - 1]

	assert_true(CampaignSystem.is_top_sector(campaign), "Top sector is detected")


# ROW-BASED REACHABILITY

func _nodes_in_sector_at_row(campaign: Dictionary, sector: String, row: int) -> Array:
	var result: Array = []
	for node in campaign["nodes"].values():
		if node["sector"] == sector and node["row"] == row:
			result.append(node)
	return result


func _max_row(campaign: Dictionary, sector: String) -> int:
	var max_r := 0
	for node in campaign["nodes"].values():
		if node["sector"] == sector:
			max_r = maxi(max_r, int(node["row"]))
	return max_r


func test_before_first_jump_only_entry_is_accessible():
	var campaign := _campaign()
	var accessible := CampaignSystem.accessible_node_ids(campaign)
	assert_eq(accessible.size(), 1, "Exactly one node accessible before any jump")
	var node := CampaignSystem.node_by_id(campaign, accessible[0])
	assert_true(node.get("is_sector_entry", false), "The accessible node is the sector entry")


func test_visiting_middle_row_opens_current_and_next_row():
	var campaign := _campaign()
	var sector := CampaignSystem.SECTORS[0]
	# Visit the entry (row 0), then a row-1 node to get to a middle row.
	CampaignSystem.visit_node(campaign, _entry(campaign, sector)["id"])
	var row1_nodes := _nodes_in_sector_at_row(campaign, sector, 1)
	assert_gt(row1_nodes.size(), 0, "precondition: sector has a row 1")
	CampaignSystem.visit_node(campaign, row1_nodes[0]["id"])

	var accessible := CampaignSystem.accessible_node_ids(campaign)
	var current_row: int = row1_nodes[0]["row"]
	for node in campaign["nodes"].values():
		if node["sector"] != sector:
			assert_false(node["accessible"],
				"Other sectors must not be accessible")
		else:
			var on_current_or_next: bool = node["row"] == current_row or node["row"] == current_row + 1
			assert_eq(node["accessible"], on_current_or_next,
				"Only current row and next row should be accessible in sector %s" % sector)
	# Verify accessible array is non-empty.
	assert_gt(accessible.size(), 0, "There should be accessible nodes after visiting a middle row")


func test_visited_siblings_remain_accessible():
	var campaign := _campaign()
	var sector := CampaignSystem.SECTORS[0]
	CampaignSystem.visit_node(campaign, _entry(campaign, sector)["id"])
	var row1_nodes := _nodes_in_sector_at_row(campaign, sector, 1)
	if row1_nodes.size() < 2:
		pass_test("sector has only one row-1 node; sibling test skipped")
		return
	# Visit the first row-1 node.
	CampaignSystem.visit_node(campaign, row1_nodes[0]["id"])
	# The sibling row-1 node should still be accessible.
	assert_true(row1_nodes[1]["accessible"],
		"A visited row's sibling nodes remain accessible after a visit")


func test_full_sweep_can_reach_every_node():
	var campaign := _campaign()
	var sector := CampaignSystem.SECTORS[0]
	var max_r := _max_row(campaign, sector)
	# Path well: sweep every node in a row (all siblings are accessible while
	# the player sits on that row) before advancing. This must make every
	# node in the sector reachable, proving full coverage is achievable.
	for row in range(0, max_r + 1):
		var row_nodes := _nodes_in_sector_at_row(campaign, sector, row)
		assert_gt(row_nodes.size(), 0, "Row %d must have at least one node" % row)
		for rn in row_nodes:
			assert_true(rn["accessible"],
				"Node %s at row %d must be accessible before it is visited" % [rn["id"], row])
			CampaignSystem.visit_node(campaign, rn["id"])
	# After a disciplined sweep, every node in the sector has been visited.
	for node in campaign["nodes"].values():
		if node["sector"] == sector:
			assert_true(node["visited"],
				"A disciplined sweep must visit every node in the sector")


func test_promotion_is_one_way():
	var campaign := _campaign()
	CampaignSystem.visit_node(campaign, _exit(campaign, CampaignSystem.SECTORS[0])["id"])
	CampaignSystem.promote(campaign)

	# After promotion no node from the previous sector is accessible.
	for node in campaign["nodes"].values():
		if node["sector"] == CampaignSystem.SECTORS[0]:
			assert_false(node["accessible"],
				"Prior sector nodes must not be accessible after promotion")


func test_reset_sector_to_shop_converts_entry_and_clears_visits():
	var campaign := _campaign()
	var sector := CampaignSystem.SECTORS[0]
	# First do some visiting so there are visited nodes to reset.
	CampaignSystem.visit_node(campaign, _entry(campaign, sector)["id"])

	CampaignSystem.reset_sector_to_shop(campaign, sector)

	var entry := _entry(campaign, sector)
	assert_eq(entry["type"], CampaignSystem.NODE_TYPE_SHOP,
		"reset_sector_to_shop must convert the entry node to a shop")
	assert_false(entry.has("enemy_fleet"),
		"The converted shop entry must have no enemy_fleet")
	assert_eq(campaign["current_node_id"], "",
		"current_node_id must be cleared after reset")
	for node in campaign["nodes"].values():
		if node["sector"] == sector:
			assert_false(node["visited"],
				"All sector visits must be cleared after reset")
	assert_true(entry["accessible"],
		"The entry node must be accessible after reset")
