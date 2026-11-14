class_name StatBar
extends Control
## Ten-segment bar for a 1-10 car stat (mockups/03_Autovalinta.png).

@export var segment_count: int = 10
@export var segment_gap: float = 3.0
@export var chamfer: float = 3.0
@export var fill_color: Color = UiStyle.ACCENT
@export var empty_color: Color = UiStyle.GAUGE_TRACK

var value: int = 0:
	set(new_value):
		value = new_value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 12.0)


func _draw() -> void:
	var width: float = (size.x - segment_gap * float(segment_count - 1)) / float(segment_count)
	for i: int in segment_count:
		var x: float = float(i) * (width + segment_gap)
		# Small cut corners echo the panel shape.
		draw_colored_polygon(PackedVector2Array([
			Vector2(x + chamfer, 0.0), Vector2(x + width, 0.0), Vector2(x + width, size.y - chamfer),
			Vector2(x + width - chamfer, size.y), Vector2(x, size.y), Vector2(x, chamfer),
		]), fill_color if i < value else empty_color)
