class_name CameraRig
extends Node3D
## Fixed-angle orthographic isometric camera that follows a car (SPEC.md section 1).
## The rig never rotates with the car; it only translates and zooms.

@export var target: Car

@export_group("Angle")
@export_range(0.0, 360.0, 0.5) var yaw_degrees: float = 45.0
@export_range(-45.0, -30.0, 0.5) var pitch_degrees: float = -35.0
## Camera distance from the focus point. Only affects clipping in orthographic mode.
@export var distance: float = 90.0

@export_group("Framing")
## Vertical view size in metres at standstill.
@export var base_size: float = 27.0
## Extra view size at zoom_reference_speed (0.12 = +12 %).
@export_range(0.0, 0.3, 0.01) var speed_zoom: float = 0.12
## Speed (m/s) at which the full speed zoom is reached.
@export var zoom_reference_speed: float = 40.0

@export_group("Follow")
## How far ahead the camera looks, as seconds of travel at the current velocity.
@export var look_ahead_time: float = 0.45
@export var max_look_ahead: float = 9.0
@export var follow_sharpness: float = 8.0
@export var look_ahead_sharpness: float = 2.5
@export var zoom_sharpness: float = 2.0

var _focus: Vector3 = Vector3.ZERO
var _look_ahead: Vector3 = Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = base_size
	_apply_angle()
	snap_to_target()


## Jumps straight to the target without smoothing (start of race, respawn).
func snap_to_target() -> void:
	if target == null:
		return
	_focus = target.global_position
	_look_ahead = Vector3.ZERO
	global_position = _focus


func _process(delta: float) -> void:
	if target == null:
		return
	_apply_angle()

	var target_position: Vector3 = target.get_global_transform_interpolated().origin
	_focus = _focus.lerp(target_position, _smoothing(follow_sharpness, delta))

	var velocity: Vector3 = target.get_velocity()
	velocity.y = 0.0
	var desired_ahead: Vector3 = (velocity * look_ahead_time).limit_length(max_look_ahead)
	_look_ahead = _look_ahead.lerp(desired_ahead, _smoothing(look_ahead_sharpness, delta))
	global_position = _focus + _look_ahead

	var speed_ratio: float = clampf(velocity.length() / zoom_reference_speed, 0.0, 1.0)
	var desired_size: float = base_size * (1.0 + speed_zoom * speed_ratio)
	_camera.size = lerpf(_camera.size, desired_size, _smoothing(zoom_sharpness, delta))


func _apply_angle() -> void:
	rotation_degrees = Vector3(pitch_degrees, yaw_degrees, 0.0)
	_camera.position = Vector3(0.0, 0.0, distance)


## Frame-rate independent lerp weight.
func _smoothing(sharpness: float, delta: float) -> float:
	return 1.0 - exp(-sharpness * delta)
