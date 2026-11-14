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
## True only on the tick the reset button went down.
var reset_pressed: bool = false

var _reset_held: bool = false


func update_reset(held: bool) -> void:
	reset_pressed = held and not _reset_held
	_reset_held = held


func clear() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	handbrake = false
	update_reset(false)
