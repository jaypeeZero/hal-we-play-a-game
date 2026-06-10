# 05 — Bring remaining crew roles to the fighter-pilot quality bar

Condensed carry-forward of the old `crew_ai_rework` plans (phases 1–4;
phase 0, the per-role file split, shipped long ago). The fighter pilot
(PR #51) sets the bar: an explicit FSM for the engagement cycle, a
personality axis beyond raw skill (`aggression`, `composure`),
self-preservation, and named hard-override interrupts.

Status when last audited: each role has its module file and basic
decisions, but not the FSM/interrupt structure.

## Per role (one PR each, in this order)

1. **Large-ship pilot** (`large_ship_pilot_ai.gd`) — closest to done:
   FSM and leash exist; still reads legacy stat keys in places and
   lacks `threat_appeared`/`ship_damaged` tactical-break interrupts.
2. **Gunner** (`gunner_ai.gd`) — fire-discipline FSM (acquire → track →
   burst → assess), section-targeting commitment, point-defense and
   ceasefire states. `tests/test_gunner_ai.gd` does not exist yet.
3. **Captain** (`captain_ai.gd`) — command-tempo FSM, posture
   commitment (don't flip-flop orders every tick), damage-driven
   posture shifts. `tests/test_captain_ai.gd` does not exist yet.
4. **Squadron leader + fleet commander** (`squadron_leader_ai.gd`,
   `commander_ai.gd`) — strategic FSM: assess → commit → execute →
   reassess on trigger (ship lost, play completed, odds shifted).

## Standards (from CLAUDE.md, non-negotiable)

- Static methods on `RefCounted`, state on the crew dict only.
- Named constants; no fallback/legacy paths left behind.
- Behavior tests per role; `./test.sh` green; change visible in the
  battle log (plan 01) — every FSM transition should be loggable.

## Done when

- Each role file has an explicit FSM with named states, at least one
  personality-modulated behavior, and a test file exercising the FSM
  transitions.
