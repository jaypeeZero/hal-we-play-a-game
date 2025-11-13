class_name MovementTraits
extends Resource

## Movement trait configuration for creatures
## Defines gait speeds, acceleration, turning, and locomotion type

# Gait speed thresholds and max speeds
@export var walk_speed: float = 30.0
@export var trot_speed: float = 70.0
@export var run_speed: float = 120.0
@export var gallop_speed: float = 180.0

# Locomotion type determines movement pattern
@export_enum("quadruped", "hopper", "slitherer") var locomotion_type: String = "quadruped"

# Hopping parameters (used if locomotion_type == "hopper")
@export var hop_duration: float = 0.3
@export var pause_between_hops_min: float = 0.2
@export var pause_between_hops_max: float = 0.6

# Turn rate (radians per second)
@export var base_turn_rate: float = 3.0

# Acceleration/momentum
@export var max_acceleration: float = 300.0
@export var max_deceleration: float = 400.0
@export var inertia: float = 1.0  # Higher = more momentum
