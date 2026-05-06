# Pending-Intent / Reaction Latency

## Goal

Make `piloting` (and `tactics` for capital captains) gate the **time
between deciding and acting**. Elite pilots commit an evasive decision
in ~80 ms; rookies in ~700 ms. Combined with Phase 03's detection
latency, this produces Scenarios S1 ("The First Burst") and S1b
("Shaken by the Hit").

This is the marquee feature of the overhaul. The architecture is
already perfect for it; it's been left half-built.

## Design — pending intent buffer

Today, `crew_scheduler_system.gd:166–168` short-circuits to evasion on
urgent events (post-Phase 03: `threat_appeared`, `ship_damaged`). The
decision commits immediately into `ship_data.orders`.

New flow:

1. Decision functions return `{type: "evasive", commit_at: game_time + reaction_delay, payload: {...}}`.
2. The integration step does **not** apply the new orders — it stashes
   the intent in `ship_data.pending_intent`:
   ```gdscript
   ship_data.pending_intent = { intent_type, payload, commit_at }
   ```
3. A new tiny system `pending_intent_system.gd` runs each frame in the
   main loop **before MovementSystem**:
   ```gdscript
   static func commit_due(ships: Array, game_time: float) -> Array:
       for ship in ships:
           if ship.has("pending_intent") and game_time >= ship.pending_intent.commit_at:
               apply_intent(ship, ship.pending_intent)
               ship.erase("pending_intent")
       return ships
   ```
4. New intents always replace older pending ones (a fresh decision
   supersedes one waiting to commit). Replacement events are logged.

### Two-phase reaction latency

Detection latency (Phase 03) and commit latency (this phase) compose:

| Phase | Gated by | Range | Effect |
|---|---|---|---|
| Detection | `awareness` | 0–900 ms | When crew receives the event |
| Commit | `piloting` (pilots), `tactics` (captains) | 0–700 ms | Delay between decision and order taking effect |

Combined for an elite pilot: ~50 ms + ~80 ms ≈ **130 ms total**.
Combined for a rookie: ~900 ms + ~700 ms ≈ **1.6 s total**.

At fighter combat speeds, that's the difference between life and
death.

### Stress / composure modulation

Reaction commit delay isn't pure `piloting`. Under stress, low
composure adds delay:

```gdscript
var base = (1.0 - effective(crew, "piloting")) * MAX_REACTION_DELAY
var stress_penalty = max(0.0, crew.stats.stress - effective(crew, "composure") * 0.4)
var commit_delay = base * (1.0 + stress_penalty * REACTION_STRESS_PENALTY_FACTOR)
```

S1b: a low-composure ace under fire reacts slower than usual. A
high-composure rookie performs above their `piloting` baseline.

## Edits

### 4.1 New file: `scripts/space/systems/pending_intent_system.gd`

~60 lines. Pure functional, `extends RefCounted`, all methods static.
API:

- `attach(ship_data, intent_type, payload, commit_at) -> ship_data`
- `commit_due(ships, game_time) -> ships` — applies all pending
  intents whose commit_at has passed.
- `cancel(ship_data) -> ship_data` — clears pending intent (e.g.
  when crew chooses a different action mid-wait).

### 4.2 Decision-function updates

In `crew_ai_system.gd` (or whichever role module owns it post the
`crew_ai_rework/` Phase 0 split):

- `make_evasive_decision(crew, awareness, ship_data) -> Dictionary`
  now returns `{commit_at: ..., intent_type: "evasive", payload: ...}`
  instead of immediate orders.
- Same for any other urgent-path decisions: `make_brace_decision`,
  `make_break_off_decision` — anything that should feel reactive.

Non-urgent decisions (steady-state engagement, formation flying)
**don't** use pending-intent — they flow through the existing path. The
buffer is for *reactive* decisions only.

### 4.3 Integration in `_apply_crew_decisions`

Branch on `commit_at`:

```gdscript
if decision.has("commit_at") and decision.commit_at > game_time:
    PendingIntentSystem.attach(ship_data, decision.intent_type, decision.payload, decision.commit_at)
else:
    apply_orders(ship_data, decision)
```

### 4.4 Frame loop

In `space_battle_game.gd` main update, before MovementSystem tick:

```gdscript
ships = PendingIntentSystem.commit_due(ships, game_time)
```

## Constants (wing_constants.gd)

New:
- `MAX_REACTION_DELAY = 0.7` — seconds; rookie commit delay.
- `REACTION_STRESS_PENALTY_FACTOR = 1.5` — stress amplifies commit lag.

## Tests

New:
- `test_pending_intent_commit_timing.gd` — intent attached at t=0 with
  commit_at=0.5 does not apply at t=0.4 but does apply at t=0.5.
- `test_reaction_delay_skill_ordering.gd` — commit delay strictly
  ordered by `piloting` for pilots and `tactics` for captains.
- `test_reaction_stress_modulation.gd` — high-stress + low-composure
  crew has longer commit delay than baseline.
- `test_pending_intent_supersession.gd` — a fresh decision replaces a
  waiting one; the waiting one never applies.

Updated:
- Tests that asserted decisions apply immediately now assert via
  `commit_due` after advancing game time.

## Acceptance

1. `./test.sh` is green.
2. **S1.** In a scripted 1v1 with fixed initial conditions, elite
   pilot survives the bandit's first burst at ≥ 80% across 50 trials.
   Rookie survives at ≤ 25%.
3. **S1b.** With bandit landing the first hit at known time, elite
   pilot's commit lag from `ship_damaged` to `evasive` order is ≤ 200
   ms; rookie's is ≥ 1.0 s.
4. `decision_committed` BattleEventLogger events are emitted with
   `decided_at` and `commit_at`; latency analysis confirms ordering.
5. Performance: 200-ship sim runs at no worse than 1% slower than
   pre-Phase-8 baseline. (PendingIntentSystem.commit_due is a single
   O(ships) array scan.)

## Definition of done

- [ ] `pending_intent_system.gd` lands; integrated in main loop.
- [ ] All urgent-path decisions return `commit_at` form.
- [ ] All tests pass.
- [ ] Zero compile warnings.
- [ ] Playtest: difference between elite and rookie reaction is
      noticeable to a human observer without telemetry.
- [ ] Acceptance ticked.
