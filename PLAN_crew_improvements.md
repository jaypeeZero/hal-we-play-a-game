# Plan: Improve Crew AI for All Ship Types

## Executive Summary

The Fighter Pilot AI works well. Other crew types are broken or severely limited. This plan fixes them by applying the same patterns that made Fighter Pilot AI successful.

---

## CRITICAL BUG: Heavy Fighter Gunners Never Shoot

### Root Cause Analysis

**Bug:** Heavy Fighter rear turrets never fire.

**Why:** Two independent issues:

1. **Gunner decisions are disconnected from weapon firing:**
   - `crew_ai_system.gd:make_gunner_decision()` creates fire decisions with `target_id`
   - `crew_integration_system.gd:apply_fire_decision()` sets `ship_data.orders.target_id`
   - `weapon_system.gd:update_weapons()` **IGNORES** `orders.target_id` - it auto-picks targets from the `targets` array
   - **Result:** Gunner AI runs but has no effect on actual weapon firing

2. **Heavy Fighter pilots never expose the rear:**
   - Heavy Fighter pilot uses same logic as regular Fighter (`fighter_pilot_ai.gd`)
   - Pilot pursues enemies (enemies end up in FRONT)
   - Rear turret arc is behind the ship (weapon.facing = π radians)
   - Enemies are never in the rear turret's arc
   - **Result:** Rear turret finds no valid targets

---

## What Made Fighter Pilot AI Successful

From commits `0a2850c`, `8764dcc`, `e5d74eb`, `08c4f4e`, `67b13b4`:

1. **Knowledge-Driven Decisions** - Queries `TacticalKnowledgeSystem` instead of if/else
2. **Situation String Generation** - Creates strings like `"fighter vs fighter far approach"`
3. **Skill-Gated Maneuvers** - Falls back to simpler maneuvers if skill is low
4. **Distance-Based Throttle** - `calculate_intuitive_throttle()` in `movement_system.gd`
5. **Lateral Thrust** - Uses lateral thrust for positioning while facing target

---

## Implementation Plan

### Phase 1: Fix Heavy Fighter Gunner (Bug Fix)

This is the most visible bug. Heavy Fighters have a rear gunner that never shoots.

#### Step 1.1: Add Heavy Fighter Pilot Awareness of Rear Arc

**File:** `scripts/space/ai/fighter_pilot_ai.gd`

**Location:** Add new function after `_make_fighter_vs_fighter_decision()` (around line 480)

**What to add:**

```gdscript
## Check if ship is heavy_fighter type
static func _is_heavy_fighter(ship_data: Dictionary) -> bool:
    return ship_data.get("type", "") == "heavy_fighter"

## Check if any enemy is in the rear turret arc (behind the ship)
## Returns the enemy ship_data if found, empty dict if not
static func _get_enemy_in_rear_arc(ship_data: Dictionary, all_ships: Array) -> Dictionary:
    var my_team = ship_data.get("team", -1)
    var my_pos = ship_data.get("position", Vector2.ZERO)
    var my_rotation = ship_data.get("rotation", 0.0)

    # Rear is opposite of ship facing (ship faces rotation, rear is rotation + PI)
    var rear_direction = Vector2(cos(my_rotation + PI), sin(my_rotation + PI))

    for ship in all_ships:
        if ship.get("team", -1) == my_team:
            continue
        if ship.get("status", "") == "destroyed":
            continue

        var enemy_pos = ship.get("position", Vector2.ZERO)
        var to_enemy = (enemy_pos - my_pos).normalized()
        var distance = my_pos.distance_to(enemy_pos)

        # Check if enemy is within 500 units (rear turret range) and behind us
        # Behind = within 135 degrees of rear (matches rear turret arc)
        if distance < 500.0:
            var angle_to_enemy = abs(rear_direction.angle_to(to_enemy))
            if angle_to_enemy < deg_to_rad(135.0):
                return ship

    return {}
```

**Location:** Modify `_make_fighter_vs_fighter_decision()` (around line 480)

**What to change:** At the start of the function, add this check:

```gdscript
static func _make_fighter_vs_fighter_decision(crew_data: Dictionary, ship_data: Dictionary, target_ship: Dictionary, all_ships: Array, all_crew: Array, game_time: float) -> Dictionary:
    # HEAVY FIGHTER SPECIAL: If enemy is behind us, don't evade - let rear gunner engage
    if _is_heavy_fighter(ship_data):
        var rear_enemy = _get_enemy_in_rear_arc(ship_data, all_ships)
        if not rear_enemy.is_empty():
            # Enemy behind us - maintain current heading, let rear gunner shoot
            # Use gentle pursuit of our forward target instead of aggressive maneuvering
            return _make_heavy_fighter_present_rear_decision(crew_data, ship_data, target_ship, rear_enemy, game_time)

    # ... rest of existing function unchanged ...
```

**Add new function:**

```gdscript
## Heavy fighter behavior when enemy is behind - maintain heading for rear gunner
static func _make_heavy_fighter_present_rear_decision(crew_data: Dictionary, ship_data: Dictionary, forward_target: Dictionary, rear_enemy: Dictionary, game_time: float) -> Dictionary:
    var updated = crew_data.duplicate(true)

    # Continue toward forward target but at reduced throttle
    # This keeps rear exposed to the enemy behind us
    var decision = {
        "type": "maneuver",
        "subtype": "fight_pursue_tactical",  # Reuse existing maneuver
        "crew_id": crew_data.get("crew_id", ""),
        "entity_id": crew_data.get("assigned_to", ""),
        "target_id": forward_target.get("ship_id", ""),
        "rear_target_id": rear_enemy.get("ship_id", ""),  # For debugging/logging
        "skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
        "timestamp": game_time
    }

    updated.next_decision_time = game_time + randf_range(0.3, 0.5)
    return {"crew_data": updated, "decision": decision}
```

#### Step 1.2: Verify Weapon System Arc Calculation

**File:** `scripts/space/systems/weapon_system.gd`

**No changes needed** - The weapon system already correctly calculates arcs via `can_fire_at_target()` -> `is_in_firing_arc()`. The rear turret will fire automatically when targets are in arc.

#### Step 1.3: Add Test for Heavy Fighter Rear Gunner

**File:** `tests/test_heavy_fighter_gunner.gd` (NEW FILE)

```gdscript
extends GutTest

## Test that heavy fighter rear turret can fire at enemies behind the ship

func test_rear_turret_fires_at_enemy_behind():
    # Create heavy fighter facing north (rotation = -PI/2)
    var heavy_fighter = _create_heavy_fighter(Vector2(500, 500), -PI/2, 0)

    # Create enemy behind (south of) the heavy fighter
    var enemy = _create_fighter(Vector2(500, 700), 0, 1)  # 200 units behind

    # Get rear turret (weapon with facing = PI)
    var rear_turret = null
    for weapon in heavy_fighter.weapons:
        if abs(weapon.facing - PI) < 0.1:
            rear_turret = weapon
            break

    assert_not_null(rear_turret, "Heavy fighter should have rear turret")

    # Check if rear turret can fire at enemy
    var can_fire = WeaponSystem.can_fire_at_target(heavy_fighter, rear_turret, enemy)
    assert_true(can_fire, "Rear turret should be able to fire at enemy behind ship")

func test_rear_turret_cannot_fire_at_enemy_in_front():
    # Create heavy fighter facing north
    var heavy_fighter = _create_heavy_fighter(Vector2(500, 500), -PI/2, 0)

    # Create enemy in front (north of) the heavy fighter
    var enemy = _create_fighter(Vector2(500, 300), 0, 1)  # 200 units in front

    var rear_turret = null
    for weapon in heavy_fighter.weapons:
        if abs(weapon.facing - PI) < 0.1:
            rear_turret = weapon
            break

    var can_fire = WeaponSystem.can_fire_at_target(heavy_fighter, rear_turret, enemy)
    assert_false(can_fire, "Rear turret should NOT fire at enemy in front of ship")

func _create_heavy_fighter(pos: Vector2, rotation: float, team: int) -> Dictionary:
    var template = load("res://data/ship_templates/heavy_fighter.json")
    # ... create ship from template with position, rotation, team ...

func _create_fighter(pos: Vector2, rotation: float, team: int) -> Dictionary:
    # ... create basic fighter ...
```

---

### Phase 2: Corvette/Capital Pilot AI

Currently these pilots have ~15 lines of simple if/else logic. They need knowledge-driven decisions like Fighter Pilot AI.

#### Step 2.1: Create Shared Large Ship Pilot AI

**IMPORTANT: DRY Principle** - Corvettes and Capitals share most logic. Create ONE class that handles both.

**File:** `scripts/space/ai/large_ship_pilot_ai.gd` (NEW FILE)

**Pattern to follow:** Copy structure from `scripts/space/ai/fighter_pilot_ai.gd`

**Key differences from FighterPilotAI:**
- No wing formation system (large ships don't fly in wings)
- Different distance ranges (larger engagement distances)
- Different maneuvers (broadside positioning, kiting)
- Weapon arc awareness (position ship to maximize turret coverage)

```gdscript
extends RefCounted
class_name LargeShipPilotAI

## LargeShipPilotAI - Corvette and Capital ship pilot behavior
##
## Distance ranges (larger than fighters):
## - FAR_RANGE: > 3000 units - approach at full speed
## - MID_RANGE: 1500-3000 units - tactical positioning
## - CLOSE_RANGE: < 1500 units - maintain range, present broadside
##
## Core behaviors:
## - Present broadside to maximize turret coverage
## - Maintain safe distance from fighters (kite them)
## - Use lateral thrust to strafe while keeping turrets on target

const FAR_RANGE = 3000.0
const MID_RANGE = 1500.0
const CLOSE_RANGE = 800.0
const SAFE_RANGE_VS_FIGHTERS = 2000.0

## Main decision function - called by CrewAISystem
static func make_decision(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array, game_time: float) -> Dictionary:
    var ship_type = ship_data.get("type", "corvette")
    var target = _find_best_target(crew_data, ship_data, all_ships)

    if target.is_empty():
        return _make_idle_decision(crew_data, game_time)

    var target_type = target.get("type", "fighter")
    var distance = ship_data.get("position", Vector2.ZERO).distance_to(target.get("position", Vector2.ZERO))

    # Generate situation string for knowledge query
    var situation = _generate_situation(ship_type, target_type, distance, crew_data, ship_data, target)

    # Query knowledge system
    var maneuver = _query_large_ship_knowledge(situation, crew_data)

    if maneuver == "":
        maneuver = _get_default_maneuver(ship_type, target_type, distance)

    return _create_maneuver_decision(crew_data, ship_data, target, maneuver, game_time)

## Generate situation string for knowledge query
## Format: "{ship_type} vs {target_type} {distance_category} {position_advantage}"
static func _generate_situation(ship_type: String, target_type: String, distance: float, crew_data: Dictionary, ship_data: Dictionary, target: Dictionary) -> String:
    var parts = [ship_type]

    # Target type category
    if target_type in ["fighter", "heavy_fighter"]:
        parts.append("fighters")
    elif target_type == "corvette":
        parts.append("corvette")
    else:
        parts.append("capital")

    # Distance category
    if distance > FAR_RANGE:
        parts.append("far")
    elif distance > MID_RANGE:
        parts.append("mid")
    else:
        parts.append("close")

    # Broadside status
    if _is_presenting_broadside(ship_data, target):
        parts.append("broadside")
    else:
        parts.append("not_broadside")

    return " ".join(parts)

## Check if ship is presenting broadside to target (perpendicular)
static func _is_presenting_broadside(ship_data: Dictionary, target: Dictionary) -> bool:
    var my_pos = ship_data.get("position", Vector2.ZERO)
    var my_rotation = ship_data.get("rotation", 0.0)
    var target_pos = target.get("position", Vector2.ZERO)

    var to_target = (target_pos - my_pos).normalized()
    var my_facing = Vector2(cos(my_rotation), sin(my_rotation))

    # Broadside = perpendicular = angle ~90 degrees
    var angle = abs(my_facing.angle_to(to_target))
    return abs(angle - PI/2) < deg_to_rad(30.0)  # Within 30 degrees of perpendicular

## Get default maneuver when knowledge query returns empty
static func _get_default_maneuver(ship_type: String, target_type: String, distance: float) -> String:
    if target_type in ["fighter", "heavy_fighter"]:
        if distance < SAFE_RANGE_VS_FIGHTERS:
            return "large_ship_kite"  # Back away from fighters
        else:
            return "large_ship_broadside"  # Present broadside at safe range
    else:
        # vs corvette/capital
        if distance > FAR_RANGE:
            return "large_ship_approach"
        else:
            return "large_ship_broadside"

## Query knowledge system for large ship tactics
static func _query_large_ship_knowledge(situation: String, crew_data: Dictionary) -> String:
    var knowledge = TacticalKnowledgeSystem.query_pilot_knowledge(situation, 3)
    if knowledge.is_empty():
        return ""

    # Select maneuver based on skill (same pattern as FighterPilotAI)
    var skill = crew_data.get("stats", {}).get("skill", 0.5)
    var content = knowledge[0].get("content", {})
    var maneuvers = content.get("maneuvers", [])
    var skill_requirements = content.get("skill_requirements", {})

    for m in maneuvers:
        var required = skill_requirements.get(m, 0.0)
        if skill >= required:
            return m

    return maneuvers[-1] if maneuvers.size() > 0 else ""

static func _find_best_target(crew_data: Dictionary, ship_data: Dictionary, all_ships: Array) -> Dictionary:
    var my_team = ship_data.get("team", -1)
    var my_pos = ship_data.get("position", Vector2.ZERO)
    var best_target = {}
    var best_score = -1.0

    for ship in all_ships:
        if ship.get("team", -1) == my_team:
            continue
        if ship.get("status", "") == "destroyed":
            continue

        var distance = my_pos.distance_to(ship.get("position", Vector2.ZERO))
        var score = 10000.0 - distance  # Prefer closer targets

        # Prefer damaged targets
        if ship.get("status", "") == "damaged":
            score += 5000.0

        if score > best_score:
            best_score = score
            best_target = ship

    return best_target

static func _make_idle_decision(crew_data: Dictionary, game_time: float) -> Dictionary:
    var updated = crew_data.duplicate(true)
    updated.next_decision_time = game_time + randf_range(1.0, 2.0)
    return {"crew_data": updated}

static func _create_maneuver_decision(crew_data: Dictionary, ship_data: Dictionary, target: Dictionary, maneuver: String, game_time: float) -> Dictionary:
    var updated = crew_data.duplicate(true)

    var decision = {
        "type": "maneuver",
        "subtype": maneuver,
        "crew_id": crew_data.get("crew_id", ""),
        "entity_id": crew_data.get("assigned_to", ""),
        "target_id": target.get("ship_id", ""),
        "skill_factor": crew_data.get("stats", {}).get("skill", 0.5),
        "timestamp": game_time
    }

    updated.next_decision_time = game_time + randf_range(0.5, 1.0)
    return {"crew_data": updated, "decision": decision}
```

#### Step 2.2: Add Large Ship Knowledge Patterns

**File:** `scripts/space/systems/tactical_knowledge_system.gd`

**Location:** Add after the existing fighter knowledge patterns (around line 200)

```gdscript
# ============================================================================
# LARGE SHIP PILOT KNOWLEDGE - Corvette and Capital tactics
# ============================================================================

"large_ship_vs_fighters_close": {
    "role": CrewData.Role.PILOT,
    "tags": ["corvette", "capital", "fighters", "close", "kite"],
    "text": "corvette capital fighters close kite back away maintain distance",
    "content": {
        "maneuvers": ["large_ship_kite", "large_ship_broadside"],
        "skill_requirements": {"large_ship_kite": 0.3, "large_ship_broadside": 0.0},
        "priority": "defensive",
        "context": "Back away from fighters, maintain turret range"
    }
},

"large_ship_vs_fighters_mid": {
    "role": CrewData.Role.PILOT,
    "tags": ["corvette", "capital", "fighters", "mid", "broadside"],
    "text": "corvette capital fighters mid range broadside turrets",
    "content": {
        "maneuvers": ["large_ship_broadside", "large_ship_kite"],
        "skill_requirements": {"large_ship_broadside": 0.0, "large_ship_kite": 0.3},
        "priority": "tactical",
        "context": "Present broadside for maximum turret coverage"
    }
},

"large_ship_vs_fighters_far": {
    "role": CrewData.Role.PILOT,
    "tags": ["corvette", "capital", "fighters", "far", "approach"],
    "text": "corvette capital fighters far approach close distance",
    "content": {
        "maneuvers": ["large_ship_approach"],
        "skill_requirements": {"large_ship_approach": 0.0},
        "priority": "normal",
        "context": "Close distance to engagement range"
    }
},

"large_ship_vs_capital_close": {
    "role": CrewData.Role.PILOT,
    "tags": ["corvette", "capital", "close", "broadside", "firing"],
    "text": "corvette capital close range broadside firing solution",
    "content": {
        "maneuvers": ["large_ship_broadside", "large_ship_orbit"],
        "skill_requirements": {"large_ship_broadside": 0.0, "large_ship_orbit": 0.5},
        "priority": "aggressive",
        "context": "Maintain broadside firing position"
    }
},

"large_ship_vs_capital_far": {
    "role": CrewData.Role.PILOT,
    "tags": ["corvette", "capital", "far", "approach"],
    "text": "corvette capital far approach closing",
    "content": {
        "maneuvers": ["large_ship_approach"],
        "skill_requirements": {"large_ship_approach": 0.0},
        "priority": "normal",
        "context": "Close to engagement range"
    }
},
```

#### Step 2.3: Add Large Ship Maneuvers to Movement System

**File:** `scripts/space/systems/movement_system.gd`

**Location:** Add in the maneuver execution section (find where `fight_` maneuvers are handled)

**What to add:**

```gdscript
## Execute large ship maneuvers
## These are simpler than fighter maneuvers - less aggressive turning, more lateral thrust

static func _execute_large_ship_maneuver(ship_data: Dictionary, target: Dictionary, maneuver: String, delta: float) -> Dictionary:
    match maneuver:
        "large_ship_approach":
            return _execute_large_ship_approach(ship_data, target, delta)
        "large_ship_broadside":
            return _execute_large_ship_broadside(ship_data, target, delta)
        "large_ship_kite":
            return _execute_large_ship_kite(ship_data, target, delta)
        "large_ship_orbit":
            return _execute_large_ship_orbit(ship_data, target, delta)
        _:
            return ship_data

## Approach target at full speed
static func _execute_large_ship_approach(ship_data: Dictionary, target: Dictionary, delta: float) -> Dictionary:
    var updated = ship_data.duplicate(true)
    var my_pos = ship_data.get("position", Vector2.ZERO)
    var target_pos = target.get("position", Vector2.ZERO)

    # Face target and thrust forward
    var to_target = (target_pos - my_pos).normalized()
    var target_rotation = to_target.angle()

    updated.orders.desired_rotation = target_rotation
    updated.orders.throttle = 0.8  # Large ships don't go full speed
    updated.orders.lateral_thrust = 0.0

    return updated

## Present broadside to target - perpendicular facing for maximum turret coverage
static func _execute_large_ship_broadside(ship_data: Dictionary, target: Dictionary, delta: float) -> Dictionary:
    var updated = ship_data.duplicate(true)
    var my_pos = ship_data.get("position", Vector2.ZERO)
    var target_pos = target.get("position", Vector2.ZERO)

    var to_target = (target_pos - my_pos).normalized()
    var target_angle = to_target.angle()

    # Broadside = perpendicular to target (rotate 90 degrees from facing target)
    var broadside_angle = target_angle + PI/2

    updated.orders.desired_rotation = broadside_angle
    updated.orders.throttle = 0.2  # Slow, controlled movement
    # Use lateral thrust to slide toward/away from target while maintaining broadside
    var distance = my_pos.distance_to(target_pos)
    if distance < 1500.0:
        updated.orders.lateral_thrust = -0.5  # Strafe away
    else:
        updated.orders.lateral_thrust = 0.3  # Strafe closer

    return updated

## Kite target - back away while facing them
static func _execute_large_ship_kite(ship_data: Dictionary, target: Dictionary, delta: float) -> Dictionary:
    var updated = ship_data.duplicate(true)
    var my_pos = ship_data.get("position", Vector2.ZERO)
    var target_pos = target.get("position", Vector2.ZERO)

    var to_target = (target_pos - my_pos).normalized()
    var target_angle = to_target.angle()

    # Face target (for forward turrets) but thrust backward
    updated.orders.desired_rotation = target_angle
    updated.orders.throttle = -0.4  # Reverse thrust
    updated.orders.lateral_thrust = 0.0

    return updated

## Orbit target at current range
static func _execute_large_ship_orbit(ship_data: Dictionary, target: Dictionary, delta: float) -> Dictionary:
    var updated = ship_data.duplicate(true)
    var my_pos = ship_data.get("position", Vector2.ZERO)
    var target_pos = target.get("position", Vector2.ZERO)

    var to_target = (target_pos - my_pos).normalized()
    var target_angle = to_target.angle()

    # Face target but strafe perpendicular to orbit
    updated.orders.desired_rotation = target_angle
    updated.orders.throttle = 0.1
    updated.orders.lateral_thrust = 0.6  # Strong lateral thrust to orbit

    return updated
```

#### Step 2.4: Wire Up Large Ship AI in CrewAISystem

**File:** `scripts/space/systems/crew_ai_system.gd`

**Location:** Replace `make_corvette_pilot_decision()` and `make_capital_pilot_decision()` (around lines 289-323)

**Change FROM:**
```gdscript
static func make_corvette_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
    # ... existing simple if/else code ...
```

**Change TO:**
```gdscript
static func make_corvette_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
    var ship_data = context.get("ship_data", {})
    var all_ships = context.get("all_ships", [])
    return LargeShipPilotAI.make_decision(crew_data, ship_data, all_ships, game_time)

static func make_capital_pilot_decision(crew_data: Dictionary, context: Dictionary, game_time: float) -> Dictionary:
    var ship_data = context.get("ship_data", {})
    var all_ships = context.get("all_ships", [])
    return LargeShipPilotAI.make_decision(crew_data, ship_data, all_ships, game_time)
```

**ALSO** update `analyze_tactical_context()` to include `ship_data` and `all_ships` in the returned context dictionary.

---

### Phase 3: Fix Captain/Squadron Leader TODOs

These functions always return false/null. They need actual implementations.

#### Step 3.1: Fix `_is_ship_critically_damaged()`

**File:** `scripts/space/systems/crew_ai_system.gd`

**Location:** Line 734

**Change FROM:**
```gdscript
static func _is_ship_critically_damaged(crew_data: Dictionary) -> bool:
    # TODO: Check actual ship damage from awareness
    return false
```

**Change TO:**
```gdscript
static func _is_ship_critically_damaged(crew_data: Dictionary) -> bool:
    # Check known entities for our own ship's status
    var ship_id = crew_data.get("assigned_to", "")
    var known = crew_data.get("awareness", {}).get("known_entities", [])

    # Also check if we have direct damage info
    var threats = crew_data.get("awareness", {}).get("threats", [])
    var threat_count = threats.size()
    var stress = crew_data.get("stats", {}).get("stress", 0.0)

    # Consider critically damaged if:
    # - High stress (indicates taking damage)
    # - Many threats (overwhelmed)
    if stress > 0.7 and threat_count >= 3:
        return true

    return false
```

#### Step 3.2: Fix `_find_damaged_subordinate()`

**File:** `scripts/space/systems/crew_ai_system.gd`

**Location:** Line 1026

**Change FROM:**
```gdscript
static func _find_damaged_subordinate(crew_data: Dictionary) -> Variant:
    # TODO: Check subordinate ship status
    return null
```

**Change TO:**
```gdscript
static func _find_damaged_subordinate(crew_data: Dictionary) -> Variant:
    var subordinates = crew_data.get("command_chain", {}).get("subordinates", [])
    var known_entities = crew_data.get("awareness", {}).get("known_entities", [])

    for sub_id in subordinates:
        for entity in known_entities:
            if entity.get("id", "") == sub_id:
                var status = entity.get("status", "")
                if status in ["damaged", "critical", "disabled"]:
                    return entity

    return null
```

#### Step 3.3: Fix `_is_squadron_scattered()`

**File:** `scripts/space/systems/crew_ai_system.gd`

**Location:** Line 1031

**Change FROM:**
```gdscript
static func _is_squadron_scattered(crew_data: Dictionary) -> bool:
    # TODO: Check subordinate positions
    return false
```

**Change TO:**
```gdscript
const SCATTERED_THRESHOLD = 2000.0  # Units

static func _is_squadron_scattered(crew_data: Dictionary) -> bool:
    var subordinates = crew_data.get("command_chain", {}).get("subordinates", [])
    if subordinates.size() < 2:
        return false

    var known_entities = crew_data.get("awareness", {}).get("known_entities", [])
    var positions = []

    for sub_id in subordinates:
        for entity in known_entities:
            if entity.get("id", "") == sub_id:
                positions.append(entity.get("position", Vector2.ZERO))
                break

    if positions.size() < 2:
        return false

    # Check if any pair is too far apart
    for i in range(positions.size()):
        for j in range(i + 1, positions.size()):
            if positions[i].distance_to(positions[j]) > SCATTERED_THRESHOLD:
                return true

    return false
```

---

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `scripts/space/ai/fighter_pilot_ai.gd` | MODIFY | Add heavy fighter rear arc awareness |
| `scripts/space/ai/large_ship_pilot_ai.gd` | NEW | Shared AI for corvettes and capitals |
| `scripts/space/systems/tactical_knowledge_system.gd` | MODIFY | Add large ship knowledge patterns |
| `scripts/space/systems/movement_system.gd` | MODIFY | Add large ship maneuvers |
| `scripts/space/systems/crew_ai_system.gd` | MODIFY | Wire up new AI, fix TODOs |
| `tests/test_heavy_fighter_gunner.gd` | NEW | Test rear turret functionality |
| `tests/test_large_ship_pilot_ai.gd` | NEW | Test large ship AI |

---

## Implementation Order

1. **Phase 1: Heavy Fighter Gunner** (Critical bug fix)
   - Modify `fighter_pilot_ai.gd` to detect enemies behind
   - Add test to verify fix

2. **Phase 2: Large Ship Pilot AI** (Most visible improvement)
   - Create `large_ship_pilot_ai.gd`
   - Add knowledge patterns
   - Add maneuvers to movement system
   - Wire up in crew_ai_system

3. **Phase 3: Captain/Squadron Leader TODOs** (Enables better coordination)
   - Fix `_is_ship_critically_damaged()`
   - Fix `_find_damaged_subordinate()`
   - Fix `_is_squadron_scattered()`

---

## Success Criteria

After implementation:

1. **Heavy Fighter rear turret fires** at enemies behind the ship
2. **Corvettes kite fighters** by backing away while keeping turrets on target
3. **Corvettes and Capitals present broadside** to maximize turret coverage
4. **Captains withdraw** when the ship is critically damaged
5. **Squadron Leaders call for support** when subordinates are damaged
6. **Squadron Leaders reform** when the squadron is scattered

---

## DRY Checklist

- [ ] `LargeShipPilotAI` handles BOTH corvettes AND capitals (no duplicate code)
- [ ] Maneuver execution reuses existing patterns from `movement_system.gd`
- [ ] Knowledge query pattern matches `FighterPilotAI._query_fighter_knowledge()`
- [ ] Situation string generation matches `FighterPilotAI._generate_fighter_situation()` pattern
- [ ] Test helpers are shared between test files
