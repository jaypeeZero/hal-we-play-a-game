class_name TacticsSystem
extends RefCounted

## Emergent combat tactics: dial resolution for the fleet → squadron → ship
## inheritance model (plans/emergent-combat-tactics/01-tactics-model.md).
##
## Four dial families per ship:
##   1. Formation & spatial shape  (shape, spacing, depth, anchor, line_height)
##   2. Mentality & engagement range  (mentality, engagement_range, line_height)
##   3. Targeting & focus-fire  (concentration, priority, sector_focus)
##   4. Roles, duties & pursuit discipline  (role, duty, pursuit_discipline)
##
## Resolution order (most specific wins, per dial):
##   ship_override → role_default → squadron → fleet → engine_default
##
## Every ship is the atomic unit (the "footballer"). Role/duty are ship-level.
## Squadron- and fleet-level role/duty are just inherited defaults.
##
## Nothing in this file mutates game state. No global mutable state except the
## lazy preset cache (_presets / _presets_loaded), mirroring DoctrineSystem.

const PRESETS_PATH := "res://data/tactics/doctrine_presets.json"

# ---------------------------------------------------------------------------
# Ordinal → scalar mappings (named consts; no magic numbers anywhere)
# ---------------------------------------------------------------------------

## Mentality ordinal values → 0..1 aggression scalar.
## defensive=0, cautious=0.25, balanced=0.5, attacking=0.75, all_out=1.0
const MENTALITY_SCALE: Dictionary = {
	"defensive": 0.0,
	"cautious":  0.25,
	"balanced":  0.5,
	"attacking": 0.75,
	"all_out":   1.0,
}

## Engagement-range ordinal → 0..1 preferred-range factor.
## 0 = closest possible (knife); 1 = maximum standoff (kite).
const ENGAGEMENT_RANGE_SCALE: Dictionary = {
	"knife":    0.0,
	"close":    0.25,
	"optimal":  0.5,
	"standoff": 0.75,
	"kite":     1.0,
}

## Valid shape presets. Guards against typos in preset JSON.
const VALID_SHAPES: Array = [
	"wall", "wedge", "layered", "vanguard_reserve", "line_abreast", "globe",
]

## Valid targeting priorities.
const VALID_PRIORITIES: Array = [
	"capitals_first", "fighters_first", "weakest_first", "command_first", "nearest",
]

## Valid sector focus values.
const VALID_SECTOR_FOCUS: Array = ["none", "left", "center", "right"]

## Valid anchor types.
const VALID_ANCHORS: Array = ["enemy_centroid"]

## Valid duty values.
const VALID_DUTIES: Array = ["hold", "support", "press"]

# ---------------------------------------------------------------------------
# Role bundles — default dial values keyed by role name.
# The role is a *named bundle of dial defaults*, not a mode.
# These are the per-ship weights that role-level inheritance provides when
# neither squadron nor fleet sets the dial explicitly.
# ---------------------------------------------------------------------------

## anchor/brawler: hold center, close range, absorb fire.
const ROLE_ANCHOR: Dictionary = {
	"mentality":          "cautious",
	"engagement_range":   "close",
	"duty":               "hold",
	"pursuit_discipline": 0.15,
	"concentration":      0.5,
	"priority":           "nearest",
	"shape":              "wall",
	"spacing":            0.2,
	"depth":              0.2,
	"line_height":        0.4,
	"sector_focus":       "none",
	"anchor":             "enemy_centroid",
}

## skirmisher: mid-range harassment, moderate aggression, some chase.
const ROLE_SKIRMISHER: Dictionary = {
	"mentality":          "balanced",
	"engagement_range":   "optimal",
	"duty":               "support",
	"pursuit_discipline": 0.5,
	"concentration":      0.3,
	"priority":           "weakest_first",
	"shape":              "line_abreast",
	"spacing":            0.5,
	"depth":              0.3,
	"line_height":        0.5,
	"sector_focus":       "none",
	"anchor":             "enemy_centroid",
}

## interceptor: fast, aggressive, chases fighters.
const ROLE_INTERCEPTOR: Dictionary = {
	"mentality":          "attacking",
	"engagement_range":   "close",
	"duty":               "press",
	"pursuit_discipline": 0.8,
	"concentration":      0.4,
	"priority":           "fighters_first",
	"shape":              "wedge",
	"spacing":            0.4,
	"depth":              0.2,
	"line_height":        0.7,
	"sector_focus":       "none",
	"anchor":             "enemy_centroid",
}

## artillery: standoff firepower, stays back, spread fire.
const ROLE_ARTILLERY: Dictionary = {
	"mentality":          "defensive",
	"engagement_range":   "standoff",
	"duty":               "hold",
	"pursuit_discipline": 0.05,
	"concentration":      0.7,
	"priority":           "capitals_first",
	"shape":              "layered",
	"spacing":            0.3,
	"depth":              0.8,
	"line_height":        0.2,
	"sector_focus":       "none",
	"anchor":             "enemy_centroid",
}

## flanker: wide sweep, sector-focused, press discipline.
const ROLE_FLANKER: Dictionary = {
	"mentality":          "attacking",
	"engagement_range":   "close",
	"duty":               "press",
	"pursuit_discipline": 0.75,
	"concentration":      0.6,
	"priority":           "weakest_first",
	"shape":              "wedge",
	"spacing":            0.6,
	"depth":              0.3,
	"line_height":        0.65,
	"sector_focus":       "right",
	"anchor":             "enemy_centroid",
}

## screen: protective screen in front of friendlies, intercept threats.
const ROLE_SCREEN: Dictionary = {
	"mentality":          "cautious",
	"engagement_range":   "optimal",
	"duty":               "support",
	"pursuit_discipline": 0.3,
	"concentration":      0.2,
	"priority":           "nearest",
	"shape":              "vanguard_reserve",
	"spacing":            0.4,
	"depth":              0.1,
	"line_height":        0.55,
	"sector_focus":       "none",
	"anchor":             "enemy_centroid",
}

## Dispatch table: role name → bundle. Used by resolve_tactics().
const ROLE_BUNDLES: Dictionary = {
	"anchor":      ROLE_ANCHOR,
	"brawler":     ROLE_ANCHOR,      # alias — same playstyle
	"skirmisher":  ROLE_SKIRMISHER,
	"interceptor": ROLE_INTERCEPTOR,
	"artillery":   ROLE_ARTILLERY,
	"flanker":     ROLE_FLANKER,
	"screen":      ROLE_SCREEN,
}

# ---------------------------------------------------------------------------
# Engine defaults — the baseline every dial falls through to if nothing
# above it in the inheritance chain is set. Produces coherent behavior for
# an unconfigured ship.
# ---------------------------------------------------------------------------
const ENGINE_DEFAULTS: Dictionary = {
	# Formation & spatial shape
	"shape":              "line_abreast",
	"spacing":            0.5,
	"depth":              0.5,
	"anchor":             "enemy_centroid",
	"line_height":        0.5,
	# Mentality & engagement range
	"mentality":          "balanced",
	"engagement_range":   "optimal",
	# Targeting & focus-fire
	"concentration":      0.5,
	"priority":           "nearest",
	"sector_focus":       "none",
	# Roles, duties & pursuit discipline
	"role":               "skirmisher",
	"duty":               "support",
	"pursuit_discipline": 0.5,
}

## All dial keys that resolve_tactics() guarantees in its output.
## Any new dial must appear here AND in ENGINE_DEFAULTS.
const ALL_DIAL_KEYS: Array = [
	"shape", "spacing", "depth", "anchor", "line_height",
	"mentality", "engagement_range",
	"concentration", "priority", "sector_focus",
	"role", "duty", "pursuit_discipline",
]

# ---------------------------------------------------------------------------
# Lazy preset cache (mirrors DoctrineSystem._templates pattern)
# ---------------------------------------------------------------------------

static var _presets: Dictionary = {}
static var _presets_loaded := false


static func _ensure_presets_loaded() -> void:
	## Load presets from JSON on first access. No-op on subsequent calls.
	if _presets_loaded:
		return
	_presets_loaded = true
	var raw := FileAccess.get_file_as_string(PRESETS_PATH)
	if raw.is_empty():
		push_error("TacticsSystem: cannot read %s" % PRESETS_PATH)
		return
	var data = JSON.parse_string(raw)
	if not data is Dictionary:
		push_error("TacticsSystem: invalid JSON in %s" % PRESETS_PATH)
		return
	_presets = data


static func get_all_presets() -> Dictionary:
	## Returns the full preset catalog (keyed by preset id).
	_ensure_presets_loaded()
	return _presets


static func get_preset(preset_id: String) -> Dictionary:
	## Returns one preset dict, or {} if not found.
	_ensure_presets_loaded()
	return _presets.get(preset_id, {})


# ---------------------------------------------------------------------------
# Core resolution
# ---------------------------------------------------------------------------

## Resolve every dial for ONE ship, collapsing the inheritance chain:
##   ship_override → role_default → squadron → fleet → engine_default
##
## Parameters
##   fleet_tactics     : Dictionary  — fleet-level dial overrides (may be {})
##   squadron_tactics  : Dictionary  — squadron-level dial overrides (may be {})
##   ship_role         : String      — role name; selects the role bundle
##   ship_override     : Dictionary  — per-ship dial overrides (may be {})
##
## Returns a flat ResolvedTactics Dictionary with every key in ALL_DIAL_KEYS
## populated (no missing keys guaranteed).
##
## Key types:
##   shape             : String   — one of VALID_SHAPES
##   spacing           : float    — 0..1 tight↔dispersed
##   depth             : float    — 0..1 class-layering strength
##   anchor            : String   — one of VALID_ANCHORS
##   line_height       : float    — 0..1 how far forward of anchor
##   mentality         : String   — one of MENTALITY_SCALE keys
##   engagement_range  : String   — one of ENGAGEMENT_RANGE_SCALE keys
##   concentration     : float    — 0..1 spread↔focus-fire
##   priority          : String   — one of VALID_PRIORITIES
##   sector_focus      : String   — one of VALID_SECTOR_FOCUS
##   role              : String   — one of ROLE_BUNDLES keys
##   duty              : String   — one of VALID_DUTIES
##   pursuit_discipline: float    — 0..1 hold-formation↔break-to-chase
##   mentality_scalar  : float    — derived; MENTALITY_SCALE[mentality]
##   range_scalar      : float    — derived; ENGAGEMENT_RANGE_SCALE[engagement_range]
static func resolve_tactics(
	fleet_tactics: Dictionary,
	squadron_tactics: Dictionary,
	ship_role: String,
	ship_override: Dictionary
) -> Dictionary:
	var role_bundle: Dictionary = ROLE_BUNDLES.get(ship_role, {})
	var resolved := {}

	for dial in ALL_DIAL_KEYS:
		# Most specific first; fall through each scope until a value is found.
		if ship_override.has(dial):
			resolved[dial] = ship_override[dial]
		elif role_bundle.has(dial):
			resolved[dial] = role_bundle[dial]
		elif squadron_tactics.has(dial):
			resolved[dial] = squadron_tactics[dial]
		elif fleet_tactics.has(dial):
			resolved[dial] = fleet_tactics[dial]
		else:
			resolved[dial] = ENGINE_DEFAULTS[dial]

	# Derived scalars — computed once so callers never re-map the ordinals.
	resolved["mentality_scalar"] = MENTALITY_SCALE.get(resolved["mentality"], 0.5)
	resolved["range_scalar"]     = ENGAGEMENT_RANGE_SCALE.get(resolved["engagement_range"], 0.5)

	return resolved


## Convenience: resolve tactics directly from a named preset.
## squadron_id selects a squadron block inside the preset (may be "").
## ship_role and ship_override work the same as resolve_tactics().
static func resolve_from_preset(
	preset_id: String,
	squadron_id: String,
	ship_role: String,
	ship_override: Dictionary = {}
) -> Dictionary:
	## Extracts fleet/squadron dicts from the preset then delegates to resolve_tactics().
	var preset := get_preset(preset_id)
	if preset.is_empty():
		return resolve_tactics({}, {}, ship_role, ship_override)
	var fleet_tactics: Dictionary  = preset.get("fleet", {})
	var squadron_tactics: Dictionary = {}
	if not squadron_id.is_empty():
		squadron_tactics = preset.get("squadrons", {}).get(squadron_id, {})
	return resolve_tactics(fleet_tactics, squadron_tactics, ship_role, ship_override)


## Compute the mentality scalar for a resolved tactics dict.
## Convenience so callers don't import the const table.
static func mentality_scalar(resolved: Dictionary) -> float:
	## Returns 0..1; 0=defensive, 1=all_out.
	return resolved.get("mentality_scalar", 0.5)


## Compute the engagement-range scalar for a resolved tactics dict.
static func range_scalar(resolved: Dictionary) -> float:
	## Returns 0..1; 0=knife, 1=kite.
	return resolved.get("range_scalar", 0.5)


# Run-state structure

## Default (empty) tactics run-state dict. Shape mirrors DoctrineSystem.empty_doctrine():
## fleet and squadron dicts are scopes for dial overrides; ship_overrides is keyed by hull_id.
## Passing all three empty to resolve_tactics() yields coherent engine defaults — no behavior change.
static func empty_tactics() -> Dictionary:
	return {"fleet": {}, "squadrons": {}, "ship_overrides": {}}


# Ship-class → default role (the ship is the "footballer"; role is overridable by doctrine)
# These defaults are used when neither the squadron nor fleet scope in tactics_doctrine sets a role.
# Keys are the ship_type strings from data/ship_templates/ (fighter.json, etc.).
const SHIP_CLASS_ROLES: Dictionary = {
	"fighter":       "interceptor",
	"heavy_fighter": "skirmisher",
	"torpedo_boat":  "skirmisher",
	"corvette":      "brawler",
	"capital":       "anchor",
}

## Default role when ship_type is not in SHIP_CLASS_ROLES.
const DEFAULT_ROLE := "brawler"


# Crew compilation (battle spawn)

## Resolve combat tactics for one crew member and attach the result to crew["tactics"].
## Pure: returns a duplicate of crew with tactics block attached; input is never mutated.
##
## Why this exists: mirrors DoctrineSystem.compile_for_crew() for the tactics system.
## Called at battle spawn so the resolved tactics block is attached once and read
## by the steering blender every decision, without re-resolving it each tick.
##
## Role resolution order:
##   ship_overrides[hull_id].role  (per-ship override in the tactics doctrine)
##   squadrons[squadron_id].role   (squadron default)
##   fleet.role                    (fleet default)
##   SHIP_CLASS_ROLES[ship_type]   (class default — the footballer's natural position)
##   DEFAULT_ROLE                  (final fallback)
static func compile_for_crew(
	crew: Dictionary,
	ship_type: String,
	squadron_id: String,
	tactics_doctrine: Dictionary
) -> Dictionary:
	var updated: Dictionary = crew.duplicate(true)

	var fleet_tactics: Dictionary    = tactics_doctrine.get("fleet", {})
	var squadron_tactics: Dictionary = tactics_doctrine.get("squadrons", {}).get(squadron_id, {})
	var ship_override: Dictionary    = tactics_doctrine.get("ship_overrides", {}).get(updated.get("hull_id", ""), {})

	# Determine the ship's role from the most specific scope that sets it,
	# falling back through the class default so unconfigured ships still get
	# a sensible role bundle without requiring the player to set one.
	var ship_role: String = (
		ship_override.get("role",
		squadron_tactics.get("role",
		fleet_tactics.get("role",
		SHIP_CLASS_ROLES.get(ship_type, DEFAULT_ROLE))))
	)

	updated["tactics"] = resolve_tactics(fleet_tactics, squadron_tactics, ship_role, ship_override)
	return updated
