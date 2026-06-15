# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Space Battle - A tactical space combat game built with Godot 4 using functional programming principles and data-driven systems.

See `README.md` for controls, gameplay details, and architecture overview.

## Development Setup

**Requirements:**
- Godot 4: `brew install godot`
- GUT testing framework (included in `addons/gut/`)

**Running the game:**
```bash
godot scenes/space_battle.tscn
```

**Running tests:**
```bash
`./test.sh` or `godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests -gexit`
```


## Programming Principles

When working on this codebase:
- Keep code simple - code is the enemy
- Delete code whenever possible rather than adding complexity
- Prioritize a working, maintainable system over anything else
- Favor simple solutions over clever ones
- Follow Godot best practices and naming conventions
- Implement clean separation between game logic, UI, and data
- Design systems to be modular and easily testable
- Prioritize readability and maintainability over premature optimization
- Use Godot's signal system for loose coupling between components
- Warnings when compiling code are just unresolved errors, don't leave them around

## Avoid

- Do NOT retain "fallback" or "legacy" code unless the user specifies.
- Do NOT use hard-coded numbers, define CONSTANTS with descriptive names

## Architecture

**Signal-based event system:**
- Direct signal connections for local events (e.g., ship.damaged, projectile.hit)
- Avoid signal bubbling through multiple parent nodes

**Functional + Data-Driven:**
- Pure functions process state (DamageResolver, WeaponSystem, CrewSchedulerSystem, ...)
- Dictionaries/JSON define entities (ships, weapons, armor, crew)
- No global state in game logic
- One-owner per-frame state (e.g., projectile position) is mutated in place
  via clearly-named functions (`advance_projectile_in_place`); cross-system
  values stay immutable

**Crew AI (event-driven scheduler):**
- Crew dicts carry `next_decision_time` and a per-crew mailbox lives in the game node
- `CrewSchedulerSystem.tick_with_awareness` processes only crew that wake
  (timer due or events pending); sleeping crew cost ~zero
- Event sources (`InformationSystem`, weapon/collision/projectile systems)
  post into the mailbox via `_queue_crew_event`; the scheduler drains them,
  applies side effects (tactical memory, current-target clearing, order
  delivery), refreshes awareness, then runs the role's decision function
- Urgent events (threat_appeared, ship_damaged) for a pilot with known threats
  short-circuit to evasion

**Combat AI (tactics → steering blend):**
- `TacticsSystem` resolves fleet → squadron → ship/role doctrine into a per-crew
  `tactics` block (mentality/range scalars, target priority, sector focus),
  attached once at battle spawn and read every decision
- `SteeringBlender.build_directive` turns that block + the live situation into a
  weighted *steering goal* directive (subtype `"tactical"`): pursue / keep_range /
  evade / formation / separation / support, plus `preferred_range` and a role
  `facing_mode` (auto / nose_on / broadside). This replaces discrete engage modes
  with one continuous blend
- `MovementSystem.calculate_blended_control` is the live steering path for ships
  carrying a `"tactical"` order: it re-blends those goals each frame from current
  positions, so movement stays continuous between decisions
- Reflexes (evasion, collision break, area leash) remain hard overrides — they run
  before the brain and short-circuit the blend; orders never do
- **Postures** ride a single channel (`combat_posture`): `withdraw` (evade-dominant,
  disengage), `hold` (formation-dominant, anchor the line), `press` (pursue-dominant,
  close and brawl). AI commit decisions and the player All-Out Attack order both
  write here, so they converge on one read path
- **Collision separation**: a separation goal repels friendlies that crowd within a
  few hull-radii, ramping steeply at contact so ships keep formation without piling up

**Crew command hierarchy:**
- Command roles are HATS on existing crew, stamped each tick by
  `CommandDesignationSystem` after wings form: the best-ship captain also wears the
  Commander hat; the best wing pilot also wears the Squadron Leader hat. No new crew
  are created
- `CrewAISystem` reads the hats to dispatch `CommanderBrain` / `SquadronLeaderBrain`
  alongside the crew's normal role brain
- Command brains issue formation / focus-fire / posture orders down the chain. Orders
  are ABSORBED into the receiver's steering blend (posture weights, focus-target
  boost in `InformationSystem` targeting), never short-circuited into discrete moves
- Focus-fire: a designated target gets a targeting-weight boost so a wing concentrates
  fire without forcing every ship onto it

**Roguelike meta-layer navigation:**
- `NavGraph` (pure `RefCounted`) owns the screen enum, scene paths, and the
  FIXED Back hierarchy (Map→Fleet Manager; Crew/News/Pre/Post-Battle→Map; Fleet
  Manager is the floor — Back never goes past it). All routing logic is here and
  unit-tested (`tests/test_nav_graph.gd`)
- `Nav` autoload is a thin scene-switch shim over `NavGraph` (`goto`/`back`)
- `NavBar` is built in code, not a scene. Use `NavBar.attach(parent, screen,
  tabs_on, back_cb)` — it is RUN-SCOPED (adds nothing unless `RoguelikeRun.active`),
  so title-menu/skirmish entries to Crew Manager / Pre-Battle keep their own back.
  Attach it AFTER a screen's base UI so it draws on top; runtime modals added later
  still cover it (you can't nav away mid-modal)
- Tabs jump straight to a screen; Back walks the fixed parent. Adding an area =
  one `NavGraph.Screen` value + a `SCENE_PATHS`/`PARENTS` row + one `NavBar.TABS` entry

**Event logging and monitoring:**
- `BattleEventLogger` - Centralized event stream logger that emits standardized events for all battle interactions
- Event history tracking available for debugging, replay, and analysis
- Used for testing, statistics collection, and event stream analysis

**Rendering system:**
- `IRenderable` base class for all visual entities
- `VisualBridge` manages rendering of entities
- Active renderer is `Renderer3D` (3D ship models from `data/ship_visuals.json`
  drawn top-down beneath the 2D world); set on `VisualBridge` at startup
- `Renderer78` (hull outlines from `data/hull_shapes/` JSON) is retained, unwired,
  for A/B comparison only

## Testing Standards

**Philosophy:**
- Tests should test FUNCTIONALITY ONLY - behaviors and capabilities, not specific data values
- Tests should not be tied to data because data may change
- Tests should be DRY (Don't Repeat Yourself)
- Tests should verify expected behaviors through assertions

**What to test:**
- ✅ "Armor penetration occurs when damage exceeds armor"
- ✅ "Weapon fires when ready and target is in range"
- ✅ "Damaged engine reduces ship max speed"
- ❌ "Fighter has exactly 20 armor on nose section"
- ❌ "Light cannon deals 5 damage"

**Test coverage:**
- Core systems (ShipData, DamageResolver, WeaponSystem) must have comprehensive test coverage
- All tests are in `tests/` directory and use GUT framework
- Test files follow naming convention: `test_<system_name>.gd`

**Running specific tests:**
```bash
# Run all tests
./test.sh

# Run specific test file
godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests -gfile=test_damage_resolver.gd -gexit
```
