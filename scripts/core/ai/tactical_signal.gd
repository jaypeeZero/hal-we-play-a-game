class_name TacticalSignal

## Represents a tactical event/signal emitted by creatures to communicate tactical information
## to the TacticalInfluenceMap without direct creature-to-creature communication.

enum Type {
	# Basic signals (simple swarms like rats)
	PRESENCE,           # "I'm here" - updates ally density
	PANIC,             # "Danger here!" - spreads fear
	NEAR_DEATH,        # "I'm critically wounded" - generic low health signal

	# Pack signals (coordinated hunters like wolves)
	TARGET_SPOTTED,    # "Enemy at location X"
	ATTACKING,         # "I'm engaging enemy Y"
	NEED_SUPPORT,      # "Help me at location Z"
	KILL_CONFIRMED,    # "Enemy eliminated"

	# Elite signals (tactical units like goblins)
	FLANKING_OPPORTUNITY,  # "Attack from this angle"
	DEFENSIVE_POSITION,    # "Hold this ground"
	RETREAT_SUGGESTED,     # "Fall back to position X"
	FOCUS_FIRE,           # "All units target entity Y"
	SUPPRESS_AREA         # "Keep enemies away from zone Z"
}

# Core data
var signal_type: Type
var position: Vector2           # Where is this signal relevant?
var emitter_id: int             # Which creature sent this?
var owner_id: int               # Which player owns the emitter?
var coordination_group_id: String = ""  # Which tactical group (for granular coordination)
var strength: float = 1.0       # How strong is this signal?
var radius: float = 100.0       # How far does it influence?
var duration: float = 2.0       # How long does it last?

# Optional context
var target_entity: Node2D = null  # For TARGET_SPOTTED, ATTACKING, etc.
var direction: Vector2 = Vector2.ZERO  # For FLANKING_OPPORTUNITY, RETREAT_SUGGESTED


## Static factory methods for convenience

static func presence(pos: Vector2, owner: int, emitter: int) -> TacticalSignal:
	var sig = TacticalSignal.new()
	sig.signal_type = Type.PRESENCE
	sig.position = pos
	sig.owner_id = owner
	sig.emitter_id = emitter
	sig.strength = 0.5
	sig.radius = 50.0
	sig.duration = 0.5
	return sig


static func panic(pos: Vector2, owner: int, emitter: int) -> TacticalSignal:
	var sig = TacticalSignal.new()
	sig.signal_type = Type.PANIC
	sig.position = pos
	sig.owner_id = owner
	sig.emitter_id = emitter
	sig.strength = 2.0
	sig.radius = 150.0
	sig.duration = 3.0
	return sig


static func near_death(pos: Vector2, owner: int, emitter: int) -> TacticalSignal:
	var sig = TacticalSignal.new()
	sig.signal_type = Type.NEAR_DEATH
	sig.position = pos
	sig.owner_id = owner
	sig.emitter_id = emitter
	sig.strength = 1.5
	sig.radius = 100.0
	sig.duration = 2.0
	return sig


static func target_spotted(pos: Vector2, target: Node2D, owner: int, emitter: int) -> TacticalSignal:
	var sig = TacticalSignal.new()
	sig.signal_type = Type.TARGET_SPOTTED
	sig.position = pos
	sig.target_entity = target
	sig.owner_id = owner
	sig.emitter_id = emitter
	sig.strength = 1.5
	sig.radius = 200.0
	sig.duration = 4.0
	return sig


static func attacking(pos: Vector2, target: Node2D, owner: int, emitter: int) -> TacticalSignal:
	var sig = TacticalSignal.new()
	sig.signal_type = Type.ATTACKING
	sig.position = pos
	sig.target_entity = target
	sig.owner_id = owner
	sig.emitter_id = emitter
	sig.strength = 1.2
	sig.radius = 120.0
	sig.duration = 2.0
	return sig


static func need_support(pos: Vector2, owner: int, emitter: int) -> TacticalSignal:
	var sig = TacticalSignal.new()
	sig.signal_type = Type.NEED_SUPPORT
	sig.position = pos
	sig.owner_id = owner
	sig.emitter_id = emitter
	sig.strength = 2.0
	sig.radius = 200.0
	sig.duration = 3.0
	return sig


static func flanking_opportunity(pos: Vector2, flank_dir: Vector2, owner: int, emitter: int) -> TacticalSignal:
	var sig = TacticalSignal.new()
	sig.signal_type = Type.FLANKING_OPPORTUNITY
	sig.position = pos
	sig.direction = flank_dir
	sig.owner_id = owner
	sig.emitter_id = emitter
	sig.strength = 2.0
	sig.radius = 180.0
	sig.duration = 5.0
	return sig


static func focus_fire(target: Node2D, owner: int, emitter: int) -> TacticalSignal:
	var sig = TacticalSignal.new()
	sig.signal_type = Type.FOCUS_FIRE
	sig.position = target.global_position if target else Vector2.ZERO
	sig.target_entity = target
	sig.owner_id = owner
	sig.emitter_id = emitter
	sig.strength = 3.0
	sig.radius = 300.0
	sig.duration = 6.0
	return sig


static func retreat_suggested(pos: Vector2, owner: int, emitter: int) -> TacticalSignal:
	var sig = TacticalSignal.new()
	sig.signal_type = Type.RETREAT_SUGGESTED
	sig.position = pos
	sig.owner_id = owner
	sig.emitter_id = emitter
	sig.strength = 1.5
	sig.radius = 150.0
	sig.duration = 4.0
	return sig
