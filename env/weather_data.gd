class_name WeatherData
extends Resource
## Weather layered on top of a time-of-day EnvPreset: light, haze, falling
## particles and how slippery the road gets.

enum Precipitation { NONE, RAIN, SNOW }

@export var display_name: String = ""
## Multiplies tyre grip on every surface (1.0 = dry).
@export_range(0.3, 1.0, 0.01) var grip_multiplier: float = 1.0

@export_group("Light")
@export_range(0.0, 1.5, 0.01) var sun_energy_scale: float = 1.0
@export_range(0.0, 1.5, 0.01) var ambient_energy_scale: float = 1.0
@export_range(0.0, 1.5, 0.01) var saturation_scale: float = 1.0

@export_group("Haze")
## Added to the preset's volumetric fog density.
@export var volumetric_fog_density: float = 0.0
## Plain distance fog density (works on every quality level). 0 = off.
@export var fog_density: float = 0.0
@export var fog_color: Color = Color(0.7, 0.75, 0.8)

@export_group("Precipitation")
@export var precipitation: Precipitation = Precipitation.NONE
@export_range(0.0, 1.0, 0.01) var precipitation_amount: float = 1.0
