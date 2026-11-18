class_name WorldPreview
extends Control
## Renders a track with full lighting in its own 3D world. Used as the living
## menu backdrop (camera flies along the road) and as the track select
## preview (static overview).

enum CameraMode { FLYOVER, OVERVIEW }

@export var camera_mode: CameraMode = CameraMode.FLYOVER
@export var env_preset: EnvPreset = preload("res://env/presets/evening_clear.tres")
@export var camera_pitch_degrees: float = -35.0
@export var camera_yaw_degrees: float = 45.0
@export var camera_distance: float = 110.0
@export var camera_far: float = 400.0

@export_group("Performance")
## Most rendered pixels per UI pixel. 1.0 keeps a Retina or 4K screen from
## rendering the backdrop at full device resolution.
@export var max_pixel_scale: float = 1.0
@export var msaa: Viewport.MSAA = Viewport.MSAA_2X
## Heaviest environment effects the preview uses, whatever the quality setting.
@export var max_quality: Settings.Quality = Settings.Quality.MEDIUM

@export_group("Flyover")
## Vertical view size in metres.
@export var flyover_view_size: float = 30.0
## Speed of the point the camera follows along the road (m/s).
@export var flyover_speed: float = 7.0
## Shifts the picture sideways in metres, e.g. to keep the road clear of a menu column.
@export var flyover_shift: float = 0.0

@export_group("Overview")
@export var overview_view_size: float = 175.0
@export var overview_center: Vector3 = Vector3.ZERO

var _viewport: SubViewport
var _picture: TextureRect
## Anti-aliasing outside the retro style.
var _smooth_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _camera: Camera3D
var _track: Track
var _offset: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_smooth_msaa = msaa
	_viewport.msaa_3d = msaa
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_picture = TextureRect.new()
	var picture: TextureRect = _picture
	picture.texture = _viewport.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(picture)

	resized.connect(_update_viewport_size)
	Settings.changed.connect(_update_viewport_size)
	visibility_changed.connect(_update_rendering)
	_update_viewport_size()


## Builds the given track inside the preview world, replacing any previous one.
func show_track(track: TrackInfo) -> void:
	for child: Node in _viewport.get_children():
		child.queue_free()
	_track = null
	if track == null or not track.is_available():
		return

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	_viewport.add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	_viewport.add_child(sun)
	_track = track.instantiate_track()
	_viewport.add_child(_track)
	var controller: EnvironmentController = EnvironmentController.new()
	controller.preset = env_preset
	controller.max_quality = max_quality
	controller.world_environment = world_environment
	controller.sun = sun
	_viewport.add_child(controller)

	_camera = Camera3D.new()
	# Moved every frame in _process, not in physics steps.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.far = camera_far
	_camera.rotation_degrees = Vector3(camera_pitch_degrees, camera_yaw_degrees, 0.0)
	_viewport.add_child(_camera)
	if camera_mode == CameraMode.OVERVIEW:
		_camera.size = overview_view_size
		_camera.position = overview_center + _camera.basis.z * camera_distance
	else:
		_camera.size = flyover_view_size
		_camera.h_offset = flyover_shift
		_update_flyover(0.0)


func _process(delta: float) -> void:
	if camera_mode == CameraMode.FLYOVER and _track != null and is_visible_in_tree():
		_update_flyover(delta)


func _update_flyover(delta: float) -> void:
	_offset = fposmod(_offset + flyover_speed * delta, _track.get_length())
	_camera.position = _track.get_position_at(_offset) + _camera.basis.z * camera_distance


func _update_viewport_size() -> void:
	var retro: bool = Retro.is_on()
	if retro:
		_viewport.size = Retro.get_render_size(size)
		_viewport.msaa_3d = Viewport.MSAA_DISABLED
	else:
		var pixel_scale: Vector2 = (Vector2(get_window().size) / get_viewport_rect().size).min(Vector2.ONE * max_pixel_scale)
		var pixels: Vector2 = (size * pixel_scale).round()
		_viewport.size = Vector2i(maxi(2, int(pixels.x)), maxi(2, int(pixels.y)))
		_viewport.msaa_3d = _smooth_msaa
	Retro.style_picture(_picture, retro)


## A hidden preview stops rendering so it costs nothing.
func _update_rendering() -> void:
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	)
