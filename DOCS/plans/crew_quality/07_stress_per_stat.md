# Per-Stat Stress / Fatigue Decay

## Goal

Composure becomes a real saving throw. Rookies fall apart under
pressure; veterans hold. The 2nd / 3rd consecutive engagement reduces
effective stats so "fresh elite fleet" ≠ "elite fleet that's been
fighting all day."

This is the smallest phase but the most important for variety —
without it, the game tilts toward "elite always wins, watching is
boring." With it, low-composure aces have panic moments and
high-composure rookies have clutch moments.

## Edits

### 7.1 Replace `calculate_effective_skill`

Today (`crew_ai_system.gd:66`):

```gdscript
static func calculate_effective_skill(crew: Dictionary) -> float:
    return crew.stats.skill - (crew.stats.stress * 0.3) - (crew.stats.fatigue * 0.2)
```

After Phase 03 the legacy `stats.skill` is gone. The new API:

```gdscript
static func effective(crew: Dictionary, stat_name: String) -> float:
    var base = crew.skills.get(stat_name, 0.0)
    var composure = crew.skills.get("composure", 0.0)
    var stress = crew.stats.stress
    var fatigue = crew.stats.fatigue
    var effective_stress = max(0.0, stress - composure * COMPOSURE_STRESS_LIFT)
    var stress_decay = STAT_STRESS_DECAY.get(stat_name, 0.0)
    var fatigue_decay = STAT_FATIGUE_DECAY.get(stat_name, 0.0)
    return base * (1.0 - effective_stress * stress_decay - fatigue * fatigue_decay)
```

Constants in `wing_constants.gd`:

```gdscript
const COMPOSURE_STRESS_LIFT = 0.4

const STAT_STRESS_DECAY = {
    "aim":        0.45,   # twitch task
    "piloting":   0.45,   # twitch task
    "awareness":  0.25,   # medium decay
    "tactics":    0.25,   # medium decay
    "composure":  0.0,    # composure IS the stress system
    "aggression": 0.0,    # personality, not stress-affected
}

const STAT_FATIGUE_DECAY = {
    "aim":        0.30,
    "piloting":   0.30,
    "awareness":  0.20,
    "tactics":    0.20,
    "composure":  0.10,   # tired crews crack easier
    "aggression": 0.0,
}
```

### 7.2 Stress source events

Stress sources already exist via `tactical_memory_system.gd`. Surface
as +stress deltas on the appropriate crew:

- `ship_damaged` → +`STRESS_FROM_DAMAGE * (damage / max_hull)`.
- `ally_killed` (ally crew destroyed) → `+STRESS_FROM_ALLY_LOSS`.
- `near_miss` → `+STRESS_FROM_NEAR_MISS` (smaller).
- `withdraw_ordered` → `+STRESS_FROM_RETREAT` for the retreating
  ship's crew.

Stress decays at `STRESS_DECAY_RATE` per second when no new sources
fire — recovery for the surviving crew between waves.

### 7.3 Caller updates

Every read of the old single-arg `calculate_effective_skill` becomes a
call to `effective(crew, stat)` with the appropriate stat for the
decision. No back-compat shim, no alias — old name is deleted in the
same change.

Major call sites (file:line refs from baseline audit):

- `crew_scheduler_system.gd:tick_with_awareness` — picks stat by role.
- `fighter_pilot_ai.gd` — `piloting` for maneuvering, `aim` for shot
  decisions.
- `gunner_ai.gd` (post the `crew_ai_rework/` Phase 0 split) — `aim` for accuracy, `awareness`
  for target acquisition.
- `captain_ai.gd` — `tactics` for command, `awareness` for sensing.
- All crew-modifier writes in `crew_integration_system.gd` —
  `apply_pilot_skill_modifiers` etc. read from the appropriate stat
  via `effective`.

### 7.4 Debug overlay updates

Phase 02 deferred showing degraded values; this phase activates them.
The overlay table cells now display:

```
piloting
  18→14
```

When `effective(crew, "piloting") < base * 0.95`, render as `base→eff`
with the `eff` half color-graded by the delta (red if ≥ 30% drop,
yellow if 10–30%, no color shift if < 10%). When stress is < 0.1,
render as a single number.

The stress bar line below the table activates when any crew has
stress > 0.1.

## Constants (wing_constants.gd)

New (in addition to the dictionaries above):
- `STRESS_FROM_DAMAGE = 0.4` — multiplied by damage fraction.
- `STRESS_FROM_ALLY_LOSS = 0.15`.
- `STRESS_FROM_NEAR_MISS = 0.05`.
- `STRESS_FROM_RETREAT = 0.1`.
- `STRESS_DECAY_RATE = 0.04` per second under safe conditions.

## Tests

New:
- `test_stress_per_stat_decay.gd` — stress reduces `aim` and
  `piloting` more than `tactics` and `awareness`; doesn't affect
  `composure` or `aggression`.
- `test_composure_dampens_stress.gd` — high-composure crew at the
  same stress level retains more effective stat.
- `test_stress_recovery.gd` — stress decays under safe conditions.
- `test_battle_of_attrition_drift.gd` — over a sustained engagement,
  low-composure crew effective `aim` drops ≥ 50%; high-composure
  crew drops < 15%.

Deleted:
- Any tests asserting the old uniform stress penalty.
- The old `calculate_effective_skill` tests.

## Acceptance

1. `./test.sh` is green.
2. In a battle of attrition (3 waves vs same fleet), low-composure
   rookie crews' effective `aim` drops ≥ 50% from baseline by mid-
   fight; elite high-composure crews drop < 15%.
3. Upset scenarios reproduce: low-composure ace under fire performs
   measurably worse than high-composure mid-tier crew at the same
   stat baseline + 2.0 stress.
4. Debug overlay shows `base→eff` notation for degraded stats.

## Definition of done

- [ ] `effective(crew, stat)` API replaces `calculate_effective_skill`
      everywhere.
- [ ] Stress sources wired at damage, ally-loss, near-miss, retreat.
- [ ] Debug overlay displays degraded values.
- [ ] All tests pass.
- [ ] Zero compile warnings.
- [ ] Playtest: a sustained engagement visibly degrades low-composure
      crews more than high-composure crews.
- [ ] Acceptance ticked.
