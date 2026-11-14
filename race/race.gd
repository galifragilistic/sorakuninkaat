extends Node3D
## Race scene: builds the selected track, spawns one car per player on the
## grid, runs the race through RaceManager and shows each player their own
## view via SplitScreen. Also owns the pause menu and the results screen.

@export var car_scene: PackedScene
## Seconds between the last finisher and the results screen.
@export var results_delay: float = 2.0
## Canvas layer of the pause and results overlays (above the HUD).
@export var overlay_layer: int = 10

var _cars: Array[Car] = []
var _track: Track
var _overlay: CanvasLayer
var _pause_menu: PauseMenu

@onready var _split_screen: SplitScreen = $ViewLayer/SplitScreen
@onready var _environment: EnvironmentController = $EnvironmentController
@onready var _race_manager: RaceManager = $RaceManager


func _ready() -> void:
	_track = GameState.selected_track.scene.instantiate() as Track
	_track.name = "Track"
	add_child(_track)

	_race_manager.setup(_track, GameState.lap_count)
	var slot: int = 0
	for player: int in GameState.get_race_players():
		var car: Car = car_scene.instantiate() as Car
		car.player_index = player
		car.name = "Car%d" % (player + 1)
		add_child(car)
		car.apply_setup(GameState.players[player])
		car.global_transform = _track.get_grid_transform(slot)
		car.reset_physics_interpolation()
		_cars.append(car)
		_race_manager.add_racer(car, player, tr("Pelaaja %d") % (player + 1))
		slot += 1

	_overlay = CanvasLayer.new()
	_overlay.layer = overlay_layer
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

	_split_screen.setup(_race_manager, _track, _race_manager.racers, GameState.split_layout)
	_environment.preset_applied.connect(_on_preset_applied)
	_on_preset_applied(_environment.preset)
	_race_manager.lap_completed.connect(_on_lap_completed)
	_race_manager.state_changed.connect(_on_state_changed)
	_race_manager.start_countdown()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.ACTION_PAUSE) and _can_pause():
		get_viewport().set_input_as_handled()
		_set_paused(true)


func _can_pause() -> bool:
	var state: RaceManager.State = _race_manager.state
	return _pause_menu == null and (state == RaceManager.State.RACING or state == RaceManager.State.COUNTDOWN)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if paused:
		_pause_menu = PauseMenu.new()
		_pause_menu.resume_requested.connect(_set_paused.bind(false))
		_pause_menu.restart_requested.connect(GameState.start_race)
		_pause_menu.quit_requested.connect(_leave_race)
		_overlay.add_child(_pause_menu)
	elif _pause_menu != null:
		_pause_menu.queue_free()
		_pause_menu = null


func _on_lap_completed(_racer: RacerState, lap_time: float, _is_best: bool) -> void:
	GameState.submit_lap_time(GameState.selected_track, lap_time)


func _on_state_changed(state: RaceManager.State) -> void:
	if state != RaceManager.State.FINISHED:
		return
	var standings: Array[RacerState] = _race_manager.get_standings()
	for i: int in standings.size():
		GameState.points[standings[i].player_index] += Catalog.get_points(i + 1)
	await get_tree().create_timer(results_delay).timeout
	_show_results()


func _show_results() -> void:
	var results: ResultsScreen = ResultsScreen.new()
	_overlay.add_child(results)
	results.setup(_race_manager, GameState.selected_track)
	results.rematch_requested.connect(GameState.start_race)
	results.change_track_requested.connect(_change_track)
	results.leave_requested.connect(_leave_race)


## Back to the lobby in multiplayer, to the main menu otherwise.
func _leave_race() -> void:
	var is_multi: bool = GameState.mode == GameState.Mode.MULTI
	GameState.go_to_menu(MenuScreen.LOBBY if is_multi else MenuScreen.MAIN)


func _change_track() -> void:
	var is_multi: bool = GameState.mode == GameState.Mode.MULTI
	GameState.menu_start_context = {
		"start_race": true, "return_to": MenuScreen.LOBBY if is_multi else MenuScreen.MAIN,
	}
	GameState.go_to_menu(MenuScreen.TRACK_SELECT)


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
