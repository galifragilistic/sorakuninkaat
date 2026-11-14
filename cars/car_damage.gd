class_name CarDamage
extends Node
## Damage in four zones (SPEC.md section 3). Front damage hurts steering,
## middle and rear damage cost top speed, tyre damage costs grip.

signal changed

enum Zone { FRONT, MIDDLE, REAR, TIRES }

const ZONE_COUNT: int = 4

## Speed change (m/s) within one physics tick that counts as a crash.
@export var impact_threshold: float = 3.0
## Damage (0..1) per m/s of speed change above the threshold.
@export var damage_per_speed: float = 0.02
## Damage multiplier for durability stat 1 (x) and stat 10 (y).
@export var durability_multiplier_range: Vector2 = Vector2(1.6, 0.6)
## Share of a body hit that also wears the tyres.
@export_range(0.0, 1.0, 0.01) var tire_share: float = 0.25

@export_group("Effects at 100 % zone damage")
@export_range(0.0, 1.0, 0.01) var max_steering_loss: float = 0.35
@export_range(0.0, 1.0, 0.01) var max_top_speed_loss: float = 0.3
@export_range(0.0, 1.0, 0.01) var max_grip_loss: float = 0.2

var _zones: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


## local_impulse is the direction the car was pushed, in the car's local space.
func apply_impact(local_impulse: Vector3, speed_change: float, durability: int) -> void:
	if not Settings.damage_enabled or speed_change < impact_threshold:
		return
	var amount: float = (speed_change - impact_threshold) * damage_per_speed
	amount *= CarStats.stat_to_value(durability, durability_multiplier_range)

	var direction: Vector3 = local_impulse.abs()
	if direction.y > direction.x and direction.y > direction.z:
		# Hard landing.
		_add(Zone.TIRES, amount)
	else:
		var zone: Zone = Zone.MIDDLE
		if direction.z >= direction.x:
			# Forward is -Z: a push towards +Z means the nose hit something.
			zone = Zone.FRONT if local_impulse.z > 0.0 else Zone.REAR
		_add(zone, amount * (1.0 - tire_share))
		_add(Zone.TIRES, amount * tire_share)
	changed.emit()


func repair() -> void:
	_zones.fill(0.0)
	changed.emit()


func get_zone(zone: Zone) -> float:
	return _zones[zone]


## Average of all zones, 0..1.
func get_total() -> float:
	var sum: float = 0.0
	for value: float in _zones:
		sum += value
	return sum / float(ZONE_COUNT)


func get_steering_multiplier() -> float:
	return 1.0 - _zones[Zone.FRONT] * max_steering_loss


func get_top_speed_multiplier() -> float:
	var body: float = maxf(_zones[Zone.MIDDLE], _zones[Zone.REAR])
	return 1.0 - body * max_top_speed_loss


func get_grip_multiplier() -> float:
	return 1.0 - _zones[Zone.TIRES] * max_grip_loss


func _add(zone: Zone, amount: float) -> void:
	_zones[zone] = clampf(_zones[zone] + amount, 0.0, 1.0)
