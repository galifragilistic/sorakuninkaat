class_name Checkpoint
extends Area3D
## Gate across the road. Index 0 is the start/finish line.

signal car_passed(checkpoint: Checkpoint, car: Car)

var index: int = 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var car: Car = body as Car
	if car != null:
		car_passed.emit(self, car)
