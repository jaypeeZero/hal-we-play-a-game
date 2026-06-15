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
- **1** - Spawn fighter squadron of 6 in V-formation (Player Team)
- **2** - Spawn 1 Corvette (Player Team)
- **3** - Spawn 1 Capital Ship (Player Team)
- **4** - Spawn fighter squadron of 6 in V-formation (Enemy Team)
- **5** - Spawn 1 Corvette (Enemy Team)
- **6** - Spawn 1 Capital Ship (Enemy Team)

After pressing a spawn key, click on the battlefield to place the ship(s).
Squadron-spawned fighters share a command chain (Alpha leads, Beta–Zeta
follow); single-spawn fighters fly solo.

### Debug Visualization
- **F1** - Toggle debug visualizer (armor sections, internals, weapon arcs, velocity,
  crew stats, formation links, and the Tactics State / Tactics Telemetry layers showing
  each ship's resolved doctrine and steering blend). Layers are individually gated in settings.

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
3. **Functional**: Pure functions process state (DamageResolver, WeaponSystem, CrewSchedulerSystem, ...)
4. **Event-driven NPCs**: Crew don't tick every frame — they wake on schedule or when an event lands in their mailbox
5. **Blended combat**: Engagement is a weighted steering blend driven by resolved tactics, not discrete engage modes

### Crew AI flow

NPCs (pilots, gunners, captains, squadron leaders) are processed by an
event-driven scheduler.  A crew member is only updated when:

- their `next_decision_time` has been reached, **or**
- their mailbox has pending events posted by another system
  (`sensor_contact`, `target_lost`, `ship_damaged`, `threat_appeared`, ...)

Per tick, the scheduler drains a waking crew's events, applies the
side effects (tactical-memory recording, current-target clearing, order
processing), refreshes their awareness against the current world, and
runs the role-specific decision (pilot / gunner / captain / squadron
leader).  Sleeping crew with no events cost essentially nothing.

Urgent events (fresh threat, damage taken) for a pilot with known
threats short-circuit to an evasive maneuver, so reactions don't wait
for the next scheduled wake.

### Combat AI

Engagement behaviour is a continuous steering blend rather than fixed
modes. `TacticsSystem` resolves fleet → squadron → ship/role doctrine
into a per-crew `tactics` block; `SteeringBlender` turns it plus the
live situation into weighted goals (pursue / keep_range / evade /
formation / separation / support) with a preferred range and facing
mode; `MovementSystem` re-blends those goals each frame from current
positions. Reflexes (evasion, collision, area leash) stay hard
overrides. Command roles are hats on existing crew — the best ship's
captain is also Commander, the best wing pilot is also Squadron Leader —
and they issue posture (withdraw / hold / press), formation, and
focus-fire orders that are absorbed into subordinates' blends rather
than forcing discrete moves.

### Roguelike meta-layer navigation

A persistent top nav-bar gives every roguelike meta screen (Fleet Manager,
Map, Crew Manager, News, Pre/Post-Battle) a consistent way to move around.
`NavGraph` (pure, `RefCounted`) holds the screen enum, scene paths and a
**fixed Back hierarchy** (Map → Fleet Manager; Crew/News/Pre/Post-Battle →
Map; Fleet Manager is the floor — Back never goes past it). The `Nav`
autoload is a thin shim that turns that graph into `change_scene_to_file`
calls. `NavBar` (built in code, `NavBar.attach(parent, screen)`) renders the
icon tabs + Back button, plus a live **credits readout** (`RoguelikeRun.money`)
on the right; `attach` is **run-scoped** — it adds nothing unless a roguelike
run is active, so title-menu/skirmish entries keep their own navigation. Tabs
jump straight to a screen; Back walks up the fixed hierarchy. Adding a new area
= one `NavGraph.Screen` value + a `SCENE_PATHS`/`PARENTS` row + one
`NavBar.TABS` entry.

Screen specifics:
- **News** (`NewsScreen`) renders the campaign dispatch feed with the *same*
  shared renderer as the map's side panel (`DispatchesPanel.populate_feed`), so
  the two never diverge.
- **Crew** is the shared `crew_manager` screen, which has two modes chosen by
  `RoguelikeRun.active`: in a run (nav Crew tab) it is a **read-only** view of
  the run's hired crew (`RoguelikeRun.fielded_crew`) that also reports each
  selected member's ship assignment (which ship + position, via
  `RoguelikeRun.assignment_of`); standalone from the title menu it stays the
  editable global-roster editor.

### Key Classes

#### Data Layer (RefCounted - Pure Data)
- `ShipData` — Ship templates and factory methods
- `CrewData` — Crew templates (pilot, gunner, captain, squadron leader) and command-chain helpers

#### Pure-function Systems
- `DamageResolver` — Damage and armor-penetration calculations
- `WeaponSystem` — Weapon firing logic
- `ProjectileSystem` — Projectile movement (mutates in place; one-owner state)
- `CollisionSystem` — Hit detection and damage application
- `MovementSystem` — Ship motion and obstacle avoidance
- `InformationSystem` — Per-crew awareness (visible entities, threats, opportunities)
- `CommandChainSystem` — Order distribution down the chain, awareness merge up
- `CrewAISystem` — Role-specific decision functions (pilot, gunner, captain, squadron leader); dispatches command brains via crew hats
- `TacticsSystem` — Resolves fleet/squadron/ship doctrine into each crew's `tactics` block
- `SteeringBlender` — Builds the weighted steering directive from tactics + live situation
- `CommandDesignationSystem` — Stamps Commander / Squadron Leader hats onto the best-fit crew each tick
- `CrewMailboxSystem` — Per-crew event queue (10-event cap, oldest dropped)
- `CrewSchedulerSystem` — Wakes crew on time-or-event, applies event side effects, drives the decision
- `WingFormationSystem` — Dynamic wing pairing for fighters
- `TacticalMemorySystem` — Recent-events log on each crew member

#### Entity Layer (Node2D - Scene Tree)
- `ShipEntity` — Main ship entity, extends IRenderable
- `ProjectileEntity` — Projectile entity

#### Orchestration
- `SpaceBattleGame` — Game loop; calls the systems in order each frame
- `ShipDebugVisualizer` — Debug overlay (armor sections, weapon arcs, velocity)

#### Rendering Layer (IVisualRenderer)
- `Renderer3D` (active) — 3D models (CC0 Quaternius pack) rendered top-down in a
  SubViewport beneath the 2D world; ship type → model mapping in `data/ship_visuals.json`
- `Renderer78` — line-based hull outlines drawn from `data/hull_shapes/` JSON
  (kept for A/B comparison until the 3D migration completes)

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
  │   ├── ship_data.gd                # Ship templates and factories
  │   └── crew_data.gd                # Crew templates + command-chain helpers
  ├── systems/
  │   ├── damage_resolver.gd          # Damage / armor-penetration math
  │   ├── weapon_system.gd            # Weapon firing logic
  │   ├── projectile_system.gd        # Projectile movement (in-place)
  │   ├── collision_system.gd         # Hit detection
  │   ├── movement_system.gd          # Ship motion
  │   ├── information_system.gd       # Per-crew awareness
  │   ├── command_chain_system.gd     # Orders down, awareness up
  │   ├── crew_ai_system.gd           # Role-specific decisions
  │   ├── crew_mailbox_system.gd      # Per-crew event queue
  │   ├── crew_scheduler_system.gd    # Event-driven crew tick
  │   ├── crew_integration_system.gd  # Apply decisions to ships
  │   ├── wing_formation_system.gd    # Dynamic wing pairing
  │   └── tactical_memory_system.gd   # Recent-events log
  ├── ai/
  │   ├── fighter_pilot_ai.gd         # Fighter wing/lead/wingman tactics
  │   └── large_ship_pilot_ai.gd      # Corvette/capital tactics
  ├── entities/
  │   ├── ship_entity.gd              # Main ship entity
  │   └── projectile_entity.gd        # Projectile entity
  └── space_battle_game.gd            # Game orchestrator

tests/
  └── test_<system>.gd                # GUT tests, one file per system
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

1. Add a template JSON to `data/ship_templates/`
2. Define armor sections (with arcs)
3. Define internal components (with effects)
4. Define weapons (with stats)
5. Add a hull shape JSON to `data/hull_shapes/`

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
