class_name Car
extends RigidBody3D
## Arcade rally car: a RigidBody3D carried by four raycast suspension points.
## Tyre forces are clamped to a friction circle, so the car slides when the
## surface grip runs out (SPEC.md section 3).

signal surface_changed(surface: SurfaceData)

## Every car is in this group (tunnels look for cars inside them).
const GROUP: StringName = &"cars"
## A crash or hard landing; speed_change is the velocity lost in one tick (m/s).
signal impact(speed_change: float)

const WHEEL_COUNT: int = 4
const FRONT_WHEEL_COUNT: int = 2

@export var stats: CarStats
@export var player_index: int = 0
## While false the car ignores its player and holds the handbrake (countdown, after the finish).
@export var controls_enabled: bool = true

## Set by an AiDriver; when null the car reads its player's device.
var input_source: PlayerInput
## Extra grip multiplier from the weather (1.0 = dry).
var weather_grip: float = 1.0
## Network client: the host simulates this car; it is only placed where the
## host says and keeps its wheels, dust and sound going.
var is_puppet: bool = false
## Velocity reported by the host while this car is a puppet.
var puppet_velocity: Vector3 = Vector3.ZERO
## False on a network client's own predicted car: crashes still make their
## sound, but the damage comes from the host so it is not counted twice.
var apply_local_damage: bool = true

@export_group("Stat ranges (stat 1 .. stat 10)")
## Top speed in m/s.
@export var top_speed_range: Vector2 = Vector2(26.0, 50.0)
## Peak acceleration in m/s^2.
@export var acceleration_range: Vector2 = Vector2(6.0, 14.0)
## Grip multiplier from the car's grip stat for the current surface.
@export var grip_multiplier_range: Vector2 = Vector2(0.85, 1.15)

@export_group("Chassis")
@export var wheel_base: float = 2.4
@export var track_width: float = 1.6
## Local height of the suspension mount points.
@export var mount_height: float = 0.6
@export var wheel_radius: float = 0.33

@export_group("Suspension")
@export var suspension_rest_length: float = 0.4
@export var spring_stiffness: float = 35000.0
@export var spring_damping: float = 3500.0

@export_group("Tyres")
## Base friction coefficient, multiplied by surface grip and the car's grip stat.
@export var tire_friction: float = 1.8
## How quickly sideways slip is cancelled (1/s). Keep well below the physics tick rate.
@export var tire_response: float = 18.0
@export_range(0.5, 1.2, 0.01) var front_grip_scale: float = 1.0
@export_range(0.5, 1.2, 0.01) var rear_grip_scale: float = 0.85
## Largest share of the friction circle that drive/brake force may use.
## The rest is always left for cornering.
@export_range(0.1, 1.0, 0.01) var max_longitudinal_share: float = 0.8
## The same for two-wheel-drive cars, whose driven axle carries all the power
## and would otherwise spin out under throttle.
@export_range(0.1, 1.0, 0.01) var two_wheel_drive_share: float = 0.55
## Tyre forces are applied this far above the contact point to limit body roll.
@export var tire_force_height: float = 0.2

@export_group("Steering")
@export_range(0.0, 60.0, 0.5) var steer_angle_low_speed: float = 30.0
@export_range(0.0, 60.0, 0.5) var steer_angle_high_speed: float = 11.0
## Steering input slew rate (full lock per second).
@export var steer_speed: float = 5.0
## Extra steering lock per degree of body slip angle.
@export_range(0.0, 2.0, 0.05) var countersteer_gain: float = 1.0
## Below this speed (m/s) the car is not considered to be sliding.
@export var slip_min_speed: float = 3.0

@export_group("Brakes")
## Peak deceleration from the foot brake in m/s^2.
@export var brake_deceleration: float = 16.0
## Peak deceleration from the handbrake (rear wheels) in m/s^2.
@export var handbrake_deceleration: float = 7.0
## Rear lateral grip multiplier while the handbrake is held.
@export_range(0.0, 1.0, 0.01) var handbrake_grip: float = 0.35
@export var brake_response: float = 20.0
## Below this forward speed (m/s) the brake input drives the car backwards.
@export var reverse_threshold: float = 1.0
@export_range(0.0, 1.0, 0.01) var reverse_speed_share: float = 0.3
@export_range(0.0, 1.0, 0.01) var reverse_force_share: float = 0.6

@export_group("Gearbox (cosmetic)")
## Number of forward gears shown on the HUD.
@export var gear_count: int = 5

@export_group("Lights")
@export var headlights_enabled: bool = true:
	set(value):
		headlights_enabled = value
		_update_headlights()

@export_group("Dust")
@export var dust_scene: PackedScene
## Time in the air (s) after which touching down kicks up a dust burst.
@export var landing_air_time: float = 0.25
@export var landing_dust_time: float = 0.35

@export_group("Damage smoke")
## Total damage (0..1) at which the engine starts to smoke.
@export_range(0.0, 1.0, 0.01) var smoke_start_damage: float = 0.35
@export var smoke_color: Color = Color(0.12, 0.12, 0.14, 0.5)
@export var smoke_position: Vector3 = Vector3(0.0, 0.95, -1.2)
## Speed (m/s) at which rolling dust reaches full strength.
@export var dust_full_speed: float = 22.0
## Share of the dust that appears just from rolling; the rest comes from sliding.
@export_range(0.0, 1.0, 0.01) var dust_rolling_share: float = 0.35
## Slip angle (degrees) at which sliding dust reaches full strength.
@export var dust_full_slip: float = 25.0
@export var dust_min_speed: float = 3.0

@export_group("Air")
## Yaw torque available from steering while no wheel touches the ground.
@export var air_control_torque: float = 900.0
@export var reset_lift: float = 1.0

var _steer: float = 0.0
var _grounded_wheels: int = 0
var _current_surface: SurfaceData
var _mount_points: Array[Vector3] = []
var _wheel_surfaces: Array[SurfaceData] = []
var _dust_emitters: Array[Dust] = []
var _previous_velocity: Vector3 = Vector3.ZERO
var _throttle: float = 0.0
var _air_time: float = 0.0
var _landing_dust_left: float = 0.0
var _smoke: Dust
var _idle_input: PlayerInput = PlayerInput.new()

@onready var _wheel_nodes: Array[Node3D] = [
	$Wheels/FrontLeft, $Wheels/FrontRight, $Wheels/RearLeft, $Wheels/RearRight,
]
@onready var _model: CarModel = $Visual
@onready var _headlights: Node3D = $Headlights
@onready var damage: CarDamage = $Damage


func _ready() -> void:
	add_to_group(GROUP)
	var half_width: float = track_width * 0.5
	var half_base: float = wheel_base * 0.5
	_mount_points = [
		Vector3(-half_width, mount_height, -half_base),
		Vector3(half_width, mount_height, -half_base),
		Vector3(-half_width, mount_height, half_base),
		Vector3(half_width, mount_height, half_base),
	]
	for i: int in WHEEL_COUNT:
		_wheel_nodes[i].position = _mount_points[i] + Vector3.DOWN * suspension_rest_length
		_wheel_surfaces.append(null)
	_idle_input.handbrake = true
	set_model(stats)
	_apply_player_color()
	_update_headlights()
	_create_dust_emitters()


## Top speed in m/s, including damage.
func get_top_speed() -> float:
	return get_base_top_speed() * damage.get_top_speed_multiplier()


## Top speed in m/s of an undamaged car.
func get_base_top_speed() -> float:
	return CarStats.stat_to_value(stats.top_speed, top_speed_range)


## 1..gear_count going forwards, 0 at standstill, -1 in reverse.
func get_gear() -> int:
	var forward_speed: float = get_forward_speed()
	if forward_speed < -reverse_threshold:
		return -1
	if absf(forward_speed) < reverse_threshold:
		return 0
	var ratio: float = clampf(forward_speed / get_base_top_speed(), 0.0, 1.0)
	return clampi(1 + floori(ratio * float(gear_count)), 1, gear_count)


func get_forward_speed() -> float:
	return get_velocity().dot(-global_basis.z)


## Velocity in m/s, from physics or, for a network puppet, from the host.
func get_velocity() -> Vector3:
	return puppet_velocity if is_puppet else linear_velocity


## Smoothed steering position (-1 left .. 1 right).
func get_steer() -> float:
	return _steer


## Hands the car over to the network: no physics, input only drives the visuals.
func make_puppet(visual_input: PlayerInput) -> void:
	is_puppet = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	input_source = visual_input
	controls_enabled = true


## Throttle input used on the last physics tick (0..1).
func get_throttle() -> float:
	return _throttle


func get_speed_kmh() -> float:
	return get_velocity().length() * 3.6


## Angle in degrees between where the car points and where it is going (0 = no slide).
func get_slip_angle() -> float:
	return _get_slip_angle()


func get_current_surface() -> SurfaceData:
	return _current_surface


func is_grounded() -> bool:
	return _grounded_wheels > 0


## Puts the car back on its wheels where it is, keeping its heading.
func reset_upright() -> void:
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var origin: Vector3 = global_position + Vector3.UP * reset_lift
	global_transform = Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), origin)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_previous_velocity = Vector3.ZERO
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	var input: PlayerInput = _idle_input
	if controls_enabled:
		input = input_source if input_source != null else InputManager.get_input(player_index)
	if not is_puppet:
		if input.reset_pressed:
			reset_upright()
		_detect_impact()

	var top_speed: float = get_top_speed()
	var forward_speed: float = get_forward_speed()
	# A puppet's steering already comes smoothed from the host.
	_steer = input.steer if is_puppet else move_toward(_steer, input.steer, steer_speed * delta)
	var speed_ratio: float = clampf(absf(forward_speed) / top_speed, 0.0, 1.0)
	var max_angle: float = lerpf(steer_angle_low_speed, steer_angle_high_speed, speed_ratio)
	# Sliding unlocks extra steering lock so a drift can always be caught.
	max_angle = minf(steer_angle_low_speed, max_angle + _get_slip_angle() * countersteer_gain)
	max_angle *= damage.get_steering_multiplier()
	# Positive rotation around +Y turns -Z towards -X, so steering right is negative.
	var steer_angle: float = -_steer * deg_to_rad(max_angle)

	var drive_force: float = _get_drive_force(input, forward_speed, top_speed)
	_throttle = input.throttle
	var braking: float = input.brake if forward_speed > reverse_threshold else 0.0

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var surface: SurfaceData = null
	_grounded_wheels = 0
	for i: int in WHEEL_COUNT:
		var hit_surface: SurfaceData = _simulate_wheel(
			i, space, steer_angle, drive_force, braking, input.handbrake
		)
		_wheel_surfaces[i] = hit_surface
		if hit_surface != null:
			surface = hit_surface
	_update_dust()

	if _grounded_wheels == 0:
		apply_torque(global_basis.y * -_steer * air_control_torque)
		_air_time += delta
	else:
		if _air_time >= landing_air_time:
			_landing_dust_left = landing_dust_time
		_air_time = 0.0
	_landing_dust_left = maxf(0.0, _landing_dust_left - delta)

	if surface != _current_surface and surface != null:
		_current_surface = surface
		surface_changed.emit(surface)


## A sudden change of velocity between two ticks is a crash (or a hard landing).
func _detect_impact() -> void:
	var change: Vector3 = linear_velocity - _previous_velocity
	_previous_velocity = linear_velocity
	var speed_change: float = change.length()
	if speed_change >= damage.impact_threshold:
		if apply_local_damage:
			damage.apply_impact(global_basis.inverse() * change, speed_change, stats.durability)
		impact.emit(speed_change)


func _get_slip_angle() -> float:
	var velocity: Vector3 = get_velocity()
	velocity.y = 0.0
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	if velocity.length() < slip_min_speed or forward.is_zero_approx():
		return 0.0
	return rad_to_deg(forward.normalized().angle_to(velocity.normalized()))


## Total engine force for this tick, shared between the driven wheels.
func _get_drive_force(input: PlayerInput, forward_speed: float, top_speed: float) -> float:
	var peak: float = mass * CarStats.stat_to_value(stats.acceleration, acceleration_range)
	var force: float = 0.0
	if input.throttle > 0.0:
		var ratio: float = clampf(forward_speed / top_speed, 0.0, 1.0)
		force += input.throttle * peak * (1.0 - ratio * ratio)
	if input.brake > 0.0 and forward_speed <= reverse_threshold:
		var reverse_top: float = top_speed * reverse_speed_share
		var ratio: float = clampf(-forward_speed / reverse_top, 0.0, 1.0)
		force -= input.brake * peak * reverse_force_share * (1.0 - ratio * ratio)
	return force


## Runs suspension and tyre forces for one wheel. Returns the surface it touches, or null.
func _simulate_wheel(
	index: int,
	space: PhysicsDirectSpaceState3D,
	steer_angle: float,
	drive_force: float,
	braking: float,
	handbrake: bool,
) -> SurfaceData:
	var is_front: bool = index < FRONT_WHEEL_COUNT
	var up: Vector3 = global_basis.y
	var ray_length: float = suspension_rest_length + wheel_radius
	var ray_start: Vector3 = global_transform * _mount_points[index]
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_start, ray_start - up * ray_length, collision_mask, [get_rid()]
	)
	var hit: Dictionary = space.intersect_ray(query)
	var wheel_node: Node3D = _wheel_nodes[index]
	wheel_node.rotation.y = steer_angle if is_front else 0.0

	if hit.is_empty():
		wheel_node.position.y = mount_height - suspension_rest_length
		return null

	_grounded_wheels += 1
	var contact: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var distance: float = ray_start.distance_to(contact)
	wheel_node.position.y = mount_height - (distance - wheel_radius)

	var center_of_mass_global: Vector3 = global_transform * center_of_mass
	var point_velocity: Vector3 = (
		linear_velocity + angular_velocity.cross(contact - center_of_mass_global)
	)

	# Suspension.
	var compression: float = ray_length - distance
	var load_force: float = maxf(
		0.0, spring_stiffness * compression - spring_damping * point_velocity.dot(normal)
	)
	apply_force(normal * load_force, contact - global_position)

	# Tyre directions on the ground plane.
	var forward: Vector3 = -global_basis.z
	if is_front:
		forward = forward.rotated(up, steer_angle)
	forward = (forward - normal * forward.dot(normal)).normalized()
	var right: Vector3 = forward.cross(normal)

	var surface_body: SurfaceBody = hit["collider"] as SurfaceBody
	var surface: SurfaceData = surface_body.surface if surface_body != null else null
	var surface_grip: float = 1.0
	var rolling_drag: float = 0.0
	var grip_multiplier: float = 1.0
	if surface != null:
		surface_grip = surface.grip
		rolling_drag = surface.rolling_drag
		grip_multiplier = CarStats.stat_to_value(
			stats.get_grip_stat(surface.kind), grip_multiplier_range
		)

	var wheel_mass: float = mass / float(WHEEL_COUNT)
	var long_speed: float = point_velocity.dot(forward)
	var lat_speed: float = point_velocity.dot(right)
	var axle_grip: float = front_grip_scale if is_front else rear_grip_scale
	var max_friction: float = tire_friction * surface_grip * grip_multiplier * axle_grip * load_force
	max_friction *= damage.get_grip_multiplier() * weather_grip

	# Longitudinal: engine, brakes, rolling drag.
	var long_force: float = 0.0
	if stats.is_wheel_driven(is_front):
		long_force += drive_force / float(stats.get_driven_wheel_count())
	var brake_limit: float = braking * brake_deceleration * wheel_mass
	if handbrake and not is_front:
		brake_limit += handbrake_deceleration * mass / float(WHEEL_COUNT - FRONT_WHEEL_COUNT)
	if brake_limit > 0.0:
		long_force += clampf(-long_speed * brake_response * wheel_mass, -brake_limit, brake_limit)
	long_force -= long_speed * rolling_drag * wheel_mass
	var share: float = max_longitudinal_share
	if stats.get_driven_wheel_count() < WHEEL_COUNT:
		share = two_wheel_drive_share
	var long_limit: float = max_friction * share
	long_force = clampf(long_force, -long_limit, long_limit)

	# Lateral: cancel side slip with whatever is left of the friction circle.
	var lat_limit: float = sqrt(maxf(0.0, max_friction * max_friction - long_force * long_force))
	if handbrake and not is_front:
		lat_limit *= handbrake_grip
	var lat_force: float = clampf(-lat_speed * tire_response * wheel_mass, -lat_limit, lat_limit)

	var force_point: Vector3 = contact + up * tire_force_height
	apply_force(forward * long_force + right * lat_force, force_point - global_position)
	return surface


func _update_headlights() -> void:
	if _headlights != null:
		_headlights.visible = headlights_enabled


## One emitter per rear wheel, parented to the wheel node so it follows the suspension.
func _create_dust_emitters() -> void:
	if dust_scene == null:
		return
	for i: int in range(FRONT_WHEEL_COUNT, WHEEL_COUNT):
		var dust: Dust = dust_scene.instantiate() as Dust
		_wheel_nodes[i].add_child(dust)
		dust.position = Vector3.DOWN * wheel_radius
		_dust_emitters.append(dust)
	_smoke = dust_scene.instantiate() as Dust
	add_child(_smoke)
	_smoke.position = smoke_position


func _update_dust() -> void:
	# Horizontal speed only, so settling on the suspension raises no dust.
	var velocity: Vector3 = get_velocity()
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var rolling: float = clampf(speed / dust_full_speed, 0.0, 1.0) * dust_rolling_share
	var sliding: float = clampf(_get_slip_angle() / dust_full_slip, 0.0, 1.0) * (1.0 - dust_rolling_share)
	for i: int in _dust_emitters.size():
		var surface: SurfaceData = _wheel_surfaces[FRONT_WHEEL_COUNT + i]
		if surface == null or speed < dust_min_speed:
			_dust_emitters[i].set_intensity(0.0, Color.WHITE)
			continue
		var amount: float = rolling + sliding
		if _landing_dust_left > 0.0:
			amount = 1.0
		_dust_emitters[i].set_intensity(amount * surface.dust_amount, surface.dust_color)
	if _smoke != null:
		var smoke: float = inverse_lerp(smoke_start_damage, 1.0, damage.get_total())
		_smoke.set_intensity(clampf(smoke, 0.0, 1.0), smoke_color)


func _apply_player_color() -> void:
	set_paint(GameState.get_player_color(player_index), PlayerSetup.Pattern.STRIPE)


## Applies the car, paint and pattern a player picked in the menus.
func apply_setup(setup: PlayerSetup) -> void:
	stats = setup.stats
	set_model(stats)
	set_paint(setup.color, setup.pattern)


## Rebuilds the body, wheels and lamps in the shape of car_stats' model.
func set_model(car_stats: CarStats) -> void:
	var look: CarLook = car_stats.look if car_stats != null and car_stats.look != null else CarLook.new()
	_model.build(look, _mount_points, wheel_radius)
	var wheel_mesh: ArrayMesh = _model.build_wheel_mesh(look, wheel_radius)
	var wheel_material: StandardMaterial3D = _model.make_wheel_material()
	for wheel: Node3D in _wheel_nodes:
		var mesh_node: MeshInstance3D = wheel.get_node("Mesh") as MeshInstance3D
		mesh_node.mesh = wheel_mesh
		mesh_node.material_override = wheel_material
	var spotlights: Array[Node] = _headlights.get_children()
	for i: int in mini(spotlights.size(), _model.head_lamp_positions.size()):
		(spotlights[i] as Node3D).position = _model.head_lamp_positions[i]


func set_paint(color: Color, pattern: PlayerSetup.Pattern) -> void:
	_model.set_paint(color, pattern)
