extends Node
class_name HealthComponent

signal damaged(amount: float, source_id: int)
signal died()
signal health_changed(current: float, maximum: float)

@export var max_health: float = 100.0
var health: float = 0.0

# Callback for custom damage processing
var damage_processor: Callable = Callable()

func _ready() -> void:
    # Initialize health to max_health when added to scene
    if health == 0.0:
        health = max_health

func set_damage_processor(processor: Callable) -> void:
    damage_processor = processor

func take_damage(amount: float, source: Node = null) -> void:
    # Process damage through callback if provided
    var processed_damage: float = amount
    if damage_processor.is_valid():
        processed_damage = damage_processor.call(amount, source)

    if processed_damage <= 0:
        return  # Damage was negated/blocked

    # Apply the processed damage
    health -= processed_damage
    health = max(0, health)

    var source_id: int = source.get_instance_id() if source else -1
    damaged.emit(processed_damage, source_id)
    health_changed.emit(health, max_health)

    if health == 0:
        died.emit()

func heal(amount: float) -> void:
    health = min(health + amount, max_health)
    health_changed.emit(health, max_health)

func get_health_percent() -> float:
    return health / max_health if max_health > 0 else 0.0
