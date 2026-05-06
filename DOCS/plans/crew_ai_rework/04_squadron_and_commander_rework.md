# Phase 4 — Squadron leader + fleet commander rework

## Goal

Bring `squadron_leader_ai.gd` and `commander_ai.gd` (extracted in Phase 0) up
to the PR #51 quality bar. These two roles are bundled because they share
the same shape — fan-out commanders that issue orders down a chain — and
because their effects only become visible once captains (Phase 3) commit
to orders correctly.

Player should notice:
- Squadrons that hold formation, mass against one target, then disengage
  together rather than dribbling in one ship at a time.
- Fleets that commit a reserve at the right moment, or pivot focus when
  one flank collapses.
- Distinct "personalities" at the strategic level: a cautious commander
  vs an aggressive one produces visibly different battles with the same
  ship roster.

## Patterns to import from PR #51

1. **Doctrine FSM** at each level (squadron / fleet)
2. **Order tempo** — a commander cannot issue a new strategic shift more
   often than `STRATEGIC_TEMPO`. Mirrors captain commit duration.
3. **Loss-driven posture shifts** — analogue to self-preservation, scaled
   to "how is the squadron / fleet doing?"
4. **Tactical-break analogue** at strategic scope.
5. **Heavy GUT coverage** of all transitions.

This plan sits on top of the canonical six-stat schema in
[`../crew_quality/01_overview.md`](../crew_quality/01_overview.md). All
stat reads use `effective(crew, stat_name)` — the per-stat API defined
in [`../crew_quality/07_stress_per_stat.md`](../crew_quality/07_stress_per_stat.md).

## Shared infrastructure (do this first inside Phase 4)

Squadron and fleet decisions share helpers:
- "score the strategic situation" (force ratio, casualty rate, objective
  proximity)
- "is X scattered" (already exists in current monolith for squadrons)
- "is X concentrated against the right target"

Put genuinely shared helpers in `scripts/space/ai/strategic_assessment.gd`
(new). Keep it small — only move helpers that are demonstrably used by
both `squadron_leader_ai.gd` and `commander_ai.gd`. Don't preemptively
generalize.

---

## 4a. Squadron leader

### FSM

`crew_data.combat_state.squadron_phase`:

| Phase | Enter when | Exit when |
|---|---|---|
| `forming_up` | start, or after dispersal | formation tight enough |
| `coordinated_attack` | target prioritised, formation tight | target dies / scatter |
| `mutual_support` | a subordinate critically damaged | subordinate stable / lost |
| `screening_withdrawal` | fleet order to retreat | safe |
| `reform` | post-event regrouping | new posture |

### Constants

```
const FORMATION_TIGHT_RADIUS = 800.0
const FORMATION_SCATTERED_RADIUS = 1800.0
const COORDINATED_ATTACK_COMMIT = 6.0
const TARGET_REASSIGN_COOLDOWN = 3.0
const SUBORDINATE_CRITICAL_HULL = 0.35
const SQUADRON_LOSS_FORCE_REGROUP = 0.34   # lost ≥ 1/3 → reform
```

### Stat reads

Per the canonical role-read table, squadron leaders are primarily
`tactics` + `awareness`, with `composure` and `aggression` as secondary:

- `effective(crew, "tactics")` — squadron coordination tier, target
  assignment quality. The `TARGET_REASSIGN_COOLDOWN` floor still
  applies regardless of tactics — high-tactics leads pick the right
  target the first time.
- `effective(crew, "awareness")` — feeds threat sensing across the
  squadron's frontage.
- `effective(crew, "composure")` — holds the FSM steady under cascading
  loss events.
- `aggression` — willingness to push into a numerical disadvantage;
  modulates the loss thresholds at which `mutual_support` overrides
  `coordinated_attack`.

Personality is expressed through the canonical `aggression` and
`composure` stats — see `../crew_quality/01_overview.md`. No
role-specific axis.

### Loss-driven shifts

- Lost ≥ `SQUADRON_LOSS_FORCE_REGROUP` of starting strength → forced
  `reform` (or `screening_withdrawal` if fleet has signaled retreat).
- A subordinate hull below `SUBORDINATE_CRITICAL_HULL` → `mutual_support`
  unless aggression > 0.8.

### Tactical break

- Fleet commander issued a new doctrine
- Squadron primary target destroyed
- Subordinate ship destroyed (force reform consideration)

### Tests (`tests/test_squadron_leader_ai.gd`)

- target reassignment respects `TARGET_REASSIGN_COOLDOWN`
- scattered formation forces `forming_up`
- losing 1/3 of squadron forces regroup
- mutual support triggers on a damaged subordinate
- two leads, same `tactics`, different `aggression` → different
  willingness to press attack against equal numbers

---

## 4b. Fleet commander

### FSM

`crew_data.combat_state.strategy_phase`:

| Phase | Enter when | Exit when |
|---|---|---|
| `assessing_battle` | start, or after major event | doctrine chosen |
| `concentrate_force` | one flank/objective is decisive | success / failure |
| `commit_reserves` | reserve worth committing | committed |
| `shift_focus` | weight needs to move to a different flank | shifted |
| `hold_line` | parity, nothing better available | situation changes |
| `strategic_withdrawal` | fleet-level loss ratio breached | extracted / destroyed |

### Constants

```
const STRATEGIC_TEMPO = 8.0                # minimum seconds between strategic shifts
const FLEET_LOSS_WITHDRAW = 0.45           # lose ≥ 45% → withdrawal doctrine
const FLEET_LOSS_DEFENSIVE = 0.25
const RESERVE_COMMIT_DECISIVE_RATIO = 0.6  # commit reserves when local advantage ≥ 60%
const FLANK_COLLAPSE_RATIO = 0.6           # one flank lost 60%+ of its strength
const STRATEGIC_REASSESS_COOLDOWN = 1.5
```

### Stat reads

Per the canonical role-read table, fleet commanders are primarily
`tactics` + `awareness`, with `composure` as secondary:

- `effective(crew, "tactics")` — quality of doctrine selection, force
  scoring, flank-collapse recognition. Strategic-level command tier.
- `effective(crew, "awareness")` — feeds the picture of where the
  fight is (which flank is collapsing, which objective is contested).
- `effective(crew, "composure")` — degrades less under the cascading
  stress of fleet-scale losses.
- `aggression` — governs `RESERVE_COMMIT_DECISIVE_RATIO` and how
  readily `concentrate_force` is chosen vs `hold_line`.

Personality is expressed through the canonical `aggression` and
`composure` stats — see `../crew_quality/01_overview.md`. No
role-specific axis.

### Loss-driven shifts

- Cumulative fleet loss ≥ `FLEET_LOSS_WITHDRAW` → forced
  `strategic_withdrawal`.
- Fleet loss ≥ `FLEET_LOSS_DEFENSIVE` and aggression < 0.6 →
  `hold_line` becomes default.
- A flank's strength below `FLANK_COLLAPSE_RATIO` of its starting → trigger
  `shift_focus` consideration.

### Tactical break

- Squadron destroyed (lose a whole subordinate squadron)
- Player-controlled ship event (if relevant)
- Objective state change (if mission objectives exist; otherwise skip)

### Tests (`tests/test_commander_ai.gd`)

- strategic shift respects `STRATEGIC_TEMPO`
- 25% loss with low aggression → `hold_line`
- 45% loss → `strategic_withdrawal` regardless of aggression
- flank collapse triggers `shift_focus`
- two commanders, same `tactics`, different `aggression` → measurably
  different doctrine choices on the same situation

---

## Acceptance checklist

- [ ] `squadron_leader_ai.gd` and `commander_ai.gd` own their respective
  decisions; no role logic remains in `crew_ai_system.gd`
- [ ] `strategic_assessment.gd` contains only genuinely shared helpers
  (no premature abstraction)
- [ ] All literals are named constants
- [ ] No `# legacy`, no commented-out blocks, no warnings
- [ ] All new tests pass; `test_crew_ai_system.gd` still green
- [ ] In playtest: a fleet under heavy loss visibly withdraws as a unit
- [ ] In playtest: a squadron that loses 1/3 strength reforms instead of
  charging in piecemeal
- [ ] In playtest: two commanders with the same `tactics` but different
  `aggression` produce noticeably different battles on the same map

## Out of scope

- New strategic objective types (e.g. capture-the-flag-style)
- Communications model (jamming, comms loss) — would touch
  `InformationSystem`; defer
- AI-vs-AI matchmaking ladder for testing — useful but separate work
