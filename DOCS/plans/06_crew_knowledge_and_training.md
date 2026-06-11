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
   Player-authored patterns register with a priority flag — relevant
   instructions outrank doctrine, irrelevant ones stay silent, never
   visible to baseline crew — and land in the crew member's
   `known_patterns`. Roguelike crew persist across battles
   (`RoguelikeRun.fleet_crew`, `CrewData.reset_for_battle`), so
   instructions attach to a stable crew identity. The stopgap per-crew
   `user://standing_instructions/` files were replaced by increment 2b.
2b. **Fleet doctrine document + pre-battle authoring.** ✅ SHIPPED.
   `DoctrineSystem` + `data/instruction_templates.json` implement the
   interaction model below: doctrine is run state
   (`RoguelikeRun.doctrine`), the crew roster is created at run start
   (callsigns, `RoguelikeRun._create_fleet_roster`), and
   `compile_for_crew()` resolves scopes into `known_patterns` at
   battle spawn. `DoctrinePanel` on the pre-battle positioning screen
   is the dropdown-driven editor (ship dropdown = scope selector,
   synced two-way with map clicks; crew addressed only via the crew
   dropdown). Tests in `tests/test_doctrine_system.gd` (scopes,
   overrides, disables, recompile lifecycle, done-criterion) and
   `tests/test_doctrine_panel.gd` (dropdown behaviors).
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

Shipped — feature documentation lives in `DOCS/fleet_doctrine.md`.
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
   (`pre_battle.tscn`), not the fleet editor, and the editor is
   dropdown-driven: the ship dropdown is the scope selector ("Entire
   fleet" / "All fighters" / individual hulls), clicking a ship on the
   map syncs the dropdown and vice versa, and a hull's crew are
   operated on only through the crew dropdown — never by clicking the
   ship visual. Edits are committed when the battle starts: scope
   resolution runs once at spawn and lands in each crew member's
   `known_patterns` — the query engine stays dumb, precedence is
   resolved at compile time.
6. **Doctrine is run state, fresh each run.** It lives in
   `RoguelikeRun`, is wiped by `end_run()`, and nothing carries across
   runs. No profile-level presets for now.
7. **Evidence closes the loop** (increment 4): the same surface shows
   per-instruction outcomes from tactical memory ("Torpedo runs:
   ordered 12×, succeeded 3×") so doctrine is tuned from results.

**Code consequences (as built):**
- The crew roster is created at **run start** (the positioning screen
  works from fleet counts; crew otherwise wouldn't exist before
  battle 1). Battle spawn *binds* roster groups to hulls instead of
  creating crew.
- Entry↔crew binding is an ordering contract, not a `BattlePlan`
  schema change: ships spawn in plan-entry order and
  `take_saved_crew()` pops the first remaining group of the type, so
  the n-th entry of a type gets the n-th group.
  `DoctrineSystem.map_entries_to_crew_groups` computes the same
  mapping for the UI.
- The `user://standing_instructions/` files and their system were
  deleted (no legacy path). `DoctrineSystem._apply_patterns` is the
  compile target; the priority/leak semantics in
  `TacticalKnowledgeSystem` are unchanged. Baseline expansion skips
  `player_priority` patterns so one crew member's compiled orders
  never enter another's baseline.

## Retrieval engine: keep or replace BM25?

Keep for now — it's small (~70 lines), tested, cached, and the
per-crew filtering above doesn't depend on it. Revisit only if logs
show bad pattern selection; the simple replacement is exact tag/
condition matching against the situation summary instead of word
overlap. Decide from battle-log evidence, not speculation.

## Done when (increment 3, the next concrete step)

- Between battles, spending a training resource on a roster crew
  member adds a template/pattern to their `known_patterns`, raises a
  skill, or lowers a known pattern's `skill_requirements` gate — the
  change persists into the next battle and a test asserts it. The
  doctrine panel's "can't execute yet" warning is the natural entry
  point ("drill this").
