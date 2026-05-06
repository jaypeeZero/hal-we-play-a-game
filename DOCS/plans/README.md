# Plans

Multi-phase design plans for the game, grouped by sub-project. Each
sub-project has its own folder, README, and ordered phase files.

| Sub-project | Status | Description |
|---|---|---|
| [`crew_ai_rework/`](crew_ai_rework/) | Phase 0 done; 1–4 partial | Bring every crew role (large-ship pilot, gunner, captain, squadron leader, fleet commander) up to the PR #51 quality bar set by the fighter pilot rework — FSMs, personality axes, self-preservation, hard-override interrupts. |
| [`crew_quality/`](crew_quality/) | Not started | Make crew stats **mechanically dramatic**. Wire up the disconnected modifiers, consolidate stats to a six-stat schema (`aim`, `piloting`, `awareness`, `tactics`, `composure`, `aggression`), add reaction-latency / detection-latency / squadron plays, plus an always-on debug overlay. |

`crew_quality/` runs after (or alongside) `crew_ai_rework/`. Where they
overlap (gunner, captain, squadron-leader behavior), `crew_quality/`
extends what `crew_ai_rework/` lays down — it does not duplicate or
replace that work.

## Coding standards (every plan must satisfy)

Lifted from `CLAUDE.md` and PR #51 itself:

- **Pure functional**: every AI module is `extends RefCounted` + `class_name`
  with `static` methods only. No instance/global state.
- **Data-driven**: state lives on the crew dict, mutated only via
  `crew_data.duplicate(true)` returns from decision functions.
- **Named constants only**: no magic numbers. Every literal at the top
  of the file with a one-line comment explaining what it represents.
- **No fallback / legacy code**: do not leave old behavior next to new.
  Delete what's replaced. No aliases, no back-compat shims.
- **Zero compile warnings**: warnings are unresolved errors.
- **Behavior-only tests**: assert capabilities, not specific data values
  (per CLAUDE.md "Testing Standards").
- **Personality**: every role gets at least one axis beyond raw skill,
  matching how PR #51 used `aggression` to give wings personality.
- **Self-preservation analogue**: every role has a "don't fight to the
  death pointlessly" trigger appropriate to its scale.
- **Tactical-break interrupts**: explicit, named, bypassing the FSM.
- **Section-comment headers**: `# === SECTION ===` blocks like
  `fighter_pilot_ai.gd`, with a paragraph of *why* the section exists.

## Per-phase definition of done

Each phase ships only when:

1. The relevant `tests/test_<role>_ai.gd` passes.
2. `./test.sh` is green.
3. A playtest of the relevant scenario shows the change is visible to
   a player without telemetry.
4. The acceptance checklist in that phase's plan is fully ticked.
