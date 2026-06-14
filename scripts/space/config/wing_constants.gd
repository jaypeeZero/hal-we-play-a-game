class_name WingConstants
extends RefCounted

## Wing Formation Constants
## All distance and threshold values for the dynamic wing system

# =============================================================================
# WING FORMATION - When wings form and break
# =============================================================================

## Distance within which fighters will form wings with each other
const FORMATION_RANGE = 1000.0

## Distance at which an existing wing breaks apart
const BREAK_RANGE = 3600.0

## Maximum wingmen per wing (Lead + this many = wing size)
const MAX_WINGMEN = 2

# =============================================================================
# WING POSITIONING - Where wingmen fly relative to lead
# =============================================================================

## Base distance wingman maintains from lead
const POSITION_DISTANCE = 200.0

## Angle offset from directly behind lead (degrees)
## 135 = 45 degrees behind and to the side
const POSITION_ANGLE = 135.0

## Skill modifier range for position distance
## Low skill (0.0) = farther (130% of base)
## High skill (1.0) = closer (80% of base)
const POSITION_SKILL_FAR_MODIFIER = 1.3
const POSITION_SKILL_CLOSE_MODIFIER = 0.8

## Position prediction time based on skill (seconds ahead)
const POSITION_PREDICTION_MIN = 0.2  # Low skill
const POSITION_PREDICTION_MAX = 0.5  # High skill

## Error magnitude for low-skill wingmen (units)
const POSITION_ERROR_MAX = 60.0

# =============================================================================
# FORMATION STATUS - Determining if wingman is "in formation"
# =============================================================================

## Tolerance for being "in formation" (added to POSITION_DISTANCE)
## Low skill gets more tolerance, high skill less
const IN_FORMATION_TOLERANCE_LOW_SKILL = 300.0
const IN_FORMATION_TOLERANCE_HIGH_SKILL = 160.0

# =============================================================================
# WING REJOIN - Wingman returning to formation
# =============================================================================

## Distance thresholds for rejoin behavior
const REJOIN_FAR_THRESHOLD_LOW_SKILL = 300.0
const REJOIN_FAR_THRESHOLD_HIGH_SKILL = 200.0
const REJOIN_CLOSE_THRESHOLD_LOW_SKILL = 160.0
const REJOIN_CLOSE_THRESHOLD_HIGH_SKILL = 100.0

## Brake angle threshold (radians) - when to brake before turning
const REJOIN_BRAKE_ANGLE_LOW_SKILL = PI / 3.0   # 60 degrees
const REJOIN_BRAKE_ANGLE_HIGH_SKILL = PI / 5.0  # 36 degrees

## Speed matching thresholds
const REJOIN_MATCH_HEADING_DISTANCE = 80.0  # Distance at which to match lead heading

# =============================================================================
# WING FOLLOW - Maintaining formation while cruising
# =============================================================================

## Distance at which to head toward formation vs match lead heading
const FOLLOW_HEAD_TOWARD_DISTANCE = 120.0

## Distance at which to face formation position when lead is slow
const FOLLOW_FACE_FORMATION_DISTANCE = 40.0

## Distance threshold for speed control
const FOLLOW_TOO_CLOSE_DISTANCE = 60.0

## Speed difference threshold for braking
const FOLLOW_SPEED_DIFF_BRAKE = 30.0

# =============================================================================
# WING ENGAGE - Combat while maintaining formation
# =============================================================================

## Formation distance at which to increase formation priority
const ENGAGE_FORMATION_PRIORITY_INCREASE_DISTANCE = 300.0

## Target distance at which formation priority can decrease
const ENGAGE_TARGET_CLOSE_DISTANCE = 800.0

## Formation distance required to allow priority decrease
const ENGAGE_FORMATION_CLOSE_DISTANCE = 200.0

## Max attack offset distance
const ENGAGE_ATTACK_OFFSET_MAX = 400.0

## Distance thresholds for facing target
const ENGAGE_FACE_TARGET_DISTANCE = 1200.0
const ENGAGE_FACE_TARGET_FORMATION_DISTANCE = 240.0

## Formation distance for speed matching
const ENGAGE_SPEED_MATCH_FORMATION_DISTANCE = 200.0

## Brake angle thresholds
const ENGAGE_BRAKE_ANGLE_LOW_SKILL = PI / 3.5
const ENGAGE_BRAKE_ANGLE_HIGH_SKILL = PI / 5.0

# =============================================================================
# LEAD TARGET SELECTION - How leads pick targets
# =============================================================================

## Skill threshold for target fixation (low skill leads stick to bad targets)
const LEAD_TARGET_FIXATION_SKILL = 0.3

## Skill threshold for noticing damaged targets
const LEAD_NOTICE_DAMAGED_SKILL = 0.5

## Skill threshold for coordinating fire with friendlies
const LEAD_COORDINATE_FIRE_SKILL = 0.4

## Skill threshold for noticing threats facing them
const LEAD_NOTICE_THREATS_SKILL = 0.5

## Target score weights
const TARGET_SCORE_DISTANCE_DIVISOR = 500.0
const TARGET_SCORE_DISTANCE_MAX = 5000.0
const TARGET_SCORE_DAMAGED_WEIGHT = 5.0
const TARGET_SCORE_FRIENDLY_ENGAGING_WEIGHT = 2.0
## Per-engager penalty when picking a fighter target — WW2 squadron doctrine:
## pairs split targets so each engagement is 1-on-1 (or 2-on-1 max). Without
## this, every wing's scorer favors the same closest enemy and combat
## degenerates into a swarm. Tuned so that ~3 friendlies on a target shifts
## a wing to an alternative target up to ~3000u further away.
const TARGET_SCORE_DECONFLICTION_PENALTY = 4.0
## Bonus for the squadron commander's designated focus target. Strong enough
## to overcome a couple thousand units of distance, weak enough that a
## deconfliction penalty for a target with several engagers on it (4.0 each)
## still wins. So the squadron *converges* but doesn't *swarm*.
const TARGET_SCORE_SQUADRON_FOCUS_BONUS = 6.0
## Skill below which a lead doesn't yet think about target deconfliction
## (rookies fixate; mid+ skill spreads engagement)
const LEAD_DECONFLICT_SKILL = 0.3

## Aggression thresholds that bias a wing lead's approach doctrine. Two leads
## with identical skill but different aggression pick different approaches —
## this gives 6v6 a mix of head-on chargers, flankers, and standoff
## harassers instead of one uniform suicide rush.
const LEAD_DOCTRINE_RUSH_AGGRESSION = 0.7   # >= this: commits head-on
const LEAD_DOCTRINE_FLANK_AGGRESSION = 0.3  # <= this: angles/harasses
const TARGET_SCORE_THREAT_FACING_WEIGHT = 3.0
const TARGET_SCORE_THREAT_FACING_ANGLE = 45.0  # degrees

## Skill thresholds for target selection quality
const LEAD_PICK_BEST_SKILL = 0.8       # Always picks best
const LEAD_PICK_TOP_THREE_SKILL = 0.3  # Picks from top 3
# Below 0.3 = random selection

# =============================================================================
# PILOT SKILL - Movement capability modifiers
# =============================================================================
# These create DRAMATIC differences between low and high skill pilots
# A 0-skill pilot should fly straight at targets
# A 1.0-skill pilot should dance circles around them

## Turn rate modifier range (multiplied by base turn rate)
const PILOT_TURN_RATE_MIN = 0.5       # 0-skill: 50% turn rate
const PILOT_TURN_RATE_MAX = 1.5       # 1.0-skill: 150% turn rate

## Acceleration modifier range
const PILOT_ACCEL_MIN = 0.6           # 0-skill: 60% acceleration
const PILOT_ACCEL_MAX = 1.2           # 1.0-skill: 120% acceleration

## Lateral thrust capability (critical for evasion)
const PILOT_LATERAL_MIN = 0.2         # 0-skill: 20% lateral capability
const PILOT_LATERAL_MAX = 1.2         # 1.0-skill: 120% lateral capability

## Inertial dampening (flight assist) — skilled pilots ride the stick tighter,
## so the auto-counter-thrust kills perpendicular drift faster.
const PILOT_DAMPENING_MIN = 0.4       # 0-skill: 40% dampening (sloppy stick)
const PILOT_DAMPENING_MAX = 1.2       # 1.0-skill: 120% dampening (precision)

# =============================================================================
# PILOT SKILL - Behavior thresholds
# =============================================================================
# Low skill pilots can only do simple maneuvers
# Higher skill unlocks more sophisticated tactics

## Skill to approach from angles instead of direct
const PILOT_APPROACH_ANGLE_SKILL = 0.4

## Skill to jink (random lateral movement) during approach
const PILOT_JINKING_SKILL = 0.6

## Skill to use pursuit curves (lead/lag pursuit)
const PILOT_PURSUIT_CURVE_SKILL = 0.7

## Skill for complex defensive maneuvers (spiral, break)
const PILOT_DEFENSIVE_MANEUVER_SKILL = 0.85

## Skill to begin evasive maneuvering pre-emptively when an enemy has a
## firing solution (pre-commit evasion — elite pilots only)
const PILOT_PRE_COMMIT_EVASION_SKILL = 0.85

## Cone dot-product threshold for "enemy is pointing at me" (cos 30°)
const PRE_COMMIT_TARGETING_CONE_DOT = 0.866

## Maximum distance at which pre-commit evasion is relevant
const PRE_COMMIT_ENGAGEMENT_RANGE = 3000.0

# =============================================================================
# PILOT SKILL - Jinking parameters
# =============================================================================

## Jink amplitude range (how much lateral thrust when jinking)
const PILOT_JINK_AMPLITUDE_MIN = 0.0  # Low skill: no jinking
const PILOT_JINK_AMPLITUDE_MAX = 0.7  # High skill: strong jinking

## Jink hold duration (ms) — how long a committed strafe direction is held
## before re-rolling. Dodge displacement under momentum physics is a·t²/2,
## so the hold must run long enough to clear the hit circle; but holding far
## past projectile flight time settles into constant lateral velocity, which
## a leading gunner predicts perfectly. Skilled pilots flip on the shot
## timescale; sloppy pilots hold too long and telegraph their vector.
const PILOT_JINK_HOLD_LOW_SKILL_MS = 1600.0
const PILOT_JINK_HOLD_HIGH_SKILL_MS = 800.0

# =============================================================================
# PILOT SKILL - Approach angle parameters
# =============================================================================

## Approach offset angle range (radians)
const PILOT_APPROACH_ANGLE_MIN = 0.0          # Direct approach
const PILOT_APPROACH_ANGLE_MAX = 0.7          # ~40 degrees offset

# =============================================================================
# GUNNER SKILL - Weapon accuracy and targeting modifiers
# =============================================================================
# These create DRAMATIC differences between low and high skill gunners
# A 0-skill gunner sprays wildly and can't track moving targets
# A 1.0-skill gunner lands precise shots on specific subsystems

## Lead calculation accuracy (projectile prediction)
const GUNNER_LEAD_MIN = 0.0                  # 0-skill: no lead (aims at current position)
const GUNNER_LEAD_MAX = 1.0                  # 1.0-skill: perfect lead calculation

# =============================================================================
# GUNNER SKILL - Behavior thresholds
# =============================================================================
# Low skill gunners use simple targeting
# Higher skill unlocks sophisticated aiming techniques

## Skill to use basic velocity lead (predict where target will be)
const GUNNER_LEADING_SKILL = 0.4

## Skill to use full predictive aiming (anticipate maneuvers)
const GUNNER_PREDICTIVE_SKILL = 0.6

## Skill to target specific subsystems (engines, weapons)
const GUNNER_SUBSYSTEM_SKILL = 0.9

# =============================================================================
# GUNNER SKILL - Stress response
# =============================================================================

## Panic fire threshold - below this composure, gunner panics
const GUNNER_PANIC_COMPOSURE = 0.3

## Panic fire spread cone (overrides the skill curve when panicking)
const GUNNER_AIM_PANIC_SPREAD_RAD = PI / 12.0  # 15°

# =============================================================================
# GUNNER SKILL - Spread cone (aim-driven)
# =============================================================================
# Spread cone is driven directly by raw `aim` skill. At 1.0 aim the cone is
# zero (perfect line). At 0.0 aim it matches roughly what the legacy mid-skill
# default felt like, so untrained crew "feel current" rather than absurd.

## Spread cone at zero aim. ~7.5° — close to the pre-rework default mid-skill
## spread, which becomes the new floor for untrained gunners.
const GUNNER_AIM_WORST_SPREAD_RAD = PI / 24.0

## Reference target radius (smallest hostile, fighter base_size). Used by tests
## to assert "almost never miss at one patrol diameter" for elite crew.
const GUNNER_AIM_TARGET_RADIUS = 15.0

## Minimum range_factor a skilled gunner requires before firing. Scales with aim_skill.
## At skill 1.0: threshold 0.90 → fires only within 33% of max weapon range.
## Below skill ~0.78 the threshold falls under 0.70 (already guaranteed within range).
const GUNNER_MIN_RANGE_FACTOR = 0.90

# =============================================================================
# CAPTAIN SKILL - Ship coordination modifiers
# =============================================================================
# These create DRAMATIC differences between low and high skill captains
# A 0-skill captain issues confused, late orders
# A 1.0-skill captain orchestrates crew perfectly

## Coordination bonus range (applied to crew effectiveness)
const CAPTAIN_COORDINATION_MIN = 0.9         # 0-skill: -10% coordination
const CAPTAIN_COORDINATION_MAX = 1.3         # 1.0-skill: +30% coordination

## Damage control effectiveness
const CAPTAIN_DAMAGE_CONTROL_MIN = 0.5       # 0-skill: 50% repair speed
const CAPTAIN_DAMAGE_CONTROL_MAX = 1.2       # 1.0-skill: 120% repair speed

## Decision delay range (seconds to issue orders)
const CAPTAIN_DECISION_DELAY_MIN = 0.3       # 1.0-skill: fast decisions
const CAPTAIN_DECISION_DELAY_MAX = 1.5       # 0-skill: slow, hesitant

# =============================================================================
# CAPTAIN SKILL - Behavior thresholds
# =============================================================================
# Low skill captains react slowly with poor priorities
# Higher skill enables foresight and adaptation

## Skill for standard command (follows doctrine)
const CAPTAIN_STANDARD_SKILL = 0.5

## Skill for tactical command (anticipates situations)
const CAPTAIN_TACTICAL_SKILL = 0.7

## Skill for adaptive command (reads battle, adjusts strategy)
const CAPTAIN_ADAPTIVE_SKILL = 0.85

# =============================================================================
# CAPTAIN SKILL - Order quality
# =============================================================================

## Order clarity penalty for low skill (subordinates confused)
const CAPTAIN_ORDER_CLARITY_MIN = 0.6        # 0-skill: 60% order effectiveness
const CAPTAIN_ORDER_CLARITY_MAX = 1.0        # 1.0-skill: 100% order effectiveness

## Threat assessment accuracy
const CAPTAIN_THREAT_ASSESSMENT_MIN = 0.4    # 0-skill: often wrong about threats
const CAPTAIN_THREAT_ASSESSMENT_MAX = 1.0    # 1.0-skill: accurate assessment

# =============================================================================
# SQUADRON LEADER SKILL - Multi-ship coordination
# =============================================================================
# These create DRAMATIC differences in squadron cohesion and effectiveness
# A 0-skill squadron leader has ships fighting individually
# A 1.0-skill squadron leader orchestrates complex maneuvers

## Skill for loose coordination (wingman pairing, mutual support, focus fire)
const SQUADRON_LOOSE_SKILL = 0.4

## Skill for play-driven orchestrated coordination (pincer, bracket, kill-box)
const SQUADRON_ORCHESTRATED_SKILL = 0.8

# =============================================================================
# SQUADRON LEADER SKILL - Target assignment
# =============================================================================

## Target assignment quality (optimal ship-to-target matching)
const SQUADRON_ASSIGNMENT_QUALITY_MIN = 0.3  # 0-skill: poor matching
const SQUADRON_ASSIGNMENT_QUALITY_MAX = 1.0  # 1.0-skill: optimal matching

# =============================================================================
# SUBSYSTEM TARGETING - elite gunner damage routing
# =============================================================================

## Probability that a hit from a SUBSYSTEM-aimed shot routes its internal
## damage to the explicitly intended subsystem (vs. closest-component fallback).
const SUBSYSTEM_INTENDED_HIT_BIAS = 0.7

# =============================================================================
# AWARENESS & DETECTION
# =============================================================================
# Skill-based detection latency. Awareness gates how quickly a crew member's
# mailbox actually receives a `threat_appeared` event after the world fires
# it; rookie crew lag, elites snap to it. Damage is felt faster than threats
# are spotted, but still not instant.

## Maximum mailbox delivery delay for `threat_appeared` (seconds).
## A 0.0-awareness crew waits this long; a 1.0-awareness crew is immediate.
const MAX_DETECTION_LAG = 0.9

## Same for `ship_damaged` — you feel a hit faster than you spot a fighter.
const MAX_DAMAGE_PERCEPTION_LAG = 0.25

## How many threats the highest-awareness crew can hold on their list. The
## visible cap scales as `floor(awareness * MAX_VISIBLE_THREATS)` (min 1).
const MAX_VISIBLE_THREATS = 8

## At/above this `tactics`, threat ordering is clean. Below it, ranking is
## perturbed by random noise (low-tactics crew sometimes attack the wrong
## threat first).
const HIGH_TACTICS_THRESHOLD = 0.7

## Multiplicative urgency noise applied to low-tactics crew's threat
## ranking. ±this fraction at zero tactics; tapers to 0 at HIGH_TACTICS_THRESHOLD.
const TACTICS_NOISE = 0.5

# =============================================================================
# REACTION LATENCY
# =============================================================================
# Pilots/captains commit a reactive decision after a delay gated by skill.
# Composes with detection latency: rookies are doubly slow.

## Maximum commit delay for a reactive decision (seconds). A 0.0-piloting
## pilot waits this long between deciding to evade and the order taking
## effect; a 1.0-piloting pilot commits immediately.
const MAX_REACTION_DELAY = 0.7

## Multiplier applied to commit delay when stress exceeds the crew's
## composure buffer. Low-composure aces under fire react slower than usual.
const REACTION_STRESS_PENALTY_FACTOR = 1.5

# =============================================================================
# DEBUG OVERLAY - floating crew table
# =============================================================================

## Pixel offset between the ship's hull bottom-right and the table corner.
const OVERLAY_HULL_OFFSET_PX = Vector2(8.0, 8.0)

## Color thresholds for the 0–20 stat gradient. Buckets: red 0–6, yellow 7–13,
## green 14–20. A "dim" gray is used for stats the role does not read.
const OVERLAY_STAT_COLOR_LOW = Color(0.95, 0.35, 0.35, 1.0)
const OVERLAY_STAT_COLOR_MID = Color(0.95, 0.85, 0.30, 1.0)
const OVERLAY_STAT_COLOR_HIGH = Color(0.45, 0.95, 0.45, 1.0)
const OVERLAY_STAT_COLOR_DIM = Color(0.55, 0.55, 0.55, 0.7)
const OVERLAY_STAT_LOW_MAX = 6
const OVERLAY_STAT_MID_MAX = 13

# =============================================================================
# SQUADRON PLAYS - Coordinated multi-fighter maneuvers (pincer, bracket, ...)
# =============================================================================
# Plays are defined as data in data/squadron_plays.json. The leader's tactics
# stat gates which plays unlock and how cleanly they execute. Low-tactics
# leaders scatter offsets and drift phase timing; elites hit marks tightly.

## Max position scatter (units) for a leader at 0.0 effective tactics.
## Scales linearly with (1 - tactics).
const PLAY_JITTER_MAX_OFFSET = 80.0

## Max phase-transition jitter (seconds) for a leader at 0.0 tactics.
const PLAY_JITTER_MAX_TIMING = 1.2

## Leader re-evaluates which play to run on this interval (seconds).
const PLAY_REPLAN_INTERVAL = 6.0

# =============================================================================
# SURVIVAL TACTICAL DISENGAGE — elite tacticians only
# =============================================================================

## Minimum tactics skill required to trigger a proactive tactical disengage
## when damaged, outnumbered, and unsupported.
const SURVIVAL_TACTICAL_DISENGAGE_SKILL = 0.80

## Hull ratio below which the tactical disengage fires (if other conditions met)
const SURVIVAL_TACTICAL_HULL_RATIO = 0.40

# =============================================================================
# ELITE RE-EVALUATION AFTER KILL
# =============================================================================

## Piloting skill at which a pilot immediately re-evaluates on their current
## target's death, rather than waiting for the normal decision cadence.
const ELITE_REASSESS_AFTER_KILL_SKILL = 0.80

## How soon after the kill the elite pilot re-evaluates (seconds)
const ELITE_REASSESS_AFTER_KILL_DELAY = 0.05

# =============================================================================
# ELITE SITUATIONAL AWARENESS — friendly collision and close-target relock
# =============================================================================

## Piloting skill above which a pilot checks for and avoids collisions with
## friendly ships (display 15/20). Below this, they fixate on the enemy.
const PILOT_FRIENDLY_COLLISION_SKILL = 0.75

## Piloting skill above which a pilot breaks their engagement lock when a
## significantly closer threat enters close combat range.
const CLOSE_TARGET_RELOCK_SKILL = 0.75

# =============================================================================
# ENGINEER REPAIR
# =============================================================================

## Engineers rolled per hull when a ship's crew is created.
const CORVETTE_ENGINEERS_MIN = 0
const CORVETTE_ENGINEERS_MAX = 2
const CAPITAL_ENGINEERS_MIN = 1
const CAPITAL_ENGINEERS_MAX = 5

## Fraction of the target's maximum restored per in-battle repair action,
## lerped on the engineer's effective machinery skill.
const ENGINEER_REPAIR_FRACTION_MIN = 0.02
const ENGINEER_REPAIR_FRACTION_MAX = 0.08

## Seconds between an engineer's repair actions, and between idle checks
## when nothing aboard needs fixing.
const ENGINEER_REPAIR_CADENCE_MIN = 2.0
const ENGINEER_REPAIR_CADENCE_MAX = 3.0
const ENGINEER_IDLE_CADENCE_MIN = 4.0
const ENGINEER_IDLE_CADENCE_MAX = 6.0

## How long the green repair pulse stays visible on a ship after a repair
## lands. Shorter than the repair cadence so ongoing repairs blink.
const ENGINEER_REPAIR_FLASH_SECONDS = 1.2

## Roguelike jump repair: fraction of max restored per engineer per star
## date of travel time, scaled by their machinery skill.
const REPAIR_FRACTION_PER_STAR_DATE = 0.01

## R&R downtime multiplies the jump repair.
const RNR_REPAIR_MULTIPLIER = 3.0

# --- Crew progression (post-battle skill development) ---
const USED_GAIN_MIN := 0.001          # floor for a skill the crew actually used
const USED_GAIN_MAX := 0.015          # ceiling, extreme circumstances
const USED_PRIMARY_WEIGHT := 1.0      # role's primary skill grows fastest
const USED_SECONDARY_WEIGHT := 0.5    # supporting skills grow slower
const TRICKLE_GAIN_MIN := 0.0001      # mentoring whisper from an exceptional shipmate
const TRICKLE_GAIN_MAX := 0.0005
const EXCEPTIONAL_SKILL_THRESHOLD := 0.85   # "exceptional ability" bar for mentoring
const LEADER_MULT_MIN := 0.6          # coaching multiplier at commander tactics 0.0
const LEADER_MULT_MAX := 1.4          # coaching multiplier at commander tactics 1.0
const MASTERY_TAPER_START := 0.85     # gains taper above this skill value
const MASTERY_TAPER_FLOOR := 0.25     # multiplier on gains at skill 1.0
# aggression adversity response (composure decides direction, NOT coached/mentored)
const AGGRESSION_SHIFT_MIN := 0.001   # shift after light adversity
const AGGRESSION_SHIFT_MAX := 0.020   # shift after a mauling
const COMPOSURE_PIVOT := 0.5          # composure >= pivot -> aggression up, else down

# --- Repair parts pool (Layer D) ---
## Pool as a fraction of total max armor + total max internal health.
## A ship can repair at most this fraction of its total health across a full battle.
## Lower = battles end faster. Start at 0.5 (half total health).
const REPAIR_POOL_FRACTION_OF_MAX_HEALTH := 0.5

# --- Press-attack maneuver ---
## Desired distance when a fighter presses a capital under press_attack posture.
const PRESS_ATTACK_RANGE := 700.0
## Tolerance band around PRESS_ATTACK_RANGE; no thrust when within this band.
const PRESS_ATTACK_RANGE_TOLERANCE := 150.0

# --- Commit decisions (Layers B & C) ---
## Operational enemy count considered "few" — triggers few-enemies commit.
const COMMIT_ENEMY_COUNT_THRESHOLD := 2
## Minimum engagement duration (seconds) before few-enemies trigger fires.
const COMMIT_ENGAGEMENT_SECONDS := 45.0
## Window over which damage progress is sampled for the stalemate detector.
const COMMIT_STALL_WINDOW_SECONDS := 20.0
## Net hull delta (damage - repair) at or below which we declare stalemate.
const COMMIT_STALL_NET_DAMAGE_EPSILON := 5.0
## How long a press_attack posture lasts. Must exceed captain re-decide interval.
const COMMIT_POSTURE_DURATION := 15.0
## GOAP cost for a commit/press-attack action — must beat hold/standoff.
const COMMIT_COST := 0.2
## Minimum doctrine aggression (resolved mentality_scalar, 0..1) for the
## commit-to-press escalation to fire. Below this, defensive/balanced fleets
## hold their tactics (a kiting doctrine never auto-charges) — preserves the
## emergent variety between aggressive and defensive doctrines.
const COMMIT_MIN_AGGRESSION := 0.6
