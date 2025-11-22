# Plan: Skill-Based AI Behavior Differentiation

## Current Status: Core System Implemented ✓

The skill-gated decision tree in `fighter_pilot_ai.gd:101-126` is working:
- **Rookie (<0.3):** Only `pursue_full_speed`, ignores collision warnings
- **Average (0.3-0.6):** Adds `tight_pursuit` when behind target
- **Skilled (>=0.6):** Full tactical repertoire + collision awareness

Next: Secondary Considerations, then Multiple Skills expansion.

---

## Stage 1: Secondary Considerations

### 1.1 Target Fixation for Rookies

**Problem:** All pilots currently re-evaluate targets every decision cycle. Rookies should "tunnel vision" on their initial target even when disadvantaged.

**Location:** `fighter_pilot_ai.gd` - `_find_best_target()` and decision flow

**Implementation:**
```gdscript
# In crew_data, add combat state tracking
"combat_state": {
  "locked_target_id": "",
  "lock_start_time": 0.0
}

# In _find_best_target():
func _find_best_target(crew_data: Dictionary, all_ships: Array) -> String:
  if skill < 0.3:
    # Rookie: stick with current target if valid and alive
    var locked_target = crew_data.get("combat_state", {}).get("locked_target_id", "")
    if locked_target != "" and _is_ship_valid(locked_target, all_ships):
      return locked_target  # Tunnel vision - don't re-evaluate

  # Normal target selection for average+ pilots
  var threats = crew_data.get("awareness", {}).get("threats", [])
  var opportunities = crew_data.get("awareness", {}).get("opportunities", [])

  if not threats.is_empty():
    return threats[0]
  elif not opportunities.is_empty():
    return opportunities[0]
  return ""
```

**Observable behavior:** Rookie engages Fighter A, Fighter B gets behind rookie → rookie keeps chasing A instead of defending. Skilled pilot would switch to address the threat.

---

### 1.2 Panic Behavior When Disadvantaged

**Problem:** Low-skill pilots make the same decisions when an enemy is behind them. They should make poor escape choices.

**Location:** `fighter_pilot_ai.gd` - `_make_fighter_vs_fighter_decision()`

**Implementation:**
```gdscript
# Add helper function
static func _am_i_in_front_of_target(my_ship: Dictionary, target_ship: Dictionary) -> bool:
  # Inverse of _am_i_behind_target
  # Returns true if target is behind ME (I'm in front of them)
  var my_pos = my_ship.get("position", Vector2.ZERO)
  var target_pos = target_ship.get("position", Vector2.ZERO)
  var my_rotation = my_ship.get("rotation", 0.0)

  var to_target = (target_pos - my_pos).normalized()
  var my_facing = Vector2(cos(my_rotation), sin(my_rotation))
  var angle_diff = rad_to_deg(my_facing.angle_to(to_target))

  # I'm in front if angle difference is ~180 degrees
  return abs(abs(angle_diff) - 180.0) < BEHIND_ANGLE_TOLERANCE

# In _make_fighter_vs_fighter_decision(), add check:
var enemy_behind_me = _am_i_in_front_of_target(ship_data, target_ship)

if enemy_behind_me:
  if skill < 0.3:
    # Panic: fly straight (worst choice - easy target)
    maneuver_type = "pursue_full_speed"
  elif skill < 0.6:
    # Basic evasion: hard turn (predictable but better)
    maneuver_type = "evasive_turn"
  else:
    # Skilled: break and scissors, unpredictable
    maneuver_type = "defensive_break"
```

**New maneuvers needed in `movement_system.gd`:**
- `evasive_turn`: Hard turn in one direction (predictable, 30°/frame)
- `defensive_break`: Sharp break with alternating direction changes (skilled evasion)

**Observable behavior:** Ace gets behind rookie → rookie flies predictably straight → easy kill. Ace gets behind another ace → defensive scissors ensue.

---

### 1.3 Prediction Quality (Target Lead)

**Problem:** `_calculate_behind_position()` uses fixed 0.5s prediction. Skilled pilots should predict further ahead.

**Location:** `fighter_pilot_ai.gd` - `_calculate_behind_position()`

**Implementation:**
```gdscript
static func _calculate_behind_position(target_ship: Dictionary, skill: float = 0.5) -> Vector2:
  var target_pos = target_ship.get("position", Vector2.ZERO)
  var target_rotation = target_ship.get("rotation", 0.0)
  var target_velocity = target_ship.get("velocity", Vector2.ZERO)

  # Prediction lookahead scales with skill
  # Rookie (0.0): 0.1s ahead
  # Average (0.5): 0.3s ahead
  # Skilled (1.0): 0.8s ahead
  var prediction_time = lerp(0.1, 0.8, skill)

  var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * CLOSE_RANGE
  var predicted_pos = target_pos + target_velocity * prediction_time

  return predicted_pos + behind_offset
```

**Update call sites:**
- In `_make_fighter_vs_fighter_decision()` line 86: `_calculate_behind_position(target_ship, skill)`

**Observable behavior:** Rookie flies where target WAS. Ace flies where target WILL BE.

---

## Stage 2: Multiple Skills (FM-Style)

Replace single `skill` stat with discrete skills that affect specific behaviors.

### 2.1 New Skill Structure

**Location:** `crew_data.gd` - `create_crew_member()` and stat initialization

**Implementation:**
```gdscript
# Old structure (keep for backward compatibility):
"stats": {
  "skill": 0.5,              # Overall competency (0.0-1.0)
  "reaction_time": 0.15,     # Seconds
  "awareness_range": 800.0,  # Pixels
  "stress": 0.0,
  "fatigue": 0.0,

  # NEW: Discrete skills (each 0.0-1.0)
  "skills": {
    "situational_awareness": 0.5,  # Detection, threat tracking
    "aggression": 0.5,             # Engagement distance, closing behavior
    "composure": 0.5,              # Performance under pressure
    "anticipation": 0.5,           # Target prediction accuracy
    "marksmanship": 0.5            # Weapon accuracy
  }
}

---

### 2.2 Skill Mappings

| Skill | What It Affects | Implementation Location |
|-------|-----------------|------------------------|
| `situational_awareness` | Number of threats tracked, detection range modifier | `information_system.gd`, `_find_best_target()` |
| `aggression` | Engagement distance thresholds, willingness to close | `fighter_pilot_ai.gd` - distance checks in decision |
| `composure` | Decision quality when disadvantaged (replaces panic skill check) | `fighter_pilot_ai.gd` - enemy_behind_me logic |
| `anticipation` | Target movement prediction accuracy (replaces prediction time scaling) | `_calculate_behind_position()` |
| `marksmanship` | Weapon accuracy modifier | `crew_integration_system.gd` (already exists) |

---

### 2.3 Situational Awareness Implementation

**Problem:** All pilots currently see all threats in range equally. Low awareness pilots should only track 1-2 threats.

**Location:** `information_system.gd` - `identify_threats()` and `identify_opportunities()`

**Implementation:**
```gdscript
# In identify_threats():
static func identify_threats(crew_data: Dictionary, visible_enemies: Array) -> Array:
  var awareness = crew_data.get("stats", {}).get("skills", {}).get("situational_awareness", 0.5)

  # Max threats tracked scales with awareness
  # 0.0 awareness = 1 threat
  # 0.5 awareness = 2-3 threats
  # 1.0 awareness = 4+ threats
  var max_threats = int(1 + awareness * 4)

  # Score and sort threats
  var scored_threats = []
  for enemy in visible_enemies:
    var threat_score = _calculate_threat_score(crew_data, enemy)
    scored_threats.append({"id": enemy.ship_id, "score": threat_score})

  scored_threats.sort_by(func(a, b): return a.score > b.score)

  # Return top N
  return scored_threats.slice(0, min(max_threats, scored_threats.size()))

# Detection range modifier:
var effective_range = base_awareness_range * (0.7 + awareness * 0.6)
# 0.0 awareness = 70% range
# 0.5 awareness = 100% range
# 1.0 awareness = 130% range
```

**Observable behavior:** Low awareness pilot fixates on one enemy while others flank unnoticed. High awareness pilot tracks multiple bogeys.

---

### 2.4 Aggression Implementation

**Problem:** All pilots use same distance thresholds. Aggressive pilots should close faster, cautious pilots hang back.

**Location:** `fighter_pilot_ai.gd` - distance constants in `_make_fighter_vs_fighter_decision()`

**Implementation:**
```gdscript
static func _make_fighter_vs_fighter_decision(crew_data: Dictionary, ship_data: Dictionary,
                                             target_ship: Dictionary, all_ships: Array,
                                             all_crew: Array, game_time: float) -> Dictionary:
  var skill = crew_data.get("stats", {}).get("skills", {}).get("anticipation", 0.5)
  var aggression = crew_data.get("stats", {}).get("skills", {}).get("aggression", 0.5)

  # Dynamic distance thresholds based on aggression
  # Aggressive (1.0): closer thresholds (close faster)
  # Cautious (0.0): farther thresholds (stay distant)
  var far_range = FAR_RANGE * (1.4 - aggression * 0.8)
  # aggression 0.0 = 140% FAR_RANGE (hangs back: 7000 units)
  # aggression 0.5 = 100% FAR_RANGE (normal: 5000 units)
  # aggression 1.0 = 60% FAR_RANGE (charges in: 3000 units)

  var close_range = CLOSE_RANGE * (1.2 - aggression * 0.4)
  # aggression 0.0 = 120% CLOSE_RANGE (780 units)
  # aggression 0.5 = 100% CLOSE_RANGE (650 units)
  # aggression 1.0 = 80% CLOSE_RANGE (520 units)

  var distance = my_pos.distance_to(target_pos)

  # ... rest of maneuver selection uses dynamic thresholds
  if distance > far_range:
    maneuver_type = "pursue_full_speed"
  # etc.
```

**Observable behavior:** Aggressive rookie charges in recklessly (easy to ambush). Cautious ace stays at optimal range (hard to catch).

---

### 2.5 Composure Implementation

**Problem:** Panic behavior should scale with composure, not overall skill. Stress should affect decision quality.

**Location:** `fighter_pilot_ai.gd` - defensive decisions

**Implementation:**
```gdscript
# In _make_fighter_vs_fighter_decision(), replace panic logic:
var enemy_behind_me = _am_i_in_front_of_target(ship_data, target_ship)

if enemy_behind_me:
  var composure = crew_data.get("stats", {}).get("skills", {}).get("composure", 0.5)
  var stress = crew_data.get("stats", {}).get("stress", 0.0)

  # Effective composure degrades under stress
  # At stress 0.5: composure is halved
  # At stress 1.0: composure is zero
  var effective_composure = composure * (1.0 - stress * 0.5)

  if effective_composure < 0.3:
    maneuver_type = "pursue_full_speed"  # Panic - fly straight
  elif effective_composure < 0.6:
    maneuver_type = "evasive_turn"       # Basic evasion
  else:
    maneuver_type = "defensive_break"    # Skilled evasion
```

**Stress interaction:** Even a composed pilot (1.0) panics under high stress (0.8). A low-composure pilot (0.2) panics easily even when fresh (0.0 stress).

**Observable behavior:** Fresh pilot: can handle pressure. Same pilot after taking damage: makes worse decisions. High-composure veteran: stays calm under fire.

---

### 2.6 Anticipation Implementation

**Problem:** Prediction quality should use anticipation skill with some error variance for low skill.

**Location:** `fighter_pilot_ai.gd` - `_calculate_behind_position()`

**Implementation:**
```gdscript
static func _calculate_behind_position(target_ship: Dictionary, anticipation: float = 0.5) -> Vector2:
  var target_pos = target_ship.get("position", Vector2.ZERO)
  var target_rotation = target_ship.get("rotation", 0.0)
  var target_velocity = target_ship.get("velocity", Vector2.ZERO)

  # Prediction lookahead scales with anticipation
  # 0.0 = 0.1s ahead, 0.5 = 0.3s, 1.0 = 0.8s
  var prediction_time = lerp(0.1, 0.8, anticipation)

  var behind_offset = Vector2(cos(target_rotation + PI), sin(target_rotation + PI)) * CLOSE_RANGE
  var predicted_pos = target_pos + target_velocity * prediction_time

  # Low anticipation adds prediction error (missing where target actually is)
  var error_magnitude = (1.0 - anticipation) * 100.0  # 0-100 units of error
  var error_angle = randf_range(0, TAU)
  var error_offset = Vector2(cos(error_angle), sin(error_angle)) * error_magnitude

  return predicted_pos + behind_offset + error_offset
```

**Update call sites:**
- In `_make_fighter_vs_fighter_decision()` line 86: `_calculate_behind_position(target_ship, anticipation)`

**Observable behavior:** Low anticipation pilot's intended position is far from target. High anticipation pilot intercepts perfectly.

---

### 2.7 Crew Generation with Multiple Skills

**Location:** `crew_data.gd` - `create_crew_member()`, `create_solo_fighter_crew()`, `create_fighter_squadron()`

**Implementation:**
```gdscript
static func create_crew_member(role: Role, skill_level: float) -> Dictionary:
  # Generate varied discrete skills around the base skill_level
  var skills = {}
  var skill_names = ["situational_awareness", "aggression", "composure", "anticipation", "marksmanship"]

  for skill_name in skill_names:
    # Each skill varies ±0.15 from base, clamped to 0-1
    var variance = randf_range(-0.15, 0.15)
    skills[skill_name] = clamp(skill_level + variance, 0.0, 1.0)

  # Create base crew member
  var crew = {
    "crew_id": generate_crew_id(),
    "role": role,
    "stats": {
      "skill": skill_level,  # Keep for backward compatibility
      "skills": skills,      # New discrete skills
      "reaction_time": _get_reaction_time_for_role(role),
      "awareness_range": _get_awareness_range_for_role(role),
      "stress": 0.0,
      "fatigue": 0.0
    },
    # ... other crew fields
  }

  return crew

# Optional: Named pilot presets for archetypes
static func create_pilot_archetype(archetype: String, skill_level: float) -> Dictionary:
  var base_crew = create_crew_member(Role.PILOT, skill_level)
  var skills = base_crew.stats.skills

  match archetype:
    "aggressive_ace":
      skills["aggression"] = 0.9
      skills["composure"] = 0.7
    "calculating_ace":
      skills["aggression"] = 0.4
      skills["anticipation"] = 0.95
      skills["situational_awareness"] = 0.9
    "survivor":
      skills["composure"] = 0.95
      skills["situational_awareness"] = 0.9
      skills["aggression"] = 0.3
    "hot_head":
      skills["aggression"] = 0.95
      skills["composure"] = 0.2
      skills["anticipation"] = 0.3

  return base_crew
```

---

## Implementation Order

1. **Secondary Considerations first** (simpler, validates approach):
   - 1.3 Prediction quality (smallest change, ~5 lines)
   - 1.1 Target fixation (~20 lines, one data field)
   - 1.2 Panic behavior + new maneuvers (~30 lines + movement system)

2. **Multiple Skills second** (requires more changes):
   - 2.1 New skill structure in crew_data (~20 lines)
   - 2.7 Crew generation with varied skills (~30 lines)
   - 2.4 Aggression (easiest to test: ~10 lines in fighter_pilot_ai.gd)
   - 2.3 Situational awareness (~25 lines in information_system.gd)
   - 2.5 Composure (replaces panic behavior skill check: ~15 lines)
   - 2.6 Anticipation (replaces prediction quality skill check: ~10 lines)

---

## Test Verification

After full implementation, a battle between varied pilots should show:

1. **Aggressive low-awareness pilot:** Charges in recklessly, gets flanked by enemies they didn't see
2. **Cautious high-anticipation pilot:** Stays at range, leads targets perfectly
3. **Low-composure pilot under stress:** Falls apart when enemy gets advantage, panics
4. **High-composure low-aggression pilot:** Hard to kill but rarely gets kills (survivor type)
5. **Rookie with target fixation:** Ignores new threats, dies to flanking maneuver

The combat should feel like pilots have **personalities and distinct playstyles**, not just skill levels.

---

## Files to Modify

**Stage 1 (Secondary Considerations):**
1. `scripts/space/ai/fighter_pilot_ai.gd` - Add fixation, panic, prediction
2. `scripts/space/systems/movement_system.gd` - Add `evasive_turn` and `defensive_break` maneuvers

**Stage 2 (Multiple Skills):**
3. `scripts/space/data/crew_data.gd` - New skill structure, archetype presets
4. `scripts/space/systems/information_system.gd` - Threat tracking limits
5. `scripts/space/systems/crew_integration_system.gd` - Apply skill modifiers (if needed)

All tests in `tests/test_crew_ai_system.gd` should continue to pass after each stage.
