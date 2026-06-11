extends GutTest

## Tests for CampaignSaveManager - FUNCTIONALITY ONLY
## Save/load must round-trip the campaign payload, survive a corrupt file,
## and report its lifecycle through has_save.

const TEST_SEED := 7


func before_each() -> void:
	CampaignSaveManager.delete_save()


func after_each() -> void:
	CampaignSaveManager.delete_save()


func _campaign() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = TEST_SEED
	return CampaignGenerator.generate(rng)


func _payload() -> Dictionary:
	var campaign := _campaign()
	CampaignSystem.visit_node(campaign, CampaignSystem.accessible_node_ids(campaign)[0])
	var ship: Dictionary = ShipData.create_ship_instance("fighter", 0, Vector2(3, 4))
	ship["armor_sections"][0]["current_armor"] = 1
	return {
		"campaign": campaign,
		"fleet": {"fighter": 2, "heavy_fighter": 0, "torpedo_boat": 0,
			"corvette": 1, "capital": 0},
		"fleet_ships": [ship],
		"fleet_crew": [{"ship_type": "fighter", "crew": [{"crew_id": "c1", "callsign": "Alpha"}]}],
		"doctrine": DoctrineSystem.empty_doctrine(),
		"enemy_fleet": {"fighter": 3, "heavy_fighter": 0, "torpedo_boat": 0,
			"corvette": 0, "capital": 0},
		"current_star_date": 2310,
		"callsign_counter": 6,
	}


func test_has_save_lifecycle():
	assert_false(CampaignSaveManager.has_save(), "No save before the first write")

	assert_true(CampaignSaveManager.save_campaign(_payload()), "Save reports success")
	assert_true(CampaignSaveManager.has_save(), "Save exists after writing")

	CampaignSaveManager.delete_save()
	assert_false(CampaignSaveManager.has_save(), "Save is gone after deletion")


func test_round_trip_restores_campaign_position_and_accessibility():
	var payload := _payload()
	CampaignSaveManager.save_campaign(payload)

	var loaded := CampaignSaveManager.load_campaign()

	var campaign: Dictionary = loaded["campaign"]
	assert_eq(campaign["current_sector"], payload["campaign"]["current_sector"],
		"Current sector survives the round trip")
	assert_eq(campaign["current_node_id"], payload["campaign"]["current_node_id"],
		"Current node survives the round trip")
	assert_eq(CampaignSystem.accessible_node_ids(campaign),
		CampaignSystem.accessible_node_ids(payload["campaign"]),
		"Accessibility survives the round trip")


func test_round_trip_restores_integer_typed_fields():
	CampaignSaveManager.save_campaign(_payload())

	var loaded := CampaignSaveManager.load_campaign()

	assert_typeof(loaded["current_star_date"], TYPE_INT)
	assert_typeof(loaded["callsign_counter"], TYPE_INT)
	assert_typeof(loaded["fleet"]["fighter"], TYPE_INT)
	var first_node: Dictionary = loaded["campaign"]["nodes"].values()[0]
	assert_typeof(first_node["row"], TYPE_INT)
	assert_typeof(first_node["star_date_gap"], TYPE_INT)


func test_round_trip_restores_fleet_counts_and_ship_damage():
	var payload := _payload()
	CampaignSaveManager.save_campaign(payload)

	var loaded := CampaignSaveManager.load_campaign()

	assert_eq(loaded["fleet"], payload["fleet"], "Fleet counts survive the round trip")
	assert_eq(loaded["enemy_fleet"], payload["enemy_fleet"],
		"Enemy fleet counts survive the round trip")
	var ship: Dictionary = loaded["fleet_ships"][0]
	assert_eq(int(ship["armor_sections"][0]["current_armor"]), 1,
		"Ship damage state survives the round trip")
	assert_typeof(ship["position"], TYPE_VECTOR2)
	assert_eq(ship["position"], Vector2(3, 4),
		"Vector fields inside ship dicts survive the round trip")


func test_round_trip_restores_crew_identity():
	CampaignSaveManager.save_campaign(_payload())

	var loaded := CampaignSaveManager.load_campaign()

	assert_eq(loaded["fleet_crew"][0]["crew"][0]["callsign"], "Alpha",
		"Crew identity survives the round trip")


func test_missing_save_loads_as_empty():
	assert_eq(CampaignSaveManager.load_campaign(), {},
		"Loading with no save on disk yields an empty payload")


func test_corrupt_save_loads_as_empty():
	var file := FileAccess.open(CampaignSaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{not valid json!!")
	file.close()

	assert_eq(CampaignSaveManager.load_campaign(), {},
		"A corrupt save file yields an empty payload instead of crashing")
	assert_push_error("Failed to parse campaign save JSON")


func test_wrong_version_loads_as_empty():
	var file := FileAccess.open(CampaignSaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": CampaignSaveManager.SAVE_VERSION + 1}))
	file.close()

	assert_eq(CampaignSaveManager.load_campaign(), {},
		"A save from an unknown version is treated as missing")
