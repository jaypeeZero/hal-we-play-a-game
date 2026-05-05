# Phase 2 — Gunner rework

## Goal

Bring `gunner_ai.gd` (extracted in Phase 0) up to the PR #51 quality bar.
Today gunners are essentially: `find best target → query knowledge →
fire | hold-fire`. They have no fire-discipline state, no section-targeting
plan, no temperament. Every gunner with the same skill behaves the same way.

A good gunner pass should make the player notice things like:
- "That gunner is *patient* — waiting for the bow to come around."
- "They're walking shots into the same armor section."
- "When the captain calls concentrate-fire, they actually concentrate."

## Patterns to import from PR #51

1. **Fire-discipline FSM** — the gunner equivalent of the engagement cycle
2. **Skill × temperament personality** — temperament is to gunners what
   aggression is to pilots
3. **Self-preservation analogue** — ammo conservation, overheat caution
4. **Hard-override interrupts** — point-defense priority when missile incoming
5. **Knowledge integration** — already partial; route through the FSM
6. **Heavy GUT coverage** of FSM transitions and personality differentiation

## FSM design

`crew_data.combat_state.fire_phase`:

| Phase | Enter when | Exit when |
|---|---|---|
| `acquiring` | no target, or just switched | target locked + lead solution stable |
| `tracking` | locked, waiting for arc/range | shot solution within tolerance |
| `firing_burst` | solution good, weapon ready | burst budget spent, or solution lost |
| `cooling` | post-burst recovery | timer or weapon ready, whichever per weapon |
| `point_defense` | incoming missile/torpedo within PD range | threat handled or lost |
| `ceasefire` | captain ordered hold-fire, or friendly-fire risk | order lifted |

`fire_phase`, `phase_started_at`, `current_target_section` are stored on
the crew dict. Mirrors how pilots store `engagement_phase`.

### Constants (top of `gunner_ai.gd`)

```
const TRACKING_SOLUTION_DOT = 0.985            # how close lead must align
const TRACKING_TIMEOUT = 2.0
const BURST_BASE_DURATION = 1.2
const BURST_TEMPERAMENT_SPREAD = 1.8
const COOLING_BASE_DURATION = 0.6
const PD_RANGE = 900.0
const PD_PRIORITY_OVERRIDE_DOT = 0.0           # PD ignores arc preference
const FRIENDLY_FIRE_CONE_DOT = 0.97
const SECTION_FOCUS_COMMIT_DURATION = 4.0
```

## Personality: skill × temperament

Add `temperament` (0.0 = patient, 1.0 = twitchy) to
`crew_data.stats.skills` for `Role.GUNNER` only. Affects:

- `BURST_BASE_DURATION × spread^(temperament-0.5)` — twitchy gunners
  fire shorter, more frequent bursts; patient gunners hold and dump.
- `TRACKING_SOLUTION_DOT` — patient gunners require a tighter solution
  before firing (shrinks toward 0.995); twitchy gunners loosen toward 0.97.
- `COOLING_BASE_DURATION` shortens with temperament.

Skill axes already on the crew dict that gunners should actually use:

- `marksmanship` — feeds the tier selector against
  `TacticalKnowledgeSystem.query_gunner_knowledge` (mirror how pilots
  use `skill` to pick a maneuver tier)
- `anticipation` — quality of lead-prediction in the solution
- `composure` — already used via `calculate_effective_skill`

## Section-targeting commitment

A skilled gunner doesn't repick a section every shot. Once a target's
section is selected, commit for `SECTION_FOCUS_COMMIT_DURATION` unless:
- the section is destroyed (then advance to next-most-exposed)
- the captain issues a new section order
- the target changes

Section choice via the existing `gunner_armor_section_targeting` knowledge
entry. The commit is new — a state field on the crew dict, not a
knowledge change.

## Hard-override interrupts

These bypass the FSM:

1. **Captain hold-fire** → `ceasefire` phase regardless of current state
2. **Incoming missile/torpedo within PD_RANGE** → `point_defense` phase,
   override target to the projectile (gunner needs read access to
   `ProjectileSystem` snapshot via context)
3. **Friendly in fire cone** (dot to friendly > `FRIENDLY_FIRE_CONE_DOT`)
   → forced `tracking`, no fire decision emitted

Mirrors fighter "tactical break" interrupt at line 61.

## "Self-preservation" analogue: ammo + heat

Today there's no ammo or heat economy in the codebase. Either:

- **(a)** Skip this for now and document it as a deferred scope item
  (cleaner; matches "no fallback for scenarios that can't happen").
- **(b)** Add ammo/heat as part of this phase, plumbed through `WeaponSystem`.

**Recommendation: (a).** Adding economy mid-phase risks balance churn that
would obscure whether the gunner-behavior changes are felt. Track the
deferred work as Phase 2.5 if/when the user wants it.

## Tests (`tests/test_gunner_ai.gd`)

- `acquiring → tracking` when lead solution within tolerance
- `tracking → firing_burst` when solution + weapon ready
- `firing_burst → cooling` when burst duration elapses
- `any → point_defense` when missile within PD range
- `any → ceasefire` when captain order received
- twitchy vs patient temperament at the same skill produces different
  burst lengths
- section commit holds for `SECTION_FOCUS_COMMIT_DURATION` even when
  another section becomes momentarily more exposed
- friendly-fire cone suppresses fire decision

Behavior-only assertions per CLAUDE.md.

## Acceptance checklist

- [ ] `gunner_ai.gd` owns all gunner decisions
- [ ] No magic numbers in `gunner_ai.gd`
- [ ] No `# legacy`, no commented-out code, no warnings
- [ ] `temperament` added to gunner stat generation in `crew_data.gd`
- [ ] All new tests pass; `test_crew_ai_system.gd` still green
- [ ] In playtest: distinguishable patient vs twitchy gunners
- [ ] In playtest: gunners stop firing when captain orders hold-fire
- [ ] In playtest: PD interrupt triggers visibly when a missile closes

## Out of scope

- Ammo / heat economy (defer to Phase 2.5 if wanted)
- New weapon types
- Captain order semantics (Phase 3)
- Squadron-level fire coordination (Phase 4)
