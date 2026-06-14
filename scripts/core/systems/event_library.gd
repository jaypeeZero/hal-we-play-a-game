class_name EventLibrary
extends RefCounted

## Loads and validates the event template library from JSON.
## Mirrors the AttributeLibrary / CrewRosterManager pattern:
## validate on load, drop bad rows with push_warning.
##
## Event templates are a flat map: id -> template. The generator
## selects from this pool each jump; this library only owns the data.

const LIBRARY_PATH := "res://data/events/event_library.json"

## Known effect kinds. Templates containing any other kind are dropped.
const VALID_EFFECT_KINDS := [
	"crew_skill",
	"ship_modifier",
	"ship_repair",
	"ship_damage",
	"add_attribute",
	"remove_attribute",
	"money",
	"intel",
]

## Required top-level fields on every event template.
const REQUIRED_FIELDS := ["category", "target", "weight", "polarity", "headline", "body", "effects"]

## Valid target values.
const VALID_TARGETS := ["ship", "crew", "fleet", "none"]

static var _cache: Dictionary = {}
static var _loaded: bool = false


## All validated event templates, keyed by id.
static func all() -> Dictionary:
	"""Return the full event library as an id -> template map."""
	_ensure_loaded()
	return _cache


## Return a single template by id, or {} when absent.
static func get_template(id: String) -> Dictionary:
	"""Return the template for `id`, or an empty dict when absent."""
	_ensure_loaded()
	return _cache.get(id, {})


## Stub: returns all templates. Phase 3 will filter by run_state requires.
## Signature is fixed so callers don't change when the real filter lands.
static func candidates(_run_state: Dictionary) -> Array:
	"""Return templates whose requires pass for the given run state.
	Phase 0 stub — returns all templates; filtering is Phase 3."""
	_ensure_loaded()
	return _cache.values()


## Drop the in-memory cache so the next call re-reads from disk.
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
		push_error("EventLibrary: file missing: " + LIBRARY_PATH)
		return {}

	var file := FileAccess.open(LIBRARY_PATH, FileAccess.READ)
	if file == null:
		push_error("EventLibrary: cannot open: " + LIBRARY_PATH)
		return {}

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_error("EventLibrary: JSON parse error: " + json.get_error_message())
		return {}

	var raw = json.get_data()
	if not raw is Dictionary:
		push_error("EventLibrary: expected a top-level JSON object")
		return {}

	var validated: Dictionary = {}
	for id in raw:
		var entry = raw[id]
		if not entry is Dictionary:
			push_warning("EventLibrary: skipping non-dict entry for id '%s'" % id)
			continue

		var ok := true
		for field in REQUIRED_FIELDS:
			if not entry.has(field):
				push_warning("EventLibrary: entry '%s' missing required field '%s' — skipped" % [id, field])
				ok = false
				break
		if not ok:
			continue

		if not VALID_TARGETS.has(entry["target"]):
			push_warning("EventLibrary: entry '%s' has unknown target '%s' — skipped" % [id, entry["target"]])
			continue

		if not entry["effects"] is Array:
			push_warning("EventLibrary: entry '%s' effects is not an Array — skipped" % id)
			continue

		# Validate each effect descriptor
		var effects_ok := true
		for effect in entry["effects"]:
			if not effect is Dictionary or not effect.has("kind"):
				push_warning("EventLibrary: entry '%s' has malformed effect — skipped" % id)
				effects_ok = false
				break
			if not VALID_EFFECT_KINDS.has(effect["kind"]):
				push_warning("EventLibrary: entry '%s' has unknown effect kind '%s' — skipped" % [id, effect["kind"]])
				effects_ok = false
				break
		if not effects_ok:
			continue

		validated[id] = entry

	return validated
