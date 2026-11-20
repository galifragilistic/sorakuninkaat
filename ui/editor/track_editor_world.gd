class_name TrackEditorWorld
extends Control
## The race map behind the track editor: the same track, camera angle and
## lighting a race uses, in its own viewport. The editor draws its handles
## on top and moves this camera.

signal view_changed

## Extra metres of camera distance beyond what framing the ground needs.
@export var camera_clearance: float = 40.0

var _viewport: SubViewport
var _picture: TextureRect
var _rig: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _controller: EnvironmentController
var _track: Track
var _shown: Dictionary = {}
var _shadow_distance: float = 140.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_picture = TextureRect.new()
	_picture.texture = _viewport.get_texture()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_picture)

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	_viewport.add_child(world_environment)
	_sun = DirectionalLight3D.new()
	_viewport.add_child(_sun)
	_controller = EnvironmentController.new()
	_controller.preset = GameState.get_time_preset()
	_controller.weather = GameState.get_weather()
	_controller.max_quality = Settings.Quality.HIGH
	_controller.world_environment = world_environment
	_controller.sun = _sun
	_controller.preset_applied.connect(_on_preset_applied)
	_viewport.add_child(_controller)

	# Same rig as a race camera (CameraRig): orthographic, fixed yaw and pitch.
	var rig_script: Script = CameraRig as Script
	_rig = Node3D.new()
	_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rig.rotation_degrees = Vector3(
		float(rig_script.get_property_default_value("pitch_degrees")),
		float(rig_script.get_property_default_value("yaw_degrees")),
		0.0
	)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_camera.near = float((PlayerView as Script).get_property_default_value("camera_near"))
	_camera.far = float((PlayerView as Script).get_property_default_value("camera_far"))
	_camera.cull_mask = Track.get_view_cull_mask(0)
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rig.add_child(_camera)
	_viewport.add_child(_rig)

	resized.connect(_update_viewport_size)
	Settings.changed.connect(_update_viewport_size)
	_update_viewport_size()
	set_view(Vector2.ZERO, float(rig_script.get_property_default_value("base_size")))


func get_track() -> Track:
	return _track


func get_camera_basis() -> Basis:
	return _rig.global_transform.basis


## Rebuilds the track when the design changed.
func show_design(design: TrackDesign) -> void:
	var snapshot: Dictionary = design.to_dict()
	if snapshot == _shown and _track != null:
		return
	_shown = snapshot
	if _track != null:
		_viewport.remove_child(_track)
		_track.free()
	_track = design.build_track()
	# The editor never draws the forest. Placed props stay; the race builds the trees.
	for child: Node in _track.get_children():
		var scenery: TrackScenery = child as TrackScenery
		if scenery != null:
			scenery.tree_count = 0
	_viewport.add_child(_track)
	_apply_lights()


## Moves the road to match the design. Trees and terrain stay until show_design.
func update_road(design: TrackDesign) -> void:
	if _track == null:
		show_design(design)
		return
	design.apply_road(_track)
	_track.rebuild_road()


## Looks at focus (x, z) with view_size metres of vertical ortho size.
func set_view(focus: Vector2, view_size: float) -> void:
	var pitch: float = absf(deg_to_rad(_rig.rotation_degrees.x))
	var ground_depth: float = view_size / maxf(sin(pitch), 0.25)
	var race_distance: float = float((CameraRig as Script).get_property_default_value("distance"))
	var distance: float = maxf(race_distance, ground_depth * 0.5 + camera_clearance)
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.size = view_size
	var race_far: float = float((PlayerView as Script).get_property_default_value("camera_far"))
	_camera.far = maxf(race_far, distance + ground_depth + camera_clearance)
	_rig.position = Vector3(focus.x, 0.0, focus.y)
	var preset_shadow: float = _shadow_distance
	if _controller != null and _controller.preset != null:
		preset_shadow = _controller.preset.sun_shadow_max_distance
	_shadow_distance = maxf(preset_shadow, distance + ground_depth * 0.5)
	_apply_shadow_distance()
	view_changed.emit()


## World x, z under the cursor: the ground or road that is actually drawn,
## or the y = 0 plane when the ray hits nothing.
func pick_xz(screen: Vector2) -> Vector2:
	var fallback: Vector2 = ground_at(screen, 0.0)
	if _track == null or _viewport == null or _viewport.size.x < 2 or size.x < 2.0:
		return fallback
	var pixel: Vector2 = screen * Vector2(_viewport.size) / size
	var origin: Vector3 = _camera.project_ray_origin(pixel)
	var direction: Vector3 = _camera.project_ray_normal(pixel)
	var space: PhysicsDirectSpaceState3D = _track.get_world_3d().direct_space_state
	if space == null:
		return fallback
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * _camera.far)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return fallback
	var point: Vector3 = hit.position
	return Vector2(point.x, point.z)


## Screen position to world x, z on the horizontal plane at height.
func ground_at(screen: Vector2, height: float) -> Vector2:
	if _viewport == null or _viewport.size.x < 2 or size.x < 2.0:
		return Vector2.ZERO
	var pixel: Vector2 = screen * Vector2(_viewport.size) / size
	var origin: Vector3 = _camera.project_ray_origin(pixel)
	var direction: Vector3 = _camera.project_ray_normal(pixel)
	if absf(direction.y) < 0.00001:
		return Vector2(origin.x, origin.z)
	var along: float = (height - origin.y) / direction.y
	var hit: Vector3 = origin + direction * along
	return Vector2(hit.x, hit.z)


## World point to a position on this control.
func project(world_point: Vector3) -> Vector2:
	if _viewport == null or _viewport.size.x < 2 or size.x < 2.0:
		return Vector2.ZERO
	var pixel: Vector2 = _camera.unproject_position(world_point)
	return pixel * size / Vector2(_viewport.size)


func _on_preset_applied(_preset: EnvPreset) -> void:
	_apply_shadow_distance()
	_apply_lights()


func _apply_shadow_distance() -> void:
	if _sun != null:
		_sun.directional_shadow_max_distance = _shadow_distance


func _apply_lights() -> void:
	if _track == null or _controller == null or _controller.preset == null:
		return
	for child: Node in _track.get_children():
		var scenery: TrackScenery = child as TrackScenery
		if scenery != null:
			scenery.set_lights_enabled(_controller.preset.track_lights_on)


func _update_viewport_size() -> void:
	var retro: bool = Retro.is_on()
	if retro:
		_viewport.size = Retro.get_render_size(size)
		_viewport.msaa_3d = Viewport.MSAA_DISABLED
	else:
		var pixel_scale: Vector2 = Vector2(get_window().size) / get_viewport_rect().size
		var pixels: Vector2 = (size * pixel_scale).round()
		_viewport.size = Vector2i(maxi(2, int(pixels.x)), maxi(2, int(pixels.y)))
		_viewport.msaa_3d = get_viewport().msaa_3d
	Retro.style_picture(_picture, retro)
	view_changed.emit()
