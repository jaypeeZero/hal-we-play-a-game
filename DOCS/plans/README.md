# Crew & ship-AI quality rework — plan index

These plans extend the quality bar set by PR #51 (fighter pilot rework) to the
rest of the ship and crew AI. Run in order; each phase is one PR.

| # | File | What it does | Depends on |
|---|---|---|---|
| 0 | [00_crew_ai_split.md](00_crew_ai_split.md) | Split `crew_ai_system.gd` monolith into per-role modules. Pure refactor, no behavior change. | — |
| 1 | [01_large_ship_pilot_rework.md](01_large_ship_pilot_rework.md) | Bring corvette + capital pilots to PR #51 quality (FSM, personality, self-preservation, leash). | 0 |
| 2 | [02_gunner_rework.md](02_gunner_rework.md) | Fire-discipline FSM, temperament axis, section-targeting commitment. | 0 |
| 3 | [03_captain_rework.md](03_captain_rework.md) | Command-tempo FSM, decisiveness axis, posture commitment, damage-driven shifts. | 0 |
| 4 | [04_squadron_and_commander_rework.md](04_squadron_and_commander_rework.md) | Strategic FSM at squadron and fleet scope. | 0, 3 |

## Coding standards (every phase must satisfy)

Lifted from `CLAUDE.md` and PR #51 itself:

- **Pure functional**: every AI module is `extends RefCounted` + `class_name`
  with `static` methods only. No instance/global state.
- **Data-driven**: state lives on the crew dict, mutated only via
  `crew_data.duplicate(true)` returns from decision functions.
- **Named constants only**: no magic numbers. Every literal at the top
  of the file with a one-line comment explaining what it represents.
- **No fallback / legacy code**: do not leave old behavior next to new.
  Delete what's replaced.
- **Zero compile warnings**: warnings are unresolved errors.
- **Behavior-only tests**: assert capabilities, not specific data values
  (per CLAUDE.md "Testing Standards").
- **Personality**: every role gets at least one axis beyond `skill`,
  matching how PR #51 used `aggression` to give wings personality.
- **Self-preservation analogue**: every role has a "don't fight to the
  death pointlessly" trigger appropriate to its scale.
- **Tactical-break interrupts**: explicit, named, bypassing the FSM.
- **Section-comment headers**: `# === SECTION ===` blocks like
  `fighter_pilot_ai.gd`, with a paragraph of *why* the section exists.

## Per-phase definition of done

Each phase ships only when:

1. The relevant `tests/test_<role>_ai.gd` passes
2. `./test.sh` is green
3. A playtest of the relevant scenario shows the change is visible to
   a player without telemetry
4. The acceptance checklist in that phase's plan is fully ticked
