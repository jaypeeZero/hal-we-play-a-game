# Tactical Knowledge System

## System Overview

The tactical knowledge system provides AI crew members with retrievable tactical guidance during combat. The system consists of three components:

1. **TacticalKnowledgeSystem** - BM25-based knowledge retrieval (`scripts/space/systems/tactical_knowledge_system.gd`)
2. **TacticalMemorySystem** - Situation summarization and experience tracking (`scripts/space/systems/tactical_memory_system.gd`)
3. **KnowledgeLoader** - JSON file loading (`scripts/space/systems/knowledge_loader.gd`)

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

**Function**: `query_knowledge(situation: String, role: int, top_k: int = 3) -> Array`

Performs BM25-style text matching:

```
score = (matching_terms / total_query_terms) + (0.2 * matching_tags)
```

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
- `query_pilot_knowledge(situation, top_k)`
- `query_gunner_knowledge(situation, top_k)`
- `query_captain_knowledge(situation, top_k)`
- `query_squadron_knowledge(situation, top_k)`
- `query_commander_knowledge(situation, top_k)`

**Cache**: Results cached by `"{situation}_{role}_{top_k}"` key. Cache cleared when size exceeds 50 entries.

### KnowledgeLoader

**Location**: `scripts/space/systems/knowledge_loader.gd`

**Function**: `initialize_knowledge_base() -> void`

Called at game startup. Loads JSON files from `res://data/knowledgebase/annotated/`. Falls back to `res://data/knowledgebase/complete/` if annotated directory fails.

**Role Assignment**: Determined by keyword scoring in entry text:

| Keywords | Role |
|----------|------|
| thrust, maneuver, velocity, trajectory | PILOT |
| weapon, firing, target | GUNNER |
| tactical, combat, awareness | CAPTAIN |
| multi-ship, coordination | SQUADRON_LEADER |
| strategic, fleet | FLEET_COMMANDER |

## Knowledge Entry Format

**Location**: `data/knowledgebase/annotated/*.json`

```json
{
    "id": "pilot_perpendicular_evasion",
    "title": "Perpendicular Evasion Burn",
    "category": "piloting",
    "summary": "Brief description",
    "details": "Full tactical guidance text",
    "annotations": ["Developer note 1", "Developer note 2"]
}
```

**Fields used by system**:
- `id` - Pattern identifier
- `title`, `summary`, `details`, `annotations` - Concatenated for BM25 text indexing
- `category` - Used for tag generation

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
