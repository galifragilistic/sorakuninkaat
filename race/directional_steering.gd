class_name DirectionalSteering
extends Node
## Directional steering for one local player: the stick (or WASD) points where
## the car should head on screen, and this turns that into ordinary steering
## before the car (and, online, the network) reads the input. With the keys,
## pushing a direction also gives throttle.

## Runs after InputManager has read the devices and before the cars.
const PHYSICS_PRIORITY: int = -50

## Heading difference at which the wheel is at full lock (degrees).
@export var full_lock_degrees: float = 35.0
## Past this heading difference the car keeps turning the way it already
## turns, so it does not flip between left and right when aimed straight back.
@export var turn_around_degrees: float = 150.0
## Below this forward speed (m/s, negative = backwards) the steering is
## mirrored, so a reversing car still swings its nose towards the stick.
@export var reverse_speed: float = -1.0

var _car: Car
var _input: PlayerInput
## Screen right and screen up as directions on the ground.
var _screen_right: Vector3 = Vector3.RIGHT
var _screen_up: Vector3 = Vector3.FORWARD
var _last_side: float = 1.0


## view_yaw_degrees: the camera's yaw, which decides where "up" on screen is.
func setup(car: Car, input: PlayerInput, view_yaw_degrees: float) -> void:
	_car = car
	_input = input
	var turn: Basis = Basis(Vector3.UP, deg_to_rad(view_yaw_degrees))
	_screen_right = turn * Vector3.RIGHT
	_screen_up = turn * Vector3.FORWARD


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY


func _physics_process(_delta: float) -> void:
	if _car == null or not is_instance_valid(_car) or _input == null:
		return
	var aim: Vector2 = _input.aim
	if _input.aim_from_keys:
		# The keys are the direction now, so they also drive the car forward.
		_input.throttle = 1.0 if aim != Vector2.ZERO else 0.0
		_input.brake = 0.0
	if aim == Vector2.ZERO:
		_input.steer = 0.0
		return
	var target: Vector3 = (_screen_right * aim.x + _screen_up * aim.y).normalized()
	var forward: Vector3 = -_car.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	# Positive angle = target is to the left (counter-clockwise seen from above).
	var angle: float = rad_to_deg(forward.normalized().signed_angle_to(target, Vector3.UP))
	if absf(angle) > turn_around_degrees:
		angle = absf(angle) * _last_side
	elif absf(angle) > 0.0:
		_last_side = signf(angle)
	# Positive steering turns right, which is a negative angle.
	var steer: float = clampf(-angle / full_lock_degrees, -1.0, 1.0)
	if _car.get_forward_speed() < reverse_speed:
		steer = -steer
	_input.steer = steer
