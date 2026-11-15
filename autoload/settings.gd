extends Node
## Global user settings, saved to user://settings.cfg.

signal changed

enum Quality { LOW, MEDIUM, HIGH }

const SAVE_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"
const VOLUME_STEPS: int = 10
const MASTER_BUS: int = 0

var quality: Quality = Quality.HIGH:
	set(value):
		quality = value
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

var _loading: bool = false


func _ready() -> void:
	_load()
	_apply_volume()


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


func _load() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	_loading = true
	quality = clampi(config.get_value(SECTION, "quality", quality), Quality.LOW, Quality.HIGH) as Quality
	damage_enabled = config.get_value(SECTION, "damage_enabled", damage_enabled)
	fullscreen = config.get_value(SECTION, "fullscreen", fullscreen)
	volume = config.get_value(SECTION, "volume", volume)
	_loading = false


func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION, "quality", quality)
	config.set_value(SECTION, "damage_enabled", damage_enabled)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "volume", volume)
	config.save(SAVE_PATH)
