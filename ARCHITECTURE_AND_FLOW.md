# ARCHITECTURE_AND_FLOW.md

## Core Principles

**Signal-based architecture**: Components communicate via signals rather than direct coupling
**System composition**: Battlefield orchestrates independent systems rather than monolithic logic
**Entity hierarchy**: All game objects inherit from base classes (Damageable → specialized types)
**Hand/Deck pattern**: Card-based spell/creature system with draw-replace mechanics

## Component Responsibilities

### Battlefield (Root Orchestrator)
- Instantiates players at configured positions
- Creates and injects dependencies between systems
- Connects top-level signal handlers (player death, projectile explosions)
- Owns UI layer (status bars, hand displays)

### Systems (Stateless Logic)
- **InputHandler**: Translates raw input → player movement + casting requests
- **CombatSystem**: Validates mana, consumes cards, delegates spawning
- **EntitySpawner**: Instantiates entities in scene tree with proper initialization

### Players
- Extend Damageable (health, damage signals)
- Own Hand → Satchel relationship
- Emit mana_changed signals
- Regenerate mana each frame

### Hand System
- **Satchel**: Infinite deck with predetermined medallion distribution
- **Hand**: Fixed-size (5 cards), play → draw replacement pattern
- **Medallion**: Data container for entity type + cost

### Entities
All inherit from Damageable or its children:
- **CastableEntity**: Base for all spawnable game objects
- **MovingEntity**: Adds movement toward target_position
- **Projectile**: Moves → explodes on arrival
- **Unit**: Moves with steering behaviors → attacks on collision

### Units (Creatures)
- Dynamic targeting: prioritize enemy creatures → fallback to enemy player
- Steering behaviors: seek/arrive with acceleration/turn rate limiting
- HitBox collision detection for melee attacks
- Auto-draw health bars on damage

## Core Flow Patterns

### Input → Cast Flow
```
User presses key
  → InputHandler.handle_casting_input()
    → CombatSystem.cast_from_hand()
      → Player.spend_mana() [validation]
      → Hand.play_card() [draws replacement]
      → EntitySpawner.spawn_entity() [instantiate in scene]
```

### Entity Lifecycle
```
Spawn
  → initialize(data, target_pos, enemy_player)
  → Add to groups ("combatants", "creatures", etc.)
  → Connect signals (died → cleanup)
Each frame
  → MovingEntity._move_toward_target()
  → Unit updates dynamic_target periodically
On arrival/collision
  → Projectile: explodes, queue_free()
  → Unit: attacks, persists
On death
  → emit died signal
  → queue_free()
```

### Damage Flow
```
Entity.take_damage()
  → health -= amount
  → emit damaged(amount)
    → UI updates (status bars)
  → if health == 0: emit died()
    → Battlefield._on_player_died() [game over]
    → Unit._on_unit_died() [cleanup]
```

### Hand Flow
```
Initial: Satchel.draw() × 5 → populate Hand
Play card: Hand.play_card(slot)
  → emit card_played(slot, medallion)
  → Satchel.draw() → replace slot
  → emit card_drawn(slot, new_medallion)
    → HandUI updates display
```

## Signal Topology

**Local signals** (parent-child connections):
- Player.damaged → PlayerStatusBars.set_health()
- Player.mana_changed → PlayerStatusBars.set_mana()
- Hand.card_drawn → HandUI.update_card()
- Unit.died → Unit._on_unit_died() [self cleanup]

**Upward signals** (child notifies orchestrator):
- Player.died → Battlefield._on_player_died()
- EntitySpawner.projectile_spawned → Battlefield._on_projectile_spawned()
- Projectile.exploded → Battlefield._on_projectile_exploded()

**No global event bus currently used** (GameEvents autoload exists but unused)

## Key Patterns for Extension

**Adding new entity types**:
1. Inherit from Projectile or Unit
2. Override `initialize()` for custom data
3. Override `_calculate_steering_force()` for custom movement (Units only)
4. Add MedallionType enum value
5. Add entity data to EntitySpawner

**Adding new systems**:
1. Create as RefCounted or Node class
2. Instantiate in Battlefield._ready()
3. Inject dependencies (players, other systems)
4. Hook into _process() or _input() from Battlefield

**UI updates**:
- Always connect to entity signals (damaged, mana_changed, etc.)
- Never poll entity state each frame
- UI lives in CanvasLayer for proper Z-ordering

## File Organization

```
scripts/
  battlefield.gd              # Root orchestrator
  systems/                    # Stateless logic processors
    input_handler.gd
    combat_system.gd
    entity_spawner.gd
  players/                    # Player-specific code
    player.gd
  hand_system/                # Card/deck mechanics
    hand.gd, satchel.gd, medallion.gd
  entities/                   # Spawnable game objects
    damageable.gd             # Base health/damage
    castable_entity.gd        # Base spawnable
    moving_entity.gd          # Base movement
    projectile.gd, unit.gd    # Specialized types
    [entity]_unit.gd          # Concrete creatures
  ai/                         # Movement algorithms
    steering_behaviors.gd
  ui/                         # Display components
  utilities/                  # Shared helpers
```

## Inheritance Hierarchy

```
Node2D
  └─ Damageable (health, damaged signal, died signal)
      └─ PlayerCharacter (mana, Hand, Satchel)
      └─ CastableEntity (base for spawned entities)
          └─ MovingEntity (movement toward target_position)
              └─ Projectile (linear movement, explodes on arrival)
                  └─ Fireball (fast, high damage)
              └─ Unit (steering, collision, dynamic targeting)
                  └─ WolfUnit (pack behavior)
                  └─ RatUnit (swarm characteristics)
                  └─ [Other creatures]

RefCounted
  └─ Hand (5-card hand, draw-replace)
  └─ Satchel (infinite deck)
  └─ Medallion (data: type + cost)
  └─ SteeringBehaviors (static methods)
  └─ CollisionUtils (static helpers)

Node
  └─ InputHandler (keyboard → actions)
  └─ CombatSystem (mana validation, card consumption)
  └─ EntitySpawner (scene instantiation)
```

## Data Flow by Feature

### Player Movement
```
_process(delta)
  → InputHandler.handle_movement()
    → Read keyboard state for each player
    → Update player.global_position directly
```

### Casting Spells/Creatures
```
_input(event)
  → InputHandler.handle_casting_input()
    → Identify which player + which hand slot
    → CombatSystem.cast_from_hand(player, slot, target_pos)
      → Check mana via player.spend_mana()
      → Consume card via player.hand.play_card()
      → EntitySpawner.spawn_entity()
        → Instantiate entity scene
        → Call entity.initialize(data, target, enemy_player)
        → Add to scene tree
        → Emit projectile_spawned if applicable
```

### Creature AI
```
Unit._process(delta)
  → Periodically update dynamic_target
    → Priority: nearest enemy creature > enemy player
  → Calculate steering force based on target
  → Apply acceleration/turn rate limiting
  → Update velocity and position
  → Check for collision via Area2D.area_entered
    → If hit enemy: deal damage, emit hit_target
```

### Win Condition
```
Any entity.take_damage()
  → health -= amount
  → emit damaged
  → if health == 0: emit died
    → If Player: Battlefield._on_player_died()
      → Print winner
      → get_tree().quit()
    → If Unit: Unit._on_unit_died()
      → queue_free()
```

## Testing Architecture

Tests mirror production structure:
- `test_player.gd` - Player health, mana, hand integration
- `test_[entity].gd` - Entity-specific behavior (movement, damage, targeting)
- `test_hand.gd` - Card draw/play mechanics
- `test_combat_system.gd` - Mana validation, card consumption

All tests use GUT framework with:
- `before_each()` - Set up test entities
- `after_each()` - Clean up with `free_all()`
- Assertions on signals (`watch_signals()`, `assert_signal_emitted()`)
- Direct method calls (no input simulation needed)

## Common Pitfalls

**Memory leaks**: Always connect entity.died to queue_free() or manual cleanup
**Invalid references**: Check `is_instance_valid()` before accessing dynamic_target
**Signal double-firing**: Disconnect signals before freeing nodes if manually managed
**Z-order issues**: UI must be in CanvasLayer, not direct scene children
**Mana exploits**: Always validate via spend_mana() before casting, never deduct separately
**Card state desync**: Let Hand.play_card() handle both removal and replacement atomically

## Future Extension Points

**Multiplayer**: Systems already player-indexed, add network synchronization layer
**More spells/creatures**: Add to MedallionType enum + EntitySpawner data
**Terrain**: Add tilemap collision detection to steering behaviors
**Buffs/Debuffs**: Add status effect system to Damageable
**Deck customization**: Replace fixed Satchel with player-defined deck composition
**Abilities**: Add cooldown system to Hand or separate ability bar
