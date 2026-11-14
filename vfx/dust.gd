class_name Dust
extends GPUParticles3D
## Wheel dust cloud. The car drives it with set_intensity() every physics tick.

@export var max_particles: int = 90
@export var particle_lifetime: float = 1.3
## Billboard size in metres at birth and at the end of life.
@export var size_range: Vector2 = Vector2(1.0, 3.0)
@export var rise_speed_range: Vector2 = Vector2(0.4, 1.4)
@export_range(0.0, 180.0, 1.0) var spread_degrees: float = 50.0
@export var emission_radius: float = 0.25
@export var drift: Vector3 = Vector3(0.0, 0.35, 0.0)
@export var damping: float = 1.2
## Intensities below this switch the emitter off.
@export var min_intensity: float = 0.05
@export var sprite_resolution: int = 64

var _particle_material: ParticleProcessMaterial


func _ready() -> void:
	amount = max_particles
	lifetime = particle_lifetime
	emitting = false
	amount_ratio = 0.0
	local_coords = false

	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, size_range.x / size_range.y))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_texture: CurveTexture = CurveTexture.new()
	grow_texture.curve = grow

	var fade: Gradient = Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0),
	])
	var fade_texture: GradientTexture1D = GradientTexture1D.new()
	fade_texture.gradient = fade

	_particle_material = ParticleProcessMaterial.new()
	_particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_particle_material.emission_sphere_radius = emission_radius
	_particle_material.direction = Vector3.UP
	_particle_material.spread = spread_degrees
	_particle_material.initial_velocity_min = rise_speed_range.x
	_particle_material.initial_velocity_max = rise_speed_range.y
	_particle_material.gravity = drift
	_particle_material.damping_min = damping
	_particle_material.damping_max = damping
	_particle_material.scale_min = size_range.y * 0.7
	_particle_material.scale_max = size_range.y
	_particle_material.scale_curve = grow_texture
	_particle_material.color_ramp = fade_texture
	process_material = _particle_material

	var sprite_material: StandardMaterial3D = StandardMaterial3D.new()
	sprite_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sprite_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sprite_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sprite_material.vertex_color_use_as_albedo = true
	sprite_material.albedo_texture = LowPoly.radial_texture(sprite_resolution)
	var quad: QuadMesh = QuadMesh.new()
	quad.material = sprite_material
	draw_pass_1 = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## intensity 0..1 scales the emission rate; tint is the surface's dust colour.
func set_intensity(intensity: float, tint: Color) -> void:
	var active: bool = intensity >= min_intensity
	emitting = active
	if active:
		amount_ratio = clampf(intensity, 0.0, 1.0)
		_particle_material.color = tint
