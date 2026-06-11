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
2. **Player standing instructions.** ✅ SHIPPED. A player-authored
   pattern (same schema) lives in
   `user://standing_instructions/{crew_id}.json`;
   `StandingInstructionsSystem` registers it with a priority flag
   (relevant instructions outrank doctrine; irrelevant ones stay
   silent; never visible to baseline crew) and adds it to the crew
   member's `known_patterns`. Roguelike crew now persist across
   battles (`RoguelikeRun.fleet_crew`, `CrewData.reset_for_battle`),
   so instructions attach to a stable crew identity. UI comes later.
   Tests in `tests/test_standing_instructions.gd`, including the
   done-criterion (saved crew member with an instruction measurably
   changes maneuver choice vs an identical uninstructed pilot).
3. **Training regimes.** Between battles (roguelike fleet management
   screen), spend a resource to: add a pattern to `known_patterns`,
   raise a skill stat, or reduce a `skill_requirements` gate for one
   known pattern (drilling a specific maneuver). Battle experience can
   queue "candidate" patterns the crew member saw used against them.
4. **Outcome feedback.** `TacticalMemorySystem` already counts
   successful/failed tactics per crew member. Surface that in the
   battle log (plan 01) and fleet screen, and let it bias
   `calculate_relevance_score` — crew favor what has worked for them.

## Retrieval engine: keep or replace BM25?

Keep for now — it's small (~70 lines), tested, cached, and the
per-crew filtering above doesn't depend on it. Revisit only if logs
show bad pattern selection; the simple replacement is exact tag/
condition matching against the situation summary instead of word
overlap. Decide from battle-log evidence, not speculation.

## Done when (increment 3, the next concrete step)

- On the fleet management screen between battles, spending a training
  resource on a saved crew member adds a pattern to their
  `known_patterns` (or raises a skill / lowers a known pattern's
  `skill_requirements` gate), the change persists into the next
  battle, and a test asserts it.
