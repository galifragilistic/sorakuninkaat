class_name CarLook
extends Resource
## Shape and details of one car model. CarModel builds the low-poly body from
## these numbers, so each car in the garage gets its own silhouette.
## Lengths are metres in the car's space: forward is -Z, the origin is between the axles.

enum Spoiler { NONE, LIP, WING }

## A model made in Blender (tools/blender/build_cars.py). When set, the car is
## shown with it and the shape numbers below are not used.
@export var model: PackedScene
enum Lamps { RECT, ROUND }

@export_group("Body")
@export var length: float = 3.7
@export var width: float = 1.72
## Height of the body's underside.
@export var clearance: float = 0.36
## Body top at the base of the windscreen.
@export var hood_height: float = 0.86
## Body top at the base of the rear window.
@export var deck_height: float = 0.88
## How much lower the front end of the hood is than its rear end.
@export var hood_slope: float = 0.06
## Length of the tapered nose and how much it drops, lifts and narrows.
@export var nose_length: float = 0.45
@export var nose_drop: float = 0.12
@export var nose_lift: float = 0.08
@export var nose_pinch: float = 0.06
@export var tail_length: float = 0.3
@export var tail_drop: float = 0.06
@export var tail_lift: float = 0.06
@export var tail_pinch: float = 0.04
## Chamfer along the top edges and the sills.
@export var shoulder: float = 0.1
@export var sill: float = 0.06

@export_group("Cabin")
## Z of the windscreen base and of the rear window base.
@export var cabin_start: float = -0.35
@export var cabin_end: float = 1.25
@export var cabin_height: float = 0.52
## Roof is this much narrower than the body on each side.
@export var roof_inset: float = 0.12
## Horizontal run of the windscreen and the rear window (bigger = more raked).
@export var windscreen_run: float = 0.55
@export var rear_window_run: float = 0.35
## Width of the painted frame around each window.
@export var pillar: float = 0.08

@export_group("Details")
@export var spoiler: Spoiler = Spoiler.NONE
@export var lamps: Lamps = Lamps.RECT
## Extra driving lights on the front bumper: 0, 2 or 4.
@export_range(0, 4, 2) var bumper_lights: int = 2
## A light pod with four lamps on the front of the roof.
@export var roof_lights: bool = false
@export var roof_rack: bool = false
@export var bull_bar: bool = false
@export var fender_flares: bool = false
@export var mud_flaps: bool = true
@export var spare_wheel: bool = false
@export var hood_scoop: bool = false
## How far the bumpers stick out from the body.
@export var bumper_depth: float = 0.08

@export_group("Wheels")
@export var wheel_width: float = 0.26
## Rim size as a share of the tyre radius.
@export_range(0.2, 0.9, 0.01) var rim_ratio: float = 0.6
@export var rim_color: Color = Color(0.72, 0.74, 0.78)

@export_group("Colours")
@export var trim_color: Color = Color(0.1, 0.11, 0.15)
@export var glass_color: Color = Color(0.11, 0.13, 0.2)
@export var tire_color: Color = Color(0.09, 0.09, 0.11)
