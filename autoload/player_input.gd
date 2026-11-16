class_name PlayerInput
extends RefCounted
## One player's driving input for the current physics tick.

## 0..1
var throttle: float = 0.0
## 0..1, doubles as reverse when the car is nearly stopped.
var brake: float = 0.0
## -1 (left) .. 1 (right)
var steer: float = 0.0
var handbrake: bool = false
## Direction pushed on screen (x right, y up, length 0..1): the left stick,
## or the direction keys when no stick is pushed. Used by directional steering.
var aim: Vector2 = Vector2.ZERO
## True when aim came from the keys rather than a stick.
var aim_from_keys: bool = false
## True only on the tick the reset button went down.
var reset_pressed: bool = false

var _reset_held: bool = false


func is_reset_held() -> bool:
	return _reset_held


func update_reset(held: bool) -> void:
	reset_pressed = held and not _reset_held
	_reset_held = held


func clear() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	handbrake = false
	aim = Vector2.ZERO
	aim_from_keys = false
	update_reset(false)
