extends Node3D
## Race scene: spawns one car per local player on the grid, runs the race
## through RaceManager and shows each player their own view via SplitScreen.
## The environment preset decides which lights are on.

@export var car_scene: PackedScene
## Seconds after the finish before a new race can be started, so a held
## button does not skip the result.
@export var restart_delay: float = 1.5

var _cars: Array[Car] = []
var _finished_time: float = 0.0

@onready var _track: Track = $Track
@onready var _split_screen: SplitScreen = $ViewLayer/SplitScreen
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

	_split_screen.setup(_race_manager, _track, _race_manager.racers, GameState.split_layout)
	_environment.preset_applied.connect(_on_preset_applied)
	_on_preset_applied(_environment.preset)
	_race_manager.start_countdown()


func _process(delta: float) -> void:
	if _race_manager.state == RaceManager.State.FINISHED:
		_finished_time += delta


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	if _race_manager.state == RaceManager.State.FINISHED and _finished_time >= restart_delay:
		get_tree().reload_current_scene()


## Temporary shortcuts until the lobby exists (phase 5):
## F1 = one player, F2 = two players, F3 = swap vertical / horizontal split.
func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F1:
			GameState.player_count = 1
		KEY_F2:
			GameState.player_count = 2
		KEY_F3:
			var vertical: bool = GameState.split_layout == GameState.SplitLayout.VERTICAL
			GameState.split_layout = (
				GameState.SplitLayout.HORIZONTAL if vertical else GameState.SplitLayout.VERTICAL
			)
		_:
			return
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
	_split_screen.apply_preset(preset)
