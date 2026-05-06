# Squadron Plays

## Goal

Make squadron leader `tactics` matter at the **wing scale**, not just
in individual decisions. Elite leaders execute coordinated maneuvers
(pincer, bracket, kill-box). Rookies all merge on the same target from
the same vector.

Produces Scenario S4 ("Coordinated Pincer"). Probably the most "the
elite squadron just outmaneuvered me" moment in the game.

`CoordinationStyle.ORCHESTRATED` (`crew_integration_system.gd:35`) is
currently a label with no payload. This phase puts a real playbook
behind it.

## Design

### Plays as data, not code

`data/squadron_plays.json` defines plays:

```json
{
  "pincer": {
    "min_tactics": 0.5,
    "min_wing_size": 4,
    "phases": [
      { "duration": 3.0, "roles": { "A": "engage_frontal", "B": "loop_wide_left" } },
      { "duration": 4.5, "roles": { "A": "hold_pressure", "B": "approach_target_six" } },
      { "duration": 0.0, "roles": { "A": "merge_attack", "B": "merge_attack" } }
    ]
  },
  "bracket": { ... },
  "kill_box": { ... }
}
```

Each play declares per-role offsets, sequencing, phase-transition
triggers (timer or geometry-based).

### Squadron leader picks plays

Squadron leader's decision tick chooses a play based on:

- `effective(crew, "tactics")`: gates which plays unlock — `min_tactics`.
- `effective(crew, "aggression")`: biases offensive vs defensive
  selection.
- Current geometry: target count, fleet positions, range.

Selection is done in pure functional terms — given inputs, returns
`play_id` plus per-fighter role assignments.

### Wingmen consume orders, don't run plays

Wingman pilots don't need to know what a "pincer" is. The leader
issues per-fighter orders:

```gdscript
crew.orders.received = {
  play_id: "pincer",
  play_role: "A" | "B",
  phase: 0,
  target_offset: Vector2(...),
  target_id: ...
}
```

Existing maneuver dispatch in
`fighter_pilot_ai.gd:apply_maneuver_decision` reads these as
constraints on its own decisions. Pilots still have local autonomy
(dodging incoming fire, etc.) but their *intent* is constrained by
the play.

### Execution-quality scattering

Play execution timing and offsets are scattered by
`(1 - effective(leader, "tactics")) * jitter`:

- Elite squadron: phase transitions tightly synced; offsets precisely
  hit.
- Rookie squadron: phases drift, offsets miss by tens of meters,
  fighters arrive at the merge out of order.

## Edits

### 5.1 New file: `scripts/space/systems/squadron_play_system.gd`

Pure functional. API:

- `select_play(leader_crew, wing_state, geometry) -> Dictionary` —
  returns `{play_id, role_assignments}` or null.
- `tick_play(squadron_state, game_time) -> squadron_state` — advances
  phases, computes per-fighter target offsets.
- `apply_jitter(offset, leader_tactics) -> offset` — adds execution
  quality scatter.

### 5.2 New file: `data/squadron_plays.json`

Three starter plays: `pincer`, `bracket`, `kill_box`. Bracket and
kill-box can be stubs for first ship — pincer is enough to demonstrate
S4.

### 5.3 Squadron leader AI integration

`squadron_leader_ai.gd` decision function calls
`SquadronPlaySystem.select_play` on tick. If a play is selected, it:

1. Stores active play in `squadron_state.active_play`.
2. Issues per-fighter orders into wingmen's `orders.received`.
3. Subsequent ticks call `tick_play` to advance phases and re-issue.

### 5.4 Wingman pilot consumption

`fighter_pilot_ai.gd:apply_maneuver_decision` reads
`crew.orders.received.play_role` and treats it as a constraint:

- "engage_frontal" → bias attack vector toward target's nose aspect.
- "loop_wide_left" → set waypoint to the computed offset; switch to
  attack only on next phase.
- "merge_attack" → standard engagement.

Local self-preservation (dodge incoming fire, break formation when
locked) overrides play orders — pilots still have autonomy.

### 5.5 Delete

- Any unused `CoordinationStyle` enum members that don't unlock real
  behavior. Keep only `INDIVIDUAL`, `LOOSE`, `ORCHESTRATED` (the names
  that actually correspond to real wing behavior). Stub members go.

## Constants (wing_constants.gd)

New:
- `PLAY_JITTER_MAX_OFFSET = 80.0` — max position scatter for low-
  tactics leaders.
- `PLAY_JITTER_MAX_TIMING = 1.2` — max phase-transition jitter
  seconds.
- `PLAY_REPLAN_INTERVAL = 6.0` — leader re-evaluates plays this often.

## Tests

New:
- `test_squadron_play_selection.gd` — high-tactics leader selects
  pincer when geometry favors it; low-tactics leader picks generic
  merge.
- `test_pincer_geometry.gd` — pair B's path actually arcs to the
  target's six in the second phase.
- `test_play_jitter_by_skill.gd` — execution scatter strictly ordered
  by leader's `tactics`.

## Acceptance

1. `./test.sh` is green.
2. **S4.** Elite 6-fighter squadron beats rookie 6-fighter squadron at
   ≥ 70% in 50 trials.
3. In replay, elite squadron's per-fighter heading variance at
   engagement is ≥ 2× rookie's — they actually split.
4. Fraction of kills with `attacker_aspect=rear` is ≥ 30% for elite
   squadrons; < 5% for rookies.
5. `play_executed` BattleEventLogger events are emitted; analysis
   confirms play selection varies with `tactics`.

## Definition of done

- [ ] `squadron_play_system.gd` and `data/squadron_plays.json` land.
- [ ] Wingman AI consumes play orders.
- [ ] All tests pass.
- [ ] Zero compile warnings.
- [ ] Playtest: a human watching can identify "they're trying to
      pincer me" without telemetry.
- [ ] Acceptance ticked.
