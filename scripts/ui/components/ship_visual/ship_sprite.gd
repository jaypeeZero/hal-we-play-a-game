class_name ShipSprite
extends RefCounted

## Static helper: resolves ship-type strings to their sprite textures.
## Single source of truth for sprite paths and team tint colours.
## All callers should use this instead of building paths directly.

const SPRITE_DIR := "res://assets/sprites/ships/"

## Authoritative ship types that have sprites on disk.
const KNOWN_TYPES: Array[String] = [
	"fighter",
	"heavy_fighter",
	"torpedo_boat",
	"corvette",
	"capital",
]

## Team tint colours (alpha intentionally opaque — apply via TextureRect.modulate).
## team 0 = player blue, team 1 = enemy red. Matches pre_battle.gd convention.
const TEAM_COLORS: Array[Color] = [
	Color(0.4, 0.7, 1.0, 1.0),  # team 0 — blue
	Color(1.0, 0.4, 0.4, 1.0),  # team 1 — red
]

## Fallback type used when the requested type is unknown.
const FALLBACK_TYPE := "fighter"


## Returns the Texture2D for the given ship type.
## Unknown types log a warning and return the fallback placeholder.
static func texture_for_type(ship_type: String) -> Texture2D:
	var resolved: String = ship_type
	if not ship_type in KNOWN_TYPES:
		push_warning("ShipSprite: unknown ship type '%s', falling back to '%s'" % [ship_type, FALLBACK_TYPE])
		resolved = FALLBACK_TYPE
	return load(SPRITE_DIR + resolved + ".png") as Texture2D


## Returns the team tint Color for a team index (0 or 1).
## Apply this to TextureRect.modulate. Unknown teams return white (no tint).
static func team_color(team: int) -> Color:
	if team >= 0 and team < TEAM_COLORS.size():
		return TEAM_COLORS[team]
	return Color.WHITE
