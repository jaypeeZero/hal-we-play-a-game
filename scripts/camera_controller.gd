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
## Multiplicative step per mouse-wheel notch (feels even across zoom levels).
const WHEEL_ZOOM_FACTOR: float = 1.1
const PAN_SPEED: float = 500.0
const SMOOTH_SPEED: float = 5.0

# Initial state for reset
var _initial_position: Vector2
var _initial_zoom: Vector2

# Target values for smooth movement
var _target_zoom: Vector2
var _target_position: Vector2

func _ready() -> void:
	# Default zoom set so the entire battlefield (~5000x3500u) fits in the
	# viewport at game start. It's a SPACE battle — engagements happen at
	# range, not in a stadium. Players can zoom in for detail.
	zoom = Vector2(0.3, 0.3)

	# Store initial camera state
	_initial_position = position
	_initial_zoom = zoom

	# Initialize targets
	_target_zoom = zoom
	_target_position = position

	# Set up input actions
	_setup_input_actions()

## Frame an area (world center + size) so it fits the current viewport, and make
## this the camera's reset target. Used by the race scene for a track overview.
const OVERVIEW_FIT := 0.92
func set_overview(center: Vector2, world_size: Vector2) -> void:
	"""Position and zoom the camera so world_size fits the viewport."""
	var vp: Vector2 = get_viewport_rect().size
	var fit: float = 1.0
	if world_size.x > 0.0 and world_size.y > 0.0:
		fit = minf(vp.x / world_size.x, vp.y / world_size.y) * OVERVIEW_FIT
	fit = clampf(fit, ZOOM_MIN, ZOOM_MAX)
	var z := Vector2(fit, fit)
	position = center
	zoom = z
	_initial_position = center
	_initial_zoom = z
	_target_position = center
	_target_zoom = z
	make_current()


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
	# Handle input, unless the log console has captured the keyboard.
	if not LogConsole.capturing_input:
		_handle_zoom_input()
		_handle_pan_input(delta)
		_handle_reset_input()

	# Smooth interpolation
	zoom = zoom.lerp(_target_zoom, SMOOTH_SPEED * delta)
	position = position.lerp(_target_position, SMOOTH_SPEED * delta)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse-wheel zoom for both the battle and race views. Up = zoom in,
	# down = zoom out; clamped to the same range as keyboard zoom.
	if LogConsole.capturing_input:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_wheel_zoom(WHEEL_ZOOM_FACTOR)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_wheel_zoom(1.0 / WHEEL_ZOOM_FACTOR)

func _apply_wheel_zoom(factor: float) -> void:
	_target_zoom = (_target_zoom * factor).clamp(
		Vector2.ONE * ZOOM_MIN,
		Vector2.ONE * ZOOM_MAX
	)

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
