class_name SettingsPanel
extends VBoxContainer
## The settings rows, shared by the settings screen and the pause menu.
## Changes are applied and saved immediately through the Settings autoload.

var _first: OptionSpinner


func _init() -> void:
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var on_off: PackedStringArray = PackedStringArray([tr("Pois"), tr("Päällä")])
	var qualities: PackedStringArray = PackedStringArray([tr("Matala"), tr("Keski"), tr("Korkea")])

	_first = OptionSpinner.create(tr("Grafiikan laatu"), qualities, Settings.quality)
	_first.value_changed.connect(func(index: int) -> void: Settings.quality = index as Settings.Quality)
	add_child(_first)

	var fullscreen: OptionSpinner = OptionSpinner.create(tr("Koko ruutu"), on_off, int(Settings.fullscreen))
	fullscreen.value_changed.connect(func(index: int) -> void: Settings.fullscreen = index == 1)
	add_child(fullscreen)

	var volumes: PackedStringArray = PackedStringArray()
	for step: int in Settings.VOLUME_STEPS + 1:
		volumes.append(tr("%d %%") % (step * 10))
	var volume: OptionSpinner = OptionSpinner.create(tr("Äänenvoimakkuus"), volumes, Settings.volume)
	volume.value_changed.connect(func(index: int) -> void: Settings.volume = index)
	add_child(volume)

	var damage: OptionSpinner = OptionSpinner.create(tr("Vauriot"), on_off, int(Settings.damage_enabled))
	damage.value_changed.connect(func(index: int) -> void: Settings.damage_enabled = index == 1)
	add_child(damage)


func get_first_control() -> Control:
	return _first
