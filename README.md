# Space Battle

A tactical space-combat **roguelike** built in Godot 4 with functional-programming
principles and data-driven systems. You command a persistent fleet across a
multi-sector campaign: hire and grow a crew, choose where to jump, and fight
real-time tactical battles where your ships are flown by an event-driven crew AI
rather than micromanaged unit-by-unit.

> This README is the gameplay/orientation guide. For the deep technical design
> see **`ARCHITECTURE_AND_FLOW.md`** (system responsibilities and the per-tick
> game loop) and **`CLAUDE.md`** (architecture conventions and contribution
> rules).

## Quick Start

**Requirements**
- Godot 4 (`brew install godot`)
- GUT testing framework (bundled in `addons/gut/`)

**Run the game** (launches the main menu):
```bash
godot scenes/main_menu.tscn
```

**Run the tests:**
```bash
./test.sh
# or a single suite:
godot --headless --script addons/gut/gut_cmdln.gd -gdir=tests -gfile=test_damage_resolver.gd -gexit
```

## Main Menu

| Entry | What it does |
|-------|--------------|
| **Roguelite Mode** | Starts a new campaign run and drops you on the Campaign Map (the run's home screen). |
| **Continue Campaign** | Resumes a saved run (shown only when a save exists). |
| **New Game** | A one-off **skirmish**: go straight to the Pre-Battle deployment screen, then fight a single battle. |
| **Edit Fleets** | The Fleet Command editor over the saved skirmish fleets (ships, crew assignments, tactics). |
| **Ship Editor** | Tool for authoring/tuning ship templates (`tools/ship_editor.tscn`). |
| **Crew Manager** | Edit the global crew-roster template. |
| **Settings / About / Quit** | Standard. |

## The Campaign Loop (Roguelite Mode)

A run lives in the `RoguelikeRun` autoload (persistent fleet, crew, economy,
doctrine, and the generated star chart). The **Campaign Map** is the home base;
a persistent top **nav bar** (with a live credits readout) moves you between the
meta screens:

- **Campaign Map** — the multi-sector star chart. Pick a destination to jump to;
  jumps advance the star date and repair ships over the downtime. Battle nodes
  set up the next engagement. A side panel shows campaign **dispatches** (news).
- **Fleet Command** — manage your fleet: ship roster, crew assignments, and the
  fleet **tactics/doctrine** preset for the next battle.
- **Crew** — a read-only view of your hired crew and each member's ship
  assignment during a run (the same screen edits the global roster outside a run).
- **News** — the full campaign dispatch feed.
- **Pre-Battle** — deploy/position your ships before an engagement.
- **Battle** — the real-time tactical fight (see below).
- **Post-Battle** — outcome summary: rewards, casualties, insurance, and crew
  progression. Survivors carry their damage and experience back into the run.

Between battles you spend credits in the **shop** (buy hulls, hire and dismiss
crew) and can wager on the **ship race** minigame. Crew can be killed or hired,
ships can be lost, mothballed ("iced"), or repaired; everything persists for the
run and is saved via `CampaignSaveManager`.

## Battle Controls

Battles run in real time. Ships are flown by their crew AI — you shape behaviour
through fleet tactics/doctrine and commander orders rather than driving each ship.

The skirmish battle scene also supports manual spawning for testing:

| Key | Action |
|-----|--------|
| **1 / 2 / 3** | Spawn player fighter squadron (6, V-formation) / corvette / capital ship |
| **4 / 5 / 6** | Spawn enemy fighter squadron / corvette / capital ship |
| **7 / 8 / 9** | Spawn small / medium / large asteroid |
| **0** | Spawn a platform |
| **F1** | Toggle the debug visualizer |

After a spawn key, click the battlefield to place the ship(s). Squadron-spawned
fighters share a command chain (lead + wingmen); single-spawn fighters fly solo.
The camera supports free pan/zoom (`camera_controller.gd`).

**Debug visualizer (F1)** overlays armor sections, internals, weapon arcs,
velocity, crew stats, formation links, flee boundaries, and the Tactics State /
Tactics Telemetry layers (each ship's resolved doctrine and steering blend).
Individual layers are gated in the Settings menu.

## Ships

Ship definitions are **data-driven** — each type is a JSON template in
`data/ship_templates/` (armor sections with arcs, internal components, weapons,
and physics stats), so concrete numbers live in the data, not in this document.
Eight types ship today:

- **Fighter** — fast, lightly armored attack craft; swarm and hit-and-run.
- **Heavy Fighter** — tougher, harder-hitting interceptor.
- **Torpedo Boat** — light hull built around heavy anti-capital ordnance.
- **Gunboat (Medic / Pepperbox / Firecracker)** — three specialist gunboat
  variants (support/repair, sustained autocannon, burst) on a shared hull.
- **Corvette** — frontline medium combatant; anti-fighter and line-holding.
- **Capital Ship** — heavy battleship; long-range fire support and anchor.

Each type maps to a 3D model in `data/ship_visuals.json`.

## How It Works (Architecture Summary)

Full detail lives in `ARCHITECTURE_AND_FLOW.md` and `CLAUDE.md`; the essentials:

- **Functional + data-driven.** Pure-function systems (`DamageResolver`,
  `WeaponSystem`, `CollisionSystem`, `MovementSystem`, the crew/tactics systems,
  …) take state in and return state out. Game-loop state is owned by
  `SpaceBattleGame` and passed through each tick. Entities (ships, weapons, crew)
  are dictionaries built from JSON.
- **Event-driven crew AI.** Crew aren't polled every frame. A crew member wakes
  only when its `next_decision_time` is due or an event lands in its mailbox
  (`sensor_contact`, `ship_damaged`, `threat_appeared`, …). On waking the
  scheduler drains events, applies side effects (tactical memory, order
  delivery), refreshes awareness, and runs the role's decision. Sleeping crew
  cost almost nothing. Each role (pilot, gunner, captain, engineer, squadron
  leader, commander) has its own brain/action/world-state set under
  `scripts/space/ai/`.
- **Blended combat, not discrete modes.** `TacticsSystem` resolves
  fleet → squadron → ship/role doctrine into a per-crew tactics block;
  `SteeringBlender` turns that plus the live situation into weighted steering
  goals (pursue / keep_range / evade / formation / separation / support);
  `MovementSystem` re-blends them each frame. Reflexes (evasion, collision,
  area leash) stay hard overrides. Postures ride one channel —
  withdraw / hold / press.
- **Command as hats.** `CommandDesignationSystem` stamps Commander / Squadron
  Leader hats onto the best-fit existing crew each tick; their brains issue
  posture, formation, and focus-fire orders that are *absorbed* into
  subordinates' steering blends rather than forcing discrete moves.
- **Roguelike navigation.** `NavGraph` (pure `RefCounted`, unit-tested) owns the
  screen enum and fixed Back hierarchy (everything bottoms out at the Map). The
  `Nav` autoload is a thin scene-switch shim; `NavBar` (built in code, run-scoped
  via `NavBar.attach`) renders the tabs, Back, and credits readout.
- **Rendering.** `VisualBridge` drives an `IVisualRenderer`. The active renderer
  is `Renderer3D` — top-down 3D ship models (CC0 Quaternius pack, mapped in
  `data/ship_visuals.json`) drawn beneath the 2D world, with team tints, engine
  flames, and damage smoke/fire. `78_renderer` (line-based hull outlines from
  `data/hull_shapes/`) is retained, unwired, for A/B comparison.

## Project Layout

```
scenes/                 Godot scenes (main_menu, campaign_map_3d, pre/post_battle,
                        fleet_command, crew_manager, news, space_battle, ship_race, …)

scripts/
  core/
    autoload/           GameSettings, UiTheme, HullShapes, VisualBridge,
                        BattleEventLogger, RoguelikeRun, BattlePlan, Nav
    systems/            Campaign/meta: campaign_generator, campaign_system,
                        campaign_save_manager, crew_generator, event_system,
                        nav_graph, scout_report_system, hull_condition_system, …
  space/
    data/               Ship/crew/fleet data factories and loaders
    systems/            Battle ECS systems (damage, weapons, movement, crew
                        scheduler/mailbox, tactics, steering, economy, repair,
                        squadron, race, …)
    ai/                 Per-role brains, actions, and world-state
    entities/           ShipEntity, ProjectileEntity, VisualEffectEntity
    space_battle_game.gd  Battle orchestrator (the per-tick loop)
    ship_race_game.gd     Ship-race minigame
  ui/
    campaign/ menus/ fleet_command/ pre_battle/ post_battle/ roguelite/ components/

rendering/              VisualBridge, renderers (renderer_3d active, 78 legacy),
                        shared 2D overlays and 3D camera mapping

data/                   JSON: ship_templates/, hull_shapes/, ship_visuals.json,
                        crew/, events/, knowledge/, tactics/, race_tracks/, …

assets/                 3D models, crew portraits, icons, sprites
tools/                  ship_editor, duel_sim, race tools, screenshot/visual harnesses
tests/                  GUT tests (one suite per system)
```

## Contributing

- Keep code simple and data-driven; prefer deleting code to adding it.
- Tests verify **behaviour, not data values** (e.g. "armor penetrates when
  damage exceeds armor", not "fighter has 20 nose armor"). See `CLAUDE.md` for
  the full conventions and the testing philosophy.
- Adding a ship type: add a template to `data/ship_templates/`, register it in
  `fleet_data_manager.gd`, map a model in `data/ship_visuals.json`, and (for the
  legacy renderer) add a `data/hull_shapes/` entry.
