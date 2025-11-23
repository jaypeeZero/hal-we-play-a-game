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
- Pure functions process state (DamageResolver, WeaponSystem)
- Dictionaries/JSON define entities (ships, weapons, armor)
- No global state in game logic

**Event logging and monitoring:**
- `BattleEventLogger` - Centralized event stream logger that emits standardized events for all battle interactions
- Event history tracking available for debugging, replay, and analysis
- Used for testing, statistics collection, and event stream analysis

**Rendering system:**
- `IRenderable` base class for all visual entities
- `VisualBridge` manages rendering of entities
- Supports multiple renderers (Matrix, Emoji, Null for testing)

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
