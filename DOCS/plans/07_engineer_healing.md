# 07 — Healing: Engineer crew role + roguelike repair

Three player-facing features:

1. **Engineer crew role.** Each action, an Engineer repairs the ship they
   are on by a percentage based on their ability. Their maneuvers are
   `fix_gun`, `fix_engine`, `fix_armor`, etc. Corvettes carry 0–2
   Engineers, capitals 1–5.
2. **Star dates.** Each roguelike map row is a Star date —
   semi-randomized, monotonically increasing, labeled on the map.
3. **Roguelike healing.** Ships that have Engineers heal during the jump
   after a Battle node completes, and more when entering an R&R node.
   The further apart two jumps' Star dates, the more the Engineers
   repair — longer downtime, more repair time.

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
- Roguelike: surviving ship dicts (with damage) persist in
  `RoguelikeRun.fleet_ships` via `update_fleet_after_battle`
  (roguelike_run_autoload.gd line 38), repopulated from
  `space_battle_game.gd::_handle_roguelike_battle_end` (line 746).
  Map rows/nodes are generated and persisted in `roguelite_map.gd` +
  `RoguelikeRun.save_map_state`; node selection funnels through
  `_on_node_selected` (line 246). R&R nodes exist (NodeType.RANDR) but
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
left); restorable by between-jump and R&R repairs. This keeps in-battle
stakes while letting a run recover.

## Design decision: `machinery` is a role-gated skill

Add a seventh skill, `machinery`, to the skills schema in
`crew_data.gd` (and to the varied-skills list, line 323). All repair
math reads `machinery` — but only crew currently occupying the
**Engineer role** ever make repair decisions or count toward roguelike
repairs. Soccer analogy: a player may be able to play both CB and DM,
but only fills one position per match. A future multi-role crew
member's `machinery` is inert unless they're slotted as the ship's
Engineer; nothing else reads it (do not fold it into `tactics`).
`calculate_effective_skill` gets an ENGINEER → `machinery` branch, so
stress/fatigue degrade repair like every other skill.

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
2. **Engineer role.** Add `Role.ENGINEER` to `crew_data.gd` (enum, role
   modifiers with a slow decision cadence, `get_role_name`) and the
   `machinery` skill per the design decision above. New
   `scripts/space/ai/engineer_ai.gd`: on wake, scan own ship; pick the
   worst-off damaged internal (else the most-damaged armor section);
   emit `{"type": "repair", "subtype": "fix_" + component_type, ...}`
   with `skill_factor` from effective `machinery`; idle on a long
   cadence when nothing is damaged. Dispatch branch in
   `CrewAISystem.update_crew_member`; `"repair"` branch in
   `CrewIntegrationSystem.apply_decision_to_ship` converts
   `skill_factor` to a heal amount
   (`max × lerp(ENGINEER_REPAIR_FRACTION_MIN, _MAX, skill)`), scaled by
   the captain's already-computed `crew_modifiers.damage_control`
   (crew_integration_system.gd line 300 — finally consumed).
   `create_ship_crew` gains an `engineer_count` param (Engineers report
   to the captain); `create_crew_for_ship` rolls
   `CORVETTE_ENGINEERS_MIN/MAX` (0/2) and `CAPITAL_ENGINEERS_MIN/MAX`
   (1/5). Repairs go through `BattleEventLogger` so they show in the log.
   Tests: `tests/test_engineer_ai.gd` — engineer targets damaged
   component, higher `machinery` heals more, idle when undamaged,
   non-Engineer crew with high `machinery` never emits repair
   decisions; crew-count bounds per hull type.
3. **Star dates.** Map generation in `roguelite_map.gd` assigns each
   row a `star_date`: previous row's date +
   `randi_range(STAR_DATE_GAP_MIN, STAR_DATE_GAP_MAX)`, starting from
   `STAR_DATE_RUN_START`. Dates render as row labels on the map and
   persist through `save_map_state`/`load_map_state` (they're part of
   the node dicts already round-tripped). `RoguelikeRun` tracks
   `current_star_date`, updated on every node selection so the next
   jump can compute its delta.
   Tests: dates strictly increase row to row, gaps within bounds,
   dates survive a save/load round trip.
4. **Jump + R&R healing.** One hook in
   `roguelite_map.gd::_on_node_selected` (covering `_launch_battle`
   too): on every jump, `RoguelikeRun.apply_jump_repairs(date_delta,
   is_rnr)` runs `RepairSystem.apply_engineer_repairs` on each fleet
   ship — per Engineer aboard, heal
   `REPAIR_FRACTION_PER_DATE × machinery × date_delta`, times
   `RNR_REPAIR_MULTIPLIER` when the destination is an R&R node;
   destroyed components included. The map's info label reports what
   was repaired. Verify first that surviving ship dicts carry current
   crew (battle keeps a separate `_crew_list`; if `ship.crew` is
   stale, reattach crew in `_get_surviving_player_ships`).
   Tests: extend `tests/test_roguelike_run.gd` — damaged survivor with
   an Engineer comes back healthier, without one comes back unchanged;
   a wider date gap heals more than a narrow one; an R&R jump heals
   more than a battle jump at equal delta.

All tunables are named constants in `wing_constants.gd` (engineer
cadence, repair fractions, crew-count bounds, star-date gaps) — no
magic numbers.

## Done when

- A corvette with an Engineer visibly regains armor/component health
  during battle, logged in the battle event stream; one without an
  Engineer does not.
- The roguelike map shows a Star date per row, and a damaged ship with
  Engineers re-enters the next battle healthier in proportion to the
  date gap of the jump, healthier still after an R&R — all asserted in
  tests.
- Repair reads `machinery` and only the Engineer role exercises it.
- `./test.sh` green; no warnings; `multiply_ship_stat` and friends are
  gone, replaced by the single recompute path.
