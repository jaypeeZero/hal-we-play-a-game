# Plans

Current problem-driven plans, in priority order. Each is small enough to
ship as one or two PRs. Coding standards live in `CLAUDE.md` and apply to
every plan; the bar for "done" is: tests green, zero warnings, behavior
visible in a playtest or in the battle log.

Completed plans are deleted, not archived — git history has them.

| # | File | Problem it solves |
|---|---|---|
| 5 | [05_crew_role_fsms.md](05_crew_role_fsms.md) | Gunner/captain/squadron/commander AIs lack the FSM quality bar the fighter pilot has |
| 6 | [06_crew_knowledge_and_training.md](06_crew_knowledge_and_training.md) | Long-term: Football-Manager-style crew management built on `data/knowledge/` (increment 1 shipped) |
| 7 | [07_energy_bleed_flight_model.md](07_energy_bleed_flight_model.md) | Turning bleeds speed so flight skill becomes energy management (increments 1-2 shipped: duel harness + turn bleed; increment 3 shelved unless AI bleeds itself) |

Plan 5 is feature work, sized as one PR per role. Plan 6 is the
long-term direction and should inform design decisions everywhere.
