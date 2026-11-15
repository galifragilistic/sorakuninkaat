class_name CarPreview
extends Control
## A car on a slowly turning stage, rendered in its own small 3D world
## (mockups/03_Autovalinta.png). Also used for lobby cards and the podium.

const CAR_SCENE: PackedScene = preload("res://cars/car.tscn")

## Draws the spotlight cone and the stage rings behind the car.
@export var show_stage: bool = true
@export var spin_degrees_per_second: float = 24.0
@export var start_angle_degrees: float = 20.0
## Vertical size of the camera view in metres (smaller = bigger car).
@export var view_size: float = 6.2
@export var camera_pitch_degrees: float = -30.0
@export var camera_yaw_degrees: float = 45.0
@export var camera_distance: float = 20.0
## Point on the car the camera looks at.
@export var look_at_height: float = 0.75
@export var headlights_on: bool = true

@export_group("Lighting")
@export var key_light_color: Color = Color(1.0, 0.95, 0.88)
@export var key_light_energy: float = 1.6
@export var key_light_rotation_degrees: Vector3 = Vector3(-50.0, -40.0, 0.0)
@export var ambient_color: Color = Color(0.5, 0.58, 0.8)
@export var ambient_energy: float = 0.7

@export_group("Stage")
@export var ring_color: Color = UiStyle.INFO
## Ring centre and radius as fractions of the control size.
@export var ring_center: Vector2 = Vector2(0.5, 0.62)
@export var ring_radius: Vector2 = Vector2(0.44, 0.2)
@export var cone_top_half_width: float = 0.2
@export_range(0.0, 1.0, 0.01) var cone_alpha: float = 0.22

var _viewport: SubViewport
var _pivot: Node3D
var _car: Car
var _camera: Camera3D
var _pending_color: Color = Color.WHITE
var _pending_pattern: PlayerSetup.Pattern = PlayerSetup.Pattern.STRIPE
var _has_pending: bool = false
var _pending_stats: CarStats
var _shown_stats: CarStats


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.light_color = key_light_color
	key_light.light_energy = key_light_energy
	key_light.rotation_degrees = key_light_rotation_degrees
	_viewport.add_child(key_light)

	_pivot = Node3D.new()
	# Turned every frame in _process, not in physics steps.
	_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pivot.rotation_degrees.y = start_angle_degrees
	_viewport.add_child(_pivot)
	_car = CAR_SCENE.instantiate() as Car
	# A showroom model: no physics, no input.
	_car.freeze = true
	_car.process_mode = Node.PROCESS_MODE_DISABLED
	_pivot.add_child(_car)
	_car.headlights_enabled = headlights_on

	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = view_size
	_camera.rotation_degrees = Vector3(camera_pitch_degrees, camera_yaw_degrees, 0.0)
	_viewport.add_child(_camera)
	_camera.position = Vector3.UP * look_at_height + _camera.basis.z * camera_distance

	var picture: TextureRect = TextureRect.new()
	picture.texture = _viewport.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(picture)

	resized.connect(_update_viewport_size)
	_update_viewport_size()
	if _has_pending:
		show_car(_pending_color, _pending_pattern, _pending_stats)


func show_setup(setup: PlayerSetup) -> void:
	show_car(setup.color, setup.pattern, setup.stats)


## stats is optional; when given, the model takes that car's proportions.
func show_car(color: Color, pattern: PlayerSetup.Pattern, stats: CarStats = null) -> void:
	if _car == null:
		# Not in the tree yet; applied in _ready().
		_pending_color = color
		_pending_pattern = pattern
		_pending_stats = stats
		_has_pending = true
		return
	if stats != null and stats != _shown_stats:
		_shown_stats = stats
		_car.set_model(stats)
	_car.set_paint(color, pattern)


func _process(delta: float) -> void:
	if _pivot != null and is_visible_in_tree():
		_pivot.rotation_degrees.y += spin_degrees_per_second * delta


func _update_viewport_size() -> void:
	var pixel_scale: Vector2 = Vector2(get_window().size) / get_viewport_rect().size
	var pixels: Vector2 = (size * pixel_scale).round()
	_viewport.size = Vector2i(maxi(2, int(pixels.x)), maxi(2, int(pixels.y)))
	queue_redraw()


func _draw() -> void:
	if not show_stage:
		return
	var center: Vector2 = size * ring_center
	var radius: Vector2 = size * ring_radius
	# Spotlight cone: bright and narrow at the top, fading out at the stage.
	var top_left: Vector2 = Vector2(size.x * (0.5 - cone_top_half_width), 0.0)
	var top_right: Vector2 = Vector2(size.x * (0.5 + cone_top_half_width), 0.0)
	var lit: Color = Color(1.0, 1.0, 1.0, cone_alpha)
	var faded: Color = Color(1.0, 1.0, 1.0, 0.0)
	draw_polygon(
		PackedVector2Array([top_left, top_right, center + Vector2(radius.x, 0.0), center - Vector2(radius.x, 0.0)]),
		PackedColorArray([lit, lit, faded, faded])
	)
	draw_set_transform(center, 0.0, Vector2(1.0, radius.y / radius.x))
	draw_arc(Vector2.ZERO, radius.x, 0.0, TAU, 64, ring_color, 2.5, true)
	draw_arc(Vector2.ZERO, radius.x * 0.85, 0.0, TAU, 64, Color(UiStyle.LINE, 0.9), 1.5, true)
