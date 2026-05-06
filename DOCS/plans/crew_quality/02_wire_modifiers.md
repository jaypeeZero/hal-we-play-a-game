# Wire Modifiers (visible from frame one)

## Goal

Make all-3 crew vs all-18 crew **visibly different in battle** with the
smallest possible code change. Three things ship together:

1. WeaponSystem accuracy actually consumes `crew_modifiers`.
2. MovementSystem turn / accel / lateral / dampening actually consume
   `crew_modifiers`.
3. SUBSYSTEM targeting actually targets subsystems.

Plus the always-on debug overlay so the changes are visible to the
player without telemetry. See [`01_overview.md`](01_overview.md) for
vision context.

This phase deliberately **does not** rename stats yet. The legacy field
names (`stats.skill`, etc.) survive to Phase 03 where the rename pass
happens. This keeps the diff tight.

## Pre-work audit (factual baseline)

- `weapon_system.gd:395` `calculate_final_accuracy(base, ship_data)`
  returns `base` unchanged.
- `weapon_system.gd:392` `calculate_final_damage` is a stub.
- `weapon_system.gd:357–358` `TargetingStyle.SUBSYSTEM` falls through
  to `perfect_lead` — same as PREDICTIVE.
- `movement_system.gd:2264` reads `ship_data.stats.turn_rate` directly.
- `movement_system.gd:2320, 2332, 2341, 2363` read raw acceleration.
- `crew_integration_system.gd:285` `get_crew_modified_movement_stats`
  computes the right factors but is **never called in production**.
- `crew_integration_system.gd:322` `get_crew_modified_weapon_stats`
  same — never called in production.
- `crew_integration_system.gd:127, 160, 180` `apply_*_skill_modifiers`
  write `crew_modifiers.pilot_skill / gunner_skill / etc.` raw values
  rather than usable factors.

## Edits

### 2.1 WeaponSystem accuracy (un-stub)

Replace `weapon_system.gd:395`:

```gdscript
static func calculate_final_accuracy(base_accuracy: float, ship_data: Dictionary) -> float:
    var modifiers = ship_data.get("crew_modifiers", {})
    if modifiers.is_empty():
        return base_accuracy
    var aim_factor = modifiers.get("aim_accuracy_factor", 1.0)
    var captain_factor = modifiers.get("captain_coordination", 1.0)
    return clamp(base_accuracy * aim_factor * captain_factor, 0.0, 1.0)
```

`apply_gunner_skill_modifiers` (`crew_integration_system.gd:160`) now
writes `crew_modifiers.aim_accuracy_factor` directly, derived using the
existing `lerp(GUNNER_ACCURACY_MIN, GUNNER_ACCURACY_MAX, gunner_skill)`
math from `wing_constants.gd`. For fighters with fixed forward weapons,
the pilot's aim feeds the same factor through the same write — caller
picks crew based on weapon type (turret vs fixed).

**Delete entirely:**
- `get_crew_modified_weapon_stats` and its tests.
- `calculate_final_damage` stub. Damage scaling competes with weapon-
  tier scaling and muddies the design — no replacement.
- The raw `crew_modifiers.gunner_skill` and `crew_modifiers.pilot_skill`
  fields once factors land. No alias.

### 2.2 SUBSYSTEM targeting actually targets subsystems

In `weapon_system.gd:calculate_lead_position`, when style ==
SUBSYSTEM:

1. Read `target.subsystems` (already populated by `damage_resolver.gd`
   — confirm in implementation).
2. Pick the subsystem with highest `tactical_value × (1 - health_pct)`
   — i.e. weight valuable + already-damaged components.
3. Compute world position: `target.position + offset.rotated(target.rotation)`.
4. Lead-predict that point instead of the ship center.
5. Set `projectile.intended_subsystem = subsystem_id` on the spawned
   projectile.

In `damage_resolver.pick_subsystem_to_damage`, bias toward
`projectile.intended_subsystem` on hit (e.g. 70% chance of routing to
the intended subsystem if it's still functional, 30% normal damage
distribution).

This is what makes elite gunners surgically disable engines/turrets
instead of just landing more body shots.

### 2.3 MovementSystem reads crew_modifiers

Three small edits in `movement_system.gd`:

- **Line 2264** turn rate:
  ```gdscript
  var effective_turn_rate: float = _read_modified_turn_rate(ship_data) \
      * (1.0 - turn_falloff * speed_ratio)
  ```
- **Line 2320** acceleration:
  ```gdscript
  var effective_acceleration = _read_modified_acceleration(ship_data) \
      * throttle * alignment_factor
  ```
- **Lines 2332, 2341, 2363** lateral / reverse / brake — same pattern.

Three private helpers at top of `movement_system.gd`:

```gdscript
static func _read_modified_turn_rate(ship_data: Dictionary) -> float:
    var base = ship_data.stats.turn_rate
    var factor = ship_data.get("crew_modifiers", {}).get("pilot_turn_factor", 1.0)
    return base * factor

static func _read_modified_acceleration(ship_data: Dictionary) -> float:
    var base = ship_data.stats.acceleration
    var factor = ship_data.get("crew_modifiers", {}).get("pilot_accel_factor", 1.0)
    return base * factor

static func _read_modified_lateral(ship_data: Dictionary) -> float:
    return ship_data.get("crew_modifiers", {}).get("pilot_lateral_factor", 1.0)
```

(Dampening factor wires the same way at the dampening site.)

**No call into CrewIntegrationSystem from MovementSystem.** Factors are
pre-baked onto `ship_data.crew_modifiers` by the integration step;
MovementSystem just consumes. Keeps pure-function discipline.

`apply_pilot_skill_modifiers` (`crew_integration_system.gd:127`) is
rewritten to write the four factors directly:

```gdscript
modifiers.pilot_turn_factor    = lerp(PILOT_TURN_RATE_MIN,    PILOT_TURN_RATE_MAX,    skill)
modifiers.pilot_accel_factor   = lerp(PILOT_ACCEL_MIN,        PILOT_ACCEL_MAX,        skill)
modifiers.pilot_lateral_factor = lerp(PILOT_LATERAL_MIN,      PILOT_LATERAL_MAX,      skill)
modifiers.pilot_damp_factor    = lerp(PILOT_DAMPENING_MIN,    PILOT_DAMPENING_MAX,    skill)
```

**Delete entirely:** `get_crew_modified_movement_stats` and all its
tests. It was unreachable mathematics.

### 2.4 Always-on debug overlay (floating crew table)

Add to `scripts/space/debug_overlay.gd`. **No toggle. Always on.**

Per ship, render a screen-space `Control` anchored to the ship's
world-space hull bottom-right with a pixel offset so it sits outside
the sprite. Clamp to viewport edges.

Layout:

```
       | aim | piloting | awareness | tactics | composure | aggression
pilot  |  7  |    18    |    16     |   12    |    14     |    11
gunner | 17  |     8    |    13     |    9    |    15     |    10
capt'n | 12  |    11    |    19     |   18    |    17     |     8
```

- Stats shown 0–20: `int(round(stat * 20))`.
- Color: red 0–6, yellow 7–13, green 14–20.
- A stat the role doesn't read (per role-read table in
  [`01_overview.md`](01_overview.md)) is rendered in dimmed gray.
- Effective value shown as `18→14` when stress/fatigue degrades it,
  graded by delta. (Phase 07 makes this active; for Phase 02 effective
  ≈ base.)
- Below the table: stress bars per crew when any crew.stress > 0.1.
  Otherwise omitted.

Implementation:

- One `Control` per ship parented to the overlay `CanvasLayer` —
  **not** to the ship node (rotation and culling fight you).
- Each frame, compute screen position via
  `camera.unproject_position(ship.global_position + hull_bbox.bottom_right)`,
  add pixel offset, clamp to viewport rect.
- For now, a `RichTextLabel` with BBCode color spans is fine; switch
  to drawn cells if it doesn't read clearly.

This is what makes Phase 02 visibly satisfying without the player
reading logs.

## Constants (wing_constants.gd)

Already present and re-used:
- `PILOT_TURN_RATE_MIN/MAX`, `PILOT_ACCEL_MIN/MAX`,
  `PILOT_LATERAL_MIN/MAX`, `PILOT_DAMPENING_MIN/MAX`
- `GUNNER_ACCURACY_MIN/MAX`

New:
- `SUBSYSTEM_INTENDED_HIT_BIAS = 0.7` — chance an intended-subsystem
  hit routes to that subsystem.
- `OVERLAY_HULL_OFFSET_PX = Vector2(8, 8)` — pixel gap between hull
  corner and overlay table.
- `OVERLAY_STAT_COLORS` — three-color gradient table.

No magic numbers in code.

## Tests (`tests/`)

New:
- `test_weapon_system_skill_accuracy.gd` — parameterized over aim 0.0 /
  0.5 / 1.0; asserts hit-rate strictly ordered.
- `test_movement_skill_modulation.gd` — asserts effective turn rate,
  acceleration, lateral thrust, dampening all strictly ordered by
  pilot skill in long-run sim.
- `test_subsystem_targeted_aim.gd` — asserts SUBSYSTEM-style fire on a
  damaged target preferentially routes damage to the chosen subsystem.

Updated/deleted:
- Delete `test_crew_ai_system.gd::test_pilot_modifiers_have_dramatic_range`
  (the function it tests is being deleted).
- Delete `test_crew_ai_system.gd::test_gunner_modifiers_have_dramatic_range`
  (same).
- Update any test that read raw `crew_modifiers.gunner_skill` /
  `pilot_skill` to read the factor fields.

All assertions are behavior-only per CLAUDE.md ("Testing Standards").

## Acceptance

1. `./test.sh` is green.
2. Elite-pilot fighter wins ≥ 75% of identical-ship 1v1 vs rookie pilot
   over 50 trials. (S2.)
3. Elite gunner achieves ≥ 3× hit rate vs rookie at 4 km against a
   maneuvering target. (S3, partial.)
4. SUBSYSTEM-aim shots produce subsystem-disable events at ≥ 5× the
   rate of LEADING shots in equivalent scenarios.
5. In-game playtest: a human watching can identify which ship has the
   better crew without looking at logs — debug overlay or behavior
   alone makes it obvious.

## Definition of done

Per `DOCS/plans/README.md`:
- [ ] All new tests pass; deleted tests are gone.
- [ ] `./test.sh` is green.
- [ ] Zero new compile warnings.
- [ ] Vestigial functions deleted (`get_crew_modified_weapon_stats`,
      `get_crew_modified_movement_stats`, `calculate_final_damage`).
- [ ] Playtest: visible difference confirmed.
- [ ] Acceptance checklist ticked.
