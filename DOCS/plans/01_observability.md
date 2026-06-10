# 01 — One observability pipeline

**Goal**: a single battle log on disk that answers "what happened and
why did that crew member do that?" after the fact, with zero
side-channel `print()` debugging.

**Precondition**: the AI-decision-logging branch
(`claude/add-ai-decision-logging-rzUSI`) is merged. It gives
`BattleEventLogger` JSONL file output (`~/.logs/space-game/`, capped at
5 runs), `log_ai_decision()` with reasoning context, and
`log_order_issued()`.

## Steps

1. **Wire `log_ai_trigger()`** (added by that branch, currently never
   called). Call it from `CrewSchedulerSystem` where urgent mailbox
   events wake a crew member, so reactive decisions in the log are
   preceded by the event that caused them.
2. **Delete the wizard-era convenience methods** on `BattleEventLogger`
   and its autoload: `log_creature_spawned`, `log_spell_cast`,
   `log_projectile_fired`, `log_creature_died`, `log_player_died`,
   `log_mana_changed`. Callers use generic `log_event()`; only
   `log_damage_dealt` has a call site (keep it).
3. **One sink**. `GameLogger` writes to `user://logs/`,
   `BattleEventLogger` to `~/.logs/space-game/`. Pick one location and
   route both through one file writer. Suggested: keep
   `BattleEventLogger` as the battle-domain API, have it write through
   `GameLogger`'s file (or retire `GameLogger`'s file handling — choose,
   don't keep both).
4. **Fix `SignalMonitor` bugs**:
   - the per-signal lambda discards signal arguments (passes `[]` to the
     logger) — capture and forward them;
   - the lambda is recreated on every call so `is_connected()` never
     matches, producing duplicate connections — store the Callable.
5. **Migrate meaningful `print()`/`push_warning()` call sites** (~118
   prints) in `scripts/` and `rendering/` to the logger. Startup
   chatter (hull shapes loaded, renderer attached) can simply be
   deleted.
6. **Flush policy**: `BattleEventLogger` only flushes on exit; flush
   periodically (e.g., every N events) so a crash keeps the log tail.
7. **ObjectDB leak**: tests exit with "ObjectDB instances leaked".
   Track down unfreed nodes (likely renderer/entity teardown) and fix.

## Done when

- One log file per battle contains spawns, damage, kills, orders, AI
  decisions with rationale, and AI wake triggers.
- `grep -rn "print(" scripts/ rendering/` returns only the logger
  internals.
- Tests exit without leak warnings.
