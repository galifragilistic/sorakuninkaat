class_name SurfaceData
extends Resource
## Driving surface properties (SPEC.md section 3).

enum Kind { ASPHALT, GRAVEL, SAND, SNOW, ICE, GRASS }

@export var kind: Kind = Kind.GRAVEL
## UI name, passed through tr().
@export var display_name: String = ""
## Grip coefficient: asphalt 1.0, gravel 0.75, sand 0.65, snow 0.5, ice 0.3.
@export_range(0.0, 1.5, 0.01) var grip: float = 1.0
## Speed-proportional rolling drag (1/s). High values slow the car down off-road.
@export_range(0.0, 5.0, 0.01) var rolling_drag: float = 0.03
@export_group("Graybox look")
@export var color_a: Color = Color(0.5, 0.5, 0.5)
@export var color_b: Color = Color(0.45, 0.45, 0.45)
