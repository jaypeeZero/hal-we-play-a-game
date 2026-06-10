# 03 — Test suite consolidation

**Goal**: one shared factory file; tests assert behavior, not data
values; zero GUT warnings. Roughly 400–600 duplicated lines deletable.

## Steps

1. **Create `tests/test_factories.gd`** (plain `class_name` helper, not
   a test script) with the ship/crew/projectile factories currently
   copy-pasted across 26 of 39 test files: fighter/corvette/capital
   ship dicts, pilot/gunner/captain crew dicts, test targets and
   projectiles. Port files over incrementally — each file converted is
   a small, safe diff.
2. **Merge `test_large_ship_ai.gd` into `test_large_ship_pilot_ai.gd`**.
   They overlap ~40% and both exercise `LargeShipPilotAI.make_decision`
   FSM transitions. Keep the superset of assertions.
3. **Convert data-coupled assertions to behavior assertions** (violates
   CLAUDE.md testing standards). Worst offender:
   `test_obstacle_system.gd` (9 asserts on exact radius/health values).
   Also a few in `test_torpedo_system.gd`, `test_ship_data.gd` (crew
   counts → role presence), `test_damage_resolver.gd:16`.
4. **Fix the 11 GUT "Float/Int comparison" warnings** — use float
   literals in the asserts (`assert_eq(x, 50.0)` not `50`).

## Done when

- No test file defines its own ship/crew factory.
- `./test.sh` shows 0 warnings.
- One large-ship AI test file.
