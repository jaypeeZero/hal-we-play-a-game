# Crew Quality Overhaul — Overview

## Goal

Make crew-stat differences **visible in battle**. Today, all-3 vs all-18
crew differs in pacing and formation only; turn rate, weapon accuracy,
weapon damage, and effective reaction time are identical regardless of
who is on the ship. Roughly 60% of the originally-planned crew-stats
system is computed-but-never-consumed code (modifiers written to
`ship_data.crew_modifiers` and silently discarded by MovementSystem and
WeaponSystem).

This overhaul wires up the disconnected modifiers, deletes vestigial
fields, consolidates the stat schema, and adds the missing systems
(awareness/detection latency, reaction latency, squadron plays) so a
great crew is **mechanically dramatic** vs a bad crew.

The work spans six implementation phases (02–07 in this folder). This
file is the design overview; each phase has its own file with the
concrete edits.

## Vision — what "great vs bad" looks like

These scenarios are the acceptance criteria. Each must reproduce in a
deterministic test scenario after the relevant phase ships.

**S1 — The First Burst (Phase 04).** Two fighters merge at equal hull and
loadout. The elite pilot's high `awareness` fires `threat_appeared`
early; his pilot reaction commits the break-turn ~80 ms after the bandit
lines up the shot. The rookie's `threat_appeared` fires late (low
awareness range) and his reaction commits ~700 ms later — by which
time the bandit's first burst has connected. *Observable: time from
`threat_appeared` to evasion-intent commit; first-burst hit-rate per
skill bucket.*

**S1b — Shaken by the Hit (Phase 04).** First `ship_damaged` event arrives.
Elite pilot reacts in ~100 ms with a corkscrew break. Rookie pilot's
reaction lag is gated additionally by panic (low composure × incoming-
damage stress) and commits 1.2 s later, eating a second burst.

**S2 — The Knife Fight (Phase 02).** Two fighters of equal hull/weapons,
elite vs rookie pilot. The elite out-turns the rookie inside 8 s —
visibly tighter circles, less bleed-off, lateral thrust feathered. The
rookie flies in straight arcs. *Observable: average angle-off-tail per
second; turn-rate trace.*

**S3 — Surgical vs Spray (Phase 02).** Elite gunner with PREDICTIVE/
SUBSYSTEM targeting style lands 60–75% of shots on a maneuvering target
at 4 km; rookie at SIMPLE lands under 15%. Subsystem hits actually
disable engines/turrets. *Observable: hit-rate per skill bucket;
subsystem-disable events.*

**S4 — Coordinated Pincer (Phase 05).** Elite squadron leader splits the
wing: pair A engages frontally at extended range while pair B loops wide
and re-enters at the target's six. Rookie squadron all merges on the
same target from the same vector. *Observable: wing-vector dispersion at
engagement; fraction of kills with `attacker_aspect=rear`.*

**S5 — Captain Reads the Room (Phase 06).** Elite captain at 40% hull
rotates the ship to present armored side, spools point-defense, and
signals withdrawal at +0.2 s after a torpedo wave is detected. Rookie
captain keeps charging the bow at the wave. *Observable: aspect-vs-
incoming-fire; PDC-up time before missile arrival; withdraw-decision
latency.*

**S6 — Damage Control Race (Phase 06).** Two identical capitals take
identical hits to the engine room. Elite captain (high `tactics`)
restores 70% engine output in 12 s; rookie restores 30% in 25 s. The
elite ship escapes; the rookie is overrun. *Observable: time-to-restore
vs damage events.*

## Stat model

Floats `0.0–1.0` internally; rendered `0–20` in UI/logs. Existing
modifier math already does `lerp(MIN, MAX, skill)`; converting to ints
buys nothing. Display is `int(round(stat * 20))`.

**One stat block per crew member.** Six stats, every one mechanically
wired. What changes by role is *which stats are read*.

| Stat | Controls |
|---|---|
| `aim` | Weapon accuracy, lead quality, targeting-style unlock, subsystem-aim. Pilot reads it for fixed forward weapons; gunner reads it for turrets. |
| `piloting` | Effective turn rate, acceleration, lateral thrust, dampening tightness, jink quality, evasion commit delay. |
| `awareness` | Sensor range, threat-detection latency, threat prioritization quality. |
| `tactics` | Captain command-style unlock, squadron coordination tier, retreat/aspect decisions, target prioritization, damage-control speed. |
| `composure` | Performance under stress; gates panic state, slows degradation of all other stats under stress. |
| `aggression` | Engagement-range biasing, target-persistence, withdraw threshold, approach-style. **Personality dial — higher isn't better.** |

`marksmanship`, `situational_awareness`, `anticipation`, and the legacy
aggregate `skill` are **deleted**. No aliases. No fallbacks.

### Role-sensitive reads

| Role | Primary | Secondary | Mostly ignored |
|---|---|---|---|
| Pilot (fighter) | `piloting`, `awareness` | `aim`, `composure`, `aggression`, `tactics` | — |
| Pilot (capital) | `piloting`, `tactics` | `awareness`, `composure`, `aggression` | `aim` |
| Gunner | `aim`, `awareness` | `composure` | `piloting`, `tactics`, `aggression` |
| Captain | `tactics`, `awareness` | `composure`, `aggression` | `aim`, `piloting` |
| Squadron Leader | `tactics`, `awareness` | `composure`, `aggression` | `piloting`, `aim` |
| Fleet Commander | `tactics`, `awareness` | `composure` | rest |

The fighter pilot's secondary `aim` matters: a hot-stick / can't-shoot
pilot performs differently from a steady-hands / can't-fly pilot. Both
differ from a great gunner stuck on a sluggish capital.

### Stress / fatigue interaction

Replace the global `effective = skill - stress*0.3 - fatigue*0.2`
(`crew_ai_system.gd:66`) with per-stat decay rates:

```
effective(stat) = base * (1 − effective_stress * decay[stat]
                              − fatigue * fdecay[stat])
where effective_stress = max(0, stress − composure * 0.4)
```

- `aim`, `piloting`: high stress decay (twitch tasks).
- `tactics`, `awareness`: medium decay.
- `composure`, `aggression`: zero stress decay (they ARE the stress
  system).

Constants live in `wing_constants.gd` as `STAT_STRESS_DECAY` and
`STAT_FATIGUE_DECAY` dictionaries.

## Observability

### BattleEventLogger additions

Add these standardized events:

- `crew_skill_snapshot` — emitted at battle start for each crew with all
  stats + role + ship_id. Enables post-hoc "which skills explained the
  win" analysis.
- `threat_detected` — `{crew_id, threat_id, latency_ms}`.
- `decision_committed` — `{crew_id, intent, decided_at, commit_at}`.
- `subsystem_targeted` — `{shooter_crew_id, target_ship_id, subsystem,
  hit, damage}`.
- `play_executed` — `{leader_crew_id, play_id, fighters, success}`
  (Phase 05).
- `evasion_outcome` — `{crew_id, threat_id, outcome:dodged|hit|grazed,
  latency_ms}` (Phase 04).

### Regression harness

`tests/test_skill_dominance_regression.gd`:

- `simulate_battle(elite_crew, rookie_crew, seed)` — headless tick loop.
- 50 trials per matchup; matchup classes: 1v1 fighter, 6v6 squadron,
  capital duel, mixed fleet.
- Asserts per-matchup minimum win-rate floors (elite ≥ 70% for fighter
  1v1, ≥ 65% for squadrons, etc.).

### Debug overlay — floating crew table

**Always on. No toggle.** Added in Phase 02.

Per ship, render a small table in screen space anchored to the ship's
bottom-right hull corner with a pixel offset so it sits just outside
the sprite. Clamp to viewport edges so it never clips off-screen. Stats
shown 0–20 with color gradient (red 0–6, yellow 7–13, green 14–20).

```
       | aim | piloting | awareness | tactics | composure | aggression
pilot  |  7  |    18    |    16     |   12    |    14     |    11
gunner | 17  |     8    |    13     |    9    |    15     |    10
capt'n | 12  |    11    |    19     |   18    |    17     |     8
```

- Header row: six stats. Role column left-aligned, narrow.
- Effective values (post stress/fatigue) shown as `18→14` when
  different, color-graded by delta. Single number when no degradation.
- Cell for a stat the role doesn't read is dimmed gray — visually
  distinguishes "high but unused" from "high and used."
- Below the table, a single line for ship-level state when any crew has
  stress > 0.1; otherwise omitted.

Implementation: render in screen space from world-space hull-bbox
bottom-right via `Camera2D.unproject_position`. Single `Control` per
ship parented to the overlay layer, repositioned each frame —
**don't parent under the ship node** (rotation and culling fight you).

## Risks & non-goals

### Performance
- `crew_modifiers` reads in MovementSystem hot path are a single dict
  lookup with default — ~free.
- Pending-intent layer adds one Array scan per frame, O(ships) —
  negligible.
- Threat prioritization runs only on crew wake (event-driven scheduler
  protects us).
- Subsystem-aim adds a `find_best_subsystem(target)` call per fire
  decision for SUBSYSTEM-tier gunners only — rare and cheap.

Don't preemptively micro-optimize. Profile if anything regresses.

### "Elite always wins, watching is boring"

Mitigations baked in:

1. `aggression` is not skill. Two elite squadrons with high vs low
   aggression fight differently — close-range knife vs long-range
   standoff. Variety at top end.
2. Stress hurts elites too. The 2nd / 3rd consecutive engagement
   reduces effective stats — "veteran fleet that's been fighting all
   day" ≠ "fresh veteran fleet."
3. Composure-stress interaction creates upset potential. Low-composure
   ace in a panic moment performs at rookie level.
4. Numerical ranges deliberately not min-maxed. Elite aim is 130%
   accuracy, not 300%. Rookies still score hits.
5. Subsystem hits create asymmetric outcomes. A rookie who lands one
   lucky engine shot can win vs an elite who rolled high accuracy on
   hull plating.

### Explicit non-goals

- **Don't resurrect every old field.** `marksmanship`,
  `situational_awareness`, `anticipation`, the legacy `skill` aggregate
  — *delete*, no aliases.
- **Don't add stats with no mechanical hook.** If a stat doesn't appear
  in §3.5 of a phase plan, it doesn't exist.
- **Don't gate cosmetic content by skill.** Mechanical hook is the
  only justification.
- **Don't build complex order-relay simulation.** A single
  `order_clarity` knob is the whole feature.
- **Don't rebuild MovementSystem.** Touch only the four hot lines.
- **Don't deepen scheduler architecture.** It's correct. Pending-intent
  sits *next* to it, not inside it.
- **Don't keep `missile_locked` event handling.** Missile lock is not
  a real game mechanic; reaction-latency triggers off `threat_appeared`
  and `ship_damaged` instead. Delete the dead branches.
- **Don't write a back-compat shim for `calculate_effective_skill`.**
  Single-arg form goes away when the per-stat form lands. Update all
  callers in the same change.

## Phase index

| # | File | Goal |
|---|---|---|
| 01 | this file | Overview, stat model, scenarios, observability |
| 02 | [02_wire_modifiers.md](02_wire_modifiers.md) | Wire WeaponSystem accuracy + MovementSystem modifiers + SUBSYSTEM targeting + always-on debug overlay |
| 03 | [03_awareness_detection.md](03_awareness_detection.md) | Stat rename pass, threat prioritization, mailbox detection latency |
| 04 | [04_pending_intent.md](04_pending_intent.md) | Pending-intent / reaction-latency system |
| 05 | [05_squadron_plays.md](05_squadron_plays.md) | Squadron plays (pincer, bracket, kill-box) |
| 06 | [06_captain_damage_control.md](06_captain_damage_control.md) | Captain ship-aspect, withdraw decisions, damage control |
| 07 | [07_stress_per_stat.md](07_stress_per_stat.md) | Per-stat stress/fatigue decay, composure as saving throw |
