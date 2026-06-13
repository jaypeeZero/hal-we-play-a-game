class_name DestinationNamer
extends RefCounted

## Rolls flavor names for campaign destinations. Names are unique within a
## run: pass the same `used` dictionary across all calls so duplicates are
## detected and suffixed.

const SYSTEM_PREFIXES := [
	"Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
	"Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi",
	"Rho", "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega",
]

const SYSTEM_ROOTS := [
	"Cygni", "Draconis", "Eridani", "Lyrae", "Orionis", "Persei", "Tauri",
	"Ceti", "Hydrae", "Aquilae", "Centauri", "Carinae", "Velorum", "Serpentis",
	"Corvi", "Leonis", "Pavonis", "Crucis", "Lupi", "Scorpii",
]

const SHOP_NAMES := [
	"The Rust Bucket Exchange",
	"Honest Gorlak's Emporium",
	"Bolt & Plasma Outfitters",
	"Comet-Mart",
	"The Greasy Wrench",
	"Salvage & Sons",
	"Nebula Surplus",
	"Void Trader Co.",
	"The Hull Hoarder",
	"Starport Seconds",
	"Drift Market",
	"The Iron Bazaar",
	"Quasar Quick-Mart",
	"Cosmic Closeouts",
]

const RANDR_NAMES := [
	"The Slushy Pillow",
	"SuperRest TM!",
	"The Snoring Nebula",
	"Zero-G Spa & Lounge",
	"The Drowsy Drydock",
	"Hotel Heliopause",
	"The Long Nap",
	"Void Retreat",
	"Cosmic Comfort Inn",
	"The Quiet Void",
	"Stellar Slumber",
	"Gravity-Free Getaway",
	"The Drifting Hammock",
	"Pulsar Pillow Palace",
]

## Suffix applied to duplicate names, starting at this number.
const COLLISION_SUFFIX_START := 2


## Roll a flavor name for `node_type`, using `rng` for randomness.
## `used` maps name -> true for all names already claimed this campaign;
## it is mutated in place so the caller shares uniqueness across calls.
static func roll_name(node_type: String, rng: RandomNumberGenerator, used: Dictionary) -> String:
	var base := _pick_base(node_type, rng)
	var candidate := base
	var suffix := COLLISION_SUFFIX_START
	while used.has(candidate):
		candidate = "%s %d" % [base, suffix]
		suffix += 1
	used[candidate] = true
	return candidate


static func _pick_base(node_type: String, rng: RandomNumberGenerator) -> String:
	match node_type:
		CampaignSystem.NODE_TYPE_SHOP:
			return SHOP_NAMES[rng.randi() % SHOP_NAMES.size()]
		CampaignSystem.NODE_TYPE_RANDR:
			return RANDR_NAMES[rng.randi() % RANDR_NAMES.size()]
		_:
			var prefix: String = SYSTEM_PREFIXES[rng.randi() % SYSTEM_PREFIXES.size()]
			var root: String = SYSTEM_ROOTS[rng.randi() % SYSTEM_ROOTS.size()]
			return "%s %s" % [prefix, root]
