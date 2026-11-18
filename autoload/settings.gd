extends Node
## Global user settings, saved to user://settings.cfg.

signal changed

enum Quality { LOW, MEDIUM, HIGH }
## RETRO: low-resolution, dithered PS1 / N64 look (see Retro). MODERN: smooth.
enum GraphicsStyle { RETRO, MODERN }

const SAVE_PATH: String = "user://settings.cfg"
## The game was called Sorakuninkaat; its saved data lives in a folder of
## that name next to this game's own user folder.
const OLD_USER_DIR_NAME: String = "Sorakuninkaat"
## Files and folders copied from the old user folder on the first start.
const MIGRATED_ITEMS: Array[String] = ["settings.cfg", "debug_tuning.cfg", "track_editor_draft.json", "tracks"]
const SECTION: String = "settings"
const VOLUME_STEPS: int = 10
## Languages the game speaks, in menu order. The Finnish texts are the
## translation keys, so Finnish needs no translation file.
const LANGUAGES: PackedStringArray = ["fi", "en"]
## Each language's name written in that language.
const LANGUAGE_NAMES: PackedStringArray = ["Suomi", "English"]
const MASTER_BUS: int = 0

var quality: Quality = Quality.HIGH:
	set(value):
		quality = value
		_on_changed()

var graphics_style: GraphicsStyle = GraphicsStyle.RETRO:
	set(value):
		graphics_style = value
		if is_inside_tree():
			Retro.apply_window(get_tree().root)
		_on_changed()

var damage_enabled: bool = true:
	set(value):
		damage_enabled = value
		_on_changed()

var fullscreen: bool = false:
	set(value):
		fullscreen = value
		_apply_window_mode()
		_on_changed()

## Master volume in steps of ten percent (0..10).
var volume: int = 8:
	set(value):
		volume = clampi(value, 0, VOLUME_STEPS)
		_apply_volume()
		_on_changed()

var language: String = "fi":
	set(value):
		language = value if LANGUAGES.has(value) else LANGUAGES[0]
		TranslationServer.set_locale(language)
		_on_changed()

## Names chosen for player slots 1-4 on this machine ("" = default name).
## Slot 1's name is also this machine's name in network games.
var player_names: PackedStringArray = PackedStringArray(["", "", "", ""])
## Steering mode (PlayerSetup.Steering) chosen for player slots 1-4 on this machine.
var steering_modes: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])

var _loading: bool = false


func _ready() -> void:
	_migrate_old_user_data()
	# Finnish unless the player has chosen otherwise, whatever the system language.
	TranslationServer.set_locale(language)
	_load()
	_apply_volume()
	# Deferred: the engine applies the project's stretch settings to the window
	# after the autoloads are ready, which would undo this.
	Retro.apply_window.call_deferred(get_tree().root)
	for i: int in player_names.size():
		GameState.players[i].display_name = player_names[i]
	for i: int in steering_modes.size():
		GameState.players[i].steering = steering_modes[i] as PlayerSetup.Steering


func get_player_name(slot: int) -> String:
	return player_names[slot] if slot < player_names.size() else ""


## Remembers a player's name and shows it in the lobby straight away.
func set_player_name(slot: int, player_name: String) -> void:
	if slot >= player_names.size():
		return
	player_names[slot] = GameState.sanitize_name(player_name)
	GameState.players[slot].display_name = player_names[slot]
	_on_changed()


## Remembers how a player steers and applies it to their slot.
func set_steering(slot: int, mode: PlayerSetup.Steering) -> void:
	if slot >= steering_modes.size():
		return
	steering_modes[slot] = mode
	GameState.players[slot].steering = mode
	_on_changed()


func _on_changed() -> void:
	if _loading:
		return
	_save()
	changed.emit()


func _apply_window_mode() -> void:
	var mode: DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func _apply_volume() -> void:
	AudioServer.set_bus_mute(MASTER_BUS, volume == 0)
	AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(float(maxi(volume, 1)) / float(VOLUME_STEPS)))


## First start under the new name: copies settings, drafts and custom tracks
## from the old game's user folder, if there is one. The old folder is kept.
func _migrate_old_user_data() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		return
	var old_dir: String = OS.get_user_data_dir().get_base_dir().path_join(OLD_USER_DIR_NAME)
	if old_dir == OS.get_user_data_dir() or not DirAccess.dir_exists_absolute(old_dir):
		return
	for item: String in MIGRATED_ITEMS:
		_copy_recursive(old_dir.path_join(item), OS.get_user_data_dir().path_join(item))


func _copy_recursive(from: String, to: String) -> void:
	if FileAccess.file_exists(from):
		DirAccess.copy_absolute(from, to)
		return
	if not DirAccess.dir_exists_absolute(from):
		return
	DirAccess.make_dir_recursive_absolute(to)
	for file: String in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(file), to.path_join(file))
	for folder: String in DirAccess.get_directories_at(from):
		_copy_recursive(from.path_join(folder), to.path_join(folder))


func _load() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	_loading = true
	quality = clampi(config.get_value(SECTION, "quality", quality), Quality.LOW, Quality.HIGH) as Quality
	damage_enabled = config.get_value(SECTION, "damage_enabled", damage_enabled)
	graphics_style = clampi(config.get_value(SECTION, "graphics_style", graphics_style), 0, GraphicsStyle.size() - 1) as GraphicsStyle
	fullscreen = config.get_value(SECTION, "fullscreen", fullscreen)
	volume = config.get_value(SECTION, "volume", volume)
	language = config.get_value(SECTION, "language", language)
	var names: PackedStringArray = config.get_value(SECTION, "player_names", player_names)
	for i: int in mini(names.size(), player_names.size()):
		player_names[i] = GameState.sanitize_name(names[i])
	var modes: PackedInt32Array = config.get_value(SECTION, "steering_modes", steering_modes)
	for i: int in mini(modes.size(), steering_modes.size()):
		steering_modes[i] = clampi(modes[i], 0, PlayerSetup.Steering.size() - 1)
	_loading = false


func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION, "quality", quality)
	config.set_value(SECTION, "damage_enabled", damage_enabled)
	config.set_value(SECTION, "graphics_style", graphics_style)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "volume", volume)
	config.set_value(SECTION, "language", language)
	config.set_value(SECTION, "player_names", player_names)
	config.set_value(SECTION, "steering_modes", steering_modes)
	config.save(SAVE_PATH)
