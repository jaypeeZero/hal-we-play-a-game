# 04 — Magic numbers and god functions

**Goal**: every tuning value is a named constant (CLAUDE.md rule); no
function so large it can't be read in one screen. This is mechanical
work — do it file by file, tests green after each.

## Magic numbers (worst first)

1. **`collision_system.gd`** — damage formulas with inline constants:
   `pow(impact_speed / 50.0, 2.0) * 10.0` (ship-obstacle, ~line 543)
   vs `pow(impact_speed / 40.0, 2.0) * 8.0` (ship-ship, ~line 569),
   with *different* impact thresholds (20.0 vs 15.0), restitution
   (0.4 vs 0.3), explosion defaults (radius 80.0 / damage 60.0).
   Name them; decide deliberately whether the asymmetries are intended.
2. **`movement_system.gd`** — engagement/positioning distances
   (600/800/1600/2000/2400), oscillation timings
   (`Time.get_ticks_msec() / 500.0`, `/ 200.0`, `/ 1500.0`), throttle
   steps. Add a constants block at the top of the file (the file
   already does this well for `LARGE_SHIP_*` — extend the pattern).
3. **`weapon_system.gd`** — target priority scores (100/95/90/50/25),
   lead-accuracy blend factors (0.7/0.2), skill clamp bounds.
4. **`game_logger.gd`** — debounce window values (0.05, 1.0, 1.5×).
5. **`space_battle_game.gd:~945`** — `sensor_range = 800.0` with a TODO
   to read from ship stats; do that, or name the constant.

## God functions

Split for readability only — no behavior change, keep the diff
reviewable:

1. **`movement_system.gd: apply_space_physics()`** (~180 lines, 7+
   nested branches) → extract `apply_rotation`, `apply_main_thrust`,
   `apply_lateral_thrust`, `apply_braking`, `apply_inertial_dampening`.
2. **`fighter_pilot_ai.gd: make_decision()`** (~110 lines) — a cascade
   of seven bail-out checks; extract each named check into a small
   function returning an optional decision.
3. **`large_ship_pilot_ai.gd`**: `make_decision` (~110 lines),
   `_make_tactical_maneuver_decision` (~110), `_analyze_combat_geometry`
   (~95).

## Done when

- `grep -nE "[0-9]+\.[0-9]" scripts/space/systems/collision_system.gd`
  shows constants only.
- No function in the listed files exceeds ~60 lines.
