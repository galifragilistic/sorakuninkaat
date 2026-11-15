class_name AiDriver
extends Node
## Computer driver: steers its car along the track's centre line
## (SPEC.md section 4), slows down for corners and recovers when stuck.
## Add it as a child of a Car and call setup().

@export_group("Steering")
## Distance ahead on the track that the car aims at, plus seconds of travel.
@export var look_ahead_distance: float = 7.0
@export var look_ahead_time: float = 0.45
## Angle to the aim point (degrees) that gives full steering lock.
@export var full_steer_angle: float = 22.0

@export_group("Speed")
## How far ahead corners are judged, in seconds of travel plus a base distance.
@export var corner_look_time: float = 1.1
@export var corner_look_distance: float = 12.0
## Change of road direction (degrees) over that distance that counts as a hairpin.
@export var sharp_corner_angle: float = 70.0
## Speed through a hairpin on a surface with grip 1.0 (m/s).
@export var hairpin_speed: float = 11.0
## Brake when this much faster than the target speed (m/s).
@export var brake_margin: float = 3.0
## 1.0 = drives at the limit; lower values lift earlier everywhere.
@export_range(0.5, 1.0, 0.01) var skill: float = 0.9

@export_group("Recovery")
@export var stuck_speed: float = 1.5
@export var stuck_time: float = 1.2
@export var reverse_time: float = 1.1
## Put the car back on the road after this many failed reversing attempts,
## or when it is further than this from the centre line (in road widths).
@export var max_reverse_attempts: int = 2
@export var lost_distance_road_widths: float = 3.5
@export var respawn_height: float = 0.6
## A car on the ground this far above or below its road has fallen off it (m).
@export var lost_height: float = 5.0
## Counts as stuck when it has not got this far along the road (m)...
@export var min_progress: float = 4.0
## ...in this many seconds.
@export var progress_check_time: float = 2.5

var input: PlayerInput = PlayerInput.new()

var _car: Car
var _track: Track
var _offset: float = 0.0
var _stuck_timer: float = 0.0
var _reverse_timer: float = 0.0
var _reverse_attempts: int = 0
var _progress_timer: float = 0.0
var _progress_from: float = 0.0


func setup(car: Car, track: Track) -> void:
	_car = car
	_track = track
	_offset = track.get_offset_at(car.global_position)
	_progress_from = _offset
	car.input_source = input


func _physics_process(delta: float) -> void:
	if _car == null or not _car.controls_enabled:
		return
	_offset = _track.get_offset_near(_car.global_position, _offset)
	var velocity: Vector3 = _car.get_velocity()
	var speed: float = velocity.length()

	if _reverse_timer > 0.0:
		_reverse_timer -= delta
		_drive_reverse()
		return
	if _update_stuck(speed, delta):
		return

	# Steering: aim at a point further down the road.
	var aim: Vector3 = _track.get_position_at(_offset + look_ahead_distance + speed * look_ahead_time)
	var to_aim: Vector3 = aim - _car.global_position
	to_aim.y = 0.0
	var forward: Vector3 = -_car.global_basis.z
	forward.y = 0.0
	var angle: float = rad_to_deg(forward.normalized().signed_angle_to(to_aim.normalized(), Vector3.UP))
	# A positive angle means the aim point is to the left.
	input.steer = clampf(-angle / full_steer_angle, -1.0, 1.0)

	# Speed: the sharper the road bends ahead, the lower the target.
	var here: Vector3 = _track.get_direction_at(_offset + look_ahead_distance)
	var ahead: Vector3 = _track.get_direction_at(_offset + corner_look_distance + speed * corner_look_time)
	var bend: float = clampf(rad_to_deg(here.angle_to(ahead)) / sharp_corner_angle, 0.0, 1.0)
	var surface: SurfaceData = _car.get_current_surface()
	var grip: float = sqrt(surface.grip) if surface != null else 1.0
	var target: float = lerpf(_car.get_top_speed(), hairpin_speed * grip, bend) * skill

	input.throttle = 1.0 if speed < target else 0.0
	input.brake = 1.0 if speed > target + brake_margin and speed > stuck_speed * 3.0 else 0.0
	input.handbrake = false


## Returns true while a recovery action has taken over the controls.
func _update_stuck(speed: float, delta: float) -> bool:
	var lost_distance: float = _track.road_width * lost_distance_road_widths
	if _track.get_distance_to_centerline(_car.global_position) > lost_distance:
		_respawn()
		return true
	# Fell off a bridge onto a road below, or similar.
	var road_height: float = _track.get_position_at(_offset).y
	if _car.is_grounded() and absf(_car.global_position.y - road_height) > lost_height:
		_respawn()
		return true
	var stalled: bool = false
	# Standing still against something...
	if speed > stuck_speed:
		_stuck_timer = 0.0
	else:
		_stuck_timer += delta
		if _stuck_timer >= stuck_time:
			_stuck_timer = 0.0
			stalled = true
	# ...or rocking back and forth without getting anywhere.
	_progress_timer += delta
	if _progress_timer >= progress_check_time:
		var length: float = _track.get_length()
		var advanced: float = fposmod(_offset - _progress_from + length * 0.5, length) - length * 0.5
		_progress_timer = 0.0
		_progress_from = _offset
		if advanced < min_progress:
			stalled = true
		elif advanced > min_progress * 3.0:
			_reverse_attempts = 0
	if not stalled:
		return false
	if _reverse_attempts >= max_reverse_attempts:
		_respawn()
	else:
		_reverse_attempts += 1
		_reverse_timer = reverse_time
	return true


func _drive_reverse() -> void:
	input.throttle = 0.0
	# Below walking pace the brake input is reverse gear.
	input.brake = 1.0
	input.steer = -input.steer if absf(input.steer) > 0.1 else 0.0
	input.handbrake = false


func _respawn() -> void:
	_reverse_attempts = 0
	_stuck_timer = 0.0
	_progress_timer = 0.0
	_progress_from = _offset
	var origin: Vector3 = _track.get_position_at(_offset) + Vector3.UP * respawn_height
	_car.global_transform = Transform3D(Basis.looking_at(_track.get_direction_at(_offset), Vector3.UP), origin)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	_car.reset_physics_interpolation()
