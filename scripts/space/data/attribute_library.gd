class_name AttributeLibrary
extends RefCounted

## Loads and validates the attribute definition library from JSON.
## Mirrors the CrewRosterManager pattern: validate on load, drop bad rows
## with a push_warning rather than failing the whole file.
##
## Attributes are a flat map: id -> definition. Crew members hold only the
## id string; this library provides the meaning.

const LIBRARY_PATH := "res://data/attributes/attribute_library.json"

## Known combat effect kinds. Entries with any other kind are dropped.
const VALID_COMBAT_KINDS := [
	"close_range_fire_rate",
	"lead_accuracy",
	"composure_factor",
	"turn_rate",
	"aggression",
	"accel",
	"last_stand",
]

## Required top-level fields on every attribute definition.
const REQUIRED_FIELDS := ["display_name", "blurb", "category", "polarity", "roles", "rarity", "combat", "event_weights"]

static var _cache: Dictionary = {}
static var _loaded: bool = false


## All validated attribute definitions, keyed by id.
static func all() -> Dictionary:
	"""Return the full attribute library as an id -> definition map."""
	_ensure_loaded()
	return _cache


## Return the definition for a single attribute id, or {} when absent.
static func get_def(id: String) -> Dictionary:
	"""Return the definition for `id`, or an empty dict when absent."""
	_ensure_loaded()
	return _cache.get(id, {})


## Attributes whose `roles` list includes the given role name (or is empty,
## meaning universal) and whose `combat` field is non-null. Used to filter
## the combat-relevant pool for a particular crew role.
static func combat_attributes_for(role: int) -> Array:
	"""Return combat-bearing definitions relevant to `role` (CrewData.Role int)."""
	_ensure_loaded()
	var role_name: String = CrewData.role_to_name(role)
	var result: Array = []
	for id in _cache:
		var defn: Dictionary = _cache[id]
		if defn.combat == null:
			continue
		var roles: Array = defn.roles
		if roles.is_empty() or roles.has(role_name):
			result.append(defn)
	return result


## Roll a set of attribute ids for a newly generated crew member.
## count is sampled from [ATTRIBUTES_PER_CREW_MIN, ATTRIBUTES_PER_CREW_MAX].
## Candidates: eligible by role (universal or contains role_name), rarity > 0,
## not grantable_by_events_only. Weighted by rarity. With
## ATTRIBUTE_NEGATIVE_QUIRK_CHANCE one slot is filled from negative-polarity
## candidates instead. Sampled without replacement; never two ids sharing the
## same combat.kind. Pure — rng is passed in for seedable generation.
static func roll_attributes(role: int, rng: RandomNumberGenerator) -> Array:
	"""Roll a set of attribute ids appropriate for `role` using `rng`."""
	_ensure_loaded()
	var role_name: String = CrewData.role_to_name(role)
	var count: int = rng.randi_range(WingConstants.ATTRIBUTES_PER_CREW_MIN, WingConstants.ATTRIBUTES_PER_CREW_MAX)

	# Build positive/neutral candidate pool: eligible by role, rarity > 0, not events-only.
	var pos_pool: Array = []
	var neg_pool: Array = []
	for id in _cache:
		var defn: Dictionary = _cache[id]
		if defn.get("grantable_by_events_only", false):
			continue
		var rarity: float = float(defn.get("rarity", 0.0))
		if rarity <= 0.0:
			continue
		var roles: Array = defn.get("roles", [])
		if not roles.is_empty() and not roles.has(role_name):
			continue
		if defn.get("polarity", "neutral") == "negative":
			neg_pool.append({"id": id, "defn": defn, "rarity": rarity})
		else:
			pos_pool.append({"id": id, "defn": defn, "rarity": rarity})

	var result_ids: Array = []
	var used_kinds: Dictionary = {}  # combat.kind -> true

	# Decide whether to include a negative slot.
	var use_negative: bool = rng.randf() < WingConstants.ATTRIBUTE_NEGATIVE_QUIRK_CHANCE and not neg_pool.is_empty()
	var neg_slots: int = 1 if use_negative else 0
	var pos_slots: int = count - neg_slots

	# Fill positive/neutral slots.
	for _i in range(pos_slots):
		var pick: String = _weighted_pick(pos_pool, result_ids, used_kinds, rng)
		if pick.is_empty():
			break
		result_ids.append(pick)
		var kind: String = _cache[pick].get("combat", {}).get("kind", "") if _cache[pick].get("combat") != null else ""
		if not kind.is_empty():
			used_kinds[kind] = true

	# Fill negative slot(s).
	for _i in range(neg_slots):
		var pick: String = _weighted_pick(neg_pool, result_ids, used_kinds, rng)
		if pick.is_empty():
			break
		result_ids.append(pick)
		var kind: String = _cache[pick].get("combat", {}).get("kind", "") if _cache[pick].get("combat") != null else ""
		if not kind.is_empty():
			used_kinds[kind] = true

	return result_ids


## Weighted random pick from `pool` excluding already-used ids and kinds.
## Returns "" when no valid candidate remains.
static func _weighted_pick(pool: Array, used_ids: Array, used_kinds: Dictionary, rng: RandomNumberGenerator) -> String:
	"""Pick one entry from `pool` by rarity weight, excluding already-chosen ids and kinds."""
	var candidates: Array = []
	var total_weight: float = 0.0
	for entry in pool:
		var id: String = entry.id
		if used_ids.has(id):
			continue
		var combat = _cache[id].get("combat")
		if combat != null:
			var kind: String = combat.get("kind", "")
			if not kind.is_empty() and used_kinds.has(kind):
				continue
		candidates.append(entry)
		total_weight += entry.rarity

	if candidates.is_empty() or total_weight <= 0.0:
		return ""

	var roll: float = rng.randf() * total_weight
	var acc: float = 0.0
	for entry in candidates:
		acc += entry.rarity
		if roll <= acc:
			return entry.id
	return candidates[-1].id


## Drop the in-memory cache so the next call re-reads from disk.
## Useful in tests that write new data.
static func invalidate_cache() -> void:
	"""Clear the cached library; forces a reload on next access."""
	_cache = {}
	_loaded = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_cache = _load_and_validate()
	_loaded = true


static func _load_and_validate() -> Dictionary:
	if not FileAccess.file_exists(LIBRARY_PATH):
		push_error("AttributeLibrary: file missing: " + LIBRARY_PATH)
		return {}

	var file := FileAccess.open(LIBRARY_PATH, FileAccess.READ)
	if file == null:
		push_error("AttributeLibrary: cannot open: " + LIBRARY_PATH)
		return {}

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_error("AttributeLibrary: JSON parse error: " + json.get_error_message())
		return {}

	var raw = json.get_data()
	if not raw is Dictionary:
		push_error("AttributeLibrary: expected a top-level JSON object")
		return {}

	var validated: Dictionary = {}
	for id in raw:
		var entry = raw[id]
		if not entry is Dictionary:
			push_warning("AttributeLibrary: skipping non-dict entry for id '%s'" % id)
			continue

		var ok := true
		for field in REQUIRED_FIELDS:
			if not entry.has(field):
				push_warning("AttributeLibrary: entry '%s' missing required field '%s' — skipped" % [id, field])
				ok = false
				break
		if not ok:
			continue

		# Validate combat block if present
		var combat = entry.get("combat")
		if combat != null:
			if not combat is Dictionary or not combat.has("kind"):
				push_warning("AttributeLibrary: entry '%s' has malformed combat block — skipped" % id)
				continue
			if not VALID_COMBAT_KINDS.has(combat["kind"]):
				push_warning("AttributeLibrary: entry '%s' has unknown combat kind '%s' — skipped" % [id, combat["kind"]])
				continue

		validated[id] = entry

	return validated
