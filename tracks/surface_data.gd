class_name SurfaceData
extends Resource
## Driving surface properties (SPEC.md section 3).

enum Kind { ASPHALT, GRAVEL, SAND, SNOW, ICE, GRASS, WATER }

@export var kind: Kind = Kind.GRAVEL
## UI name, passed through tr().
@export var display_name: String = ""
## Grip coefficient: asphalt 1.0, gravel 0.75, sand 0.65, snow 0.5, ice 0.3.
@export_range(0.0, 1.5, 0.01) var grip: float = 1.0
## Speed-proportional rolling drag (1/s). High values slow the car down off-road.
@export_range(0.0, 5.0, 0.01) var rolling_drag: float = 0.03

@export_group("Look")
## Patches are tinted somewhere between color_a and color_b.
@export var color_a: Color = Color(0.5, 0.5, 0.5)
@export var color_b: Color = Color(0.45, 0.45, 0.45)
## Colour of the road shoulder strips.
@export var edge_color: Color = Color(0.3, 0.3, 0.3)
## Small greyscale texture laid over the colours (tracks/textures/*_detail.png).
@export var detail_texture: Texture2D
## Texture repeats per metre, and how strongly it lightens and darkens (0..1).
@export var detail_scale: float = 0.25
@export_range(0.0, 1.0, 0.01) var detail_strength: float = 0.3
@export_range(0.0, 1.0, 0.01) var roughness: float = 1.0
## How dark the tyre ruts are on a road of this surface (0 = none).
@export_range(0.0, 1.0, 0.01) var rut_strength: float = 0.0

@export_group("Dust")
## How much dust the wheels kick up (0 = none).
@export_range(0.0, 1.0, 0.01) var dust_amount: float = 0.0
@export var dust_color: Color = Color(0.8, 0.7, 0.55, 0.5)
