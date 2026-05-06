extends Node

## Holds state for an active Roguelike run: the player's persistent fleet,
## the procedurally generated map, and the fixed enemy fleet for every battle.
## When `active` is true, the battle scene and map scene swap their behavior
## to use this state instead of the on-disk team fleets.

const ENEMY_FLEET := {
	"fighter": 2,
	"heavy_fighter": 0,
	"torpedo_boat": 0,
	"corvette": 1,
	"capital": 0,
}

var active: bool = false
var started_first_battle: bool = false
var fleet: Dictionary = {}
var map_state: Dictionary = {}
var pending_battle_node_id: String = ""
var editor_return_scene: String = ""


func start_run(initial_fleet: Dictionary) -> void:
	active = true
	started_first_battle = false
	fleet = initial_fleet.duplicate(true)
	map_state = {}
	pending_battle_node_id = ""


func end_run() -> void:
	active = false
	started_first_battle = false
	fleet = {}
	map_state = {}
	pending_battle_node_id = ""


func update_fleet_after_battle(surviving_counts: Dictionary) -> void:
	fleet = surviving_counts.duplicate(true)


func is_fleet_empty() -> bool:
	for ship_type in fleet.keys():
		if int(fleet[ship_type]) > 0:
			return false
	return true


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
