extends Node3D
## Race scene: builds the selected track, spawns one car per grid slot, runs
## the race through RaceManager and shows each local player their own view
## via SplitScreen. Also owns the pause menu and the results screen.
## In a network game the host simulates everything; clients mirror it through
## NetSync and only show their own player's view.

@export var car_scene: PackedScene
## Seconds between the last finisher and the results screen.
@export var results_delay: float = 2.0
## Canvas layer of the pause and results overlays (above the HUD).
@export var overlay_layer: int = 10
@export var countdown_volume_db: float = -8.0

var _cars: Array[Car] = []
var _track: Track
var _overlay: CanvasLayer
var _pause_menu: PauseMenu
var _net_sync: NetSync
var _is_net: bool = false
## False on network clients: the host decides everything.
var _is_server: bool = true

@onready var _split_screen: SplitScreen = $ViewLayer/SplitScreen
@onready var _environment: EnvironmentController = $EnvironmentController
@onready var _race_manager: RaceManager = $RaceManager


func _ready() -> void:
	_is_net = GameState.mode == GameState.Mode.NET and Network.is_online()
	_is_server = not _is_net or Network.is_host()
	_track = GameState.selected_track.scene.instantiate() as Track
	_track.name = "Track"
	add_child(_track)

	_race_manager.setup(_track, GameState.lap_count, _is_server)
	var humans: Array[RacerState] = _spawn_cars()
	InputManager.solo_mode = humans.size() == 1
	_add_car_audio(humans)

	_overlay = CanvasLayer.new()
	_overlay.layer = overlay_layer
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

	_split_screen.setup(_race_manager, _track, humans, GameState.split_layout)
	_environment.preset_applied.connect(_on_preset_applied)
	_environment.set_preset(GameState.get_time_preset(), GameState.get_weather())
	_setup_weather(humans)
	_race_manager.lap_completed.connect(_on_lap_completed)
	_race_manager.countdown_tick.connect(_on_countdown_tick)
	_race_manager.state_changed.connect(_on_state_changed)

	if _is_net:
		_start_network()
	else:
		_race_manager.start_countdown()


## Creates the cars on the grid. Returns the racers whose view is shown on this machine.
func _spawn_cars() -> Array[RacerState]:
	var grid: Dictionary = GameState.build_grid()
	var humans: Array[RacerState] = []
	var ai_number: int = 0
	var slot: int = 0
	for player: int in grid:
		var setup: PlayerSetup = grid[player]
		var car: Car = car_scene.instantiate() as Car
		car.player_index = player
		car.name = "Car%d" % (player + 1)
		add_child(car)
		car.apply_setup(setup)
		car.global_transform = _track.get_grid_transform(slot)
		car.reset_physics_interpolation()
		_cars.append(car)
		slot += 1

		var racer_name: String = tr("Pelaaja %d") % (player + 1)
		if setup.is_ai:
			ai_number += 1
			racer_name = tr("Tekoäly %d") % ai_number
			if _is_server:
				_add_ai_driver(car)
		var racer: RacerState = _race_manager.add_racer(car, player, racer_name, setup)
		if _is_local_player(player, setup):
			humans.append(racer)
			if _is_net:
				# Online, this machine's player uses P1's devices whatever their slot.
				car.input_source = InputManager.get_input(0)
	return humans


func _is_local_player(slot: int, setup: PlayerSetup) -> bool:
	if setup.is_ai:
		return false
	return slot == Network.local_slot if _is_net else true


func _add_ai_driver(car: Car) -> void:
	var driver: AiDriver = AiDriver.new()
	driver.name = "AiDriver"
	car.add_child(driver)
	driver.setup(car, _track)


func _add_car_audio(humans: Array[RacerState]) -> void:
	var listeners: Array[Car] = []
	for racer: RacerState in humans:
		listeners.append(racer.car)
	for car: Car in _cars:
		var audio: CarAudio = CarAudio.new()
		audio.name = "Audio"
		car.add_child(audio)
		audio.setup(car, listeners)


func _start_network() -> void:
	_net_sync = NetSync.new()
	_net_sync.name = "NetSync"
	add_child(_net_sync)
	var slots: Array[int] = []
	for car: Car in _cars:
		slots.append(car.player_index)
	_net_sync.setup(_race_manager, _cars, slots)
	_net_sync.remote_player_left.connect(_on_remote_player_left)
	Network.session_changed.connect(_on_session_changed)


## Host: a player dropped out or went back to the lobby; the computer drives on.
func _on_remote_player_left(slot: int) -> void:
	for car: Car in _cars:
		if car.player_index == slot and not car.has_node("AiDriver"):
			_add_ai_driver(car)
			car.controls_enabled = _race_manager.state == RaceManager.State.RACING


## Client: the connection is gone; Network takes us back to the lobby.
func _on_session_changed() -> void:
	if not Network.is_online():
		set_process_unhandled_input(false)


## Slippery roads for everyone, and rain or snow around each local player's car.
func _setup_weather(humans: Array[RacerState]) -> void:
	var weather: WeatherData = GameState.get_weather()
	for car: Car in _cars:
		car.weather_grip = weather.grip_multiplier
	if weather.precipitation == WeatherData.Precipitation.NONE:
		return
	for racer: RacerState in humans:
		var particles: PrecipitationEmitter = PrecipitationEmitter.new()
		particles.target = racer.car
		add_child(particles)
		particles.configure(weather.precipitation, weather.precipitation_amount)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.ACTION_PAUSE) and _can_pause():
		get_viewport().set_input_as_handled()
		_set_paused(true)


func _can_pause() -> bool:
	var state: RaceManager.State = _race_manager.state
	return _pause_menu == null and (state == RaceManager.State.RACING or state == RaceManager.State.COUNTDOWN)


func _set_paused(paused: bool) -> void:
	# A network race cannot stop for one player; the menu opens over the running race.
	get_tree().paused = paused and not _is_net
	if paused:
		_pause_menu = PauseMenu.new()
		if _is_net:
			_pause_menu.show_restart = _is_server
			_pause_menu.note = tr("Verkkokisa jatkuu taustalla.")
		_pause_menu.resume_requested.connect(_set_paused.bind(false))
		_pause_menu.restart_requested.connect(_restart)
		_pause_menu.quit_requested.connect(_leave_race)
		_overlay.add_child(_pause_menu)
	elif _pause_menu != null:
		_pause_menu.queue_free()
		_pause_menu = null


func _on_countdown_tick(seconds_left: int) -> void:
	var sound: SoundBank.Sound = SoundBank.Sound.BEEP if seconds_left > 0 else SoundBank.Sound.GO
	SoundBank.play(self, sound, countdown_volume_db)


func _on_lap_completed(_racer: RacerState, lap_time: float, _is_best: bool) -> void:
	GameState.submit_lap_time(GameState.selected_track, lap_time)


func _on_state_changed(state: RaceManager.State) -> void:
	if state != RaceManager.State.FINISHED:
		return
	var standings: Array[RacerState] = _race_manager.get_standings()
	for i: int in standings.size():
		GameState.points[standings[i].player_index] += Catalog.get_points(i + 1)
	await get_tree().create_timer(results_delay).timeout
	if _pause_menu != null:
		_set_paused(false)
	_show_results()


func _show_results() -> void:
	var results: ResultsScreen = ResultsScreen.new()
	_overlay.add_child(results)
	results.setup(_race_manager, GameState.selected_track)
	results.rematch_requested.connect(_restart)
	results.change_track_requested.connect(_change_track)
	results.leave_requested.connect(_leave_race)


func _restart() -> void:
	if _is_net:
		Network.start_race()
	else:
		GameState.start_race()


## Back to the lobby in multiplayer, to the main menu otherwise. The network
## host takes everybody along; a client leaves on its own.
func _leave_race() -> void:
	if _is_net:
		if _is_server:
			Network.return_to_lobby()
		else:
			_net_sync.leave_race()
			Network.go_to_lobby()
		return
	var is_multi: bool = GameState.mode == GameState.Mode.MULTI
	GameState.go_to_menu(MenuScreen.LOBBY if is_multi else MenuScreen.MAIN)


func _change_track() -> void:
	var is_multi: bool = GameState.mode == GameState.Mode.MULTI
	GameState.go_to_menu(MenuScreen.TRACK_SELECT, {
		"start_race": true, "return_to": MenuScreen.LOBBY if is_multi else MenuScreen.MAIN,
	})


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
