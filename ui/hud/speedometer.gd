class_name Speedometer
extends Control
## Round speed gauge with the speed, unit and gear (mockups/05_Peli.png).
## Drawn in a 200x200 design space and scaled to the control size.

const DESIGN_SIZE: float = 200.0

@export var accent_color: Color = UiStyle.ACCENT
@export var arc_radius: float = 78.0
@export var arc_width: float = 12.0
@export var arc_start_degrees: float = 135.0
@export var arc_sweep_degrees: float = 270.0
@export var arc_points: int = 48
@export_range(0.0, 1.0, 0.01) var glow_alpha: float = 0.25
@export var glow_extra_width: float = 8.0
## Below this fill ratio the coloured arc is not drawn at all.
@export var min_visible_ratio: float = 0.01

@export_group("Ticks")
@export var tick_count: int = 11
@export var tick_inner_radius: float = 62.0
@export var major_tick_length: float = 8.0
@export var minor_tick_length: float = 4.0
@export_range(0.0, 1.0, 0.01) var tick_alpha: float = 0.8

@export_group("Text")
@export var speed_font_size: int = 46
@export var speed_baseline: float = 108.0
@export var unit_font_size: int = 15
@export var unit_baseline: float = 132.0
@export var gear_box: Rect2 = Rect2(80.0, 150.0, 40.0, 34.0)
@export var gear_font_size: int = 22
@export var gear_baseline: float = 175.0

## Speed in km/h.
var speed: float = 0.0:
	set(value):
		if not is_equal_approx(speed, value):
			speed = value
			queue_redraw()
## Speed at which the arc is full, km/h.
var max_speed: float = 150.0
var gear_text: String = "N":
	set(value):
		if gear_text != value:
			gear_text = value
			queue_redraw()


func _draw() -> void:
	var unit: float = minf(size.x, size.y) / DESIGN_SIZE
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(unit, unit))
	var center: Vector2 = Vector2.ONE * DESIGN_SIZE * 0.5
	var start: float = deg_to_rad(arc_start_degrees)
	var sweep: float = deg_to_rad(arc_sweep_degrees)
	var ratio: float = clampf(speed / max_speed, 0.0, 1.0)

	draw_arc(center, arc_radius, start, start + sweep, arc_points, UiStyle.GAUGE_TRACK, arc_width, true)
	if ratio > min_visible_ratio:
		var end: float = start + sweep * ratio
		draw_arc(
			center, arc_radius, start, end, arc_points,
			Color(accent_color, glow_alpha), arc_width + glow_extra_width, true
		)
		draw_arc(center, arc_radius, start, end, arc_points, accent_color, arc_width, true)

	var tick_color: Color = Color(UiStyle.TEXT, tick_alpha)
	for i: int in tick_count:
		var angle: float = start + sweep * float(i) / float(tick_count - 1)
		var direction: Vector2 = Vector2.from_angle(angle)
		var is_major: bool = i % 2 == 0
		var length: float = major_tick_length if is_major else minor_tick_length
		draw_line(
			center + direction * tick_inner_radius, center + direction * (tick_inner_radius + length),
			tick_color, 3.0 if is_major else 2.0, true
		)

	_draw_centered(UiStyle.FONT_DISPLAY, str(roundi(speed)), speed_baseline, speed_font_size, UiStyle.TEXT)
	_draw_centered(UiStyle.FONT_BOLD, tr("km/h"), unit_baseline, unit_font_size, UiStyle.TEXT_SECONDARY)
	draw_rect(gear_box, accent_color)
	_draw_centered(UiStyle.FONT_DISPLAY, gear_text, gear_baseline, gear_font_size, UiStyle.TEXT_ON_ACCENT)


func _draw_centered(font: Font, text: String, baseline: float, font_size: int, color: Color) -> void:
	draw_string(
		font, Vector2(0.0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, DESIGN_SIZE, font_size, color
	)
