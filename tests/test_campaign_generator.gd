extends GutTest

## Tests for CampaignGenerator - FUNCTIONALITY ONLY
## The generator must produce a connected multi-sector graph with bridged
## shells, regardless of the tuning values in play.

const TEST_SEED := 1234


func _rng(seed_value: int = TEST_SEED) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _generate(seed_value: int = TEST_SEED) -> Dictionary:
	return CampaignGenerator.generate(_rng(seed_value))


func _sector_nodes(campaign: Dictionary, sector: String) -> Array:
	var nodes: Array = []
	for node in campaign["nodes"].values():
		if node["sector"] == sector:
			nodes.append(node)
	return nodes


func _single_flagged_node(nodes: Array, flag: String) -> Dictionary:
	var flagged: Array = nodes.filter(func(n): return n.get(flag, false))
	assert_eq(flagged.size(), 1, "Each sector should have exactly one %s node" % flag)
	return flagged[0] if flagged.size() == 1 else {}


## Node ids reachable from `start_id` following non-bridge connections.
func _reachable_within_sector(campaign: Dictionary, start_id: String) -> Dictionary:
	var reached := {start_id: true}
	var frontier := [start_id]
	while not frontier.is_empty():
		var current: String = frontier.pop_back()
		for connection in campaign["connections"]:
			if connection["bridge"] or connection["from_id"] != current:
				continue
			if not reached.has(connection["to_id"]):
				reached[connection["to_id"]] = true
				frontier.append(connection["to_id"])
	return reached


func test_every_sector_has_single_battle_entry_and_exit():
	var campaign := _generate()
	for sector in CampaignSystem.SECTORS:
		var nodes := _sector_nodes(campaign, sector)
		assert_gt(nodes.size(), 0, "Sector %s should have nodes" % sector)
		var entry := _single_flagged_node(nodes, "is_sector_entry")
		var exit := _single_flagged_node(nodes, "is_sector_exit")
		assert_eq(entry.get("type"), CampaignSystem.NODE_TYPE_BATTLE,
			"Sector entry is a forced battle")
		assert_eq(exit.get("type"), CampaignSystem.NODE_TYPE_BATTLE,
			"Sector exit is a forced battle (boss)")


func test_every_sector_node_is_reachable_from_its_entry():
	var campaign := _generate()
	for sector in CampaignSystem.SECTORS:
		var nodes := _sector_nodes(campaign, sector)
		var entry := _single_flagged_node(nodes, "is_sector_entry")
		var reached := _reachable_within_sector(campaign, entry["id"])
		for node in nodes:
			assert_true(reached.has(node["id"]),
				"Node %s should be reachable from its sector entry" % node["id"])


func test_every_node_has_required_intra_sector_edges():
	var campaign := _generate()
	var outgoing := {}
	var incoming := {}
	for connection in campaign["connections"]:
		if connection["bridge"]:
			continue
		outgoing[connection["from_id"]] = true
		incoming[connection["to_id"]] = true
	for node in campaign["nodes"].values():
		if not node["is_sector_exit"]:
			assert_true(outgoing.has(node["id"]),
				"Non-exit node %s needs an outgoing edge" % node["id"])
		if not node["is_sector_entry"]:
			assert_true(incoming.has(node["id"]),
				"Non-entry node %s needs an incoming edge" % node["id"])


func test_exactly_one_bridge_per_adjacent_sector_pair_exit_to_entry():
	var campaign := _generate()
	var bridges: Array = campaign["connections"].filter(func(c): return c["bridge"])
	assert_eq(bridges.size(), CampaignSystem.SECTORS.size() - 1,
		"One bridge per adjacent sector pair")
	for i in CampaignSystem.SECTORS.size() - 1:
		var from_sector: String = CampaignSystem.SECTORS[i]
		var to_sector: String = CampaignSystem.SECTORS[i + 1]
		var matching: Array = bridges.filter(func(bridge):
			var from_node: Dictionary = CampaignSystem.node_by_id(campaign, bridge["from_id"])
			var to_node: Dictionary = CampaignSystem.node_by_id(campaign, bridge["to_id"])
			return from_node["sector"] == from_sector and to_node["sector"] == to_sector)
		assert_eq(matching.size(), 1,
			"Exactly one bridge from sector %s to %s" % [from_sector, to_sector])
		var bridge: Dictionary = matching[0]
		assert_true(CampaignSystem.node_by_id(campaign, bridge["from_id"])["is_sector_exit"],
			"Bridges leave from the sector exit")
		assert_true(CampaignSystem.node_by_id(campaign, bridge["to_id"])["is_sector_entry"],
			"Bridges arrive at the next sector's entry")


func test_shell_radii_strictly_decrease_toward_top_sector():
	var campaign := _generate()
	var previous_radius := INF
	for sector in CampaignSystem.SECTORS:
		var radius := 0.0
		var nodes := _sector_nodes(campaign, sector)
		for node in nodes:
			radius += CampaignSystem.node_position(node).length()
		radius /= nodes.size()
		assert_lt(radius, previous_radius,
			"Sector %s shell should sit inside the previous sector's shell" % sector)
		previous_radius = radius


func test_star_date_gaps_stay_within_bounds():
	var campaign := _generate()
	for node in campaign["nodes"].values():
		assert_between(int(node["star_date_gap"]),
			CampaignGenerator.STAR_DATE_GAP_MIN, CampaignGenerator.STAR_DATE_GAP_MAX,
			"Star-date gaps should stay within the configured bounds")


func test_only_bottom_sector_entry_is_initially_accessible():
	var campaign := _generate()
	var accessible := CampaignSystem.accessible_node_ids(campaign)
	assert_eq(accessible.size(), 1, "Exactly one node accessible at campaign start")
	var node := CampaignSystem.node_by_id(campaign, accessible[0])
	assert_eq(node["sector"], CampaignSystem.SECTORS[0],
		"The journey starts in the bottom sector")
	assert_true(node["is_sector_entry"], "The journey starts at the sector entry")


func test_no_node_starts_visited():
	var campaign := _generate()
	for node in campaign["nodes"].values():
		assert_false(node["visited"], "No node should start visited")


func test_same_seed_produces_identical_campaign():
	assert_eq(JSON.stringify(_generate(42)), JSON.stringify(_generate(42)),
		"Generation must be deterministic for a given rng seed")


func test_json_round_trip_preserves_reachability():
	var campaign := _generate()
	var restored: Dictionary = JSON.parse_string(JSON.stringify(campaign))

	assert_eq(restored["nodes"].size(), campaign["nodes"].size(),
		"Round trip should keep every node")
	assert_eq(CampaignSystem.accessible_node_ids(restored),
		CampaignSystem.accessible_node_ids(campaign),
		"Round trip should keep accessibility")
	for sector in CampaignSystem.SECTORS:
		var entry := _single_flagged_node(_sector_nodes(restored, sector), "is_sector_entry")
		var reached := _reachable_within_sector(restored, entry["id"])
		for node in _sector_nodes(restored, sector):
			assert_true(reached.has(node["id"]),
				"Round trip should keep node %s reachable" % node["id"])


func test_every_node_has_a_non_empty_name():
	var campaign := _generate()
	for node in campaign["nodes"].values():
		assert_true(node.has("name"), "Every node should have a name key")
		assert_gt(node["name"].length(), 0, "Every node name should be non-empty")


func test_all_node_names_are_unique():
	var campaign := _generate()
	var seen := {}
	for node in campaign["nodes"].values():
		var name: String = node.get("name", "")
		assert_false(seen.has(name), "Node name '%s' must be unique" % name)
		seen[name] = true


func test_battle_nodes_have_enemy_fleet_with_at_least_one_ship():
	var campaign := _generate()
	for node in campaign["nodes"].values():
		if node["type"] == CampaignSystem.NODE_TYPE_BATTLE:
			assert_true(node.has("enemy_fleet"),
				"Battle node %s should have enemy_fleet" % node["id"])
			var total := 0
			for count in node["enemy_fleet"].values():
				total += count
			assert_gte(total, 1,
				"Battle node %s enemy_fleet should have >= 1 ship" % node["id"])


func test_battle_node_enemy_fleet_count_within_jitter():
	var campaign := _generate()
	for node in campaign["nodes"].values():
		if node["type"] != CampaignSystem.NODE_TYPE_BATTLE:
			continue
		var base: Dictionary = CampaignGenerator.SECTOR_FLEET_COUNTS.get(node["sector"], {})
		for ship_type in base:
			var base_count: int = int(base[ship_type])
			var actual_count: int = node["enemy_fleet"].get(ship_type, 0)
			assert_gte(actual_count, maxi(0, base_count - CampaignGenerator.ENEMY_COUNT_JITTER),
				"Fleet count for %s on %s should be within jitter" % [ship_type, node["id"]])
			assert_lte(actual_count, base_count + CampaignGenerator.ENEMY_COUNT_JITTER,
				"Fleet count for %s on %s should be within jitter" % [ship_type, node["id"]])


func test_non_battle_nodes_have_no_enemy_fleet():
	var campaign := _generate()
	for node in campaign["nodes"].values():
		if node["type"] != CampaignSystem.NODE_TYPE_BATTLE:
			assert_false(node.has("enemy_fleet"),
				"Non-battle node %s must not have enemy_fleet" % node["id"])


func test_sector_e_battle_nodes_have_only_fighters():
	var campaign := _generate()
	var checked := 0
	for node in campaign["nodes"].values():
		if node["sector"] != "E" or node["type"] != CampaignSystem.NODE_TYPE_BATTLE:
			continue
		checked += 1
		for ship_type in node["enemy_fleet"]:
			assert_eq(ship_type, "fighter",
				"Sector E should only contain fighters, not %s" % ship_type)
	assert_gt(checked, 0, "Expected at least one Sector E battle node")


func test_capital_ships_first_appear_at_sector_b():
	# Sectors before B must have 0 base capitals; B and A must have >=1.
	var sectors_before_b := ["E", "D", "C"]
	var sectors_from_b := ["B", "A"]
	for sector in sectors_before_b:
		var base: Dictionary = CampaignGenerator.SECTOR_FLEET_COUNTS.get(sector, {})
		assert_eq(base.get("capital", 0), 0,
			"Sector %s should have no capital ships in its base fleet" % sector)
	for sector in sectors_from_b:
		var base: Dictionary = CampaignGenerator.SECTOR_FLEET_COUNTS.get(sector, {})
		assert_gt(base.get("capital", 0), 0,
			"Sector %s should have at least one capital ship in its base fleet" % sector)


func test_total_base_fleet_counts_trend_nondecreasing_with_depth():
	var previous_total := 0
	for sector in CampaignSystem.SECTORS:
		var base: Dictionary = CampaignGenerator.SECTOR_FLEET_COUNTS.get(sector, {})
		var total := 0
		for count in base.values():
			total += int(count)
		assert_gte(total, previous_total,
			"Sector %s total base fleet (%d) must be >= previous sector (%d)" % [sector, total, previous_total])
		previous_total = total
