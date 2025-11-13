extends IRenderable
class_name PlayerCharacter

# Signals
signal mana_changed(new_mana: float)

# Signals inherited from IRenderable:
# - state_changed(state: EntityState)
# - animation_requested(request: AnimationRequest)

# Player properties
@export var player_id: int = 1
@export var max_mana: float = 100.0
@export var mana_regen_rate: float = 10.0  # Mana per second

var mana: float = 0.0

# Health Component
var health_component: HealthComponent
var magic_protection: float = 0.0

# Hand system
var satchel: Satchel
var hand: Hand

# Renderable properties
var entity_id: String = ""
var visual_type: String = "wizard_player"

func _ready() -> void:
	entity_id = "player_%d" % player_id
	mana = 0.0
	add_to_group("combatants")
	add_to_group("players")

	# Setup Health Component
	health_component = HealthComponent.new()
	health_component.max_health = 100.0
	health_component.health = health_component.max_health  # Explicitly initialize health
	health_component.set_damage_processor(_process_damage)
	add_child(health_component)
	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)

	_setup_hand_system()

	# Emit initial state
	_emit_state_update()

func _setup_hand_system() -> void:
	var loadout_path: String = "res://player_loadout.json" if player_id == 1 else "res://opponent_loadout.json"
	satchel = Satchel.new(loadout_path)
	hand = Hand.new(satchel)
	# Draw initial hand of 5 cards
	for i: int in range(5):
		hand.draw()

# Custom damage processing function
func _process_damage(amount: float, source: Node) -> float:
	var final_damage: float = amount

	# Example: Apply magic protection based on source type
	if source and source is BattlefieldObject:
		if (source as BattlefieldObject).is_magical():
			final_damage *= (1.0 - magic_protection)

	return final_damage

func take_damage(amount: float, source: Node = null) -> void:
	health_component.take_damage(amount, source)
	# Request damage animation
	_request_animation("damaged", AnimationRequest.Priority.HIGH)

func _on_health_changed(_current: float, _maximum: float) -> void:
	# Emit state update when health changes
	_emit_state_update()

func _on_died() -> void:
	# Request death animation
	_request_animation("death", AnimationRequest.Priority.CRITICAL)
	# Handle player death (e.g., game over, respawn)
	queue_free()

func get_hand() -> Hand:
	return hand

func _process(delta: float) -> void:
	_regenerate_mana(delta)

func spend_mana(amount: float) -> bool:
	if mana < amount:
		return false

	mana -= amount
	mana = max(0, mana)  # Prevent negative
	mana_changed.emit(mana)
	_emit_state_update()  # Emit state when mana changes
	return true

func _regenerate_mana(delta: float) -> void:
	if mana < max_mana:
		mana += mana_regen_rate * delta
		if mana > max_mana:
			mana = max_mana
		mana_changed.emit(mana)
		_emit_state_update()  # Emit state when mana changes

## IRenderable interface implementation
func get_entity_id() -> String:
	return entity_id

func get_visual_type() -> String:
	return visual_type

## Emit state whenever visual properties change
func _emit_state_update() -> void:
	var state = EntityState.new()
	state.health_percent = health_component.health / health_component.max_health if health_component else 1.0
	state_changed.emit(state)

## Request animations instead of playing them
func _request_animation(anim_name: String, priority: AnimationRequest.Priority) -> void:
	var request = AnimationRequest.create(anim_name, priority)
	animation_requested.emit(request)
