# Crew quality overhaul — plan index

Make crew stats **mechanically dramatic**. Today, an all-3 crew vs an
all-18 crew differs in pacing and formation only — turn rate, weapon
accuracy, weapon damage, and effective reaction time are identical
regardless of who is on the ship. Roughly 60% of the originally-planned
crew-stats system is computed-but-never-consumed code.

This sub-project wires up the disconnected modifiers, deletes vestigial
fields, consolidates the schema to six stats (`aim`, `piloting`,
`awareness`, `tactics`, `composure`, `aggression`), adds the missing
systems (detection latency, reaction latency, squadron plays), and
ships an always-on debug overlay so the differences are visible without
telemetry.

Run phases in order; each is one PR. Standards in
[`../README.md`](../README.md).

| # | File | Goal |
|---|---|---|
| 1 | [01_overview.md](01_overview.md) | Vision, six-stat model, role-read table, six acceptance scenarios (S1–S6), observability, risks, non-goals. **Read this first.** |
| 2 | [02_wire_modifiers.md](02_wire_modifiers.md) | Un-stub `WeaponSystem.calculate_final_accuracy`; plumb `crew_modifiers` into MovementSystem turn/accel/lateral/dampening; make SUBSYSTEM targeting actually target subsystems; ship the always-on debug overlay. |
| 3 | [03_awareness_detection.md](03_awareness_detection.md) | Stat rename + delete pass (drop `marksmanship` / `situational_awareness` / `anticipation` / legacy `skill` aggregate / `missile_locked` events). Threat prioritization. Mailbox `deliver_at` detection latency. |
| 4 | [04_pending_intent.md](04_pending_intent.md) | Pending-intent / reaction-latency system. Marquee feature: elite ~80 ms commit delay vs rookie ~700 ms. Composure-stress modulation. |
| 5 | [05_squadron_plays.md](05_squadron_plays.md) | Squadron plays as data (pincer, bracket, kill-box). Leader picks; wingmen consume orders. Execution scatter by leader's `tactics`. |
| 6 | [06_captain_damage_control.md](06_captain_damage_control.md) | Captain aspect rotation, weapon spool, withdraw decisions, damage-control speed. |
| 7 | [07_stress_per_stat.md](07_stress_per_stat.md) | Per-stat stress/fatigue decay. Composure as saving throw. Activates `base→eff` notation in the debug overlay. |

## Relationship to `crew_ai_rework/`

`crew_ai_rework/` lays down per-role FSMs, personality axes, and
interrupts. This sub-project plugs the **stat side** into them: where
`crew_ai_rework/` decides "the gunner enters firing_burst phase," this
sub-project decides "how accurate that burst actually is, given the
gunner's `aim` minus stress decay."

Some phases here can run in parallel with the corresponding
`crew_ai_rework/` phase; some depend on it. Phase 02 here (wire-up)
has no dependency on the rework. Phases 04–07 benefit from at least
the structural Phase 0 split being complete (already done).
