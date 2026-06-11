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

## Enemy fleet counts scale with the sector's league position.
const SECTOR_DIFFICULTY_MULTIPLIERS := {"E": 1.0, "D": 1.3, "C": 1.6, "B": 2.0, "A": 2.5}


static func node_by_id(campaign: Dictionary, node_id: String) -> Dictionary:
	return campaign.get("nodes", {}).get(node_id, {})


static func node_position(node: Dictionary) -> Vector3:
	var coords: Array = node.get("position", [0.0, 0.0, 0.0])
	return Vector3(coords[0], coords[1], coords[2])


## Mark a node visited and make it the player's position. Accessibility
## narrows to the node's unvisited successors (callers gate on
## `accessible` before visiting; this function trusts them).
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


static func is_bottom_sector(campaign: Dictionary) -> bool:
	return campaign.get("current_sector", "") == SECTORS[0]


## Winning a sector moves the player one shell inward. The bridge from the
## just-won exit node already points at the next sector's entry, so the
## fresh accessibility recompute exposes exactly that entry node.
static func promote(campaign: Dictionary) -> void:
	var next_index := _sector_index(campaign) + 1
	if next_index >= SECTORS.size():
		return
	campaign["current_sector"] = SECTORS[next_index]
	_reset_sector_visits(campaign, SECTORS[next_index])
	_recompute_accessibility_from_current(campaign)


## Losing a run drops the player one shell outward for a fresh attempt at
## the lower sector: same layout, visited flags cleared, entry accessible.
## (Star dates are stored as relative gaps, so re-running a sector keeps
## time flowing forward.)
static func demote(campaign: Dictionary) -> void:
	var lower_index := _sector_index(campaign) - 1
	if lower_index < 0:
		return
	var lower_sector: String = SECTORS[lower_index]
	campaign["current_sector"] = lower_sector
	campaign["current_node_id"] = ""
	_reset_sector_visits(campaign, lower_sector)
	for node in campaign["nodes"].values():
		node["accessible"] = node.get("sector", "") == lower_sector \
			and node.get("is_sector_entry", false)


## Enemy fleet for a sector: each ship count scaled up by the sector's
## difficulty multiplier, rounded up so any present type stays present.
static func scaled_enemy_fleet(base_fleet: Dictionary, sector: String) -> Dictionary:
	var multiplier: float = SECTOR_DIFFICULTY_MULTIPLIERS.get(sector, 1.0)
	var scaled := {}
	for ship_type in base_fleet:
		scaled[ship_type] = ceili(int(base_fleet[ship_type]) * multiplier)
	return scaled


static func _sector_index(campaign: Dictionary) -> int:
	return SECTORS.find(campaign.get("current_sector", SECTORS[0]))


static func _reset_sector_visits(campaign: Dictionary, sector: String) -> void:
	for node in campaign["nodes"].values():
		if node.get("sector", "") == sector:
			node["visited"] = false


static func _recompute_accessibility_from_current(campaign: Dictionary) -> void:
	for node in campaign["nodes"].values():
		node["accessible"] = false
	var current_id: String = campaign.get("current_node_id", "")
	for connection in campaign.get("connections", []):
		if connection["from_id"] != current_id:
			continue
		var successor := node_by_id(campaign, connection["to_id"])
		if not successor.is_empty() and not successor.get("visited", false):
			successor["accessible"] = true
