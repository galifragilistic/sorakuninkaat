class_name PrecipitationEmitter
extends GPUParticles3D
## Rain or snow falling in a box that follows one car, so every player's view
## stays covered without filling the whole track with particles.

@export var target: Node3D
## Size of the emission box around the target (x, z) and its height above it.
@export var area_size: Vector2 = Vector2(70.0, 70.0)
@export var emit_height: float = 16.0

@export_group("Rain")
@export var rain_count: int = 1700
@export var rain_fall_speed: float = 24.0
@export var rain_streak_size: Vector2 = Vector2(0.05, 1.1)
@export var rain_color: Color = Color(0.78, 0.86, 1.0, 0.45)
@export var rain_wind: Vector3 = Vector3(2.5, 0.0, 1.0)

@export_group("Snow")
@export var snow_count: int = 1800
@export var snow_fall_speed: float = 3.2
@export var snow_flake_size: float = 0.36
@export var snow_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var snow_wind: Vector3 = Vector3(1.2, 0.0, 0.6)
@export var snow_turbulence: float = 0.6

@export_group("Sprite")
@export var sprite_resolution: int = 32


func configure(kind: WeatherData.Precipitation, amount: float) -> void:
	var is_rain: bool = kind == WeatherData.Precipitation.RAIN
	var fall_speed: float = rain_fall_speed if is_rain else snow_fall_speed
	var wind: Vector3 = rain_wind if is_rain else snow_wind
	amount = maxi(1, roundi(float(rain_count if is_rain else snow_count) * amount))
	lifetime = emit_height / fall_speed
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Particles live far from the emitter origin; never cull the system.
	visibility_aabb = AABB(
		Vector3(-area_size.x, -emit_height * 2.0, -area_size.y),
		Vector3(area_size.x * 2.0, emit_height * 3.0, area_size.y * 2.0)
	)

	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(area_size.x * 0.5, 0.5, area_size.y * 0.5)
	process.direction = (Vector3.DOWN * fall_speed + wind).normalized()
	process.spread = 2.0 if is_rain else 12.0
	process.initial_velocity_min = fall_speed * 0.85
	process.initial_velocity_max = fall_speed * 1.1
	process.gravity = Vector3.ZERO
	process.color = rain_color if is_rain else snow_color
	if not is_rain:
		process.turbulence_enabled = true
		process.turbulence_noise_strength = snow_turbulence
	process_material = process

	var sprite: StandardMaterial3D = StandardMaterial3D.new()
	sprite.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sprite.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sprite.vertex_color_use_as_albedo = true
	var quad: QuadMesh = QuadMesh.new()
	if is_rain:
		# Upright streaks that turn to face the camera.
		sprite.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		quad.size = rain_streak_size
	else:
		sprite.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sprite.albedo_texture = LowPoly.radial_texture(sprite_resolution)
		quad.size = Vector2.ONE * snow_flake_size
	quad.material = sprite
	draw_pass_1 = quad
	emitting = true


func _process(_delta: float) -> void:
	if target != null:
		global_position = target.global_position + Vector3.UP * emit_height
