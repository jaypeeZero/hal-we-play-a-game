# Phase 3 — Captain rework

## Goal

Bring `captain_ai.gd` (extracted in Phase 0) up to the PR #51 quality bar.
Captains today emit one of a fixed set of high-level orders per decision
cycle. They have no command tempo, no posture commitment, and no real
personality — two captains with the same skill will behave identically.

A good captain pass should make the player notice:
- "That captain *commits* — once they call a flank, they ride it out."
- "This captain reads damage and pulls the ship back when sections fail."
- "Aggressive captains brawl; cautious ones standoff and trade fire."

Captain effects are **indirect** — they manifest through the pilot and
gunners they command — so success criteria are about consequent ship
behavior, not captain telemetry.

## Patterns to import from PR #51

1. **Command-tempo FSM** — replaces "one decision per tick"
2. **Skill × aggression × decisiveness personality**
3. **Posture commitment** — once issued, an order persists
4. **Damage-driven posture shifts** — analogue to self-preservation
5. **Tactical break / interrupts** for captain-level events
6. **GUT coverage** of every transition

## FSM design

`crew_data.combat_state.command_phase`:

| Phase | Enter when | Exit when |
|---|---|---|
| `assessing` | start of fight, or after major event | a posture chosen |
| `committed_engage` | posture = engage, target chosen | target dies / posture broken |
| `committed_flank` | posture = flank | flank achieved or aborted |
| `committed_concentrate_fire` | concentrate-fire issued | target dies / timeout |
| `defensive_posture` | hull or section damage triggers | conditions clear |
| `withdrawing` | critical damage or fleet-level retreat order | safe |
| `regrouping` | post-withdraw, allies nearby | new posture chosen |

Posture commitment ranges (`POSTURE_COMMIT_DURATION`) prevent the captain
from re-issuing different orders every tick — that's the current bug.
A new order must wait for either:
- the commit timer to elapse
- a *significant event* (section destroyed, target destroyed, fleet
  order received, ally critical, missile lock on own ship)

### Constants (top of `captain_ai.gd`)

```
const POSTURE_COMMIT_BASE = 4.0
const POSTURE_COMMIT_DECISIVENESS_SPREAD = 2.0  # decisive captains commit longer
const ASSESS_DURATION = 0.6
const REASSESS_ON_EVENT_COOLDOWN = 0.5
const SECTION_CRITICAL_RATIO = 0.20
const HULL_RETREAT_RATIO = 0.30
const HULL_DEFENSIVE_RATIO = 0.55
const ALLY_SUPPORT_RANGE = 2500.0
const TARGET_PRIORITY_SHIFT_THRESHOLD = 0.25  # require 25% better score to switch
```

The last constant is critical: today the captain re-scores targets every
tick and frequently switches. Require a meaningful improvement before
shifting fire.

## Personality

Three axes, all already in `crew_data.stats.skills`:

- `skill` — quality of target prioritisation, knowledge-tier selection
- `aggression` — push/pull on engagement range; affects which postures
  are available (`committed_engage` more readily; `defensive_posture`
  thresholds raised)
- `composure` — under stress, decision delay grows less

Add **decisiveness** to gunners-style: 0.0 = waffler (short commit,
frequent reassessment), 1.0 = stubborn (long commit, ignores small events).
Lives in `crew_data.stats.skills` for `Role.CAPTAIN` only.

Decisiveness scales `POSTURE_COMMIT_BASE` via
`POSTURE_COMMIT_DECISIVENESS_SPREAD`. Mirror the pilot's
`ENGAGE_AGGRESSION_TIMING_SPREAD` formula.

## Damage-driven posture shifts

Captain checks own ship every assessing/event cycle:

- any section ≤ `SECTION_CRITICAL_RATIO` → consider `defensive_posture`
  (rotate the wreck away from the threat); aggressive captains may
  override and stay engaged.
- hull average ≤ `HULL_RETREAT_RATIO` → force `withdrawing`, regardless
  of aggression.
- engine internal damaged → cannot enter `committed_flank`; falls back
  to `committed_engage` or `defensive_posture`.

This is the captain's analogue to fighter `_assess_survival_state`
(line 1252).

## Order semantics

Today `break_down_captain_order` fans out captain orders to subordinates.
Keep the function. Tighten three things:

1. **Order persistence**: an issued order carries a `commit_until`
   timestamp; subordinates do not get superseded until that elapses
   or a higher-priority interrupt fires.
2. **Section direction**: when posture is `committed_concentrate_fire`,
   include `target_section` so gunners in Phase 2 honor the section
   commit.
3. **Frame of reference**: orders include `posture_id` so subordinates
   can detect "is this still the same plan, or did the captain change
   their mind?" — useful for gunners' state retention across order
   refreshes.

## Tactical break / interrupts

Bypass commit timer when:
- own ship section just destroyed
- own ship under missile lock
- fleet commander issued a strategic order
- primary target destroyed
- subordinate ship destroyed within `ALLY_SUPPORT_RANGE`

These set `command_phase = assessing` immediately. Each interrupt is
a named const, not a literal.

## Tests (`tests/test_captain_ai.gd`)

- captain enters `committed_engage` and stays for at least
  `POSTURE_COMMIT_BASE × commit_factor(decisiveness)` despite minor
  changes
- target shift requires score delta ≥ `TARGET_PRIORITY_SHIFT_THRESHOLD`
- section destroyed → tactical break, immediate reassessment
- hull below `HULL_RETREAT_RATIO` → `withdrawing` regardless of aggression
- two captains, same skill, different decisiveness → different commit
  durations on the same scenario
- engine damaged disables `committed_flank` posture
- subordinate destroyed within range triggers reassessment

## Acceptance checklist

- [ ] `captain_ai.gd` owns all captain decisions
- [ ] All literals are named constants
- [ ] No fallback / legacy comments; no warnings
- [ ] `decisiveness` added to captain stat generation in `crew_data.gd`
- [ ] All `tests/test_captain_ai.gd` cases pass; `test_crew_ai_system.gd`
  still green
- [ ] In playtest: orders persist visibly (no twitching between flank
  and engage on every tick)
- [ ] In playtest: damaged ships visibly shift to defensive posture
- [ ] In playtest: two captains with the same skill but different
  decisiveness behave differently in the same fight

## Out of scope

- Squadron-leader and commander rework (Phase 4)
- New posture types beyond what `break_down_captain_order` supports today
- Re-tuning damage thresholds for ship balance
