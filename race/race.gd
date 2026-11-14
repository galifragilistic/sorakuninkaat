extends Node3D
## Race scene: one car on the track, followed by the isometric camera.
## The environment preset decides which lights are on.

@onready var _track: Track = $Track
@onready var _car: Car = $Car
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _debug_hud: DebugHud = $HudLayer/DebugHud
@onready var _environment: EnvironmentController = $EnvironmentController


func _ready() -> void:
	_car.global_transform = _track.get_start_transform()
	_car.reset_physics_interpolation()
	_camera_rig.target = _car
	_camera_rig.snap_to_target()
	_debug_hud.car = _car
	_environment.preset_applied.connect(_on_preset_applied)
	_on_preset_applied(_environment.preset)


func _on_preset_applied(preset: EnvPreset) -> void:
	if preset == null:
		return
	_car.headlights_enabled = preset.headlights_on
	for child: Node in _track.get_children():
		var scenery: TrackScenery = child as TrackScenery
		if scenery != null:
			scenery.set_lights_enabled(preset.track_lights_on)
