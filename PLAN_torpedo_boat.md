# Torpedo Boat Fighter Implementation Plan

## Overview
A new fighter variant focused on anti-ship strikes with a torpedo launcher and defensive gatling gun.

**Priority Targeting**: Medium Ships > Capital Ships > Fighters

---

## 1. Ship Type Registration

**File**: `scripts/space/data/fleet_data_manager.gd` (line 10)

Update the master SHIP_TYPES constant:
```gdscript
const SHIP_TYPES := ["fighter", "heavy_fighter", "torpedo_boat", "corvette", "capital"]
```

This constant is used by all systems to enumerate available ship types.

---

## 2. Ship Template Definition

**File**: `data/ship_templates/torpedo_boat.json` (NEW)

Create a new ship template with these characteristics:
- **Name**: "Torpedo Boat"
- **Type**: "torpedo_boat"
- **Size**: ~18 units (between fighter and heavy fighter)
- **Speed**: 250 units/sec (slightly slower than fighter, carries heavy ordnance)
- **Acceleration**: 80 units/sec²
- **Mass**: 60
- **Turn Rate**: 2.5 (less agile due to torpedo launcher)
- **Armor**: Front (30), Back (25) - moderate protection

**Weapons**:
1. **Gatling Gun** (front-facing, narrow arc -25 to +25)
   - Primary defense weapon
   - Uses existing gatling_gun stats
2. **Torpedo Tube** (front-facing, narrow arc -10 to +10)
   - New weapon type for slow, high-damage torpedoes
   - Requires target alignment for launch

**Internal Components**:
- 1 engine (30 HP)

---

## 3. Hull Shape Definition

**File**: `data/hull_shapes/torpedo_boat_hull.json` (NEW)

Create hull geometry:
```json
{
    "ship_type": "torpedo_boat",
    "base_size": 18.0,
    "sections": [
        {
            "name": "front",
            "vertices": [...],
            "armor_facing": "front"
        },
        {
            "name": "back",
            "vertices": [...],
            "armor_facing": "back"
        }
    ]
}
```

Hull shape should be slightly bulkier than standard fighter to indicate torpedo storage.

---

## 4. New Weapon: Torpedo Launcher

**File**: `scripts/space/data/base_stats.gd` (add to WEAPON_STATS)

```gdscript
"torpedo_launcher": {
    "damage": 15,           # Low direct hit damage
    "range": 1200,          # Long range
    "rate_of_fire": 0.3,    # Slow reload (one every ~3.3 seconds)
    "accuracy": 0.95,       # High accuracy (big slow target)
    "projectile_speed": 200, # SLOW - key characteristic
    "size": 3               # Large weapon
}
```

---

## 5. Torpedo Projectile System

**File**: `scripts/space/systems/projectile_system.gd`

### 5.1 Extend Projectile Data Structure

Add new fields to projectile dictionary:
```gdscript
{
    # ... existing fields ...
    "projectile_type": "standard",  # or "torpedo"
    "explosion_radius": 0.0,        # 0 for standard projectiles
    "explosion_damage": 0           # Damage dealt in blast radius
}
```

### 5.2 Create Torpedo Factory Function

New function `create_torpedo()` that sets:
- `projectile_type`: "torpedo"
- `explosion_radius`: 80 units (affects multiple targets)
- `explosion_damage`: 60 (high blast damage)
- Slower max_lifetime: 15.0 seconds (slow projectiles need longer to reach target)

---

## 6. Explosion/AOE Damage System

**File**: `scripts/space/systems/collision_system.gd`

### 6.1 Torpedo Hit Detection

When a projectile with `projectile_type == "torpedo"` hits:
1. Deal initial impact damage (15) to the hit target
2. Call new `_trigger_explosion()` function

### 6.2 New Function: `_trigger_explosion()`

```gdscript
func _trigger_explosion(position: Vector2, radius: float, damage: int,
                         source_id: String, team: int, game_state: Dictionary) -> Array:
    var explosion_results = []

    # Find all ships within explosion radius
    for ship in game_state.ships.values():
        if ship.status != "operational":
            continue

        var distance = position.distance_to(ship.position)
        if distance > radius:
            continue

        # Damage falls off with distance (linear falloff)
        var damage_multiplier = 1.0 - (distance / radius)
        var applied_damage = int(damage * damage_multiplier)

        if applied_damage > 0:
            # Apply damage to nearest armor section
            var damage_result = _apply_explosion_damage(ship, applied_damage, position)
            explosion_results.append(damage_result)

    return explosion_results
```

### 6.3 Explosion Damage Application

New function `_apply_explosion_damage()`:
- Determine which armor section faces the explosion (based on angle)
- Apply damage through normal DamageResolver pipeline
- Log explosion damage events

---

## 7. Visual Effects for Explosions

### 7.1 Explosion Effect Type

**File**: `scripts/space/systems/visual_effect_system.gd`

Add new effect types:
```gdscript
const EFFECT_TORPEDO_EXPLOSION = "effect_torpedo_explosion"
const TORPEDO_EXPLOSION_DURATION = 1.0  # Longer than standard effects
```

New function:
```gdscript
static func create_torpedo_explosion(position: Vector2, radius: float) -> Dictionary:
    return {
        "effect_type": EFFECT_TORPEDO_EXPLOSION,
        "position": position,
        "radius": radius,
        "duration": TORPEDO_EXPLOSION_DURATION
    }
```

### 7.2 Explosion Rendering

**File**: `rendering/renderers/matrix_renderer.gd`

Add torpedo explosion rendering (similar to projectile but larger):

1. **Expanding Ring Effect**:
   - Multiple concentric circles expanding outward
   - Start at center, expand to explosion radius
   - Fade opacity as they expand

2. **Color Scheme**:
   - Core: Bright white/yellow (`COLOR_HIGHLIGHT`)
   - Outer ring: Orange to red gradient
   - Final flash: Brief red pulse

3. **Size Scaling**:
   - Explosion radius = 80 units (5x larger than standard projectile visual)
   - Ring thickness: 3-5 units

4. **Animation Sequence** (over 1.0 second):
   - 0.0-0.2s: Bright core flash, inner ring forms
   - 0.2-0.6s: Ring expands, core fades
   - 0.6-1.0s: Ring reaches full radius, all elements fade

---

## 8. Torpedo Visual (Projectile Rendering)

**File**: `rendering/renderers/matrix_renderer.gd`

Distinguish torpedo rendering from standard projectiles:

1. **Shape**: Elongated hexagon or diamond (torpedo-like)
2. **Size**: 2x standard projectile size (6 unit radius vs 3)
3. **Color**: Different shade (orange/yellow vs cyan)
4. **Trail**: Longer trail (20 units vs 10) to show slower movement
5. **Glow**: Stronger point light (1.2 energy vs 0.8)

Detection: Check `projectile.projectile_type == "torpedo"` before rendering

---

## 9. Targeting Priority for Torpedo Boat

### 9.1 Ship Type Priority Constants

**File**: `scripts/space/systems/weapon_system.gd`

Add torpedo boat specific priorities:
```gdscript
const TORPEDO_BOAT_PRIORITIES = {
    "corvette": 100.0,      # Medium ships - highest priority
    "capital": 80.0,        # Capital ships - second priority
    "fighter": 30.0,        # Other fighters - lowest priority
    "heavy_fighter": 25.0,
    "torpedo_boat": 20.0    # Avoid other torpedo boats
}
```

### 9.2 AI Targeting Updates

**File**: `scripts/space/ai/fighter_pilot_ai.gd`

Modify target selection to check ship type and apply different priority weights:
- If ship type is "torpedo_boat", use TORPEDO_BOAT_PRIORITIES
- Otherwise use default fighter priorities

Alternatively, add a `targeting_priorities` field to ship templates that overrides defaults.

---

## 10. Fleet Editor UI Integration

**File**: `scenes/fleet_editor.tscn`

Add new UI elements for torpedo boat selection:

### Team 0 Section (after HeavyFighterRow, before CorvetteRow):
```
TorpedoBoatRow (HBoxContainer)
├── Label: "Torpedo Boat"
└── %Team0TorpedoBoatSpinBox (SpinBox)
    - min_value: 0
    - max_value: 20
    - step: 1
```

### Team 1 Section (same structure):
```
TorpedoBoatRow (HBoxContainer)
├── Label: "Torpedo Boat"
└── %Team1TorpedoBoatSpinBox (SpinBox)
    - min_value: 0
    - max_value: 20
    - step: 1
```

**File**: `scripts/ui/menus/fleet_editor.gd`

Add @onready references:
```gdscript
@onready var team0_torpedo_boat_spinbox: SpinBox = %Team0TorpedoBoatSpinBox
@onready var team1_torpedo_boat_spinbox: SpinBox = %Team1TorpedoBoatSpinBox
```

Update `_load_fleet_data()`:
```gdscript
team0_torpedo_boat_spinbox.value = team0_fleet.get("torpedo_boat", 0)
team1_torpedo_boat_spinbox.value = team1_fleet.get("torpedo_boat", 0)
```

Update `_get_team0_fleet()` and `_get_team1_fleet()`:
```gdscript
"torpedo_boat": int(team0_torpedo_boat_spinbox.value)
```

---

## 11. Ship Editor Tool Integration

**File**: `tools/ship_editor.gd`

No code changes needed - the ship editor automatically populates from `FleetDataManager.SHIP_TYPES`.

The dropdown in `_setup_dropdown()` (lines 46-49) iterates through SHIP_TYPES and adds each as an option.

---

## 12. Crew Assignment

**File**: `scripts/space/data/crew_data.gd`

Add torpedo boat crew factory (similar to heavy_fighter - pilot + gunner):

```gdscript
static func create_torpedo_boat_crew(skill_level: float = 0.5) -> Array:
    var pilot = create_crew_member("Pilot", skill_level)
    var torpedo_operator = create_crew_member("Torpedo Operator", skill_level)

    # Torpedo operator reports to pilot
    torpedo_operator.commander_id = pilot.id
    pilot.subordinate_ids.append(torpedo_operator.id)

    return [pilot, torpedo_operator]
```

**File**: `scripts/space/space_battle_game.gd`

Update `_create_crew_for_ship()` to handle torpedo_boat:
```gdscript
"torpedo_boat":
    crew = CrewData.create_torpedo_boat_crew(skill_level)
```

---

## 13. Ship Spawning (Debug Keys)

**File**: `scripts/space/space_battle_game.gd`

Add keyboard shortcuts for torpedo boat spawning (optional, for testing):

In input handling section (around lines 396-417):
```gdscript
KEY_7: _request_spawn("torpedo_boat", 1, 0)  # Team 0 torpedo boat
KEY_8: _request_spawn("torpedo_boat", 1, 1)  # Team 1 torpedo boat
```

---

## 14. Battle Event Logging

**File**: `scripts/space/systems/battle_event_logger.gd`

Add new event types:
- `torpedo_fired` - When torpedo is launched
- `torpedo_explosion` - When torpedo detonates
- `explosion_damage` - For each ship hit by explosion (includes damage amount, distance from blast)

---

## 15. Testing Requirements

**File**: `tests/test_torpedo_system.gd` (NEW)

### Tests to Implement:

1. **Ship Type Registration**
   - "torpedo_boat" is in FleetDataManager.SHIP_TYPES
   - torpedo_boat.json template loads correctly
   - torpedo_boat_hull.json loads correctly

2. **Torpedo Creation**
   - Torpedo has correct projectile_type
   - Torpedo has explosion_radius and explosion_damage set
   - Torpedo speed is slower than standard projectiles

3. **Explosion Mechanics**
   - Ships within radius take damage
   - Ships outside radius take no damage
   - Damage falls off with distance
   - Multiple ships can be hit by single explosion
   - Friendly fire applies to explosions

4. **Targeting Priorities**
   - Torpedo boat prioritizes corvettes over capitals
   - Torpedo boat prioritizes capitals over fighters
   - Priority scoring reflects these preferences

5. **Ship Template Validity**
   - Torpedo boat template loads correctly
   - Has both gatling_gun and torpedo_launcher weapons
   - Stats are within expected ranges

6. **Crew Assignment**
   - Torpedo boat gets correct crew composition
   - Command hierarchy is established

7. **Fleet Persistence**
   - Torpedo boat count saves to fleet JSON
   - Torpedo boat count loads from fleet JSON

---

## 16. Implementation Order

1. **Ship Type Registration** - Add to FleetDataManager.SHIP_TYPES
2. **Base Stats** - Add torpedo_launcher to weapon stats
3. **Ship Template** - Create torpedo_boat.json
4. **Hull Shape** - Create torpedo_boat_hull.json
5. **Crew Factory** - Add create_torpedo_boat_crew()
6. **Fleet Editor UI** - Add spinboxes for torpedo boat
7. **Projectile System** - Add torpedo support and new fields
8. **Explosion System** - Implement AOE damage in CollisionSystem
9. **Visual Effects** - Add explosion effect type and creation
10. **Explosion Rendering** - Implement visual rendering in matrix_renderer
11. **Torpedo Rendering** - Distinguish torpedo projectiles visually
12. **Targeting Priorities** - Update AI to use custom priorities
13. **Debug Spawn Keys** - Add keyboard shortcuts (optional)
14. **Event Logging** - Add new event types
15. **Tests** - Comprehensive test coverage

---

## File Summary

| File | Changes |
|------|---------|
| `scripts/space/data/fleet_data_manager.gd` | Add "torpedo_boat" to SHIP_TYPES |
| `data/ship_templates/torpedo_boat.json` | NEW - Ship template |
| `data/hull_shapes/torpedo_boat_hull.json` | NEW - Hull geometry |
| `scripts/space/data/base_stats.gd` | Add torpedo_launcher weapon |
| `scripts/space/data/crew_data.gd` | Add create_torpedo_boat_crew() |
| `scenes/fleet_editor.tscn` | Add SpinBoxes for torpedo boat |
| `scripts/ui/menus/fleet_editor.gd` | Add spinbox references and logic |
| `scripts/space/systems/projectile_system.gd` | Add torpedo fields, create_torpedo() |
| `scripts/space/systems/collision_system.gd` | Explosion detection and AOE damage |
| `scripts/space/systems/visual_effect_system.gd` | Torpedo explosion effect |
| `rendering/renderers/matrix_renderer.gd` | Explosion and torpedo rendering |
| `scripts/space/systems/weapon_system.gd` | Targeting priorities |
| `scripts/space/ai/fighter_pilot_ai.gd` | Custom priority support |
| `scripts/space/space_battle_game.gd` | Crew assignment, debug keys |
| `scripts/space/systems/battle_event_logger.gd` | New event types |
| `tests/test_torpedo_system.gd` | NEW - Test coverage |
