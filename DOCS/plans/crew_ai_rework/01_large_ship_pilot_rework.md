# Phase 1 — Large-ship pilot rework (corvette + capital)

## Goal

Bring `scripts/space/ai/large_ship_pilot_ai.gd` (currently 162 lines, single
"situation → knowledge → maneuver" function) up to the quality bar set by
`scripts/space/ai/fighter_pilot_ai.gd` (1,668 lines).

The player should *feel* the same kind of step-change in capital and corvette
combat that PR #51 produced for fighters.

## Patterns to import from PR #51

Each of these is a section in `fighter_pilot_ai.gd`. Replicate the **shape**,
not the literals — large ships need different numbers and different states.

1. **Engagement-cycle FSM** — replaces "always emit one maneuver"
2. **Stat-driven personality** — uses the canonical six-stat schema
3. **Self-preservation** — replaces "fight until destroyed"
4. **Area leash (AI-level hard override)** — pulls a wandering capital home
5. **Tactical break (interrupt)** — fires regardless of FSM phase
6. **Knowledge integration** — already present, keep but route through the FSM
7. **Heavy GUT coverage** of the FSM transitions and survival triggers

This plan sits on top of the canonical six-stat schema in
[`../crew_quality/01_overview.md`](../crew_quality/01_overview.md). All
stat reads use `effective(crew, stat_name)` — the per-stat API defined
in [`../crew_quality/07_stress_per_stat.md`](../crew_quality/07_stress_per_stat.md).

## FSM design

A capital/corvette doesn't dogfight; it manages range and arcs. Phases:

| Phase | Enter when | Exit when |
|---|---|---|
| `closing` | target is beyond effective broadside range | inside `BROADSIDE_OPTIMAL_RANGE` |
| `broadside` | inside optimal range with arc on target | target leaves arc, or is too close |
| `kiting` | (vs fighters) anything inside `SAFE_RANGE_VS_FIGHTERS` | target outside safe range |
| `fighting_withdrawal` | survival mode = "withdraw" | hull stabilizes or out of contact |
| `repositioning` | broadside lost AND not in fighter swarm | new arc achievable |

`crew_data.combat_state.engagement_phase` carries the FSM tag plus
`phase_started_at` / `phase_target_id`, mirroring how fighter pilots store it.

### Constants (top of file)

```
const BROADSIDE_FAR_RANGE = 4500.0
const BROADSIDE_OPTIMAL_RANGE = 2200.0
const BROADSIDE_TOO_CLOSE = 900.0
const BROADSIDE_ARC_DOT = 0.30          # cos(~72°) — perpendicular ±18°
const SAFE_RANGE_VS_FIGHTERS = 2000.0   # already in current file; reuse
const PHASE_MIN_DURATION = 1.0          # commit to a phase briefly
const PHASE_REPOSITION_TIMEOUT = 6.0
const AGGRESSION_TIMING_SPREAD = 1.6
```

No magic numbers anywhere else.

## Stat reads

Per the canonical role-read table, large-ship pilots are primarily
`piloting` + `tactics`, with `awareness`, `composure`, `aggression` as
secondary. Concretely:

- `effective(crew, "piloting")` — selects between maneuver tiers from
  the knowledge query (tighter arcs, less bleed-off at the top end).
- `effective(crew, "tactics")` — gates posture-style choices (when to
  reposition vs hold, when to commit a withdrawal vector).
- `effective(crew, "awareness")` — feeds threat range / prioritization;
  perception of incoming threats arrives via mailbox latency from
  `../crew_quality/03_awareness_detection.md`.
- `aggression` modulates:
  - `BROADSIDE_OPTIMAL_RANGE` ± up to 20% (aggressive captains close in)
  - `SAFE_RANGE_VS_FIGHTERS` ± up to 20%
  - phase durations via `AGGRESSION_TIMING_SPREAD`
  - survival-trigger thresholds (see below)

Personality is expressed through the canonical `aggression` and
`composure` stats — see `../crew_quality/01_overview.md`. No
role-specific axis.

## Self-preservation (capital scale)

Large ships don't "bail" the way fighters do, but they do withdraw:

- **Critical-section trigger** — if any of the three principal armor sections
  (front/sides/rear in `ship_data.armor_sections`) drops below
  `SECTION_CRITICAL_RATIO = 0.20`, force `fighting_withdrawal`.
- **Engine-damaged trigger** — if `internals.engine` is damaged, drop max
  speed handling; current `MovementSystem` already enforces this, but the
  pilot picks a withdrawal vector instead of holding broadside.
- **Outgunned trigger** — local enemy capital count > friendly capital count
  within `OUTGUNNED_RANGE = 4000.0` AND aggression < 0.7 → `fighting_withdrawal`.

Reasoning copied from PR #51's commentary block style: brief, named, with the
*why* in a comment.

## Area leash

Capitals patrol assigned zones too (PR #51 introduced N/S/E/W areas). Today
their physics-layer leash works because they always thrust. Verify this — if
a capital can sit zero-throttle holding broadside while drifting outside its
zone, add the same hard override `fighter_pilot_ai.gd` uses (see "AREA LEASH
(AI-LEVEL HARD OVERRIDE)" section, line 1357).

## Tactical break

If a `threat_appeared` event arrives flagged with a heavy weapon class
(torpedo, capital cannon) or a capital-class threat has nose on us inside
`TACTICAL_BREAK_RANGE_LARGE = 1500.0`, interrupt the current phase and
emit a hard-turn maneuver to put thickest armor toward the threat. A
`ship_damaged` event also triggers reassessment. Mirrors fighter
`TACTICAL_BREAK_RANGE` (line 65).

## Maneuver subtypes the AI emits

These are decision strings consumed by `MovementSystem`. New entries needed:

- `large_ship_close_to_broadside`
- `large_ship_hold_broadside`     (already exists as `large_ship_broadside`; rename or alias)
- `large_ship_kite`               (exists)
- `large_ship_reposition_arc`
- `large_ship_fighting_withdrawal`
- `large_ship_present_thickest_armor`

`MovementSystem` gets one new `match` arm per subtype. No fallbacks left in.

## Tests (new: `tests/test_large_ship_pilot_ai.gd`)

Behavior-only, per CLAUDE.md testing standards. Each FSM transition gets a test:

- closing → broadside when range crosses `BROADSIDE_OPTIMAL_RANGE`
- broadside → repositioning when arc lost
- broadside → kiting when fighter enters `SAFE_RANGE_VS_FIGHTERS`
- any phase → fighting_withdrawal when section drops below critical
- aggression high vs low → different optimal-range commitment (range, not literal)
- two pilots, same `piloting`, different aggression → different phase
  choice in the same situation
- tactical break interrupts mid-broadside

Plus update `tests/test_large_ship_ai.gd` so its existing assertions still hold.

## Acceptance checklist

- [ ] `large_ship_pilot_ai.gd` is the only place capital/corvette pilot
  decisions are produced
- [ ] No magic numbers (every literal is a `const NAME`)
- [ ] No `# legacy`, no `# fallback`, no commented-out blocks
- [ ] Compiles with zero warnings
- [ ] All new tests in `tests/test_large_ship_pilot_ai.gd` pass
- [ ] `./test.sh` green
- [ ] In a 2-capital vs 2-capital playtest: ships visibly close, present
  broadside, reposition when arc lost, withdraw when wrecked
- [ ] In a 1-corvette vs 4-fighter playtest: corvette kites, doesn't grind
  into fighter swarm

## Out of scope

- Changing fighter behavior
- Capital-vs-capital squadron coordination (Phase 3 squadron leader)
- New weapon types or damage rules
- Visual / UI changes beyond what new maneuver subtypes naturally produce
