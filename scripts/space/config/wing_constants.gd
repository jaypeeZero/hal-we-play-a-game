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

## Distance thresholds for speed control
const FOLLOW_TOO_FAR_DISTANCE = 160.0
const FOLLOW_TOO_CLOSE_DISTANCE = 60.0

## Speed difference thresholds for thrust/brake
const FOLLOW_SPEED_DIFF_THRUST = -15.0
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
# DECISION TIMING - How often wingmen re-evaluate
# =============================================================================

## Decision delay ranges (seconds)
const DECISION_DELAY_REJOIN_MIN = 0.2
const DECISION_DELAY_REJOIN_MAX = 0.4
const DECISION_DELAY_FOLLOW_MIN = 0.4
const DECISION_DELAY_FOLLOW_MAX = 0.7
const DECISION_DELAY_ENGAGE_MIN = 0.2
const DECISION_DELAY_ENGAGE_MAX = 0.4

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
const TARGET_SCORE_THREAT_FACING_WEIGHT = 3.0
const TARGET_SCORE_THREAT_FACING_ANGLE = 45.0  # degrees

## Skill thresholds for target selection quality
const LEAD_PICK_BEST_SKILL = 0.6       # Always picks best
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
const PILOT_TURN_RATE_MAX = 1.3       # 1.0-skill: 130% turn rate

## Acceleration modifier range
const PILOT_ACCEL_MIN = 0.6           # 0-skill: 60% acceleration
const PILOT_ACCEL_MAX = 1.2           # 1.0-skill: 120% acceleration

## Lateral thrust capability (critical for evasion)
const PILOT_LATERAL_MIN = 0.2         # 0-skill: 20% lateral capability
const PILOT_LATERAL_MAX = 1.0         # 1.0-skill: 100% lateral capability

# =============================================================================
# PILOT SKILL - Behavior thresholds
# =============================================================================
# Low skill pilots can only do simple maneuvers
# Higher skill unlocks more sophisticated tactics

## Skill to approach from angles instead of direct
const PILOT_APPROACH_ANGLE_SKILL = 0.4

## Skill to jink (random lateral movement) during approach
const PILOT_JINKING_SKILL = 0.5

## Skill to use pursuit curves (lead/lag pursuit)
const PILOT_PURSUIT_CURVE_SKILL = 0.6

## Skill for complex defensive maneuvers (spiral, break)
const PILOT_DEFENSIVE_MANEUVER_SKILL = 0.7

# =============================================================================
# PILOT SKILL - Jinking parameters
# =============================================================================

## Jink amplitude range (how much lateral thrust when jinking)
const PILOT_JINK_AMPLITUDE_MIN = 0.0  # Low skill: no jinking
const PILOT_JINK_AMPLITUDE_MAX = 0.7  # High skill: strong jinking

## Jink frequency (ms per cycle) - skilled pilots jink faster
const PILOT_JINK_PERIOD_LOW_SKILL = 800.0   # Slow, predictable
const PILOT_JINK_PERIOD_HIGH_SKILL = 300.0  # Fast, hard to track

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

## Accuracy modifier range (multiplied by base accuracy)
const GUNNER_ACCURACY_MIN = 0.4              # 0-skill: 40% accuracy
const GUNNER_ACCURACY_MAX = 1.3              # 1.0-skill: 130% accuracy

## Rate of fire modifier range
const GUNNER_ROF_MIN = 0.7                   # 0-skill: 70% fire rate (hesitant)
const GUNNER_ROF_MAX = 1.2                   # 1.0-skill: 120% fire rate

## Tracking speed modifier (how fast turrets follow targets)
const GUNNER_TRACKING_MIN = 0.3              # 0-skill: 30% tracking speed
const GUNNER_TRACKING_MAX = 1.1              # 1.0-skill: 110% tracking speed

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
const GUNNER_SUBSYSTEM_SKILL = 0.8

## Skill threshold for target fixation (low skill sticks to bad targets)
const GUNNER_TARGET_FIXATION_SKILL = 0.3

## Target switch penalty for low skill gunners (seconds of reduced accuracy)
const GUNNER_TARGET_SWITCH_PENALTY_MAX = 1.5  # 0-skill: 1.5s penalty
const GUNNER_TARGET_SWITCH_PENALTY_MIN = 0.2  # 1.0-skill: 0.2s penalty

# =============================================================================
# GUNNER SKILL - Stress response
# =============================================================================

## Panic fire threshold - below this composure, gunner panics
const GUNNER_PANIC_COMPOSURE = 0.3

## Panic fire accuracy penalty
const GUNNER_PANIC_ACCURACY_PENALTY = 0.5    # 50% accuracy when panicking

## Panic fire rate bonus (spray and pray)
const GUNNER_PANIC_ROF_BONUS = 1.3           # 130% fire rate when panicking

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
# Higher skill enables anticipation and adaptation

## Skill for reactive command (only responds to immediate threats)
const CAPTAIN_REACTIVE_SKILL = 0.3

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

## Skill for basic wingman pairing to work
const SQUADRON_PAIRED_SKILL = 0.4

## Skill for coordinated attacks (focus fire, timing)
const SQUADRON_COORDINATED_SKILL = 0.6

## Skill for complex tactics (feints, traps, combined arms)
const SQUADRON_ORCHESTRATED_SKILL = 0.8

# =============================================================================
# SQUADRON LEADER SKILL - Target assignment
# =============================================================================

## Target assignment quality (optimal ship-to-target matching)
const SQUADRON_ASSIGNMENT_QUALITY_MIN = 0.3  # 0-skill: poor matching
const SQUADRON_ASSIGNMENT_QUALITY_MAX = 1.0  # 1.0-skill: optimal matching

## Formation coherence under pressure
const SQUADRON_FORMATION_COHERENCE_MIN = 0.2 # 0-skill: formation falls apart
const SQUADRON_FORMATION_COHERENCE_MAX = 1.0 # 1.0-skill: formation holds

## Reinforcement timing accuracy
const SQUADRON_TIMING_MIN = 0.4              # 0-skill: poor timing
const SQUADRON_TIMING_MAX = 1.0              # 1.0-skill: perfect timing

# =============================================================================
# FLEET COMMANDER SKILL - Strategic coordination
# =============================================================================
# These affect large-scale battle flow
# A 0-skill fleet commander commits everything immediately
# A 1.0-skill fleet commander controls tempo, holds reserves

## Skill for basic maneuvering (some initiative)
const FLEET_MANEUVERING_SKILL = 0.4

## Skill for tactical control (engagement timing, distance)
const FLEET_TACTICAL_SKILL = 0.6

## Skill for strategic planning (reserves, deception)
const FLEET_STRATEGIC_SKILL = 0.8

## Reserve management (how much force held back)
const FLEET_RESERVE_MIN = 0.0                # 0-skill: commits everything
const FLEET_RESERVE_MAX = 0.3                # 1.0-skill: holds 30% in reserve

## Engagement timing accuracy
const FLEET_TIMING_MIN = 0.5                 # 0-skill: poor timing
const FLEET_TIMING_MAX = 1.0                 # 1.0-skill: optimal timing
