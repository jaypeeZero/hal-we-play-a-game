# Phase 0 — Split `crew_ai_system.gd` into per-role modules

## Why this comes first

`scripts/space/systems/crew_ai_system.gd` is a 1,565-line monolith containing pilot,
gunner, captain, squadron-leader, and commander decision logic. Each subsequent
phase (large-ship pilots, gunners, captains, squadron/commander) will grow its
role into a system on the order of `fighter_pilot_ai.gd` (1,668 lines). Without
the split, the monolith will hit ~5,000+ lines and become unworkable.

PR #51 already established the target shape: `scripts/space/ai/fighter_pilot_ai.gd`
and `scripts/space/ai/large_ship_pilot_ai.gd` are pure-functional
`RefCounted`/`class_name` modules that own one role's decision-making end-to-end.
Match that shape.

## Scope

Pure structural refactor. **No behavior change.** No new constants, no new
features, no rewrites. Tests pass before and after, with the same assertions.

## Target layout

```
scripts/space/ai/
  fighter_pilot_ai.gd           # already exists — leave alone
  large_ship_pilot_ai.gd        # already exists — leave alone (Phase 1 grows it)
  gunner_ai.gd                  # NEW — extracted from crew_ai_system.gd
  captain_ai.gd                 # NEW
  squadron_leader_ai.gd         # NEW
  commander_ai.gd               # NEW
  crew_ai_shared.gd             # NEW — only if genuinely shared helpers exist
```

`crew_ai_system.gd` shrinks to:
- `update_crew_member` (the role dispatcher)
- `update_crew_state` (stress/fatigue tick)
- `can_make_decisions`, `calculate_effective_skill`, `calculate_decision_delay`
- nothing else

Everything role-specific moves out.

## Move map (functions → file)

Lines below refer to current `crew_ai_system.gd`.

### → `gunner_ai.gd`
- `make_gunner_decision` (397)
- `execute_gunner_order` (412)
- `make_target_selection_decision` (435)
- `_select_gunner_action_from_knowledge` (490)
- `_select_best_gunner_target` (519)
- `create_fire_decision_with_mode` (546)
- `create_hold_fire_decision` (559)
- `create_fire_decision` (572)

### → `captain_ai.gd`
- `make_captain_decision` (580)
- `execute_captain_order` (589)
- `make_ship_tactical_decision` (607)
- `_select_captain_action_from_knowledge` (691)
- `_is_ship_critically_damaged` (781)
- `_find_damaged_friendly` (793)
- `_select_damaged_target` (803)
- `select_best_tactical_target` (810)
- `break_down_captain_order` (819)
- All `create_*_orders` helpers used only by captain (830–944)
- `create_captain_decision` (944)

### → `squadron_leader_ai.gd`
- `make_squadron_leader_decision` (960)
- `_select_squadron_action_from_knowledge` (1048)
- `_find_damaged_subordinate` (1124)
- `_is_squadron_scattered` (1140)
- `assign_squadron_targets` (1167)
- `_calculate_target_priority_score` (1210)
- All squadron-specific `create_*_orders` (1229–1289)

### → `commander_ai.gd`
- `make_commander_decision` (1294)
- `_select_commander_action_from_knowledge` (1384)
- All commander-specific `create_*_orders` (1419–1489)

### → leave in `crew_ai_system.gd` as the dispatcher
- `update_crew_member`, `update_crew_state`, `can_make_decisions`
- `calculate_effective_skill`, `calculate_decision_delay`
- pilot dispatcher (`make_pilot_decision`, `infer_ship_type`,
  `execute_pilot_order`, `make_evasive_decision`, `make_pursuit_decision`,
  delay helpers, `_find_ship_by_id`, idle/pursuit fallbacks,
  `make_fighter_pilot_decision`, `make_corvette_pilot_decision`,
  `make_capital_pilot_decision`, `make_balanced_pilot_decision`,
  `analyze_tactical_context`)
  — these stay until Phase 1/2 absorb them into the per-class AI modules.

## Calling-convention rules

- Each new file is `extends RefCounted` + `class_name <RoleAI>`, mirroring
  `FighterPilotAI` / `LargeShipPilotAI`.
- Public entry point per role is a single `make_decision(crew_data, game_time, ...)`
  function. The dispatcher in `crew_ai_system.gd` calls it.
- Internal helpers stay `static`, prefixed `_`. No instance state.
- No `var` module-level state (pure functional, matches PR #51).
- Constants: hoist any magic numbers encountered during the move into
  `const NAME = ...` at the top of the role file, with a one-line comment.
  This is the only "behavior-adjacent" change permitted in this phase, and
  only because PR #51's standard forbids magic numbers.

## Test strategy

- `tests/test_crew_ai_system.gd` keeps passing. Where it asserts behaviors
  belonging to a moved role, the assertions stay; only the
  `class_name`/preload references update.
- Split tests opportunistically: if the existing test file already groups
  asserts by role, split into `test_gunner_ai.gd`, `test_captain_ai.gd`,
  etc. If not, leave as-is — test reorg is not in scope.
- Add no new tests in this phase. Behavior is unchanged; new tests come
  with each behavior phase.

## Acceptance checklist

- [ ] `crew_ai_system.gd` ≤ 400 lines; only contains dispatcher + crew-state
- [ ] Each new file compiles standalone (`class_name` + `static` only)
- [ ] No warnings from Godot on save
- [ ] `./test.sh` green with the same assertion count as `main`
- [ ] No `# legacy` / `# old` / `# kept for compat` comments anywhere
- [ ] No `var` exported as global state in any new file
- [ ] grep for magic literals (`grep -nE "[^_a-zA-Z][0-9]+\.[0-9]"` in new
  files) returns only items that are already named constants

## Out of scope

- Changing any decision logic
- Adding FSMs, personality axes, self-preservation, leashes (Phases 1–4)
- Touching `fighter_pilot_ai.gd` or `large_ship_pilot_ai.gd`
- Touching `crew_scheduler_system.gd` or `crew_mailbox_system.gd`
