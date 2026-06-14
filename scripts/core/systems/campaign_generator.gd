class_name CampaignGenerator
extends RefCounted

## Generates the full multi-sector campaign graph at campaign start, so
## inter-sector bridges are visible from the first jump. Everything is
## plain JSON-serializable data:
##
## campaign = {
##     "current_sector": "E",
##     "current_node_id": "",          # "" before the first jump in a sector
##     "nodes": {node_id: node},       # flat map, id = "sector_row_col"
##     "connections": [{"from_id", "to_id", "bridge": bool}],
## }
## node = {id, sector, row, col, type, star_date_gap, visited, accessible,
##     is_sector_entry, is_sector_exit, "position": [x, y, z],
##     "name": String,
##     "enemy_fleet": {ship_type: count}  (battle nodes only)}
##
## `star_date_gap` is the gap rolled for the node's row, not an absolute
## date: the destination date is computed at jump time, so re-running a
## sector after a reset keeps star dates flowing forward.

const MIN_ROWS_PER_SECTOR := 4
const MAX_ROWS_PER_SECTOR := 6
const MIN_NODES_PER_MIDDLE_ROW := 2
const MAX_NODES_PER_MIDDLE_ROW := 4

const BATTLE_NODE_WEIGHT := 0.60
const RANDR_NODE_WEIGHT := 0.25  # the remainder of the roll is a shop

const STAR_DATE_GAP_MIN := 2
const STAR_DATE_GAP_MAX := 9

const MAX_OUTGOING_CONNECTIONS := 2
const CLOSEST_TARGET_BIAS := 0.7

## Battle-node enemy fleets vary by up to this much (per ship type) around
## the sector base fleet.
const ENEMY_COUNT_JITTER := 1

## Per-sector enemy fleet compositions (ship type → base count).
const SECTOR_FLEET_COUNTS := {
	"E": {"fighter": 3},
	"D": {"fighter": 3, "heavy_fighter": 2},
	"C": {"fighter": 4, "heavy_fighter": 2, "torpedo_boat": 2, "corvette": 1},
	"B": {"fighter": 4, "heavy_fighter": 3, "torpedo_boat": 2, "corvette": 2, "capital": 1},
	"A": {"fighter": 5, "heavy_fighter": 4, "torpedo_boat": 3, "corvette": 2, "capital": 2},
}

## Concentric shell layout: sector E is the outermost shell, sector A the
## core, so winning burrows the camera inward.
const SHELL_RADIUS_CORE := 6.0
const SHELL_RADIUS_STEP := 5.0
## Rows sweep azimuth around the shell; columns fan out in latitude.
const ROW_AZIMUTH_STEP := 0.45
const COLUMN_LATITUDE_STEP := 0.24
## Each sector starts just past the previous one's end so its bridge
## renders as a short radial spoke between adjacent shells.
const BRIDGE_AZIMUTH_GAP := 0.2
const POSITION_JITTER := 0.07


static func generate(rng: RandomNumberGenerator) -> Dictionary:
	var campaign := {
		"current_sector": CampaignSystem.SECTORS[0],
		"current_node_id": "",
		"nodes": {},
		"connections": [],
	}

	var used_names := {}
	var sector_start_azimuth := 0.0
	var previous_exit_id := ""
	for sector_index in CampaignSystem.SECTORS.size():
		var sector: String = CampaignSystem.SECTORS[sector_index]
		var rows := _generate_sector_rows(campaign, sector, sector_index, sector_start_azimuth, rng, used_names)
		_connect_sector_rows(campaign, rows, rng)

		var entry_id: String = rows[0][0]
		if previous_exit_id != "":
			campaign["connections"].append(
				{"from_id": previous_exit_id, "to_id": entry_id, "bridge": true})
		previous_exit_id = rows[rows.size() - 1][0]
		sector_start_azimuth += rows.size() * ROW_AZIMUTH_STEP + BRIDGE_AZIMUTH_GAP

	# Expose the bottom sector's entry via the standard accessibility rule.
	CampaignSystem._recompute_accessibility_from_current(campaign)
	return campaign


## Build one sector's nodes. Returns the sector's rows as an Array of
## Arrays of node ids (the connection pass works row to row).
static func _generate_sector_rows(campaign: Dictionary, sector: String,
		sector_index: int, start_azimuth: float, rng: RandomNumberGenerator,
		used_names: Dictionary) -> Array:
	var row_count := rng.randi_range(MIN_ROWS_PER_SECTOR, MAX_ROWS_PER_SECTOR)
	var rows: Array = []
	for row in row_count:
		var is_edge_row := row == 0 or row == row_count - 1
		var node_count := 1 if is_edge_row \
			else rng.randi_range(MIN_NODES_PER_MIDDLE_ROW, MAX_NODES_PER_MIDDLE_ROW)
		var star_date_gap := rng.randi_range(STAR_DATE_GAP_MIN, STAR_DATE_GAP_MAX)

		var row_ids: Array = []
		for col in node_count:
			var node_type: String = CampaignSystem.NODE_TYPE_BATTLE if is_edge_row else _roll_node_type(rng)
			var node := {
				"id": "%s_%d_%d" % [sector, row, col],
				"sector": sector,
				"row": row,
				"col": col,
				"type": node_type,
				"star_date_gap": star_date_gap,
				"visited": false,
				"accessible": false,
				"is_sector_entry": row == 0,
				"is_sector_exit": row == row_count - 1,
				"position": _shell_position(sector_index, start_azimuth, row, col, node_count, rng),
				"name": DestinationNamer.roll_name(node_type, rng, used_names),
			}
			if node_type == CampaignSystem.NODE_TYPE_BATTLE:
				node["enemy_fleet"] = _roll_enemy_fleet(sector, rng)
			campaign["nodes"][node["id"]] = node
			row_ids.append(node["id"])
		rows.append(row_ids)
	return rows


## Roll a jittered enemy fleet for a battle node from the sector's base
## composition. Each ship type count is randomly nudged by ±ENEMY_COUNT_JITTER
## (clamped to 0). If the result is empty but the base was non-empty, the first
## type is set to 1 — a battle node always has someone to fight.
static func _roll_enemy_fleet(sector: String, rng: RandomNumberGenerator) -> Dictionary:
	var base: Dictionary = SECTOR_FLEET_COUNTS.get(sector, {})
	var result := {}
	for ship_type in base:
		result[ship_type] = maxi(0, int(base[ship_type]) + rng.randi_range(-ENEMY_COUNT_JITTER, ENEMY_COUNT_JITTER))
	var total := 0
	for ship_type in result:
		total += result[ship_type]
	if total == 0 and not base.is_empty():
		var first_type: String = base.keys()[0]
		result[first_type] = 1
	return result


static func _roll_node_type(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < BATTLE_NODE_WEIGHT:
		return CampaignSystem.NODE_TYPE_BATTLE
	if roll < BATTLE_NODE_WEIGHT + RANDR_NODE_WEIGHT:
		return CampaignSystem.NODE_TYPE_RANDR
	return CampaignSystem.NODE_TYPE_SHOP


## A node's spot on its sector's shell: rows advance azimuth, columns fan
## out in latitude around the equator, with a little jitter so the chart
## reads as a starfield rather than a grid.
static func _shell_position(sector_index: int, start_azimuth: float, row: int,
		col: int, node_count: int, rng: RandomNumberGenerator) -> Array:
	var radius := SHELL_RADIUS_CORE \
		+ (CampaignSystem.SECTORS.size() - 1 - sector_index) * SHELL_RADIUS_STEP
	var azimuth := start_azimuth + row * ROW_AZIMUTH_STEP \
		+ rng.randf_range(-POSITION_JITTER, POSITION_JITTER)
	var latitude := (col - (node_count - 1) / 2.0) * COLUMN_LATITUDE_STEP \
		+ rng.randf_range(-POSITION_JITTER, POSITION_JITTER)
	return [
		radius * cos(latitude) * cos(azimuth),
		radius * sin(latitude),
		radius * cos(latitude) * sin(azimuth),
	]


## Intra-sector DAG: every node feeds 1-2 next-row nodes with a bias
## toward the closest column, and every next-row node is guaranteed an
## incoming edge.
static func _connect_sector_rows(campaign: Dictionary, rows: Array,
		rng: RandomNumberGenerator) -> void:
	for row_index in rows.size() - 1:
		var current_ids: Array = rows[row_index]
		var next_ids: Array = rows[row_index + 1]

		for col in current_ids.size():
			var outgoing := rng.randi_range(1, mini(MAX_OUTGOING_CONNECTIONS, next_ids.size()))
			var col_center := float(col) / maxi(1, current_ids.size() - 1) * (next_ids.size() - 1)
			var connected: Array = []
			for _i in outgoing:
				var target := _pick_connection_target(next_ids.size(), col_center, connected, rng)
				if target >= 0:
					connected.append(target)
					campaign["connections"].append({
						"from_id": current_ids[col],
						"to_id": next_ids[target],
						"bridge": false,
					})

		for next_id in next_ids:
			if not _has_incoming(campaign, next_id):
				campaign["connections"].append({
					"from_id": current_ids[rng.randi_range(0, current_ids.size() - 1)],
					"to_id": next_id,
					"bridge": false,
				})


static func _pick_connection_target(row_size: int, col_center: float,
		excluded: Array, rng: RandomNumberGenerator) -> int:
	var candidates: Array = []
	for i in row_size:
		if i not in excluded:
			candidates.append(i)
	if candidates.is_empty():
		return -1

	candidates.sort_custom(func(a, b): return abs(a - col_center) < abs(b - col_center))
	if rng.randf() < CLOSEST_TARGET_BIAS or candidates.size() == 1:
		return candidates[0]
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _has_incoming(campaign: Dictionary, node_id: String) -> bool:
	for connection in campaign["connections"]:
		if connection["to_id"] == node_id:
			return true
	return false
