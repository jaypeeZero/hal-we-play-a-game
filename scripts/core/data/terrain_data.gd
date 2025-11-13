class_name TerrainData

# Forward declarations for terrain types
const Chasm = preload("res://scripts/entities/terrain/chasm.gd")
const TreeTerrain = preload("res://scripts/entities/terrain/tree_terrain.gd")
const Boulder = preload("res://scripts/entities/terrain/boulder.gd")

enum TerrainType {
	CHASM,
	TREE_EVERGREEN,
	TREE_DECIDUOUS,
	BOULDER
}

const TERRAIN_DATA = {
	TerrainType.CHASM: {
		"terrain_type": "chasm",
		"terrain_class": Chasm,
		"collision_radius": 30.0,
		"removes_creatures": true
	},
	TerrainType.TREE_EVERGREEN: {
		"terrain_type": "tree_evergreen",
		"terrain_class": TreeTerrain,
		"collision_radius": 15.0,
		"blocks_movement": true
	},
	TerrainType.TREE_DECIDUOUS: {
		"terrain_type": "tree_deciduous",
		"terrain_class": TreeTerrain,
		"collision_radius": 15.0,
		"blocks_movement": true
	},
	TerrainType.BOULDER: {
		"terrain_type": "boulder",
		"terrain_class": Boulder,
		"collision_radius": 20.0,
		"blocks_movement": true
	}
}

static func get_data(terrain_type: TerrainType) -> Dictionary:
	return TERRAIN_DATA.get(terrain_type, {}).duplicate()

static func get_terrain_class(terrain_type: TerrainType) -> GDScript:
	var data: Dictionary = get_data(terrain_type)
	return data.get("terrain_class", null)
