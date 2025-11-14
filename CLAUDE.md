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
godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests -gexit
```

**Adding new scripts:**
After creating new GDScript files with `class_name`, you MUST run this command to register them:
```bash
godot --headless --import
```

**CRITICAL - Godot UID Files:**
When creating ANY new `.gd` file, Godot automatically generates a corresponding `.gd.uid` file.
- ALWAYS include BOTH the `.gd` file AND its `.gd.uid` file together
- The `.gd.uid` file contains the unique identifier Godot uses to track the script
- Missing `.gd.uid` files cause Godot to break scene references and resource loading
- After creating a new script, verify the `.gd.uid` file exists
- If you create a script and the `.gd.uid` is missing, run `godot --headless --import` to generate it

## Programming Principles

When working on this codebase:
- Keep code simple - code is the enemy
- Prioritize a working, maintainable system over anything else
- Write the minimum code necessary to solve the problem
- Favor simple solutions over clever ones
- Delete code whenever possible rather than adding complexity
- Follow Godot best practices and naming conventions
- Use GDScript as the primary language unless specific performance needs require C#
- Implement clean separation between game logic, UI, and data
- Design systems to be modular and easily testable
- Prioritize readability and maintainability over premature optimization
- Use Godot's signal system for loose coupling between components
- Warnings when compiling code are just unresolved errors, don't leave them around

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
