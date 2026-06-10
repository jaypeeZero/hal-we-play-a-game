# Plans

Current problem-driven plans, in priority order. Each is small enough to
ship as one or two PRs. Coding standards live in `CLAUDE.md` and apply to
every plan; the bar for "done" is: tests green, zero warnings, behavior
visible in a playtest or in the battle log.

| # | File | Problem it solves |
|---|---|---|
| 1 | [01_observability.md](01_observability.md) | Logging is fragmented across three systems; battle events aren't all persisted; many `print()` calls bypass loggers |
| 2 | [02_ai_regressions.md](02_ai_regressions.md) | Two failing tests: elite friendly-collision break, capital leash return |
| 3 | [03_test_consolidation.md](03_test_consolidation.md) | 26 of 39 test files re-implement the same ship/crew factories (~500 duplicated lines) |
| 4 | [04_simplification.md](04_simplification.md) | Magic numbers in collision/movement/weapon math; god functions over 100 lines |
| 5 | [05_crew_role_fsms.md](05_crew_role_fsms.md) | Gunner/captain/squadron/commander AIs lack the FSM quality bar the fighter pilot has |
| 6 | [06_crew_knowledge_and_training.md](06_crew_knowledge_and_training.md) | Long-term: Football-Manager-style crew management built on `data/knowledge/` |

Plans 1–4 are cleanup/correctness and can run in any order. Plan 5 is
feature work. Plan 6 is the long-term direction and should inform design
decisions in all the others.
