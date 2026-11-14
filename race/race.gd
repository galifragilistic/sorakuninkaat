extends Node3D
## Race scene: spawns the cars on the grid, runs the race through RaceManager
## and shows the HUD. The environment preset decides which lights are on.

@export var car_scene: PackedScene

var _cars: Array[Car] = []

@onready var _track: Track = $Track
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _hud: RaceHud = $HudLayer/RaceHud
@onready var _environment: EnvironmentController = $EnvironmentController
@onready var _race_manager: RaceManager = $RaceManager


func _ready() -> void:
	_race_manager.setup(_track, GameState.lap_count)
	for i: int in GameState.player_count:
		var car: Car = car_scene.instantiate() as Car
		car.player_index = i
		car.name = "Car%d" % (i + 1)
		add_child(car)
		car.global_transform = _track.get_grid_transform(i)
		car.reset_physics_interpolation()
		_cars.append(car)
		_race_manager.add_racer(car, i, tr("Pelaaja %d") % (i + 1))

	var own: RacerState = _race_manager.racers[0]
	_camera_rig.target = own.car
	_camera_rig.snap_to_target()
	_hud.setup(_race_manager, own, _track, _camera)

	_environment.preset_applied.connect(_on_preset_applied)
	_on_preset_applied(_environment.preset)
	_race_manager.start_countdown()


func _unhandled_input(event: InputEvent) -> void:
	if _race_manager.state == RaceManager.State.FINISHED and event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()


func _on_preset_applied(preset: EnvPreset) -> void:
	if preset == null:
		return
	for car: Car in _cars:
		car.headlights_enabled = preset.headlights_on
	for child: Node in _track.get_children():
		var scenery: TrackScenery = child as TrackScenery
		if scenery != null:
			scenery.set_lights_enabled(preset.track_lights_on)
