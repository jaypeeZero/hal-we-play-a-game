# 02 — Fix the two failing AI tests

Both failures predate the cleanup branch and appear related to the two
most recent behavior-tuning commits ("Make good gunners more
discerning", "trying to tighten up flight").

## Failures

1. `tests/test_elite_pilot_collision_and_targeting.gd:42`
   `test_elite_breaks_for_friendly_on_collision_course` — expects
   `fight_lateral_break`, gets `fight_friendly_avoid`. Either the elite
   pilot's friendly-collision interrupt priority changed, or
   `fight_friendly_avoid` is now the intended decision and the test
   needs updating. Decide which behavior is correct first; the test
   name says elites should *break*, not gently avoid.
2. `tests/test_large_ship_pilot_ai.gd:325`
   `test_capital_far_outside_leash_drops_fight_to_return` — capital far
   outside its patrol leash should drop combat and return; the decision
   is not tagged as return-to-area. Check the leash distance check in
   `LargeShipPilotAI.make_decision()` against the leash constants —
   likely a threshold or ordering change from the flight-tightening
   commit.

## Done when

- `./test.sh` is fully green (509/509).
