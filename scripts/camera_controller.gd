extends Camera2D
class_name CameraController

## Camera controller for zoom, pan, and reset functionality
## Controls:
## - Zoom: - (zoom out) and + (zoom in)
## - Pan: WASD keys
## - Reset: / key (return to initial position and zoom)

# Camera settings
const ZOOM_MIN: float = 0.05
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 0.1
const PAN_SPEED: float = 500.0
const SMOOTH_SPEED: float = 5.0

# Initial state for reset
var _initial_position: Vector2
var _initial_zoom: Vector2

# Target values for smooth movement
var _target_zoom: Vector2
var _target_position: Vector2

func _ready() -> void:
	# Set default zoom to be zoomed out by 3 steps (0.7 instead of 1.0)
	zoom = Vector2(0.7, 0.7)

	# Store initial camera state
	_initial_position = position
	_initial_zoom = zoom

	# Initialize targets
	_target_zoom = zoom
	_target_position = position

	# Set up input actions
	_setup_input_actions()

func _setup_input_actions() -> void:
	"""Set up camera control input actions"""
	_ensure_action("camera_zoom_in", KEY_EQUAL)  # + key
	_ensure_action("camera_zoom_out", KEY_MINUS)  # - key
	_ensure_action("camera_pan_left", KEY_A)
	_ensure_action("camera_pan_right", KEY_D)
	_ensure_action("camera_pan_up", KEY_W)
	_ensure_action("camera_pan_down", KEY_S)
	_ensure_action("camera_reset", KEY_SLASH)

func _ensure_action(action_name: String, key: int) -> void:
	"""Ensure an input action exists, create if missing"""
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event := InputEventKey.new()
		event.keycode = key
		InputMap.action_add_event(action_name, event)

func _process(delta: float) -> void:
	# Handle input
	_handle_zoom_input()
	_handle_pan_input(delta)
	_handle_reset_input()

	# Smooth interpolation
	zoom = zoom.lerp(_target_zoom, SMOOTH_SPEED * delta)
	position = position.lerp(_target_position, SMOOTH_SPEED * delta)

func _handle_zoom_input() -> void:
	"""Handle zoom in/out with -/+ keys"""
	if Input.is_action_just_pressed("camera_zoom_in"):
		_target_zoom = (_target_zoom + Vector2.ONE * ZOOM_STEP).clamp(
			Vector2.ONE * ZOOM_MIN,
			Vector2.ONE * ZOOM_MAX
		)

	if Input.is_action_just_pressed("camera_zoom_out"):
		_target_zoom = (_target_zoom - Vector2.ONE * ZOOM_STEP).clamp(
			Vector2.ONE * ZOOM_MIN,
			Vector2.ONE * ZOOM_MAX
		)

func _handle_pan_input(delta: float) -> void:
	"""Handle camera panning with WASD keys"""
	var pan_direction := Vector2.ZERO

	if Input.is_action_pressed("camera_pan_left"):
		pan_direction.x -= 1.0
	if Input.is_action_pressed("camera_pan_right"):
		pan_direction.x += 1.0
	if Input.is_action_pressed("camera_pan_up"):
		pan_direction.y -= 1.0
	if Input.is_action_pressed("camera_pan_down"):
		pan_direction.y += 1.0

	if pan_direction.length() > 0:
		# Normalize diagonal movement and apply pan speed
		# Scale by inverse of zoom so panning feels consistent at all zoom levels
		_target_position += pan_direction.normalized() * PAN_SPEED * delta / _target_zoom.x

func _handle_reset_input() -> void:
	"""Handle camera reset with / key"""
	if Input.is_action_just_pressed("camera_reset"):
		_target_position = _initial_position
		_target_zoom = _initial_zoom
