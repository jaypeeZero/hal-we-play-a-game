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
2. **Player standing instructions.** A player-authored pattern (same
   schema) injected into a crew member's set with a priority flag —
   "prefer torpedo runs on capitals", "never close below 800". UI can
   come later; start with a JSON file per saved crew member in the
   roguelike run.
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

## Done when (increment 2, the next concrete step)

- A saved roguelike crew member carries a player-authored pattern that
  measurably changes their behavior in battle, and a test asserts it.
