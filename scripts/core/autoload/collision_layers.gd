class_name CollisionLayers

## Collision Layer System
##
## Godot uses bit flags for collision layers and masks.
## Layer numbers are 1-indexed in the UI but 0-indexed in code.
## Use bit shifting (1 << n) to set specific layers.
##
## Architecture:
## - TERRAIN: Static obstacles (trees, chasms, walls)
##   - Creatures avoid during pathfinding
##   - Terrain detects creatures entering their space
##
## - CREATURES: Dynamic entities (rats, bears, wolves, etc.)
##   - Can physically pass through each other
##   - AI steering decides if they avoid/engage
##   - Detect both terrain and other creatures for combat

# Layer bit positions (0-indexed for code)
const TERRAIN_LAYER: int = 0   # Layer 1 in Godot UI
const CREATURE_LAYER: int = 1  # Layer 2 in Godot UI

# Layer bit masks (use these with collision_layer and collision_mask)
const TERRAIN_BIT: int = 1 << TERRAIN_LAYER    # Binary: 0001 = Decimal: 1
const CREATURE_BIT: int = 1 << CREATURE_LAYER  # Binary: 0010 = Decimal: 2
const ALL_LAYERS: int = TERRAIN_BIT | CREATURE_BIT  # Binary: 0011 = Decimal: 3

## Common configurations:

# Terrain: exists on TERRAIN layer, detects CREATURES
const TERRAIN_COLLISION_LAYER: int = TERRAIN_BIT
const TERRAIN_COLLISION_MASK: int = CREATURE_BIT

# Creature: exists on CREATURE layer, detects both TERRAIN and CREATURES
const CREATURE_COLLISION_LAYER: int = CREATURE_BIT
const CREATURE_COLLISION_MASK: int = TERRAIN_BIT | CREATURE_BIT

# Pathfinding: only check for TERRAIN obstacles (ignore other creatures)
const PATHFINDING_MASK: int = TERRAIN_BIT
