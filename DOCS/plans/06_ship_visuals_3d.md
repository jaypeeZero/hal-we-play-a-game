# Plan 06 — Ship Visuals: 3D Models in a Top-Down 2D View

## Goal

Replace the hand-authored vector hull system (Renderer78 + `data/hull_shapes/` JSON +
HullShapeDrawer) with real 3D ship models rendered top-down. Gameplay stays 2D.
The result must look like a finished game, be at least as performant as today,
and make adding/changing ships a matter of dropping in a model, not typing
polygon coordinates.

## Decisions already made

| Decision | Choice | Why |
|---|---|---|
| Visual direction | 3D models, top-down orthographic camera | Holds fidelity across the 0.05x–2.0x zoom range; lighting, particles, and depth come free; ends the "programmer art" look |
| Art source | Free CC0 low-poly packs (Quaternius "Ultimate Spaceships", Kenney "Space Kit") | Easiest + cheapest that still looks good; consistent stylized (non-pixel) aesthetic; GLB drops straight into Godot 4 |
| Per-section damage colors | Replaced, not preserved | Swap blue→red section tinting for richer feedback: smoke/fire particles anchored to damaged sections, hit sparks, scorch, explosive destruction |
| Gameplay/physics | Untouched | Collision is circle-based and hit detection is angle-arc-based — neither reads hull polygon geometry, so the visual swap has zero gameplay surface |

## Architecture

**One new renderer behind the existing seam.** `VisualBridge` already hot-swaps
renderers implementing `IVisualRenderer` (`rendering/core/i_visual_renderer.gd`),
so the new system is `Renderer3D` built alongside `Renderer78`, switched when
accepted, after which Renderer78 and its support code are deleted.

```
space_battle.tscn (stays 2D root)
└── SubViewportContainer (full-rect, one for the whole battle — NOT per ship)
    └── SubViewport
        └── BattleWorld3D (Node3D, owned by Renderer3D)
            ├── Camera3D (orthographic, looking down -Y)
            ├── DirectionalLight3D + WorldEnvironment (glow enabled)
            ├── ShipVisual3D × N   (GLB instance + thrusters + damage emitters)
            ├── ProjectileVisual3D × N
            └── EffectVisual3D × N (impacts, explosions)
UI / debug overlays stay in CanvasLayer above the container.
```

**Coordinate mapping** is a small pure-function module (testable, no scene access):
- `Vector2(x, y)` game position → `Vector3(x, 0, y) * WORLD_TO_3D_SCALE`
- 2D `rotation` → yaw around Y (sign-flipped; ship models face -Z)
- Camera2D zoom value → orthographic camera `size`
All conversion factors are named constants — no magic numbers.

**Data:** new `data/ship_visuals.json` maps each `ship_type` to
`{model_path, model_scale, team_tint_material_slot}`. This replaces hull-shape
JSON as the per-ship visual definition. Note: `base_size` in hull_shapes JSON
currently feeds `collision_radius` (HullShapes.gd:82) — it must migrate into the
ship templates (where the rest of the physical stats live) before hull_shapes
is deleted.

**Damage & effects** (the "something better"):
- Engine thrust: emissive cone mesh + GPUParticles3D per engine, driven by the
  existing `is_main_engine_firing` state (replaces Polygon2D + PointLight2D).
- Section damage: smoke→fire GPUParticles3D anchored at each armor section's
  existing `position_offset`, emission rate scaled by that section's damage
  fraction from `EntityState.section_damage`. The section/arc data already
  flows to the renderer every frame; only the presentation changes.
- Hits: spark burst + brief emissive flash at hit position, driven by the
  existing `play_animation` effect events (armor_hit / penetration / internal).
- Destruction: explosion particles + debris flash, then fade (replaces the red
  flash + alpha tween).
- Tactical readability: since per-section armor color is gone, the selected
  ship gets an optional 2D overlay arc indicator showing per-section armor —
  small, deferred to the polish phase.

**Far-zoom legibility:** below a zoom threshold ships become specks regardless
of art style. Add an icon layer — per-ship billboard markers (team-colored,
type-shaped) that fade in below the threshold constant. Standard for tactical
games and solves a problem the current renderer also has.

## Performance stance

Current system is already cheap (no per-frame `_draw`, ~10–18 nodes/ship,
property mutation only). The 3D version stays at parity or better:
- 5 unique low-poly meshes (hundreds–low-thousands of tris), shared across
  instances; Godot batches identical meshes well at these counts.
- One directional light, **shadows off** initially; glow via environment.
- Particles are GPU-driven and only active on damaged/thrusting ships.
- Acceptance gate: profile frame time with the max expected fleet size against
  Renderer78 before deleting it.

## Phases

1. **Spike (throwaway allowed):** SubViewport + ortho camera + one Quaternius
   GLB driven by a live ship's position/rotation. Validate the look across the
   full zoom range and pick the model pack. *This is the go/no-go gate — if
   the free packs don't look right, revisit art source before building more.*
2. **Asset pipeline:** import chosen GLB pack under `assets/models/ships/`,
   add license file, create `data/ship_visuals.json` mapping all 5 ship types,
   apply team tint (material override on an accent slot).
3. **Renderer3D core:** implement `IVisualRenderer` (initialize / attach /
   detach / update_state / cleanup); coordinate-mapping module with unit tests
   (`tests/test_renderer3d_mapping.gd` — pure functions only, per testing
   standards).
4. **Camera unification:** existing camera controller drives the 3D ortho
   camera (position + zoom→size). Pan/zoom feel must match current behavior.
5. **Effects:** thrusters, hit sparks, per-section smoke/fire, destruction
   explosion. Wire to existing EntityState fields and animation requests.
6. **Projectiles & misc:** emissive projectile meshes with trails; torpedo
   explosion AOE visual; re-home debug overlays (direction line, leader labels)
   as 3D lines or projected 2D labels.
7. **Far-zoom icon layer** with named zoom-threshold constant.
8. **Polish + profiling:** lighting/environment tuning, fleet-scale frame-time
   comparison vs Renderer78.
9. **Deletion:** migrate `base_size` → ship templates; delete Renderer78,
   HullShapeDrawer, HullShapes, `data/hull_shapes/`, and any orphaned renderer
   stubs. No legacy/fallback code remains; `Renderer3D` becomes the sole
   renderer referenced in CLAUDE.md/README.

## Status

- Phases 1–6 core landed (2026-06): Quaternius models imported, `Renderer3D`
  active via `visual_bridge_autoload.gd`, camera slaved, team tints, engine
  flames, section smoke/fire, destruction burst, projectile/effect meshes,
  mapping tests in `tests/test_space_3d_mapping.gd`. Screenshot harness:
  `xvfb-run godot --path . res://tools/visual_check.tscn`.
- Remaining: far-zoom icon layer (phase 7), lighting polish + fleet-scale
  profiling vs Renderer78 (phase 8), Renderer78/hull-shape deletion with
  `base_size` migration (phase 9).

## Risks

- **Aesthetic mismatch** of free packs → mitigated by phase 1 gate; fallback is
  AI-generated or commissioned models using the same GLB pipeline (architecture
  unchanged).
- **3D scene/2D UI interleaving** (selection rings, formation circles) → render
  gameplay-information visuals as 2D overlay projected from world positions,
  keeping pure cosmetics in 3D.
- **Coordinate/sign errors** (Godot 3D is Y-up, -Z forward) → contained in the
  tested mapping module.
- **Loss of at-a-glance armor info** → overlay arc indicator in phase 8 if
  playtesting misses it.
