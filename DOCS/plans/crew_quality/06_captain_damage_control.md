# Captain & Damage Control

## Goal

Make `tactics` matter at the **ship scale** for capitals. Captains
position the ship intelligently (armor toward threats), spool weapons
proactively, decide when to withdraw, and run damage control. Produces
Scenarios S5 ("Captain Reads the Room") and S6 ("Damage Control Race").

## Edits

### 6.1 Captain ship-aspect decision

When awareness reports threats with weapon-arc geometry, the captain
issues a "rotate to present X" order to the ship's pilot:

```gdscript
# In captain_ai decision tick:
var threats = prioritize_threats(awareness.threats, captain, ship_data)
if threats.size() > 0 and effective(captain, "tactics") > ASPECT_DECISION_THRESHOLD:
    var preferred_aspect = compute_armor_facing(threats, ship_data)
    ship_data.orders.preferred_aspect = preferred_aspect
```

The capital pilot's existing maneuver machinery
(`large_ship_pilot_ai.gd:orders.maneuver_subtype`) already supports
biased rotation; this just wires the captain's input.

`compute_armor_facing` picks the orientation that exposes the most
armor and least vulnerable subsystems to weighted incoming-threat
vectors.

### 6.2 Captain weapon spool decision

Captain decides which weapon banks come online based on tactical
phase:

- Long-gun priority when threats are at standoff range and closing
  slowly.
- PDC priority when missiles or torpedoes are inbound (high-awareness
  captains spool early; low-awareness captains spool only after
  visible projectiles cross PD range).
- Beam priority when a single high-value target is in arc.

`ship_data.orders.weapon_priority = ["pdc", "long_gun", "beam"]` etc.
WeaponSystem already iterates banks; consume the priority order.

### 6.3 Withdraw decision

`large_ship_pilot_ai.gd:364` already has a withdraw threshold tied to
hull state. Tighten the wiring: tied to `tactics + aggression` plus
hull / threat-overmatch:

```gdscript
var hull_pct = ship_data.hull / ship_data.stats.max_hull
var should_withdraw = (
    hull_pct < WITHDRAW_HULL_BASE - effective(captain, "aggression") * AGGRESSION_HULL_BIAS
    and effective(captain, "tactics") > WITHDRAW_TACTICS_THRESHOLD
)
```

High-aggression captains stay in the fight longer; low-aggression
captains pull out earlier. High-`tactics` captains *recognize* losing
positions; low-`tactics` captains charge into bad matchups.

### 6.4 Damage control speed

`crew_modifiers.damage_control` is already computed at
`crew_integration_system.gd:252`. Currently never consumed.

Wire it in `damage_resolver.gd` repair tick:

```gdscript
var dc_factor = ship_data.get("crew_modifiers", {}).get("damage_control", 1.0)
var repair_amount = base_repair_rate * dc_factor * delta
```

`damage_control` is computed from captain's `tactics` (per the design
in [`01_overview.md`](01_overview.md) — engineer competence folds into
captain's tactics; no separate engineer role).

### 6.5 Delete

- Captain command-style enum members that don't unlock real behavior.
- Any "engineer role" stubs that exist in CrewData; the engineer is
  not a separate role in this design.

## Constants (wing_constants.gd)

New:
- `ASPECT_DECISION_THRESHOLD = 0.4` — below this `tactics`, captain
  doesn't manage aspect.
- `WITHDRAW_HULL_BASE = 0.45` — baseline hull% trigger.
- `AGGRESSION_HULL_BIAS = 0.25` — high-aggression captains tolerate
  lower hull.
- `WITHDRAW_TACTICS_THRESHOLD = 0.3` — below this, captain doesn't
  recognize losing positions and never withdraws.
- `DAMAGE_CONTROL_MIN/MAX = 0.5 / 1.8` — `tactics`-derived multiplier
  range.

## Tests

New:
- `test_captain_aspect_choice.gd` — captain with high tactics rotates
  ship so the most-incoming-fire vector hits the most-armored side.
- `test_captain_weapon_priority.gd` — high-awareness captain prioritizes
  PDC online before missile arrival; low-awareness captain reacts late.
- `test_withdraw_decision_personality.gd` — high-aggression captain
  stays at lower hull than low-aggression captain.
- `test_damage_control_repair_speed_by_skill.gd` — repair rate strictly
  ordered by captain's `tactics`.

## Acceptance

1. `./test.sh` is green.
2. **S5.** In a scripted incoming-torpedo-wave test, elite captain
   ship absorbs ≤ 50% of the damage rookie captain ship absorbs.
3. **S6.** Two identical capitals take identical engine-room hits;
   elite restores 70% engine output in 12 s, rookie ≤ 30% in 25 s.
4. Withdraw decisions split by personality: high-aggression captains
   linger > 30% longer at low hull than low-aggression captains across
   trials.

## Definition of done

- [ ] Aspect, weapon-priority, withdraw, and damage-control wiring
      land.
- [ ] All tests pass.
- [ ] Zero compile warnings.
- [ ] Playtest: capital combat visibly differs by captain quality.
- [ ] Acceptance ticked.
