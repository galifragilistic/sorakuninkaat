extends Node3D
## Phase 1 race scene: one car on the track, followed by the isometric camera.

@onready var _track: Track = $Track
@onready var _car: Car = $Car
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _debug_hud: DebugHud = $HudLayer/DebugHud


func _ready() -> void:
	_car.global_transform = _track.get_start_transform()
	_car.reset_physics_interpolation()
	_camera_rig.target = _car
	_camera_rig.snap_to_target()
	_debug_hud.car = _car
