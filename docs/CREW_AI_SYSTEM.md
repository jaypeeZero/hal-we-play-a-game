# Crew AI System

A hierarchical AI system where individual crew members make decisions based on their role, stats, and awareness. Fleet battles come down to human-level decisions propagating through a command chain.

## Overview

The Crew AI System implements a hierarchical command structure where:
- **Information flows UP** the chain (subordinates report to superiors)
- **Orders flow DOWN** the chain (superiors command subordinates)
- Each crew member makes decisions based on their **role**, **stats**, and **awareness**
- Individual "human" decisions combine to create emergent fleet behavior

## Architecture

Built on the pure ECS architecture:
- **Entities**: Crew members are data dictionaries (like ship_data)
- **Components**: Stats, awareness, orders, command chain relationships
- **Systems**: Pure functional systems that process crew data

### Core Components

```
scripts/space/data/crew_data.gd          # Crew factory and templates
scripts/space/systems/information_system.gd     # Awareness and sensors
scripts/space/systems/crew_ai_system.gd         # Decision making
scripts/space/systems/command_chain_system.gd   # Order passing
scripts/space/systems/crew_integration_system.gd # Ship integration
```

## Crew Roles

### Pilot
- **Decisions**: Evasive maneuvers, pursuit, tactical positioning
- **Awareness**: Medium range, focuses on immediate threats
- **Stats**: Fast reaction time, quick decisions
- **Solo fighter**: Acts autonomously as their own commander

### Gunner
- **Decisions**: Target selection within weapon arc
- **Awareness**: Weapon-range focused
- **Stats**: Accuracy-focused, moderate reaction time
- **Reports to**: Captain

### Captain
- **Decisions**: Ship-level tactics, crew coordination
- **Awareness**: Broad tactical view of battlefield
- **Stats**: Slower reaction but better strategic thinking
- **Commands**: Pilot and gunners on their ship

### Squadron Leader
- **Decisions**: Multi-ship coordination, target prioritization
- **Awareness**: Squadron-wide view
- **Stats**: Strategic focus, longer decision time
- **Commands**: Multiple ship captains

### Fleet Commander
- **Decisions**: Strategic fleet positioning and objectives
- **Awareness**: Strategic map view
- **Stats**: Highest-level thinking, slowest reaction
- **Commands**: Squadron leaders or individual ships

## Crew Stats

Each crew member has stats that affect their performance:

```gdscript
{
  "skill": 0.8,              # 0.0-1.0, base competency
  "reaction_time": 0.2,       # Seconds to react to events
  "awareness_range": 1000.0,  # Detection range
  "decision_time": 0.5,       # Time to make complex decisions
  "stress": 0.0,              # 0.0-1.0, increases in combat
  "fatigue": 0.0              # 0.0-1.0, increases over time
}
```

**Skill affects**:
- Decision quality (better target selection, positioning)
- Ship performance (pilots: turn rate, gunners: accuracy)
- Reaction and decision speed

**Stress** (combat pressure):
- Increases near threats
- Reduces effective skill (up to 30% penalty)
- Slows decision making
- Decays slowly when safe

**Fatigue** (time in combat):
- Increases gradually over time
- Reduces effective skill (up to 20% penalty)
- Persistent effect

## System Flow

The game loop processes crew AI in this order:

### 1. Information Gathering (`InformationSystem`)
```gdscript
var updated_crew = InformationSystem.update_all_crew_awareness(
    crew_list, ships, projectiles, game_time
)
```

Each crew member:
- Detects entities within their `awareness_range`
- Identifies **threats** (enemies, incoming fire)
- Identifies **opportunities** (good targets, tactical advantages)
- Prioritizes based on distance, type, status

### 2. Command Chain Communication (`CommandChainSystem`)
```gdscript
updated_crew = CommandChainSystem.process_command_chain(updated_crew)
```

**Information up**:
- Subordinates share their awareness with superiors
- Superiors gain broader tactical/strategic view
- Higher ranks track more entities

**Orders down**:
- Superiors issue orders to subordinates
- Orders are specific to recipient's role
- Each crew member can only receive one order at a time

### 3. Decision Making (`CrewAISystem`)
```gdscript
var ai_result = CrewAISystem.update_all_crew(updated_crew, delta, game_time)
updated_crew = ai_result.crew_list
var decisions = ai_result.decisions
```

Each crew member:
- Checks for orders from superior (higher priority)
- Makes role-appropriate decision based on awareness
- Generates action with delay based on stats
- Issues orders to subordinates if applicable

### 4. Integration with Ships (`CrewIntegrationSystem`)
```gdscript
var result = CrewIntegrationSystem.apply_crew_decisions_to_ships(
    ships, updated_crew, decisions
)
var updated_ships = result.ships
var actions = result.actions
```

Crew decisions modify ship behavior:
- Pilot decisions → ship movement orders and turn rate modifiers
- Gunner decisions → weapon target selection and accuracy modifiers
- Captain decisions → overall ship tactics and coordination bonuses

## Usage Examples

### Creating Crew

**Solo fighter**:
```gdscript
var crew = CrewData.create_solo_fighter_crew(0.7)  # 0.7 skill level
```

**Ship with crew**:
```gdscript
var weapon_count = 2
var crew = CrewData.create_ship_crew(weapon_count, 0.8)
# Returns: [captain, pilot, gunner1, gunner2]
```

**Squadron**:
```gdscript
var ship_count = 3
var weapons_per_ship = 2
var squadron = CrewData.create_squadron(ship_count, weapons_per_ship, 0.75)
# Returns: [squadron_leader, ship1_crew..., ship2_crew..., ship3_crew...]
```

**With ships**:
```gdscript
# Automatically creates appropriate crew
var ship = ShipData.create_ship_instance(
    "corvette",      # ship type
    0,               # team
    Vector2(0, 0),   # position
    true,            # create_crew
    0.7              # crew skill level
)
# ship.crew contains the crew array
```

### Assigning Crew to Entities

```gdscript
var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.8)
pilot.assigned_to = "ship_123"  # Must match ship_data.ship_id
```

### Manual Command Chain Setup

```gdscript
var captain = CrewData.create_crew_member(CrewData.Role.CAPTAIN, 0.8)
var pilot = CrewData.create_crew_member(CrewData.Role.PILOT, 0.7)

# Link them
pilot.command_chain.superior = captain.crew_id
captain.command_chain.subordinates.append(pilot.crew_id)
```

### Processing Full AI Cycle

```gdscript
# In your game loop _process(delta):

# 1. Gather information
all_crew = InformationSystem.update_all_crew_awareness(
    all_crew, ships, projectiles, current_game_time
)

# 2. Process command chain
all_crew = CommandChainSystem.process_command_chain(all_crew)

# 3. Make decisions
var ai_result = CrewAISystem.update_all_crew(all_crew, delta, current_game_time)
all_crew = ai_result.crew_list
var decisions = ai_result.decisions

# 4. Apply to ships
var integration = CrewIntegrationSystem.apply_crew_decisions_to_ships(
    ships, all_crew, decisions
)
ships = integration.ships

# 5. Process ship systems (movement, weapons, etc.)
# MovementSystem and WeaponSystem will use crew-modified stats
```

## Decision Examples

### Pilot Decision Flow

1. **Check for orders**: Has captain issued an order?
   - Yes → Execute order (pursue, evade, withdraw)
   - No → Make autonomous decision

2. **Autonomous decision**:
   - Has threats? → Evasive maneuver
   - Has opportunities? → Pursuit
   - Nothing? → Hold position

3. **Generate decision**:
```gdscript
{
  "type": "maneuver",
  "subtype": "evade",  # or "pursue"
  "crew_id": "crew_123",
  "entity_id": "ship_456",
  "target_id": "enemy_789",
  "skill_factor": 0.85,  # Effective skill after stress/fatigue
  "delay": 0.15,         # Reaction time
  "timestamp": 10.5
}
```

### Captain Decision Flow

1. **Check for orders**: Squadron leader ordering this ship?
   - Yes → Process and break down for crew
   - No → Assess tactical situation

2. **Tactical assessment**:
   - Analyze threats vs opportunities
   - Select best target
   - Determine ship-level tactics (engage, withdraw, hold)

3. **Issue orders to crew**:
```gdscript
{
  "to": "pilot_001",
  "type": "engage",
  "subtype": "pursue",
  "target_id": "enemy_789"
}
{
  "to": "gunner_002",
  "type": "engage",
  "target_id": "enemy_789"
}
```

### Squadron Leader Flow

1. **Receive awareness from all captains**
   - Aggregate threat lists
   - Identify highest-value targets

2. **Assign targets to ships**:
```gdscript
# Target 1 → Ship A
# Target 2 → Ship B
# Target 3 → Ship C
```

3. **Issue orders to captains**:
```gdscript
{
  "to": "captain_A",
  "type": "engage",
  "target_id": "enemy_1"
}
```

## Performance Characteristics

### Memory
- Each crew member: ~1KB of data
- Typical corvette (4 crew): ~4KB
- Squadron (3 ships, 12 crew): ~12KB

### Processing
- All systems are O(n) on crew count
- Information gathering: O(n * m) where m = visible entities
- Command chain: O(n) per level of hierarchy
- Decision making: O(n) with role-specific branching
- Integration: O(n) decisions

### Optimization Tips
1. **Limit awareness**: Higher ranks see more, but limit list sizes
2. **Decision throttling**: Add minimum time between decisions per crew
3. **Hierarchical updates**: Update higher ranks less frequently
4. **Spatial partitioning**: Only check awareness for nearby entities

## Design Philosophy

### Simple AI, Complex Behavior
Each crew member follows simple rules:
- Pilots: "Avoid danger, chase targets"
- Gunners: "Shoot best available target"
- Captains: "Pick tactics, coordinate crew"

Emergence comes from:
- Multiple crew members interacting
- Information flowing through hierarchy
- Individual stats creating variation

### Human-Like Decision Making
- **Reaction time**: Not instant, varies by skill
- **Decision time**: Complex decisions take longer
- **Imperfect information**: Limited awareness range
- **Stress effects**: Combat pressure reduces performance
- **Fatigue**: Extended combat degrades capability

### Data-Driven Tuning
All behavior controlled by data:
- Crew stats per role
- Threat/opportunity scoring
- Awareness ranges
- Decision delays

Easy to create varied crew (veterans, rookies, specialists).

## Extending the System

### Adding New Roles
1. Add role to `CrewData.Role` enum
2. Add case to `_get_role_modifiers()`
3. Add case to `CrewAISystem.make_*_decision()`
4. Add case to `CommandChainSystem.validate_order()`

### Adding New Decision Types
1. Add to `CrewAISystem.make_*_decision()` for relevant role
2. Add case to `CrewIntegrationSystem.apply_decision_to_ship()`
3. Update ship systems to respond to new decision

### Custom Crew Stats
Add to crew_data.stats:
```gdscript
"morale": 1.0,  # Affects stress gain rate
"training": 0.8,  # Affects skill improvement over time
```

Reference in decision systems:
```gdscript
var morale_factor = crew_data.stats.get("morale", 1.0)
stress_increase *= (2.0 - morale_factor)
```

## Testing

Run comprehensive test suite:
```bash
godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests -gexit
```

Tests cover:
- Crew creation and hierarchy setup
- Information gathering and awareness
- Decision making for all roles
- Command chain order passing
- Integration with ship systems
- Full system integration

## Future Enhancements

Possible extensions:
- **Crew experience**: Stats improve over time
- **Personality traits**: Aggressive, cautious, methodical
- **Morale system**: Victory/defeat affects performance
- **Crew transfer**: Reassign crew between ships
- **Commander replacement**: Promote subordinate when superior is lost
- **Voice lines**: "Taking fire!", "Targeting enemy fighter"
- **Crew casualties**: Internal damage affects crew
- **Crew specialization**: Veterans of specific ship types

## References

See also:
- `README.md` - Overall game architecture
- `CLAUDE.md` - Development guidelines
- `scripts/space/systems/weapon_system.gd` - Weapon decision integration
- `scripts/space/systems/movement_system.gd` - Movement decision integration
- `tests/test_crew_ai_system.gd` - Comprehensive test examples
