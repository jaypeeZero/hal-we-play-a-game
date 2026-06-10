# ARCHITECTURE_AND_FLOW.md

## Core principles

- **Functional + data-driven.** Pure-function systems (`DamageResolver`,
  `WeaponSystem`, `CollisionSystem`, `MovementSystem`,
  `CommandChainSystem`, `InformationSystem`, `CrewAISystem`,
  `CrewMailboxSystem`, `CrewSchedulerSystem`, `WingFormationSystem`,
  `TacticalMemorySystem`) take state in and return new state out.
  Game-loop state lives on `SpaceBattleGame` and is passed in/out per tick.
- **One owner per piece of state.** Ships and projectiles are owned by the
  game loop; crew state is owned by the game loop; mailboxes are owned by
  the game loop.  Cross-system messages (decisions, hits, events) are
  immutable values.  Per-frame inner-loop state with a single owner
  (e.g. projectile position/lifetime) is mutated in place via clearly
  named functions like `advance_projectile_in_place`.
- **Event-driven NPCs, not per-frame polling.**  Crew members are only
  processed when they wake — either their `next_decision_time` has been
  reached, or an event has been posted to their mailbox.
- **Signals only for engine-level concerns.**  Godot signals are used at
  the rendering boundary (`state_changed`, `event_occurred`) and for the
  initial-pause / game-over plumbing.  Game logic is pure-function calls,
  not signal traffic.

## Component responsibilities

### `SpaceBattleGame` (root orchestrator)

The Node2D that owns the game loop, the data arrays, and all system calls.

State held:
- `_ships: Array` — ship dicts.
- `_projectiles: Array` — projectile dicts.
- `_obstacles: Array` — asteroid / debris dicts.
- `_crew_list: Array` — crew dicts.
- `_crew_mailboxes: Dictionary` — `crew_id → Array[event]`.
- `_crew_index: Dictionary` — O(1) `crew_id → crew_data` lookup.
- `_previous_wings: Array` — last computed wing assignments (cached).
- `_wings_dirty: bool`, `_wings_last_formed_at: float` — wing-cache invalidation.
- `_ship_entities`, `_projectile_entities`, `_visual_effects` — Node2D
  visual representations bridged via `VisualBridgeAutoload`.

Per-frame work in `_process(delta)`:
1. `_update_crew_ai_systems(delta)` — command-chain merge, wing reform if
   dirty/stale, then `CrewSchedulerSystem.tick_with_awareness(...)`.
2. `MovementSystem.update_all_ships(...)` and `update_all_obstacles(...)`.
3. `_check_spatial_awareness_triggers()` — diff this-frame visible enemies
   against last-frame snapshot, post `sensor_contact` / `target_lost`
   events into mailboxes.
4. Weapons (every `WEAPON_UPDATE_INTERVAL = 0.1s`): `_process_weapons` →
   `_spawn_projectiles`.
5. Projectiles: `ProjectileSystem.advance_all_projectiles_in_place(...)`,
   filter expired.
6. Collisions: `CollisionSystem.process_collisions(...)` → spawn visual
   effects, `_emit_damage_events()` posts `ship_damaged` events.
7. Physical (ship-on-ship / ship-on-obstacle) collisions and effects.
8. Visual effect lifecycle.
9. Sync ship/projectile transforms and emit render state.

### Pure-function systems

| System | Purpose |
| --- | --- |
| `DamageResolver` | Damage and armor-penetration math. |
| `WeaponSystem` | Cooldowns, target acquisition, fire-command generation. |
| `ProjectileSystem` | Projectile movement and lifetime; mutates state in place (single owner). |
| `CollisionSystem` | Hit detection, damage application, explosion spawning. |
| `MovementSystem` | Ship motion, obstacle avoidance, ship-on-ship physics. |
| `InformationSystem` | Per-crew awareness: `update_crew_awareness(crew, ships, projectiles, time)` builds visible-entity / threat / opportunity lists. |
| `CommandChainSystem` | Per frame: distribute `orders.issued` to subordinates, merge subordinate awareness up to superiors. |
| `CrewAISystem` | Role-specific decision functions (pilot / gunner / captain / squadron leader / commander).  Used internally by the scheduler. |
| `CrewMailboxSystem` | Per-crew event queue.  Pure functions: `post_event`, `has_pending`, `drain_events`, `peek_events`.  10-event cap; oldest dropped on overflow. |
| `CrewSchedulerSystem` | Wakes crew, applies event side effects, refreshes awareness on wake, drives the role decision. |
| `WingFormationSystem` | Forms fighter pairs/threes by proximity; preserves existing wings via `previous_wings`. |
| `TacticalMemorySystem` | Per-crew event log (capped at `MAX_RECENT_EVENTS`) and decision-outcome tracking. |
| `CrewIntegrationSystem` | Translates crew decisions into ship-orders + crew-skill modifiers. |
| `SpatialGridSystem` | Uniform spatial grid (`build` / `query_radius`) used to narrow per-frame range queries from O(n) to O(cells). |

### Spatial grid

Per-frame range queries that used to scan the full fleet (sensor-contact
detection, per-crew visible-entity gathering, projectile hit detection)
now query a uniform grid keyed by cell coordinate.

- The game node builds two grids in `_process`:
  1. Pre-movement (`_ships`, `_projectiles`) before `_update_crew_ai_systems`
     so `InformationSystem` can use them.
  2. Post-movement (`_ships`, `_obstacles`) consumed by
     `_check_spatial_awareness_triggers` and `CollisionSystem.process_collisions`.
- The grid is a value, not a long-lived structure — built fresh each
  frame from current positions and dropped after the queries.
- `query_radius` returns a candidate superset; callers do the exact
  distance check.  Per-entity team / status filters are unchanged, so
  the optimization preserves the command-chain semantics: capital ships
  with large awareness ranges still walk many cells and detect distant
  groups exactly as before — only the inner loop scales differently.
- `cell_size` is `GRID_CELL_SIZE = 256.0` (tunable).
- All grid-aware APIs (`InformationSystem.update_crew_awareness`,
  `CollisionSystem.process_collisions`, `CrewSchedulerSystem.tick_with_awareness`)
  accept the grid as an optional argument; tests pass `{}` and the
  system falls back to the full-array scan.

### Pilot AIs (called by `CrewAISystem`)

- `FighterPilotAI` — wing/lead/wingman tactics, dogfight maneuvers.
- `LargeShipPilotAI` — corvette/capital tactics (broadside, kite, orbit).

### Entity layer (Node2D)

- `ShipEntity` — main ship, extends `IRenderable`; syncs transform from
  the ship dict each frame.
- `ProjectileEntity` — projectile, extends `IRenderable`.

### Rendering

- `VisualBridge` (autoload) — registers/unregisters renderable entities.
- `IVisualRenderer` — interface; sole implementation is `Renderer78`,
  which draws line-based hull outlines from `data/hull_shapes/` JSON.

## The crew tick in detail

`CrewSchedulerSystem.tick_with_awareness(crew_list, game_time, mailboxes,
ships, projectiles, wings)`:

For each crew:

1. Compute `has_events = mailbox has pending` and
   `is_due = game_time ≥ crew.next_decision_time`.
2. If neither, append the crew unchanged and continue (sleeping crew cost
   essentially nothing).
3. Refresh awareness:
   `aware_crew = InformationSystem.update_crew_awareness(crew, ships, projectiles, game_time)`.
4. If `has_events`, drain mailbox and call
   `apply_event_side_effects(aware_crew, events, game_time)`:
   - `sensor_contact` → record `threat_detected` in tactical memory.
   - `ship_damaged` → record `ship_damaged` in tactical memory.
   - `target_lost` → clear `awareness.current_target`.
   - `order_received` → `CommandChainSystem.process_single_order`.
5. Run `update_crew_with_events`:
   - If pilot + has urgent event (`missile_locked`, `threat_appeared`,
     `ship_damaged`) + has known threats → short-circuit to
     `make_evasive_decision`.
   - Otherwise → `CrewAISystem.update_crew_member`, which dispatches to
     the role-specific function.
   - Crew state (stress / fatigue) catches up lazily using
     `dt = game_time - last_state_update_time`.
6. Stamp `last_state_update_time = game_time` on the result and append.

Returns `{crew_list, decisions, mailboxes}`.  The game node then calls
`CrewIntegrationSystem.apply_crew_decisions_to_ships` to translate
decisions into ship orders.

## Event sources → mailbox

Every event posted via `_queue_crew_event(crew_id, type, data)` lands in
`_crew_mailboxes[crew_id]`.  The scheduler drains them next tick.

| Event type | Posted by | Side effect on wake |
| --- | --- | --- |
| `sensor_contact` | `_check_spatial_awareness_triggers` (new enemy in range) | record `threat_detected` |
| `target_lost` | `_check_spatial_awareness_triggers` (enemy left range) | clear `awareness.current_target` |
| `ship_damaged` | `_emit_damage_events` after collisions | record `ship_damaged`; urgent-event evade for pilots with threats |
| `order_received` | (issued by command-chain superiors as part of `process_command_chain`) | apply order via `process_single_order` |

The mailbox cap is 10 events per crew; if a noisy source produces more,
the oldest are dropped.

## Wing formation cache

`WingFormationSystem.form_wings` is O(n²) over fighters and runs only
when the cache is dirty:

- Marked dirty when `_remove_ship` is called (ship destruction can break
  wing membership).
- Otherwise reformed every `WING_REFORM_INTERVAL = 0.5s` as a safety net.

## Game flow walkthroughs

### Game start
```
SpaceBattleGame._ready()
  → _setup_input_actions()
  → _initialize_knowledge_base()
  → _enable_event_tracking()
  → _spawn_initial_squadrons()
    → For each team: _spawn_fleet_for_team(...)
      → ShipData.calculate_fleet_spawn_positions(...)
      → spawn_ship(type, team, position) per ship
        → ShipData.create_ship_instance(...)
        → ShipEntity.initialize(...)
        → _create_crew_for_ship(...)  [solo pilot / multi-crew / squadron]
  → get_tree().paused = true   (SPACE to start)
```

### Spawning a fighter squadron at runtime (key 1 + click)
```
_unhandled_input → spawn_fighter pressed
  → _request_squadron_spawn("fighter", 0)  [stage _pending_spawn]
mouse click
  → _execute_squadron_spawn(click_position)
    → For each of 6 V-formation slots:
        ShipData.create_ship_instance(...) → _ships.append
        ShipEntity.initialize(...)
    → CrewData.create_fighter_squadron(skill)
        Alpha is leader; Beta–Zeta have command_chain.superior = Alpha
    → assigned_to is set per ship; crew appended to _crew_list
```
Next tick, the new crew have `next_decision_time = 0` and are
processed immediately by the scheduler.

### A pilot reacting to a missile lock
```
ProjectileSystem (or wherever lock is detected) emits
  → _queue_crew_event(pilot_id, "missile_locked", {...})
    → CrewMailboxSystem.post_event into _crew_mailboxes

Next CrewSchedulerSystem.tick_with_awareness:
  → has_events = true → wake the pilot
  → drain events → apply_event_side_effects
  → update_crew_with_events sees PILOT + urgent + threats → evade
  → make_evasive_decision returns a maneuver decision

Game node:
  → CrewIntegrationSystem.apply_crew_decisions_to_ships
    → ship.orders.current_order = "evade", threat_id = ...
  → MovementSystem reads ship.orders next frame and steers accordingly
```

### A captain ordering a pilot
```
CommandChainSystem.process_command_chain
  → captain.orders.issued has [{to: pilot_id, type: "engage", ...}]
  → distribute_orders_down_chain assigns it to pilot.orders.received
  → captain.orders.issued cleared

Next CrewSchedulerSystem.tick:
  → pilot wakes (timer or event)
  → CrewAISystem.make_pilot_decision sees orders.received != null
  → execute_pilot_order returns a maneuver decision matching the order
```

## Adding a new event type

1. Pick a name (`coolant_leak`, `enemy_jumped_in`, etc.).
2. From whichever system detects the condition, call
   `space_battle_game._queue_crew_event(crew_id, "coolant_leak", payload)`.
3. In `CrewSchedulerSystem._apply_one_event`, add a `match` arm that
   mutates the crew dict (record memory, set a flag, change orders, ...).
4. If the event should force pilots into evasion regardless of threat
   priority, add it to `URGENT_EVENT_TYPES`.
5. Add a behavior test in `tests/test_crew_scheduler.gd` that posts the
   event and asserts the side effect / decision.

## Adding a new ship role

1. Add the role to `CrewData.Role`.
2. Add `make_<role>_decision` in `CrewAISystem`.
3. Add a `match` arm in `CrewAISystem.update_crew_member`.
4. If the role uses a different decision-time profile, extend the
   appropriate role-specific function with its own
   `next_decision_time` schedule.
5. If the role appears in command chains, update
   `get_awareness_limit(role)` and `validate_order` in
   `CommandChainSystem`.

## Testing

GUT-based.  Tests live in `tests/` and use the same entry points the
game uses — there are no test-only convenience helpers.

Test file naming: `test_<system_name>.gd`.

Behavior coverage focuses on what systems should DO, not specific
numeric values:
- ✅ "A pilot under missile lock chooses an evasive maneuver."
- ✅ "Mailbox events wake a sleeping crew on the next tick."
- ❌ "Fighter has exactly 20 armor."

Running:
```
./test.sh                           # full suite
godot --headless --script addons/gut/gut_cmdln.gd \
  -gdir=tests -gselect=test_crew_scheduler.gd -gexit
```

## Common pitfalls

- **Don't write to `awareness.known_entities` from outside
  `InformationSystem`.**  Spatial-trigger snapshots live under a
  dedicated `awareness._spatial_seen` key; clobbering `known_entities`
  with a different shape silently breaks `combine_known_entities`.
- **Don't add per-frame fleet-wide scans.**  If you need new awareness
  data, compute it on-wake in the scheduler's awareness refresh, not in
  a `for crew in _crew_list` loop running every frame.
- **Don't add test-only entry points.**  If a test needs to invoke
  something the game doesn't, the production API is missing the wrong
  feature — extend or migrate to the real one.
- **Don't rebuild projectile dicts each frame.**  Projectile movement
  mutates in place because the data has one owner and the previous
  frame's value is dead the moment the next frame begins.  If you need
  a snapshot for a replay buffer, duplicate before passing to
  `advance_*_in_place`.
- **Wing membership is cached.**  Mark `_wings_dirty = true` when
  membership-affecting events fire (ship destroyed, etc.); don't rely
  on the safety-net interval for correctness.
