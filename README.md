# Space Battle Tactics

A scifi battle tactics game built using the signal-based architecture from Wizard Battle Arena, designed with functional programming principles and data-driven systems.

## Quick Start

**Running the game:**
```bash
godot scenes/space_battle.tscn
```

**Running tests:**
```bash
./test.sh
```

## Game Overview

Space Battle Tactics is a real-time tactical combat game where you command fleets of spaceships. Each ship has:
- **Sectional Armor**: Armor that can be destroyed piece by piece, allowing projectiles to penetrate
- **Internal Components**: Engines that affect ship performance when damaged
- **Projectile Weapons**: Realistic ballistic weapons with human reaction times
- **Realistic Physics**: Ships have mass, acceleration, and turn rates

## Controls

### Spawning Ships
- **1** - Spawn 3 Fighters (Player Team)
- **2** - Spawn 1 Corvette (Player Team)
- **3** - Spawn 1 Capital Ship (Player Team)
- **4** - Spawn 3 Fighters (Enemy Team)
- **5** - Spawn 1 Corvette (Enemy Team)
- **6** - Spawn 1 Capital Ship (Enemy Team)

After pressing a spawn key, click on the battlefield to place the ship(s).

### Debug Visualization
- **F1** - Toggle debug visualizer (shows armor sections, internals, weapon arcs, velocity)

## Ship Types

### Fighter
- **Role**: Fast attack craft
- **Size**: Small (15 units)
- **Speed**: 300 units/sec
- **Armor**: Light (3 sections, total ~65 HP)
- **Weapons**: 1x Light Cannon (5 damage, 5 shots/sec)
- **Crew**: 1 pilot
- **Strategy**: Hit and run, swarm tactics

### Corvette
- **Role**: Medium combat vessel
- **Size**: Medium (25 units)
- **Speed**: 150 units/sec
- **Armor**: Heavy (4 sections, total ~320 HP)
- **Weapons**: 2x Medium Cannons (15 damage, 2 shots/sec)
- **Crew**: 3-5 personnel
- **Strategy**: Frontline combat, anti-fighter

### Capital Ship
- **Role**: Heavy battleship
- **Size**: Large (50 units)
- **Speed**: 80 units/sec
- **Armor**: Very Heavy (7 sections, total ~1050 HP)
- **Weapons**: 2x Heavy Cannons (50 damage, 0.5 shots/sec) + 2x Medium Cannons
- **Crew**: 10+ personnel
- **Strategy**: Anchor, long-range fire support

## Game Mechanics

### Damage System

#### Armor Penetration
1. Projectile hits ship → angle calculated
2. Armor section determined by hit angle
3. Damage applied to armor
4. If armor destroyed, remaining damage penetrates to internals

#### Internal Components
- **Engines** (Rear): Propulsion. Damaged = 60% speed/accel. Destroyed = 10% speed (drifting)

### Weapon System

#### Firing Logic
1. Weapons update every 0.1 seconds
2. Calculates lead position for moving targets
3. Checks if target is in firing arc
4. Applies accuracy spread based on ship damage
5. Adds human reaction delay (100-300ms)

#### Accuracy Factors
- Base weapon accuracy
- Distance penalty (up to 30% at max range)
- Target velocity penalty (up to 50% for fast targets)

### Realistic Speeds

All combat happens at human-speed reactions:
- Weapon reaction times: 100-300ms (simulating human gunners)
- Projectile speeds: 450-600 units/sec
- Ship speeds: 80-300 units/sec
- Turn rates: 0.5-3.0 radians/sec

This creates realistic engagement times and allows for tactical maneuvering.

## Architecture

### Core Principles
1. **Signal-Based**: No direct coupling between systems
2. **Data-Driven**: Ships defined by JSON-like dictionaries
3. **Functional**: Pure functions process state (DamageResolver, WeaponSystem)
4. **Scalable**: Designed to support fleet hierarchies down to individual crew

### Key Classes

#### Data Layer (RefCounted - Pure Data)
- `ShipData` - Ship templates and factory methods
- `DamageResolver` - Pure functions for damage calculation
- `WeaponSystem` - Pure functions for weapon firing logic

#### Entity Layer (Node2D - Scene Tree)
- `ShipObject` - Main ship entity, extends IRenderable
- `SpaceProjectile` - Projectile entity

#### System Layer (Node - Orchestration)
- `SpaceBattleGame` - Main game orchestrator
- `ShipDebugVisualizer` - Visual debugging tools

#### Rendering Layer (IVisualRenderer)
- `MatrixRenderer` - Matrix-themed green aesthetic renderer

### Data Structure Example

```gdscript
{
    "ship_id": "ship_0",
    "type": "corvette",
    "team": 0,
    "position": Vector2(500, 500),
    "rotation": 0.0,
    "velocity": Vector2(100, 0),
    "status": "operational",

    "stats": {
        "max_speed": 150.0,
        "acceleration": 50.0,
        "turn_rate": 1.5,
        "mass": 200.0
    },

    "armor_sections": [
        {
            "section_id": "front",
            "arc": {"start": -45, "end": 45},
            "max_armor": 100,
            "current_armor": 100
        }
    ],

    "internals": [
        {
            "component_id": "engine",
            "type": "engine",
            "max_health": 60,
            "current_health": 60,
            "status": "operational"
        }
    ],

    "weapons": [
        {
            "weapon_id": "turret_1",
            "stats": {
                "damage": 15,
                "rate_of_fire": 2.0,
                "range": 1000
            },
            "cooldown_remaining": 0.0
        }
    ]
}
```

## Visual Theme

### Matrix Color Palette
- **Primary Glow**: `#00FF41` - Signature Matrix green for active elements
- **Soft Glow**: `#36BA01` - Edge highlights and outlines
- **Dim**: `#009A22` - Inactive UI elements
- **Highlight**: `#80CE87` - Cursor trails, sparks, projectiles
- **Error**: `#FF003C` - Damage indicators, enemy team
- **Background**: `#0D0D0D` - Deep black space

### Visual Style
- Stylized pixelated top-down 2D graphics
- Geometric ship shapes (triangles, diamonds, hexagons)
- Glowing outlines and particle effects
- Color-coded team indicators

## Development

### File Structure
```
scripts/space/
  ├── data/
  │   └── ship_data.gd          # Ship templates
  ├── systems/
  │   ├── damage_resolver.gd    # Damage calculations
  │   └── weapon_system.gd      # Weapon firing logic
  ├── entities/
  │   ├── ship_object.gd        # Main ship entity
  │   └── space_projectile.gd   # Projectile entity
  ├── debug/
  │   └── ship_debug_visualizer.gd  # Debug tools
  └── space_battle_game.gd      # Game orchestrator

rendering/renderers/
  └── matrix_renderer.gd        # Matrix-themed renderer

tests/
  ├── test_space_ship_data.gd
  ├── test_space_damage_resolver.gd
  └── test_space_weapon_system.gd
```

### Testing

All core systems have comprehensive test coverage:

```bash
# Run all tests
./test.sh

# Test coverage:
# - ShipData template creation and validation
# - DamageResolver armor penetration and internal damage
# - WeaponSystem firing logic and accuracy
```

### Adding New Ship Types

1. Add template to `ShipData._create_XXX_template()`
2. Define armor sections (with arcs)
3. Define internal components (with effects)
4. Define weapons (with stats)
5. Add visual shape to `MatrixRenderer`

Example:
```gdscript
static func _create_destroyer_template() -> Dictionary:
    return {
        "type": "destroyer",
        "stats": {"max_speed": 120.0, ...},
        "armor_sections": [...],
        "internals": [...],
        "weapons": [...]
    }
```

## Future Expansion

The system is designed to scale to:

### Fleet Hierarchy
```gdscript
{
    "fleets": [{
        "name": "Alpha Squadron",
        "flagship": "capital_001",
        "ships": [...]
    }]
}
```

### Crew System
```gdscript
{
    "crew": [{
        "name": "Jefferies",
        "role": "gunner",
        "stats": {"reaction_time": 0.8, "accuracy": 0.7},
        "assigned_station": "turret_1"
    }]
}
```

### Sub-Ships (Recursive)
```gdscript
{
    "sub_ships": [{
        // Fighters carried by capital ships
        // Drones launched from corvettes
        // Full recursive ship definition
    }]
}
```

## Design Philosophy

### Code is the Enemy
- Keep systems simple and focused
- Favor data over code
- Delete complexity whenever possible
- Write minimum code to solve problems

### Functional + Signals + Data
- Pure functions process state
- Signals communicate changes
- Dictionaries/JSON define entities
- No global state in game logic

### Surgical, Precise, Clean
- Clear separation of concerns
- Each class has ONE responsibility
- Data flows predictably
- Easy to test, easy to understand

## Credits

Built on the foundation of Wizard Battle Arena, preserving the signal-based architecture and functional programming principles while creating an entirely new game.

## License

[Same as parent project]
