# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Wizard Battle Arena (WBA) - a 2-player wizard battle arena built with Godot 4 using Test-Driven Development.

See `README.md` for controls and gameplay details. See `manifesto.md` for long-term vision.

## Development Setup

**Requirements:**
- Godot 4: `brew install godot`
- GUT testing framework (included in `addons/gut/`)

**Running tests:**
```bash
godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests -gexit
```

**Running the game:**
```bash
godot scenes/battlefield.tscn
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

## Documentation Standards

When creating documents in `tasks/`:
- Documents are written for LLM consumption, not humans
- Do NOT include time estimates, effort assessments, or difficulty ratings
- Do NOT include subjective goals, priorities, or judgement-based criteria
- Focus on technical facts: current state, problems, solutions, implementation steps
- Include code examples, file paths, and concrete technical details
- The human developer is the sole decision-maker for priorities and effort allocation

## Architecture

**Signal-based event system:**
- Direct signal connections for local events (e.g., player.died, creature.damaged)
- Avoid signal bubbling through multiple parent nodes

**Event logging and monitoring:**
- `BattleEventLogger` - Centralized event stream logger that emits standardized events for all battle interactions
- Event history tracking available for debugging, replay, and analysis
- Used for testing, statistics collection, and event stream analysis

## Testing Standards  

 - Tests should not be tied to data because data may change
 - Tests should be DRY
 - Tests should test functionality via expectations

Refer to `manifesto.md` for long-term game design vision.
