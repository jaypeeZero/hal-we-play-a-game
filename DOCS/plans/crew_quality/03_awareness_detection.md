# Awareness & Detection

## Goal

Elite crew **see threats earlier** and **prioritize them better**. This
is the foundation Phase 04 (pending-intent reaction latency) builds on:
without latency in detection, reaction-time differences alone aren't
enough to produce S1 ("The First Burst").

Also folds in the **stat rename pass**: legacy fields are deleted and
the consolidated six-stat schema from [`01_overview.md`](01_overview.md)
becomes the only schema.

## Edits

### 3.1 Stat rename + delete

`crew_data.gd` skills dict goes from:

```gdscript
{ situational_awareness, aggression, composure, anticipation, marksmanship }
```

to:

```gdscript
{ aim, awareness, tactics, composure, aggression, piloting }
```

(`piloting` and `tactics` are *added*; the others are renamed or
deleted.)

**Field-by-field:**

| Old | New | Action |
|---|---|---|
| `stats.skill` (legacy aggregate) | — | **Delete.** Update all callers to read the appropriate per-stat field. |
| `skills.marksmanship` | `skills.aim` | Rename, update all reads. |
| `skills.situational_awareness` | `skills.awareness` | Rename. |
| `skills.anticipation` | folded into `tactics` (command roles) and `aim` (gunners — for lead/prediction) | Delete; replace reads with appropriate target stat. |
| `skills.composure` | `skills.composure` | Unchanged. |
| `skills.aggression` | `skills.aggression` | Unchanged. |
| — | `skills.piloting` (new) | Add. |
| — | `skills.tactics` (new) | Add. |

**Read-site updates** (file:line refs from baseline audit):
- `fighter_pilot_ai.gd:143–166` (composure check) — unchanged read.
- `fighter_pilot_ai.gd:332–386, 432, 664–681` — `aggression` /
  `anticipation` reads → switch `anticipation` to `tactics`.
- `large_ship_pilot_ai.gd:191–292, 364–438` — same pattern.
- `information_system.gd:58` — `situational_awareness` → `awareness`.
- `crew_ai_system.gd:66–70` — old `effective_skill` calc gets the new
  per-stat treatment in Phase 07; for now read `piloting` as the
  default for pilots, `aim` for gunners, `tactics` for captains, etc.

**No aliases. No back-compat.** Tests and fixtures referencing old
names are rewritten or deleted. `missile_locked` urgent-event branches
in `crew_scheduler_system.gd` are also deleted in this phase — missile
lock is not a real game mechanic (memory: project_no_missile_locks).

### 3.2 Threat prioritization

Today `InformationSystem.update_crew_awareness` returns a threat list
ordered by detection order, not danger. Elite and rookie crew see the
same list.

New function `InformationSystem.prioritize_threats(threats, crew, own_ship) -> Array`:

```gdscript
# Pseudo:
for threat in threats:
    var time_to_intercept = distance / max(closing_speed, EPSILON)
    var weapon_threat = threat.weapon_threat_score
    var aspect_bias = compute_aspect_bias(threat, own_ship)
    threat.urgency = (closing_speed / time_to_intercept) * weapon_threat * aspect_bias
    if effective(crew, "tactics") < HIGH_TACTICS_THRESHOLD:
        threat.urgency *= randf_range(1.0 - tactics_noise, 1.0 + tactics_noise)
return sorted_descending_by_urgency(
    threats.slice(0, floor(effective(crew, "awareness") * MAX_VISIBLE_THREATS))
)
```

- High-`tactics` crew: low noise, accurate ordering.
- Low-`tactics` crew: noisy ordering — sometimes attack the wrong
  threat first.
- Low-`awareness` crew: drop low-urgency threats off the visible list
  entirely past `floor(awareness * MAX_VISIBLE_THREATS)`.

Replace the implicit ordering inside `identify_threats` with calls to
this. Existing range-gating from `awareness_range` still applies first.

### 3.3 Mailbox detection latency

Today, when `_check_spatial_awareness_triggers` (`space_battle_game.gd:872`)
detects a threat entering range, the `threat_appeared` event lands in
the crew's mailbox immediately. Elite and rookie pilots both wake the
same tick.

Extend the mailbox event format with `deliver_at`:

```gdscript
{ type: "threat_appeared", payload: {...}, deliver_at: float_game_time }
```

`crew_mailbox_system.gd:drain_for_crew` skips events whose `deliver_at`
is in the future; they wait until eligible.

`_queue_crew_event` accepts an optional `latency_seconds` argument:

```gdscript
_queue_crew_event(crew_id, event, latency_seconds = 0.0)
# internally:
event.deliver_at = game_time + latency_seconds
```

`_check_spatial_awareness_triggers` computes detection latency per
crew per threat:

```gdscript
var awareness = effective(crew, "awareness")
var latency = (1.0 - awareness) * MAX_DETECTION_LAG
_queue_crew_event(crew.id, threat_appeared_event, latency)
```

Result: a 0.95-`awareness` pilot perceives a threat ~50 ms after it
appears. A 0.1-`awareness` pilot perceives it ~900 ms later. Combined
with Phase 04's reaction commit, this is what produces S1.

`ship_damaged` events get the same treatment, though latency is
generally lower (you feel a hit faster than you spot a fighter), via
a smaller `MAX_DAMAGE_PERCEPTION_LAG`.

## Constants (wing_constants.gd)

New:
- `MAX_DETECTION_LAG = 0.9` — seconds; rookie awareness perception lag.
- `MAX_DAMAGE_PERCEPTION_LAG = 0.25` — same for `ship_damaged`.
- `MAX_VISIBLE_THREATS = 8` — list cap for highest-awareness crew.
- `HIGH_TACTICS_THRESHOLD = 0.7` — above this, prioritization is clean.
- `TACTICS_NOISE = 0.5` — ± multiplier on urgency for low-tactics crew.

## Tests

New:
- `test_threat_prioritization.gd` — high-tactics crew orders threats by
  urgency descending; low-tactics crew shows out-of-order entries; very
  low awareness drops low-urgency threats.
- `test_mailbox_delivery_latency.gd` — events with `deliver_at` in the
  future are not drained; events become drainable when game time
  passes their `deliver_at`.
- `test_detection_latency_skill_ordering.gd` — perceived time of
  `threat_appeared` is strictly ordered by `awareness`.

Deleted:
- Any tests asserting on `marksmanship`, `situational_awareness`,
  `anticipation`, or the legacy `stats.skill` aggregate.
- `missile_locked` urgent-path tests.

## Acceptance

1. `./test.sh` is green.
2. In a scripted scenario with an incoming bandit, time from
   `threat_appeared` (system event) to the *crew* receiving it differs
   by ≥ 4× between elite and rookie crew.
3. With identical fleets but mixed awareness, low-awareness ships are
   first to die in ≥ 70% of trials.
4. No code references to `marksmanship`, `situational_awareness`,
   `anticipation`, `stats.skill` (legacy), or `missile_locked` remain.
   `grep` is clean.

## Definition of done

- [ ] All renames complete; legacy fields/events deleted.
- [ ] Threat prioritization wired into `identify_threats` callers.
- [ ] Mailbox latency wired at `_check_spatial_awareness_triggers` and
      damage-event sources.
- [ ] All tests pass.
- [ ] Zero compile warnings.
- [ ] Acceptance ticked.
