extends Node

## Holds state for an active Roguelike run: the player's persistent fleet,
## the enemy's persistent fleet, and the procedurally generated map.
## When `active` is true, the battle scene and map scene swap their behavior
## to use this state instead of the on-disk team fleets.

var active: bool = false
var started_first_battle: bool = false
var fleet: Dictionary = {}
var fleet_ships: Array = []
var enemy_fleet: Dictionary = {}
var map_state: Dictionary = {}
var pending_battle_node_id: String = ""
var editor_return_scene: String = ""


func start_run(initial_fleet: Dictionary) -> void:
	active = true
	started_first_battle = false
	fleet = initial_fleet.duplicate(true)
	fleet_ships = []
	enemy_fleet = FleetDataManager.load_fleet(1)
	map_state = {}
	pending_battle_node_id = ""


func end_run() -> void:
	active = false
	started_first_battle = false
	fleet = {}
	fleet_ships = []
	enemy_fleet = {}
	map_state = {}
	pending_battle_node_id = ""


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
