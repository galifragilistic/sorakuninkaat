class_name EnvironmentController
extends Node
## Applies an EnvPreset to the scene's WorldEnvironment and sun, scaled by the
## quality setting (SPEC.md section 2). Listeners of preset_applied handle
## their own parts (headlights, track lights, per-view vignette).

signal preset_applied(preset: EnvPreset)

@export var preset: EnvPreset
## Optional weather layered on top of the preset.
@export var weather: WeatherData
@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
## Caps the quality setting for this scene, e.g. menu backdrops that do not
## need the heaviest effects.
@export var max_quality: Settings.Quality = Settings.Quality.HIGH


func _ready() -> void:
	Settings.changed.connect(apply)
	apply()


func set_preset(new_preset: EnvPreset, new_weather: WeatherData = null) -> void:
	preset = new_preset
	weather = new_weather
	apply()


func apply() -> void:
	if preset == null:
		return
	# Work on a copy so quality tweaks never leak into the preset resource.
	var environment: Environment = preset.environment.duplicate() as Environment
	var quality: Settings.Quality = mini(Settings.quality, max_quality) as Settings.Quality
	if quality == Settings.Quality.LOW:
		environment.ssao_enabled = false
		environment.volumetric_fog_enabled = false
	if quality != Settings.Quality.HIGH:
		environment.ssil_enabled = false
		environment.sdfgi_enabled = false
	var sun_energy: float = preset.sun_energy
	if weather != null:
		sun_energy *= weather.sun_energy_scale
		environment.ambient_light_energy *= weather.ambient_energy_scale
		environment.adjustment_saturation *= weather.saturation_scale
		environment.volumetric_fog_density += weather.volumetric_fog_density
		if weather.fog_density > 0.0:
			environment.fog_enabled = true
			environment.fog_density = weather.fog_density
			# Haze takes on the brightness of the time of day.
			environment.fog_light_color = weather.fog_color * minf(1.0, environment.ambient_light_energy + sun_energy * 0.5)
	world_environment.environment = environment

	sun.light_color = preset.sun_color
	sun.light_energy = sun_energy
	sun.rotation_degrees = preset.sun_rotation_degrees
	sun.light_angular_distance = preset.sun_angular_distance
	sun.directional_shadow_max_distance = preset.sun_shadow_max_distance
	sun.shadow_enabled = true

	preset_applied.emit(preset)
