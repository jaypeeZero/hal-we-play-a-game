extends Node

## Holds state for an active Roguelike run: the player's persistent fleet,
## the enemy's persistent fleet, and the procedurally generated map.
## When `active` is true, the battle scene and map scene swap their behavior
## to use this state instead of the on-disk team fleets.

## Star dates: each map row is a star date; jump repairs scale with the
## gap between two jumps (longer downtime, more repair time).
const STAR_DATE_RUN_START = 2300
const STAR_DATE_GAP_MIN = 2
const STAR_DATE_GAP_MAX = 9

var active: bool = false
var started_first_battle: bool = false
var fleet: Dictionary = {}
var fleet_ships: Array = []
var enemy_fleet: Dictionary = {}
var map_state: Dictionary = {}
var pending_battle_node_id: String = ""
var editor_return_scene: String = ""
var current_star_date: int = STAR_DATE_RUN_START


func start_run(initial_fleet: Dictionary) -> void:
	active = true
	started_first_battle = false
	fleet = initial_fleet.duplicate(true)
	fleet_ships = []
	enemy_fleet = FleetDataManager.load_fleet(1)
	map_state = {}
	pending_battle_node_id = ""
	current_star_date = STAR_DATE_RUN_START


func end_run() -> void:
	active = false
	started_first_battle = false
	fleet = {}
	fleet_ships = []
	enemy_fleet = {}
	map_state = {}
	pending_battle_node_id = ""
	current_star_date = STAR_DATE_RUN_START


func update_fleet_after_battle(surviving_ships: Array) -> void:
	fleet_ships = surviving_ships.duplicate(true)
	fleet = {}
	for ship_type in FleetDataManager.SHIP_TYPES:
		fleet[ship_type] = 0
	for ship in fleet_ships:
		var t: String = ship.get("type", "")
		if fleet.has(t):
			fleet[t] += 1


func is_fleet_empty() -> bool:
	return fleet_ships.is_empty()


## Repair the fleet during a jump. Engineers use the downtime: each heals
## their ship by REPAIR_FRACTION_PER_STAR_DATE × machinery skill × date gap
## (× RNR_REPAIR_MULTIPLIER when the destination is an R&R stop).
## Returns {ships_repaired, points_repaired, date_delta}.
func apply_jump_repairs(destination_star_date: int, is_rnr: bool) -> Dictionary:
	var date_delta: int = maxi(0, destination_star_date - current_star_date)
	current_star_date = destination_star_date

	var fraction: float = WingConstants.REPAIR_FRACTION_PER_STAR_DATE * date_delta
	if is_rnr:
		fraction *= WingConstants.RNR_REPAIR_MULTIPLIER

	var ships_repaired := 0
	var points_repaired := 0
	for i in fleet_ships.size():
		var before := _ship_health_total(fleet_ships[i])
		var repaired: Dictionary = RepairSystem.apply_engineer_repairs(fleet_ships[i], fraction)
		var healed := _ship_health_total(repaired) - before
		if healed > 0:
			ships_repaired += 1
			points_repaired += healed
		fleet_ships[i] = repaired

	return {
		"ships_repaired": ships_repaired,
		"points_repaired": points_repaired,
		"date_delta": date_delta,
	}


func _ship_health_total(ship: Dictionary) -> int:
	return DamageResolver.calculate_total_armor(ship) + DamageResolver.calculate_total_internal_health(ship)


func save_map_state(nodes: Array, connections: Array, current_row: int) -> void:
	map_state = {
		"nodes": nodes.duplicate(true),
		"connections": connections.duplicate(true),
		"current_row": current_row,
	}


func has_map_state() -> bool:
	return not map_state.is_empty()


func load_map_state() -> Dictionary:
	return map_state
