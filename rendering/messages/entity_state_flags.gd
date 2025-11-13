## Constants for EntityState.state_flags
## Add new flags here as gameplay evolves - no need to modify EntityState
class_name EntityStateFlags

# Movement states
const MOVING = "moving"
const IDLE = "idle"
const FALLING = "falling"
const JUMPING = "jumping"

# Combat states
const ATTACKING = "attacking"
const BLOCKING = "blocking"
const DODGING = "dodging"
const PARRYING = "parrying"

# Spellcasting states
const CASTING = "casting"
const CHANNELING = "channeling"
const CHARGING = "charging"

# Control states
const STUNNED = "stunned"
const ROOTED = "rooted"
const SILENCED = "silenced"
const DISARMED = "disarmed"

# Custom game-specific states
const SUMMONING = "summoning"
const TRANSFORMING = "transforming"
const BANISHED = "banished"

# AI behavior states (from AIController signals)
const STEALTH = "stealth"
const FLEEING = "fleeing"
const CHARGING_ATTACK = "charging_attack"
const PACK_COORDINATING = "pack_coordinating"
const SWARM_ATTACKING = "swarm_attacking"
const AMBUSHING = "ambushing"
