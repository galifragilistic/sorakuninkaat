class_name CarStats
extends Resource
## Car attributes on the 1-10 scale shown in the car select screen (SPEC.md section 3).

enum Drivetrain { FWD, RWD, AWD }

const STAT_MIN: int = 1
const STAT_MAX: int = 10

@export var display_name: String = ""
@export var car_class: String = "C"
@export_range(1, 10) var top_speed: int = 5
@export_range(1, 10) var acceleration: int = 5
@export_range(1, 10) var grip_gravel: int = 5
@export_range(1, 10) var grip_asphalt: int = 5
@export_range(1, 10) var durability: int = 5
@export var drivetrain: Drivetrain = Drivetrain.AWD


## Maps a 1-10 stat onto value_range (x = stat 1, y = stat 10).
static func stat_to_value(stat: int, value_range: Vector2) -> float:
	var t: float = float(stat - STAT_MIN) / float(STAT_MAX - STAT_MIN)
	return lerpf(value_range.x, value_range.y, t)


func get_grip_stat(surface_kind: SurfaceData.Kind) -> int:
	return grip_asphalt if surface_kind == SurfaceData.Kind.ASPHALT else grip_gravel


func is_wheel_driven(is_front: bool) -> bool:
	match drivetrain:
		Drivetrain.FWD:
			return is_front
		Drivetrain.RWD:
			return not is_front
	return true


func get_driven_wheel_count() -> int:
	return 4 if drivetrain == Drivetrain.AWD else 2
