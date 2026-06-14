class_name EventSystem
extends RefCounted

## Pure functions for per-jump event generation, effect resolution, and
## temp-effect application at battle start.
##
## RoguelikeRun is the sole mutator: EventSystem decides, RoguelikeRun applies.
## All functions take a run_state snapshot and/or rng; none touch global state.
##
## run_state shape (caller builds this from RoguelikeRun vars):
## {
##   "hulls":        Array,   # fleet_hulls records
##   "crew":         Array,   # flat list of all crew dicts across all hulls
##   "star_date":    int,     # current_star_date (after advancing)
##   "places":       Array,   # Array[String] — place names from the campaign
##   "battle_count": int,     # number of battles fought this run (for min_battles)
## }


# ---------------------------------------------------------------------------
# GENERATION
# ---------------------------------------------------------------------------

## Generate all events for a jump of `date_delta` star dates.
## Returns an Array of resolved event records (polarity, headline, body,
## target, effects, seen:false). Pure: run_state and rng state both stay
## unmodified after the call returns (rng is advanced internally only).
static func generate_for_jump(run_state: Dictionary, date_delta: int, rng) -> Array:
	"""Roll the events that happened over a jump of `date_delta` star dates.
	Same seed + run_state always produces the same Array."""
	var count: int = clampi(
		roundi(float(date_delta) * WingConstants.EVENTS_PER_STARDATE),
		WingConstants.EVENTS_PER_JUMP_MIN,
		WingConstants.EVENTS_PER_JUMP_MAX
	)

	var events: Array = []
	for _i in range(count):
		var event: Dictionary = _roll_one_event(run_state, rng)
		if not event.is_empty():
			events.append(event)
	return events


# ---------------------------------------------------------------------------
# EFFECT RESOLUTION (pure split: caller applies)
# ---------------------------------------------------------------------------

## Classify the effects of a resolved event into permanent mutations and
## temp effects.  Returns:
## {
##   "permanent": Array[Dict],  # apply immediately to run state
##   "temp":      Array[Dict],  # push onto active_effects
## }
## Each permanent entry carries the original effect descriptor plus
## "resolved_target" so the caller knows what to mutate.
## Each temp entry is a ready-to-store active_effect record.
static func classify_effects(event: Dictionary) -> Dictionary:
	"""Classify event effects into permanent mutations vs temp active_effects records."""
	var permanent: Array = []
	var temp_effects: Array = []

	var target: Dictionary = event.get("target", {})

	for effect in event.get("effects", []):
		var duration: String = str(effect.get("duration", "permanent"))
		if duration == "permanent" or not duration.begins_with("battles:"):
			# Permanent — caller mutates in place
			var entry: Dictionary = effect.duplicate(true)
			entry["resolved_target"] = target.duplicate(true)
			permanent.append(entry)
		else:
			# Temporary (battles:N)
			var battles: int = _parse_battles(duration)
			var rec: Dictionary = {
				"kind": effect.get("kind", ""),
				"target": target.duplicate(true),
				"value": effect.get("value", 0.0),
				"expires_after_battles": battles,
			}
			# Copy kind-specific fields
			if effect.has("field"):
				rec["field"] = effect["field"]
			if effect.has("skill"):
				rec["skill"] = effect["skill"]
			if effect.has("scope"):
				rec["scope"] = effect["scope"]
			temp_effects.append(rec)

	return {"permanent": permanent, "temp": temp_effects}


# ---------------------------------------------------------------------------
# BATTLE-START TEMP-EFFECT APPLICATION
# ---------------------------------------------------------------------------

## Fold matching ship_modifier temp effects from active_effects onto a copy of
## ship_data's crew_modifiers.  Pure: returns a new dict; ignores effects that
## do not target this hull_id.
static func apply_active_ship_effects(
		ship_data: Dictionary, hull_id: String, active_effects: Array) -> Dictionary:
	"""Return updated ship_data with matching ship_modifier temp effects applied to crew_modifiers."""
	if active_effects.is_empty():
		return ship_data

	var updated: Dictionary = ship_data.duplicate(true)
	if not updated.has("crew_modifiers"):
		updated["crew_modifiers"] = {}

	for effect in active_effects:
		if effect.get("kind", "") != "ship_modifier":
			continue
		var t: Dictionary = effect.get("target", {})
		if t.get("kind", "") != "ship" or t.get("hull_id", "") != hull_id:
			continue
		var field: String = str(effect.get("field", ""))
		if field.is_empty():
			continue
		var value: float = float(effect.get("value", 0.0))
		updated["crew_modifiers"][field] = float(updated["crew_modifiers"].get(field, 0.0)) + value

	return updated


## Fold matching crew_skill temp effects from active_effects into a skills dict
## copy.  Pure: returns effective skills; stored skills are untouched.
static func apply_active_crew_skill(
		skills: Dictionary, crew_id: String, active_effects: Array) -> Dictionary:
	"""Return effective skills dict with matching temp crew_skill deltas folded in."""
	if active_effects.is_empty():
		return skills

	var effective: Dictionary = skills.duplicate(true)
	for effect in active_effects:
		if effect.get("kind", "") != "crew_skill":
			continue
		var t: Dictionary = effect.get("target", {})
		if t.get("kind", "") != "crew" or t.get("crew_id", "") != crew_id:
			continue
		var skill: String = str(effect.get("skill", ""))
		if skill.is_empty():
			continue
		var value: float = float(effect.get("value", 0.0))
		effective[skill] = clampf(float(effective.get(skill, 0.0)) + value, 0.0, 1.0)

	return effective


# ---------------------------------------------------------------------------
# BATTLE-END EXPIRY
# ---------------------------------------------------------------------------

## Decrement expires_after_battles on every active effect and return the
## surviving (non-expired) subset.  Pure: input array is unmodified.
static func tick_battle_effects(active_effects: Array) -> Array:
	"""Decrement battle counters; drop effects that reach 0. Pure."""
	var surviving: Array = []
	for effect in active_effects:
		var remaining: int = int(effect.get("expires_after_battles", 0)) - 1
		if remaining > 0:
			var updated: Dictionary = effect.duplicate(true)
			updated["expires_after_battles"] = remaining
			surviving.append(updated)
	return surviving


# ---------------------------------------------------------------------------
# PRIVATE HELPERS
# ---------------------------------------------------------------------------

## Roll one event from the candidate pool, bind a target, and resolve tokens.
## Returns {} when no valid candidate can be found.
static func _roll_one_event(run_state: Dictionary, rng) -> Dictionary:
	"""Pick one template, bind a target, and build the event record."""
	var candidates: Array = _build_candidate_pool(run_state)
	if candidates.is_empty():
		return {}

	# Build weighted list: {template, target, weight}
	var weighted: Array = []
	var total_weight: float = 0.0

	for tmpl in candidates:
		var id: String = str(tmpl.get("id", ""))
		var target_kind: String = str(tmpl.get("target", "none"))
		var bound_target: Dictionary = _bind_target(target_kind, run_state, rng)
		if bound_target.is_empty() and target_kind != "none":
			continue  # Could not bind a required target — skip this template

		# attribute_bias: if crew target, multiply in matching event_weights
		var bias: float = _attribute_bias(id, bound_target, run_state)
		var w: float = float(tmpl.get("weight", 1.0)) * bias
		if w <= 0.0:
			continue

		weighted.append({"tmpl": tmpl, "target": bound_target, "weight": w})
		total_weight += w

	if weighted.is_empty() or total_weight <= 0.0:
		return {}

	# Weighted pick
	var roll: float = rng.randf() * total_weight
	var acc: float = 0.0
	var chosen: Dictionary = weighted[-1]
	for entry in weighted:
		acc += float(entry.get("weight", 0.0))
		if roll <= acc:
			chosen = entry
			break

	return _resolve_event(chosen.tmpl, chosen.target, run_state, rng)


## Build candidate pool: all templates whose requires pass for run_state.
static func _build_candidate_pool(run_state: Dictionary) -> Array:
	"""Return templates from EventLibrary whose requires pass for run_state."""
	var all_templates: Dictionary = EventLibrary.all()
	var result: Array = []
	for id in all_templates:
		var tmpl: Dictionary = all_templates[id].duplicate(false)
		tmpl["id"] = id
		if _requires_pass(tmpl, run_state):
			result.append(tmpl)
	return result


## Check whether a template's requires dict is satisfied by run_state.
static func _requires_pass(tmpl: Dictionary, run_state: Dictionary) -> bool:
	"""Return true when all requires conditions are met."""
	var reqs = tmpl.get("requires")
	if reqs == null or not reqs is Dictionary:
		return true

	# requires.ship — at least one hull with a non-empty ship record
	if reqs.get("ship", false):
		var hulls: Array = run_state.get("hulls", [])
		var has_ship: bool = hulls.any(func(h): return not h.get("ship", {}).is_empty())
		if not has_ship:
			return false

	# requires.crew — at least one crew member across all hulls
	if reqs.get("crew", false):
		var crew: Array = run_state.get("crew", [])
		if crew.is_empty():
			return false

	# requires.min_battles — at least this many battles completed
	var min_b: int = int(reqs.get("min_battles", 0))
	if min_b > 0:
		if int(run_state.get("battle_count", 0)) < min_b:
			return false

	return true


## Bind a concrete target for the given target_kind from run_state.
## Returns the target dict, or {} when no eligible target exists.
## For non-crew bindings we return a light record; only crew gets a full dict.
static func _bind_target(target_kind: String, run_state: Dictionary, rng) -> Dictionary:
	"""Pick a concrete target of the requested kind."""
	match target_kind:
		"ship":
			var hulls: Array = run_state.get("hulls", [])
			var eligible: Array = hulls.filter(func(h): return not h.get("ship", {}).is_empty())
			if eligible.is_empty():
				# Fall back to any hull (pristine ships are still a ship)
				eligible = hulls
			if eligible.is_empty():
				return {}
			var hull: Dictionary = eligible[rng.randi() % eligible.size()]
			return {"kind": "ship", "hull_id": hull.get("hull_id", "")}

		"crew":
			var crew: Array = run_state.get("crew", [])
			if crew.is_empty():
				return {}
			var member: Dictionary = crew[rng.randi() % crew.size()]
			return {
				"kind": "crew",
				"crew_id": member.get("crew_id", ""),
				"callsign": member.get("callsign", ""),
			}

		"fleet":
			return {"kind": "fleet"}

		_:  # "none"
			return {"kind": "none"}


## Compute attribute bias for an event id against a bound target.
## For crew targets, multiply in each attribute's event_weights[event_id].
## For ship/fleet/none targets, returns 1.0.
static func _attribute_bias(event_id: String, bound_target: Dictionary, run_state: Dictionary) -> float:
	"""Return the attribute-based weight multiplier for this event+target pair."""
	if bound_target.get("kind", "") != "crew":
		return 1.0

	var crew_id: String = str(bound_target.get("crew_id", ""))
	var crew: Array = run_state.get("crew", [])
	var member: Dictionary = {}
	for m in crew:
		if m.get("crew_id", "") == crew_id:
			member = m
			break

	if member.is_empty():
		return 1.0

	var bias: float = 1.0
	for attr_id in member.get("attributes", []):
		var defn: Dictionary = AttributeLibrary.get_def(str(attr_id))
		if defn.is_empty():
			continue
		var weights: Dictionary = defn.get("event_weights", {})
		if weights.has(event_id):
			bias *= float(weights[event_id])

	return bias


## Build the resolved event record from a template + bound target.
static func _resolve_event(tmpl: Dictionary, bound_target: Dictionary, run_state: Dictionary, rng) -> Dictionary:
	"""Resolve tokens and build the final event record."""
	var id: String = str(tmpl.get("id", ""))
	var headline: String = str(tmpl.get("headline", ""))
	var body: String = str(tmpl.get("body", ""))

	# Resolve {ship_name}
	if headline.contains("{ship_name}") or body.contains("{ship_name}"):
		var ship_name: String = _resolve_ship_name(bound_target, run_state)
		headline = headline.replace("{ship_name}", ship_name)
		body = body.replace("{ship_name}", ship_name)

	# Resolve {callsign}
	if headline.contains("{callsign}") or body.contains("{callsign}"):
		var callsign: String = str(bound_target.get("callsign", "unknown"))
		headline = headline.replace("{callsign}", callsign)
		body = body.replace("{callsign}", callsign)

	# Resolve {place}
	if headline.contains("{place}") or body.contains("{place}"):
		var place_name: String = _resolve_place(run_state, rng)
		headline = headline.replace("{place}", place_name)
		body = body.replace("{place}", place_name)

	return {
		"id": id,
		"star_date": int(run_state.get("star_date", 0)),
		"category": str(tmpl.get("category", "")),
		"headline": headline,
		"body": body,
		"target": bound_target.duplicate(true),
		"polarity": str(tmpl.get("polarity", "neutral")),
		"effects": tmpl.get("effects", []).duplicate(true),
		"seen": false,
	}


static func _resolve_ship_name(bound_target: Dictionary, run_state: Dictionary) -> String:
	"""Look up the ship name for a ship-kind target from hull identity."""
	if bound_target.get("kind", "") != "ship":
		return "unknown"
	var hull_id: String = str(bound_target.get("hull_id", ""))
	for hull in run_state.get("hulls", []):
		if hull.get("hull_id", "") == hull_id:
			return str(hull.get("ship_name", hull.get("ship_type", "unknown")))
	return "unknown"


static func _resolve_place(run_state: Dictionary, rng) -> String:
	"""Pick a random place name from the places list, or fallback."""
	var places: Array = run_state.get("places", [])
	if places.is_empty():
		return "an unknown sector"
	var idx: int = rng.randi() % places.size()
	return str(places[idx])


static func _parse_battles(duration: String) -> int:
	"""Parse 'battles:N' into integer N. Returns 1 on malformed input."""
	var parts: Array = duration.split(":")
	if parts.size() == 2:
		return maxi(1, int(parts[1]))
	return 1
