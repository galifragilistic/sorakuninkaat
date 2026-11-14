class_name PlayerTag
extends Control
## "P2" marker floating above another player's car.

@export var chip_size: Vector2 = Vector2(50.0, 30.0)
@export var chamfer: float = 5.0
@export var pointer_size: Vector2 = Vector2(12.0, 7.0)
@export var font_size: int = 20
## Height above the car's origin that the pointer aims at (m).
@export var world_height: float = 2.4

var racer: RacerState


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = chip_size + Vector2(0.0, pointer_size.y)


## Places the tag so its pointer touches the car's projected position.
func update_position(camera: Camera3D) -> void:
	var anchor: Vector3 = racer.car.get_global_transform_interpolated().origin + Vector3.UP * world_height
	visible = not camera.is_position_behind(anchor)
	position = camera.unproject_position(anchor) - Vector2(chip_size.x * 0.5, size.y)


func _draw() -> void:
	if racer == null:
		return
	var color: Color = GameState.get_player_color(racer.player_index)
	var w: float = chip_size.x
	var h: float = chip_size.y
	draw_colored_polygon(PackedVector2Array([
		Vector2(chamfer, 0.0), Vector2(w, 0.0), Vector2(w, h - chamfer),
		Vector2(w - chamfer, h), Vector2(0.0, h), Vector2(0.0, chamfer),
	]), color)
	var middle: float = w * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(middle - pointer_size.x * 0.5, h), Vector2(middle + pointer_size.x * 0.5, h),
		Vector2(middle, h + pointer_size.y),
	]), color)
	var font: Font = UiStyle.FONT_DISPLAY
	var baseline: float = (h + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(
		font, Vector2(0.0, baseline), "P%d" % (racer.player_index + 1),
		HORIZONTAL_ALIGNMENT_CENTER, w, font_size, UiStyle.TEXT_ON_ACCENT
	)
