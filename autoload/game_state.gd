extends Node
## Global race/session state shared between scenes: who plays with what,
## on which track and with which rules, plus session records and points.

enum SplitLayout { VERTICAL, HORIZONTAL }
enum Mode { SINGLE, MULTI }

const MAX_PLAYERS: int = 4
## Player slots that can race at the moment (3-4 players come in a later phase).
const MAX_LOCAL_PLAYERS: int = 4

const MENU_SCENE: String = "res://ui/menus/menu_root.tscn"
const RACE_SCENE: String = "res://race/race.tscn"

## Player colors P1-P4 (SPEC.md section 6).
const PLAYER_COLORS: Array[Color] = [
	Color("#ff7a1a"),
	Color("#3fd8ff"),
	Color("#b6f03c"),
	Color("#ff4fa3"),
]

var mode: Mode = Mode.SINGLE
var players: Array[PlayerSetup] = []
var selected_track: TrackInfo
## Laps per race.
var lap_count: int = 3
## How the screen is divided for two players.
var split_layout: SplitLayout = SplitLayout.VERTICAL
## Menu screen to open when returning from a race ("" = main menu).
var menu_start_screen: StringName = &""
## Context handed to that screen.
var menu_start_context: Dictionary = {}
## Computer opponents in a single player race (0..MAX_PLAYERS - 1).
var ai_opponents: int = 3
## Indices into Catalog.WEATHERS and Catalog.TIME_PRESETS.
var weather: int = 0
var time_of_day: int = Catalog.DEFAULT_TIME_INDEX

## Best lap of this session per track (keyed by TrackInfo.display_name).
var track_records: Dictionary = {}
## Championship points collected this session, per player slot.
var points: Array[int] = []

## Number of players in the race about to start. Derived from the joined slots.
var player_count: int:
	get:
		var count: int = 0
		for setup: PlayerSetup in players:
			if setup.joined:
				count += 1
		return maxi(count, 1)
	set(value):
		for i: int in MAX_PLAYERS:
			players[i].joined = i < value


func _init() -> void:
	for i: int in MAX_PLAYERS:
		var setup: PlayerSetup = PlayerSetup.new()
		setup.stats = Catalog.get_default_car()
		setup.color = PLAYER_COLORS[i]
		setup.joined = i == 0
		players.append(setup)
		points.append(0)
	selected_track = Catalog.get_default_track()


func get_player_color(player_index: int) -> Color:
	return PLAYER_COLORS[clampi(player_index, 0, MAX_PLAYERS - 1)]


## Slot indices of the players taking part, in order.
func get_joined_players() -> Array[int]:
	var joined: Array[int] = []
	for i: int in MAX_PLAYERS:
		if players[i].joined:
			joined.append(i)
	if joined.is_empty():
		joined.append(0)
	return joined


## Player slots that drive in the next race: only P1 in single player.
func get_race_players() -> Array[int]:
	if mode == Mode.SINGLE:
		return [0]
	return get_joined_players()


## The starting grid, front to back: slot index -> setup. In single player the
## opponents are generated here; in multiplayer the lobby slots are used as they are.
func build_grid() -> Dictionary:
	var grid: Dictionary = {}
	if mode == Mode.MULTI:
		for slot: int in get_joined_players():
			grid[slot] = players[slot]
		return grid
	grid[0] = players[0]
	for slot: int in range(1, mini(ai_opponents, MAX_PLAYERS - 1) + 1):
		var setup: PlayerSetup = PlayerSetup.new()
		setup.stats = Catalog.CARS.pick_random()
		setup.color = PLAYER_COLORS[slot]
		setup.joined = true
		setup.is_ai = true
		grid[slot] = setup
	return grid


func get_weather() -> WeatherData:
	return Catalog.WEATHERS[weather]


func get_time_preset() -> EnvPreset:
	return Catalog.TIME_PRESETS[time_of_day]


func get_track_record(track: TrackInfo) -> float:
	return track_records.get(track.display_name, RacerState.NO_TIME)


## Stores a lap time if it beats the session record. Returns true for a new record.
func submit_lap_time(track: TrackInfo, lap_time: float) -> bool:
	var record: float = get_track_record(track)
	if record >= 0.0 and lap_time >= record:
		return false
	track_records[track.display_name] = lap_time
	return true


func start_race() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(RACE_SCENE)


func go_to_menu(screen: StringName = &"") -> void:
	menu_start_screen = screen
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
