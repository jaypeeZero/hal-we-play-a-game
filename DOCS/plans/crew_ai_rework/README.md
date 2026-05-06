# Crew AI rework — plan index

Bring every crew role up to the quality bar set by PR #51 (fighter pilot
rework). Each role gets a finite-state machine for its core engagement
cycle, a personality axis beyond raw skill, a self-preservation trigger,
and explicit tactical-break interrupts.

Run in order; each phase is one PR. Standards are in
[`../README.md`](../README.md).

| # | File | What it does | Status | Depends on |
|---|---|---|---|---|
| 0 | [00_crew_ai_split.md](00_crew_ai_split.md) | Split `crew_ai_system.gd` monolith into per-role modules. Pure refactor. | **Complete** (commit `4b23844`) | — |
| 1 | [01_large_ship_pilot_rework.md](01_large_ship_pilot_rework.md) | Corvette + capital pilots: FSM, self-preservation, leash. | **Partial** — FSM/constants present in `large_ship_pilot_ai.gd`; tests exist; canonical-stat reads (`piloting`/`tactics`/`awareness`) and `threat_appeared` / `ship_damaged` tactical-breaks not yet wired. | 0 |
| 2 | [02_gunner_rework.md](02_gunner_rework.md) | Fire-discipline FSM, section-targeting commitment. | **Partial** — Phase 0 stub at `gunner_ai.gd`; FSM phases (`fire_phase`, `BURST_BASE_DURATION`, `TRACKING_SOLUTION_DOT`, `point_defense`, `ceasefire`) not yet present; `tests/test_gunner_ai.gd` missing. | 0 |
| 3 | [03_captain_rework.md](03_captain_rework.md) | Command-tempo FSM, posture commitment, damage-driven shifts. | **Partial** — Phase 0 stub at `captain_ai.gd`; FSM markers (`command_phase`, `POSTURE_COMMIT`) absent; `tests/test_captain_ai.gd` missing. | 0 |
| 4 | [04_squadron_and_commander_rework.md](04_squadron_and_commander_rework.md) | Strategic FSM at squadron and fleet scope. | **Partial** — Phase 0 stubs at `squadron_leader_ai.gd` and `commander_ai.gd`; strategic FSM markers and `strategic_assessment.gd` absent; tests missing. | 0, 3 |

## Phase status verified

A spot-check audit (2026-05-05) read each plan, then grepped the
codebase for the FSM phase names and key constants named in the plan.
Status above reflects that audit.

For phases 1–4, the structural file split from Phase 0 is in place but
the per-role behavioral content (FSM, interrupts, tests) is the actual
remaining work. Plans 01–04 were also rewritten the same day to align
with the canonical six-stat schema in `../crew_quality/01_overview.md`
— role-specific personality axes (`temperament`, `decisiveness`) were
deleted; personality is expressed through the canonical `aggression`
and `composure` stats.
