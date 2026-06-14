class_name CampaignSystem
extends RefCounted

## Pure state transitions over the campaign dictionary (see
## CampaignGenerator.generate for its shape). The campaign is one-owner
## state held by RoguelikeRun; these functions mutate it in place.

## Sector ladder, index 0 = bottom league = outermost shell.
const SECTORS := ["E", "D", "C", "B", "A"]

const NODE_TYPE_BATTLE := "battle"
const NODE_TYPE_RANDR := "randr"
const NODE_TYPE_SHOP := "shop"

const RESULT_VICTORY := "victory"
const RESULT_DEFEAT := "defeat"


static func node_by_id(campaign: Dictionary, node_id: String) -> Dictionary:
	return campaign.get("nodes", {}).get(node_id, {})


static func node_position(node: Dictionary) -> Vector3:
	var coords: Array = node.get("position", [0.0, 0.0, 0.0])
	return Vector3(coords[0], coords[1], coords[2])


## Mark a node visited and make it the player's position. Accessibility
## opens to the current row and the next row in the same sector (visited
## nodes remain accessible so the player can revisit them).
static func visit_node(campaign: Dictionary, node_id: String) -> void:
	var node := node_by_id(campaign, node_id)
	if node.is_empty():
		return
	node["visited"] = true
	campaign["current_node_id"] = node_id
	campaign["current_sector"] = node["sector"]
	_recompute_accessibility_from_current(campaign)


static func accessible_node_ids(campaign: Dictionary) -> Array:
	var ids: Array = []
	for node in campaign.get("nodes", {}).values():
		if node.get("accessible", false):
			ids.append(node["id"])
	return ids


## The sector is complete when the player sits on its visited exit node.
static func is_sector_complete(campaign: Dictionary) -> bool:
	var node := node_by_id(campaign, campaign.get("current_node_id", ""))
	if node.is_empty():
		return false
	return node.get("is_sector_exit", false) and node.get("visited", false) \
		and node.get("sector", "") == campaign.get("current_sector", "")


static func is_top_sector(campaign: Dictionary) -> bool:
	return campaign.get("current_sector", "") == SECTORS[SECTORS.size() - 1]


## Winning a sector moves the player one shell inward. Visits are cleared for
## the new sector and current_node_id is reset so the empty-current branch
## of _recompute_accessibility_from_current exposes exactly the entry node.
static func promote(campaign: Dictionary) -> void:
	var next_index := _sector_index(campaign) + 1
	if next_index >= SECTORS.size():
		return
	campaign["current_sector"] = SECTORS[next_index]
	_reset_sector_visits(campaign, SECTORS[next_index])
	campaign["current_node_id"] = ""
	_recompute_accessibility_from_current(campaign)


## Reset the given sector for a fresh attempt, turning its entry node into
## a shop so the player can rebuild before re-engaging. Used after a defeat
## when the player can still afford to rebuild.
static func reset_sector_to_shop(campaign: Dictionary, sector: String) -> void:
	_reset_sector_visits(campaign, sector)
	campaign["current_node_id"] = ""
	campaign["current_sector"] = sector
	var entry := _sector_entry_node(campaign, sector)
	if not entry.is_empty():
		entry["type"] = NODE_TYPE_SHOP
		entry.erase("enemy_fleet")
	_recompute_accessibility_from_current(campaign)


static func _sector_index(campaign: Dictionary) -> int:
	return SECTORS.find(campaign.get("current_sector", SECTORS[0]))


static func _reset_sector_visits(campaign: Dictionary, sector: String) -> void:
	for node in campaign["nodes"].values():
		if node.get("sector", "") == sector:
			node["visited"] = false


static func _sector_entry_node(campaign: Dictionary, sector: String) -> Dictionary:
	for node in campaign["nodes"].values():
		if node.get("sector", "") == sector and node.get("is_sector_entry", false):
			return node
	return {}


## Row-based reachability:
##   current_node_id == "": only the sector's entry node is accessible.
##   Otherwise: every node on the current row AND the next row is accessible
##   (including visited nodes — players can revisit freely).
static func _recompute_accessibility_from_current(campaign: Dictionary) -> void:
	for node in campaign["nodes"].values():
		node["accessible"] = false
	var current_id: String = campaign.get("current_node_id", "")
	var current_sector: String = campaign.get("current_sector", "")
	if current_id == "":
		for node in campaign["nodes"].values():
			if node.get("sector", "") == current_sector and node.get("is_sector_entry", false):
				node["accessible"] = true
		return
	var current := node_by_id(campaign, current_id)
	if current.is_empty():
		return
	var current_row: int = current.get("row", 0)
	for node in campaign["nodes"].values():
		if node.get("sector", "") != current_sector:
			continue
		var row: int = node.get("row", -1)
		node["accessible"] = (row == current_row or row == current_row + 1)
