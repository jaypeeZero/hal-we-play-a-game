# 07 — Energy-bleed flight model (contingency)

**Status: contingency.** Only execute if the committed-evasion + soft-cap
changes (shipped on `claude/nifty-brown-hgqzi3`) don't open a visible
skill gap in playtests. Increment 1 (the duel harness) is worth shipping
regardless — it's how we decide.

## Problem

Even with evasion fixed, the flight model offers pilots few *decisions*:
thrust toward the thing, turn toward the thing. Constraints that just cap
output (hard speed clamp, turn-rate falloff) compress skill; constraints
that present a *tradeoff* create it. The classic high-skill-ceiling model
is the WW2 energy fight: turning hard costs speed, speed must be
re-earned, and the pilot who manages that budget wins. We already have
half of it — `turn_rate_falloff` is documented as the "WW2 dogfight
model" in `_compute_new_rotation`. It *refuses* the turn at speed instead
of *charging* for it. This plan converts the refusal into a price.

## The model

One new mechanic in `MovementSystem.apply_space_physics`:

- **Turn bleed**: each frame, reduce speed by
  `turn_speed_bleed × |rotation_delta| × speed` — an induced-drag analog,
  proportional to how hard the nose is being swung and how fast the ship
  is going. A 180° max-rate turn at full speed costs a large fraction of
  it; the same turn at crawl speed costs almost nothing.
- **Energy recovery**: already exists — main thrust plus the soft speed
  cap (`OVERSPEED_DECAY_RATE`). No new code; bleed + thrust defines an
  equilibrium "corner speed" where sustained turning balances regen.
- **Turn falloff shrinks**: `turn_rate_falloff` drops (0.5 → ~0.25) so
  ships *can* turn at speed — they just pay for it. Don't remove it
  entirely; a small falloff keeps top-speed passes feeling committed.

Emergent consequences, for free: yank-the-stick pilots end up slow and
predictable; extending in a straight line banks energy; boom-and-zoom
versus turn-fight becomes a real dichotomy instead of a comment.

## Increments (one PR each)

1. **Duel harness first.** Headless sim: elite pilot/gunner crew vs
   rookie crew, N seeded matches via the existing test factories +
   `BattleEventLogger`; report win rate, time-to-kill, hits taken per
   minute. Lives in `tools/` or as a GUT "stats" test. This is the
   skill-gap meter — it judges plan A's changes and gates this plan.
2. **Physics**: `_apply_turn_bleed` step in `apply_space_physics`, new
   `turn_speed_bleed` stat in ship templates (fighter ≈ 0.15/rad,
   corvette ≈ 0.05/rad — it barely turns anyway), falloff reduction.
   AI untouched; fights naturally slow into turning knife-fights.
3. **AI energy awareness**: a `corner_speed(ship_data)` helper; dogfight
   and approach maneuvers target it instead of fixed
   `max_speed × 0.35` fractions; flee/disengage decisions weigh current
   speed (a slow ship shouldn't try to extend through a fast one).

## Tuning anchors

- Corner speed should land around 40–60% of max_speed for fighters so
  there's room above (energy to spend) and below (over-spent, in danger).
- A full 180° reversal at max speed should cost enough that doing it
  twice in a row without a thrust recovery window is clearly punished.
- Keep brake thrusters as the *deliberate* way to dump speed (they have
  the heat budget); bleed is the *incidental* cost of maneuvering.

## Tests (behavior, not values)

- Hard turn at high speed loses more speed than the same turn at low speed.
- Sustained max-rate turning converges on a speed below max_speed.
- A straight-line ship retains energy a constantly-turning ship loses.
- Duel harness: elite-vs-rookie win rate exceeds the pre-change baseline.

## Risks

- Over-tuned bleed makes everything crawl — anchor on corner speed, not
  on how dramatic a single turn looks.
- Pursuit AI that constantly micro-corrects heading will bleed
  unintentionally; increment 3 exists to fix exactly that, so ship 2 and
  3 close together if it shows up.

## Done when

- Duel harness reports a clearly larger elite-vs-rookie gap than the
  plan-A baseline, tests green, zero warnings, and a playtest shows
  fights with visible fast/slow rhythm instead of constant-speed orbits.
