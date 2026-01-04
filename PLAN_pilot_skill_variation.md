# Plan: Dramatic Pilot Skill Variation

## Problem Statement

Currently, pilot skill has minimal impact on flight behavior:
- Turn rate: 0.8x to 1.2x (only 50% difference)
- Acceleration: 0.9x to 1.1x (only 22% difference)
- No skill-based approach patterns
- No evasion during attacks
- Everyone flies basically the same way

**Goal**: A 0-skill pilot should fly straight at targets. A max-skill pilot should "dance circles" around them.

---

## Design Philosophy

### Low Skill (0.0-0.3) - "Rookie"
- **Flies straight at target** - no lateral movement, no angles
- **No prediction** - aims at where target IS, not where it will be
- **Slow reactions** - commits to maneuvers too long, can't adjust
- **Panics under pressure** - when in danger, picks one direction and sticks to it
- **Tunnel vision** - faces target, ignores positioning advantage

### High Skill (0.8-1.0) - "Ace"
- **Approaches from angles** - never flies straight in
- **Constant repositioning** - jinking, weaving, lateral thrust
- **Exploits angles** - actively tries to get behind target
- **Smooth transitions** - can change maneuvers fluidly
- **Uses all thrusters** - main, lateral, braking in combination

---

## Implementation Plan

### 1. Add Skill Constants (`wing_constants.gd`)

Add new constants for skill-based behavior thresholds:

```gdscript
# PILOT SKILL - Movement capability modifiers
const PILOT_TURN_RATE_MIN = 0.5      # 0-skill: 50% turn rate
const PILOT_TURN_RATE_MAX = 1.3      # 1.0-skill: 130% turn rate
const PILOT_ACCEL_MIN = 0.6          # 0-skill: 60% acceleration
const PILOT_ACCEL_MAX = 1.2          # 1.0-skill: 120% acceleration
const PILOT_LATERAL_MIN = 0.2        # 0-skill: 20% lateral capability
const PILOT_LATERAL_MAX = 1.0        # 1.0-skill: 100% lateral capability

# PILOT SKILL - Behavior thresholds
const PILOT_APPROACH_ANGLE_SKILL = 0.4    # Skill to approach from angles
const PILOT_JINKING_SKILL = 0.5           # Skill to jink during approach
const PILOT_PURSUIT_CURVE_SKILL = 0.6     # Skill to use pursuit curves (lead/lag)
const PILOT_DEFENSIVE_MANEUVER_SKILL = 0.7 # Skill for complex defensive maneuvers
```

### 2. Expand Crew Integration Modifiers (`crew_integration_system.gd`)

Update `get_crew_modified_movement_stats()` to use wider skill ranges:

```gdscript
static func get_crew_modified_movement_stats(ship_data: Dictionary) -> Dictionary:
    var stats = ship_data.stats.duplicate()

    if not ship_data.has("crew_modifiers"):
        return stats

    var modifiers = ship_data.crew_modifiers

    if modifiers.has("pilot_skill"):
        var skill = modifiers.pilot_skill
        # MUCH wider skill impact
        stats.turn_rate *= lerp(WingConstants.PILOT_TURN_RATE_MIN,
                                WingConstants.PILOT_TURN_RATE_MAX, skill)
        stats.acceleration *= lerp(WingConstants.PILOT_ACCEL_MIN,
                                   WingConstants.PILOT_ACCEL_MAX, skill)
        # NEW: Lateral thrust capability
        stats.lateral_acceleration *= lerp(WingConstants.PILOT_LATERAL_MIN,
                                           WingConstants.PILOT_LATERAL_MAX, skill)

    return stats
```

### 3. Create Skill-Based Approach Selection (`fighter_pilot_ai.gd`)

Add function to select approach style based on skill:

```gdscript
static func _select_approach_style(skill: float, distance: float, position_advantage: String) -> String:
    # LOW SKILL (< 0.4): Always direct approach
    if skill < WingConstants.PILOT_APPROACH_ANGLE_SKILL:
        return "direct"

    # MEDIUM SKILL (0.4-0.6): Basic angle awareness
    if skill < WingConstants.PILOT_PURSUIT_CURVE_SKILL:
        if position_advantage == "behind":
            return "direct"  # Have advantage, go straight in
        else:
            return "angled"  # Try basic angle approach

    # HIGH SKILL (0.6+): Full tactical approach
    if position_advantage == "disadvantaged":
        return "defensive_spiral"  # Break contact, reposition
    elif position_advantage == "neutral":
        return "pursuit_curve"  # Lead or lag pursuit
    else:
        return "attack_run"  # Press advantage
```

### 4. Add Skill-Based Jinking to Movement (`movement_system.gd`)

Create new function for skill-aware approach:

```gdscript
static func calculate_skill_aware_approach(ship_data: Dictionary, target: Dictionary,
                                           skill: float, approach_style: String) -> Dictionary:
    var to_target = target.position - ship_data.position
    var distance = to_target.length()

    match approach_style:
        "direct":
            # Fly straight at target - no lateral, no angle
            return calculate_direct_approach(ship_data, target)

        "angled":
            # Approach from 30-45 degree offset
            return calculate_angled_approach(ship_data, target, skill)

        "pursuit_curve":
            # Lead or lag pursuit based on situation
            return calculate_pursuit_curve(ship_data, target, skill)

        "defensive_spiral":
            # Break away, build speed, come back from better angle
            return calculate_defensive_spiral(ship_data, target, skill)

        "attack_run":
            # Press behind advantage with jinking
            return calculate_attack_run(ship_data, target, skill)

    return calculate_direct_approach(ship_data, target)
```

### 5. Create New Maneuver Functions (`movement_system.gd`)

#### Direct Approach (Low Skill)
```gdscript
static func calculate_direct_approach(ship_data: Dictionary, target: Dictionary) -> Dictionary:
    var to_target = target.position - ship_data.position
    var desired_heading = direction_to_heading(to_target)

    # No lateral thrust, no prediction, just fly at them
    return {
        "desired_heading": desired_heading,
        "throttle": 1.0,  # Full speed ahead
        "thrust_active": true,
        "is_braking": false,
        "lateral_thrust": 0.0,  # NO LATERAL - key difference
        "engagement_range": 400.0,
        "current_distance": to_target.length()
    }
```

#### Angled Approach (Medium Skill)
```gdscript
static func calculate_angled_approach(ship_data: Dictionary, target: Dictionary, skill: float) -> Dictionary:
    var to_target = target.position - ship_data.position
    var distance = to_target.length()

    # Offset angle based on skill (30-45 degrees)
    var offset_angle = lerp(0.5, 0.8, skill - 0.4)  # Radians
    var approach_side = 1 if randf() > 0.5 else -1  # Pick a side

    var offset_direction = to_target.rotated(offset_angle * approach_side).normalized()
    var desired_heading = direction_to_heading(offset_direction)

    # Some lateral movement for repositioning
    var lateral_thrust = lerp(0.0, 0.5, skill) * approach_side

    return {
        "desired_heading": desired_heading,
        "throttle": calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical"),
        "thrust_active": true,
        "is_braking": false,
        "lateral_thrust": lateral_thrust,
        "engagement_range": 400.0,
        "current_distance": distance
    }
```

#### Pursuit Curve (High Skill)
```gdscript
static func calculate_pursuit_curve(ship_data: Dictionary, target: Dictionary, skill: float) -> Dictionary:
    var to_target = target.position - ship_data.position
    var distance = to_target.length()
    var target_velocity = target.get("velocity", Vector2.ZERO)

    # Lead pursuit: aim ahead of target
    var prediction_time = lerp(0.3, 1.0, skill)
    var predicted_pos = target.position + target_velocity * prediction_time
    var to_predicted = predicted_pos - ship_data.position

    var desired_heading = direction_to_heading(to_predicted)

    # Jinking during approach - high skill pilots constantly adjust
    var jink_amplitude = lerp(0.0, 0.6, skill)
    var jink_phase = fmod(Time.get_ticks_msec() / 400.0, 2.0)
    var lateral_thrust = sin(jink_phase * PI) * jink_amplitude

    return {
        "desired_heading": desired_heading,
        "throttle": calculate_intuitive_throttle(ship_data, distance, "pursuit_tactical"),
        "thrust_active": true,
        "is_braking": false,
        "lateral_thrust": lateral_thrust,
        "engagement_range": 400.0,
        "current_distance": distance
    }
```

### 6. Add Skill to Decision Output (`fighter_pilot_ai.gd`)

Ensure skill and approach style are passed through to movement:

```gdscript
var decision = {
    "type": "maneuver",
    "subtype": maneuver_type,
    # ... existing fields ...
    "skill_factor": skill,
    "approach_style": _select_approach_style(skill, distance, position),
    "can_jink": skill >= WingConstants.PILOT_JINKING_SKILL,
    "can_use_angles": skill >= WingConstants.PILOT_APPROACH_ANGLE_SKILL,
}
```

### 7. Modify Fighter Control Dispatch (`movement_system.gd`)

Update `calculate_fighter_pilot_control()` to use skill-based approach:

```gdscript
static func calculate_fighter_pilot_control(ship_data: Dictionary, target: Dictionary,
                                            nearby_ships: Array, obstacles: Array) -> Dictionary:
    var maneuver = ship_data.get("orders", {}).get("maneuver_subtype", "")
    var skill = ship_data.get("orders", {}).get("skill_factor", 0.5)
    var approach_style = ship_data.get("orders", {}).get("approach_style", "direct")

    # For approach/pursuit maneuvers, use skill-aware version
    if maneuver in ["fight_pursue_full_speed", "fight_pursue_tactical", "fight_get_behind"]:
        return calculate_skill_aware_approach(ship_data, target, skill, approach_style)

    # ... existing maneuver dispatch ...
```

---

## Summary of Changes

| File | Changes |
|------|---------|
| `wing_constants.gd` | Add pilot skill constants for turn rate, accel, lateral, thresholds |
| `crew_integration_system.gd` | Expand skill modifiers to 50%-130% range, add lateral modifier |
| `fighter_pilot_ai.gd` | Add `_select_approach_style()`, pass approach_style in decisions |
| `movement_system.gd` | Add `calculate_skill_aware_approach()` and 5 new maneuver functions |

## Expected Behavior After Changes

**0.0 Skill Pilot:**
- Turn rate: 50% of base
- Acceleration: 60% of base
- Lateral thrust: 20% of base
- Flies straight at target
- No jinking, no angle attacks
- Easily predictable, easily circled

**1.0 Skill Pilot:**
- Turn rate: 130% of base
- Acceleration: 120% of base
- Lateral thrust: 100% of base
- Uses pursuit curves and angled approaches
- Constant jinking during approach
- Can break contact and reposition when disadvantaged
- Very hard to hit, very effective at getting behind enemies

---

## Testing Strategy

1. Create test scenario with 0.0 skill fighter vs 1.0 skill fighter
2. Observe: high-skill pilot should consistently get behind low-skill pilot
3. Time how long it takes high-skill to destroy low-skill (should be fast)
4. Time reverse matchup (low-skill should struggle to ever get a shot)
5. Verify no regressions in existing wing formation behavior
