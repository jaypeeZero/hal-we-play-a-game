extends GutTest

## Tests for CampaignSystem state transitions - FUNCTIONALITY ONLY
## Visiting gates accessibility, promotion/demotion walk the sector
## ladder, and enemy scaling never weakens as sectors ascend.

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


func _successor_ids(campaign: Dictionary, node_id: String) -> Array:
	var ids: Array = []
	for connection in campaign["connections"]:
		if connection["from_id"] == node_id:
			ids.append(connection["to_id"])
	return ids


func test_visit_marks_visited_and_sets_current():
	var campaign := _campaign()
	var entry := _entry(campaign, CampaignSystem.SECTORS[0])

	CampaignSystem.visit_node(campaign, entry["id"])

	assert_true(entry["visited"], "Visiting a node marks it visited")
	assert_eq(campaign["current_node_id"], entry["id"],
		"Visiting a node makes it the player's position")


func test_visit_gates_accessibility_to_successors():
	var campaign := _campaign()
	var entry := _entry(campaign, CampaignSystem.SECTORS[0])

	CampaignSystem.visit_node(campaign, entry["id"])

	var accessible := CampaignSystem.accessible_node_ids(campaign)
	var successors := _successor_ids(campaign, entry["id"])
	assert_gt(accessible.size(), 0, "Visiting opens the next row")
	for node_id in accessible:
		assert_has(successors, node_id,
			"Only direct successors of the visited node are accessible")
	assert_false(accessible.has(entry["id"]),
		"The visited node itself is no longer accessible")


func test_sector_complete_when_exit_is_visited():
	var campaign := _campaign()
	assert_false(CampaignSystem.is_sector_complete(campaign),
		"A fresh campaign has no completed sector")

	CampaignSystem.visit_node(campaign, _exit(campaign, CampaignSystem.SECTORS[0])["id"])

	assert_true(CampaignSystem.is_sector_complete(campaign),
		"Sitting on the visited sector exit completes the sector")


func test_promote_moves_one_sector_up_and_opens_bridged_entry():
	var campaign := _campaign()
	CampaignSystem.visit_node(campaign, _exit(campaign, CampaignSystem.SECTORS[0])["id"])

	CampaignSystem.promote(campaign)

	assert_eq(campaign["current_sector"], CampaignSystem.SECTORS[1],
		"Winning a sector promotes one sector up")
	var accessible := CampaignSystem.accessible_node_ids(campaign)
	assert_eq(accessible, [_entry(campaign, CampaignSystem.SECTORS[1])["id"]],
		"After promotion only the bridged next-sector entry is accessible")


func test_demote_moves_one_sector_down_and_resets_lower_sector():
	var campaign := _campaign()
	var lower_sector: String = CampaignSystem.SECTORS[0]
	CampaignSystem.visit_node(campaign, _exit(campaign, lower_sector)["id"])
	CampaignSystem.promote(campaign)
	CampaignSystem.visit_node(campaign, _entry(campaign, CampaignSystem.SECTORS[1])["id"])

	CampaignSystem.demote(campaign)

	assert_eq(campaign["current_sector"], lower_sector,
		"Losing a run demotes one sector down")
	assert_eq(campaign["current_node_id"], "",
		"A demoted player re-enters the sector before any jump")
	for node in campaign["nodes"].values():
		if node["sector"] == lower_sector:
			assert_false(node["visited"],
				"Demotion resets the lower sector for a fresh attempt")
	assert_eq(CampaignSystem.accessible_node_ids(campaign),
		[_entry(campaign, lower_sector)["id"]],
		"After demotion only the lower sector's entry is accessible")


func test_promote_into_previously_failed_sector_resets_it():
	var campaign := _campaign()
	var upper_sector: String = CampaignSystem.SECTORS[1]
	CampaignSystem.visit_node(campaign, _exit(campaign, CampaignSystem.SECTORS[0])["id"])
	CampaignSystem.promote(campaign)
	CampaignSystem.visit_node(campaign, _entry(campaign, upper_sector)["id"])
	CampaignSystem.demote(campaign)

	# Win the lower sector again and promote back up.
	CampaignSystem.visit_node(campaign, _exit(campaign, CampaignSystem.SECTORS[0])["id"])
	CampaignSystem.promote(campaign)

	var entry := _entry(campaign, upper_sector)
	assert_false(entry["visited"],
		"Re-entering a previously failed sector is a fresh attempt")
	assert_true(entry["accessible"],
		"The re-entered sector's entry must be playable again")


func test_top_and_bottom_sector_detection():
	var campaign := _campaign()
	assert_true(CampaignSystem.is_bottom_sector(campaign),
		"A fresh campaign starts in the bottom sector")
	assert_false(CampaignSystem.is_top_sector(campaign), "The start is not the top")

	campaign["current_sector"] = CampaignSystem.SECTORS[CampaignSystem.SECTORS.size() - 1]

	assert_true(CampaignSystem.is_top_sector(campaign), "Top sector is detected")
	assert_false(CampaignSystem.is_bottom_sector(campaign), "The top is not the bottom")


func test_scaled_enemy_fleet_never_shrinks_as_sectors_ascend():
	var base := {"fighter": 2, "heavy_fighter": 1, "torpedo_boat": 0,
		"corvette": 1, "capital": 0}
	var previous := CampaignSystem.scaled_enemy_fleet(base, CampaignSystem.SECTORS[0])
	for ship_type in base:
		assert_gte(previous[ship_type], base[ship_type],
			"Scaling never reduces a ship count below the base fleet")
	for i in range(1, CampaignSystem.SECTORS.size()):
		var scaled := CampaignSystem.scaled_enemy_fleet(base, CampaignSystem.SECTORS[i])
		for ship_type in base:
			assert_gte(scaled[ship_type], previous[ship_type],
				"Higher sectors never field fewer %s than lower ones" % ship_type)
		previous = scaled


func test_scaled_enemy_fleet_keeps_absent_types_absent():
	var base := {"fighter": 1, "heavy_fighter": 0, "torpedo_boat": 0,
		"corvette": 0, "capital": 0}
	var top_sector: String = CampaignSystem.SECTORS[CampaignSystem.SECTORS.size() - 1]

	var scaled := CampaignSystem.scaled_enemy_fleet(base, top_sector)

	assert_eq(scaled["capital"], 0, "Scaling cannot conjure absent ship types")
