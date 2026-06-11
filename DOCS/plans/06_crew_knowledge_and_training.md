# 06 — Crew knowledge, instructions, and training (the Football Manager direction)

**Vision**: the player manages at any altitude — fleet doctrine down to
standing instructions for an individual crew member — and crew improve
(or stagnate) through training and battle experience.

**Foundation already in place**: `data/knowledge/{role}.json` is the
single source of tactical patterns; `TacticalKnowledgeSystem` retrieves
the most situation-relevant patterns and the role AIs execute what the
pattern's `content` says, gated by skill. Editing a pattern changes
behavior today. Build increments on top of that — do not build a
parallel system.

## Increments (each independently shippable)

1. **Per-crew knowledge sets.** ✅ SHIPPED. Crew dicts carry
   `known_patterns` (empty = role baseline); `query_knowledge()`
   filters to it and the query cache keys on it. All six role-AI query
   sites pass the crew's set. Tests in `tests/test_crew_knowledge.gd`,
   including the done-criterion (identical pilots, different doctrine,
   different maneuvers).
2. **Player standing instructions.** ✅ SHIPPED (execution layer).
   `StandingInstructionsSystem` registers a player-authored pattern
   (same schema) with a priority flag — relevant instructions outrank
   doctrine, irrelevant ones stay silent, never visible to baseline
   crew — and adds it to the crew member's `known_patterns`. Roguelike
   crew persist across battles (`RoguelikeRun.fleet_crew`,
   `CrewData.reset_for_battle`), so instructions attach to a stable
   crew identity. Tests in `tests/test_standing_instructions.gd`,
   including the done-criterion (saved crew member with an instruction
   measurably changes maneuver choice vs an identical uninstructed
   pilot). The per-crew `user://standing_instructions/{crew_id}.json`
   files were a stopgap authoring surface; increment 2b replaces them
   with the run doctrine document below.
2b. **Fleet doctrine document + pre-battle authoring.** The
   interaction model below, minus polish: run-scoped doctrine state,
   the instruction template catalog, scope resolution compiled into
   `known_patterns` at battle spawn, and the crew roster created at
   run start so individuals are addressable pre-battle.
3. **Training regimes.** Between battles (roguelike fleet management
   screen), spend a resource to: add a pattern to `known_patterns`,
   raise a skill stat, or reduce a `skill_requirements` gate for one
   known pattern (drilling a specific maneuver). Battle experience can
   queue "candidate" patterns the crew member saw used against them.
4. **Outcome feedback.** `TacticalMemorySystem` already counts
   successful/failed tactics per crew member. Surface that in the
   battle log (plan 01) and fleet screen, and let it bias
   `calculate_relevance_score` — crew favor what has worked for them.

## Fleet doctrine: the interaction model

How the player actually touches instructions (agreed direction; these
behaviors define the feature, widget layout does not):

1. **Instructions are picked from a template catalog, never
   free-typed.** Players cannot author BM25 keyword text. A
   designer-authored catalog (`data/instruction_templates.json`) holds
   parameterized templates — "Keep distance from capitals: *800m*",
   "Prefer torpedo runs on *capitals*", "Disengage when damaged" —
   each carrying the pattern skeleton (tags/text/content with
   parameter substitution), the roles/ship classes it applies to, and
   its skill gates. Picking + tuning a template compiles to a normal
   pattern.
2. **Scope is the core interaction.** Every instruction is assigned at
   one of three altitudes: fleet-wide, role/ship-class, or individual
   crew member. One doctrine document per run — not files per crew.
3. **Inheritance with visible provenance.** Selecting a crew member
   shows their *effective* set: personal orders plus everything
   inherited from class and fleet, each labeled with its origin. More
   specific scope wins (individual > class > fleet); an overridden
   inherited instruction is shown as overridden, and the player can
   explicitly disable an inherited instruction for one individual
   ("everyone keeps distance, but Alpha may close").
4. **Capability is visible at assignment time.** If a crew member's
   skill is below an instruction's `skill_requirements` gate, the UI
   says so on the spot ("Gamma can't execute this — piloting 0.4,
   needs 0.6") instead of the order silently doing nothing in battle.
   This warning is the natural entry point for increment 3 training
   ("drill this").
5. **Doctrine is edited on the pre-battle fleet positioning screen**
   (`pre_battle.tscn`), not the fleet editor. Selecting a ship there
   is also the entry point to its crew's orders; no selection / a
   fleet header reaches fleet scope. Edits are committed when the
   battle starts: scope resolution runs once at spawn and lands in
   each crew member's `known_patterns` — the query engine stays dumb,
   precedence is resolved at compile time.
6. **Doctrine is run state, fresh each run.** It lives in
   `RoguelikeRun`, is wiped by `end_run()`, and nothing carries across
   runs. No profile-level presets for now.
7. **Evidence closes the loop** (increment 4): the same surface shows
   per-instruction outcomes from tactical memory ("Torpedo runs:
   ordered 12×, succeeded 3×") so doctrine is tuned from results.

**Code consequences:**
- The crew roster must be created at **run start**, not at battle
  spawn: the positioning screen currently works from fleet counts and
  crew don't exist until `space_battle.tscn` spawns them, so
  individuals would not be addressable pre-battle (and battle 1 would
  have no roster at all). Battle spawn then *binds* roster groups to
  hulls instead of creating crew. This also makes which ace flies
  which hull a pre-battle decision (the FM team sheet).
- `BattlePlan` entries gain the crew-group binding so individual
  orders land on the hull at the planned position.
- The `user://standing_instructions/` files and their load path are
  deleted once the doctrine document compiles to `known_patterns`
  (no legacy path retained). `apply_instructions` and the priority/
  leak semantics in `TacticalKnowledgeSystem` are unchanged — they
  are the compile target.

## Retrieval engine: keep or replace BM25?

Keep for now — it's small (~70 lines), tested, cached, and the
per-crew filtering above doesn't depend on it. Revisit only if logs
show bad pattern selection; the simple replacement is exact tag/
condition matching against the situation summary instead of word
overlap. Decide from battle-log evidence, not speculation.

## Done when (increment 2b, the next concrete step)

- The crew roster exists at run start and a doctrine document on
  `RoguelikeRun` holds template-instantiated instructions at fleet,
  class, and individual scope.
- Compiling doctrine at battle spawn puts the right pattern ids in
  each crew member's `known_patterns`, with individual > class >
  fleet precedence and per-individual disables honored — asserted by
  tests at each scope.
- The per-crew `user://standing_instructions/` files are gone.
