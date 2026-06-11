# 07 — Healing: Engineer crew role + roguelike repair

Two player-facing features:

1. **Engineer crew role.** Each action, an Engineer repairs the ship they
   are on by a percentage based on their ability. Their maneuvers are
   `fix_gun`, `fix_engine`, `fix_armor`, etc. Corvettes carry 0–2
   Engineers, capitals 1–5.
2. **Roguelike healing.** Ships that have Engineers heal after a Battle
   node completes, and again when entering an R&R node.

## Foundation (what exists today)

- Crew roles are an enum + factory in `crew_data.gd` (Role enum line 10,
  per-role modifiers line 88, `create_ship_crew` line 248). Crew counts
  per hull are decided in `ship_data.gd::create_crew_for_ship` (line 135).
- Decisions flow: `CrewSchedulerSystem.tick_with_awareness` wakes due
  crew → `CrewAISystem.update_crew_member` dispatches by role (line 26)
  → decisions return to `space_battle_game.gd::_apply_crew_decisions`
  (line 857) → `CrewIntegrationSystem.apply_decision_to_ship` matches on
  decision `type` (line 64: maneuver / fire / tactical).
- Health model: `armor_sections[].current_armor/max_armor` and
  `internals[].current_health/max_health/status` with `effect_on_ship`
  multipliers applied by `DamageResolver` on status transitions.
  **No repair function exists anywhere.**
- The six-stat skill schema already reserves damage-control speed under
  `tactics` (crew_data.gd line 81) — Engineers need no new stat.
- Roguelike: surviving ship dicts (with damage) persist in
  `RoguelikeRun.fleet_ships` via `update_fleet_after_battle`
  (roguelike_run_autoload.gd line 38), repopulated from
  `space_battle_game.gd::_handle_roguelike_battle_end` (line 746).
  R&R nodes exist on the map (`roguelite_map.gd` NodeType.RANDR) but
  selecting one currently does nothing beyond marking it visited
  (line 259).

## Design decision: stats must be recomputed, not un-multiplied

`DamageResolver.multiply_ship_stat` (line 284) mutates `ship.stats`
multiplicatively with no stored baseline, so repair cannot invert it
(damaged→destroyed→repaired would compound multipliers). Fix: snapshot
`base_stats` (and base weapon damage/accuracy) at ship creation in
`ShipData.create_ship_instance`, and add a pure
`recompute_stats_from_components(ship_data)` that derives effective
stats from `base_stats` × the `effect_on_ship` of every non-operational
internal. **Both DamageResolver and repair call it** — one path, the
incremental multiply helpers get deleted (no parallel/legacy code).

Destroyed components: not repairable in battle (Engineers triage what's
left); restorable by post-battle and R&R repairs. This keeps in-battle
stakes while letting a run recover.

## Increments (each independently shippable)

1. **Repair primitives.** New `scripts/space/systems/repair_system.gd`
   (pure static funcs): `repair_armor_section(ship, section_id, amount)`,
   `repair_component(ship, component_id, amount)` (clamps to max,
   recomputes status with the same thresholds DamageResolver uses), and
   `repair_ship_fraction(ship, fraction, include_destroyed)` for the
   roguelike heals. Includes the `base_stats` snapshot +
   `recompute_stats_from_components` refactor above.
   Tests: `tests/test_repair_system.gd` — repairing a damaged engine
   restores max_speed, repair clamps at max, destroyed stays destroyed
   when `include_destroyed` is false.
2. **Engineer role.** Add `Role.ENGINEER` to `crew_data.gd` (enum,
   role modifiers with a slow decision cadence, `get_role_name`,
   effective skill reads `tactics`). New `scripts/space/ai/engineer_ai.gd`:
   on wake, scan own ship; pick the worst-off damaged internal (else the
   most-damaged armor section); emit
   `{"type": "repair", "subtype": "fix_" + component_type, ...}` with
   `skill_factor`; idle on a long cadence when nothing is damaged.
   Dispatch branch in `CrewAISystem.update_crew_member`; `"repair"`
   branch in `CrewIntegrationSystem.apply_decision_to_ship` converts
   `skill_factor` to a heal amount
   (`max × lerp(ENGINEER_REPAIR_FRACTION_MIN, _MAX, skill)`), scaled by
   the captain's already-computed `crew_modifiers.damage_control`
   (crew_integration_system.gd line 300 — finally consumed).
   `create_ship_crew` gains an `engineer_count` param (Engineers report
   to the captain); `create_crew_for_ship` rolls
   `CORVETTE_ENGINEERS_MIN/MAX` (0/2) and `CAPITAL_ENGINEERS_MIN/MAX`
   (1/5). Repairs go through `BattleEventLogger` so they show in the log.
   Tests: `tests/test_engineer_ai.gd` — engineer targets damaged
   component, higher skill heals more, idle when undamaged; crew-count
   bounds per hull type.
3. **Post-battle healing.** `RepairSystem.apply_engineer_repairs(ship,
   fraction_per_engineer)`: heal `fraction × engineer skill` per
   Engineer aboard, destroyed components included. Called on each
   survivor inside `RoguelikeRun.update_fleet_after_battle` with
   `POST_BATTLE_REPAIR_FRACTION`. Verify first that surviving ship
   dicts carry current crew (battle keeps a separate `_crew_list`; if
   `ship.crew` is stale, reattach crew in
   `_get_surviving_player_ships`).
   Tests: extend `tests/test_roguelike_run.gd` — damaged survivor with
   an Engineer comes back healthier, without one comes back unchanged.
4. **R&R healing.** In `roguelite_map.gd::_on_node_selected`, the RANDR
   branch calls `RoguelikeRun.apply_rnr_repairs()` → same
   `apply_engineer_repairs` with the larger `RNR_REPAIR_FRACTION`, and
   reports the result in the map's info label.
   Tests: R&R heals more than post-battle; engineerless fleet gets
   nothing.

All tunables are named constants in `wing_constants.gd` (engineer
cadence, repair fractions, crew-count bounds) — no magic numbers.

## Done when

- A corvette with an Engineer visibly regains armor/component health
  during battle, logged in the battle event stream; one without an
  Engineer does not.
- In a roguelike run, a damaged ship with Engineers re-enters the next
  battle healthier than it left the last one, and an R&R stop heals it
  further — both asserted in tests.
- `./test.sh` green; no warnings; `multiply_ship_stat` and friends are
  gone, replaced by the single recompute path.
