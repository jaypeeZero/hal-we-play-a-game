# Tactical Knowledge System

## System Overview

The tactical knowledge system provides AI crew members with retrievable tactical guidance during combat. The system consists of two components:

1. **TacticalKnowledgeSystem** - BM25-based knowledge retrieval (`scripts/space/systems/tactical_knowledge_system.gd`); lazily loads patterns from `data/knowledge/*.json` (one file per crew role) on first query
2. **TacticalMemorySystem** - Situation summarization and experience tracking (`scripts/space/systems/tactical_memory_system.gd`)

The JSON files are the single source of tactical knowledge: editing a pattern's `content` (maneuvers, skill requirements, priorities) directly changes what the AI does. This is the foundation for future per-crew knowledge, player-issued standing instructions, and training.

## Data Flow

```
CrewAISystem.make_decision()
    │
    ├─► TacticalMemorySystem.generate_situation_summary(crew_data)
    │       Returns: String (e.g., "piloting close enemy incoming fire evasion")
    │
    ├─► TacticalKnowledgeSystem.query_knowledge(situation, role, top_k)
    │       Returns: Array of matching knowledge entries sorted by relevance score
    │
    └─► Decision made using knowledge content + crew experience data
```

## Component Details

### TacticalMemorySystem

**Location**: `scripts/space/systems/tactical_memory_system.gd`

**Function**: `generate_situation_summary(crew_data: Dictionary) -> String`

Converts crew state into searchable text by concatenating:

| Source | Example Output |
|--------|----------------|
| Role | `"piloting navigation"` (PILOT), `"gunnery targeting"` (GUNNER), `"tactics coordination"` (CAPTAIN) |
| Threats | `"close enemy immediate danger"` (high priority), `"incoming fire"` (projectile) |
| Opportunities | `"damaged enemy target"`, `"disabled enemy opportunity"` |
| Recent Events | `"under fire"` (took damage), `"combat"` (fired weapons) |
| Current Orders | `"evasion"`, `"pursuit"`, `"retreat"` |

**Function**: `get_tactic_success_rate(crew_data: Dictionary, tactic_id: String) -> float`

Returns success rate (0.0-1.0) for a specific tactic based on crew's recorded outcomes. Returns 0.5 if tactic has not been tried.

**Function**: `record_decision_outcome(crew_data: Dictionary, decision: Dictionary, success: bool) -> Dictionary`

Increments success or failure counter for the tactic. Tactic ID format: `"{type}_{subtype}"` (e.g., `"maneuver_perpendicular_burn"`).

### TacticalKnowledgeSystem

**Location**: `scripts/space/systems/tactical_knowledge_system.gd`

**Function**: `query_knowledge(situation: String, role: int, top_k: int = 3, known_patterns: Array = []) -> Array`

`known_patterns` restricts retrieval to the pattern ids a specific crew member knows; an empty array means the full role baseline (doctrine from the JSON files only — player-authored patterns are never part of the baseline).

Performs BM25-style text matching:

```
score = (matching_terms / total_query_terms) + (0.2 * matching_tags)
```

Player-authored patterns (standing instructions, registered with `player_priority`) additionally receive `PLAYER_INSTRUCTION_SCORE_BONUS` when — and only when — their base score is above zero: a relevant instruction always outranks doctrine, an irrelevant one stays silent.

Returns array of dictionaries:
```gdscript
{
    "pattern_id": String,
    "score": float,
    "content": Dictionary,  # From JSON entry
    "tags": Array
}
```

**Role-specific convenience functions**:
- `query_pilot_knowledge(situation, top_k, known_patterns)`
- `query_gunner_knowledge(situation, top_k, known_patterns)`
- `query_captain_knowledge(situation, top_k, known_patterns)`
- `query_squadron_knowledge(situation, top_k, known_patterns)`
- `query_commander_knowledge(situation, top_k, known_patterns)`

**Cache**: Results cached by `"{situation}_{role}_{top_k}_{known_patterns.hash()}"` key. Cache cleared when size exceeds 50 entries.

### DoctrineSystem

**Location**: `scripts/space/systems/doctrine_system.gd`

Player standing instructions for the roguelike run (plan 06). Players pick parameterized templates from `data/instruction_templates.json` (never authoring pattern text) and assign them at fleet, ship-class, or individual-crew scope; the doctrine lives on `RoguelikeRun.doctrine` and is edited via the `DoctrinePanel` dropdowns on the pre-battle positioning screen. At battle spawn `compile_for_crew()` resolves scopes (individual > class > fleet per template, per-crew disables honored), instantiates each template into a normal pattern, registers it with the `player_priority` flag (namespaced `doctrine__{crew_id}__{template_id}`), and adds it to the crew member's `known_patterns` — expanding an empty set to the explicit role baseline first (player-priority patterns excluded) so standing orders extend role doctrine rather than replace it. Previously compiled doctrine ids are stripped on every compile, so instructions removed between battles do not linger.

## Knowledge Entry Format

**Location**: `data/knowledge/{role}.json` — one file per role (`pilot.json`, `gunner.json`, `captain.json`, `squadron_leader.json`, `fleet_commander.json`)

```json
{
    "role": "pilot",
    "patterns": {
        "fighter_flank_mid": {
            "tags": ["fighter", "flank", "mid", "tactical", "positioning"],
            "text": "fighter mid range flank behind position tactical maneuver angle",
            "content": {
                "maneuvers": ["fight_flank_behind", "fight_pursue_tactical"],
                "skill_requirements": {"fight_flank_behind": 0.6, "fight_pursue_tactical": 0.3},
                "priority": "tactical",
                "context": "Get behind enemy at mid range"
            }
        }
    }
}
```

**Fields**:
- `tags` - Boost relevance score when present in the situation string
- `text` - Keyword soup matched against the situation string (BM25)
- `content` - The actionable payload. For pilots: `maneuvers` (ordered best-first) and `skill_requirements`/`composure_requirements` gates. Other roles carry role-specific keys (e.g., captain patterns carry `actions`/`conditions`). This is what the AI actually executes — change it and behavior changes.

## Crew Experience Data Structure

Stored in `crew_data.awareness.tactical_memory`:

```gdscript
{
    "recent_events": [],           # Last 10 battle events
    "current_situation": "",       # Cached situation summary
    "successful_tactics": {},      # {"tactic_id": count}
    "failed_tactics": {}           # {"tactic_id": count}
}
```

## Performance Configuration (if needed)

- `TacticalKnowledgeSystem.enable_knowledge_queries`: Set to `false` to disable all queries
- `MAX_CACHE_SIZE`: 50 entries before cache clear
- `MAX_RECENT_EVENTS`: 10 events per crew member
