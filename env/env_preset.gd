class_name EnvPreset
extends Resource
## One time-of-day / weather look: environment, sun and which lights are on.

@export var display_name: String = ""
@export var environment: Environment

@export_group("Sun")
@export var sun_color: Color = Color.WHITE
@export var sun_energy: float = 1.0
## Pitch (negative = pointing down) and yaw of the light direction.
@export var sun_rotation_degrees: Vector3 = Vector3(-45.0, 0.0, 0.0)
## Apparent sun size in degrees. Larger = softer shadow edges (PCSS).
@export_range(0.0, 5.0, 0.05) var sun_angular_distance: float = 1.5
@export var sun_shadow_max_distance: float = 140.0

@export_group("Lights")
@export var headlights_on: bool = true
@export var track_lights_on: bool = true

@export_group("Post-process")
@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.45
@export var vignette_color: Color = Color(0.03, 0.04, 0.09)
