class_name EnvironmentController
extends Node
## Applies an EnvPreset to the scene's WorldEnvironment and sun, scaled by the
## quality setting (SPEC.md section 2). Listeners of preset_applied handle
## their own parts (headlights, track lights, per-view vignette).

signal preset_applied(preset: EnvPreset)

@export var preset: EnvPreset
@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D


func _ready() -> void:
	Settings.changed.connect(apply)
	apply()


func set_preset(new_preset: EnvPreset) -> void:
	preset = new_preset
	apply()


func apply() -> void:
	if preset == null:
		return
	# Work on a copy so quality tweaks never leak into the preset resource.
	var environment: Environment = preset.environment.duplicate() as Environment
	var quality: Settings.Quality = Settings.quality
	if quality == Settings.Quality.LOW:
		environment.ssao_enabled = false
		environment.volumetric_fog_enabled = false
	if quality != Settings.Quality.HIGH:
		environment.ssil_enabled = false
		environment.sdfgi_enabled = false
	world_environment.environment = environment

	sun.light_color = preset.sun_color
	sun.light_energy = preset.sun_energy
	sun.rotation_degrees = preset.sun_rotation_degrees
	sun.light_angular_distance = preset.sun_angular_distance
	sun.directional_shadow_max_distance = preset.sun_shadow_max_distance
	sun.shadow_enabled = true

	preset_applied.emit(preset)
