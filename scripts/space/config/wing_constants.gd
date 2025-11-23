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
