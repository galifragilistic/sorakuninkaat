class_name TrackOutline
extends Control
## Static track outline for menus, drawn in the game camera's isometric
## orientation. Reads the control points straight from the track scene.

@export var margin: float = 16.0
@export var sample_spacing: float = 4.0
@export var outline_width: float = 9.0
@export var road_width: float = 5.0
@export var road_color: Color = UiStyle.MAP_ROAD
@export var background_color: Color = UiStyle.MAP_OUTLINE
@export var view_yaw_degrees: float = 45.0
@export var view_pitch_degrees: float = 35.0
## Shown instead of an outline for tracks that are not built yet.
@export var placeholder_text: String = ""

var track: TrackInfo:
	set(value):
		track = value
		_rebuild()

var _points: PackedVector2Array = PackedVector2Array()
var _bounds: Rect2 = Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _rebuild() -> void:
	_points.clear()
	if track != null and track.is_available():
		# Only the exported layout is needed, so the scene never enters the tree.
		var instance: Track = track.instantiate_track()
		var curve: Curve3D = Track.make_curve(instance.control_points, instance.tangent_scale, sample_spacing * 0.25)
		instance.free()
		var length: float = curve.get_baked_length()
		var steps: int = ceili(length / sample_spacing)
		for i: int in steps + 1:
			_points.append(Minimap.project(
				curve.sample_baked(length * float(i) / float(steps), true), view_yaw_degrees, view_pitch_degrees
			))
		_bounds = Rect2(_points[0], Vector2.ZERO)
		for point: Vector2 in _points:
			_bounds = _bounds.expand(point)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	if _points.is_empty():
		var font: Font = UiStyle.caps_font()
		var font_size: int = UiStyle.MIN_FONT_SIZE
		var baseline: float = (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		draw_string(
			font, Vector2(0.0, baseline), placeholder_text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, font_size, UiStyle.TEXT_DISABLED
		)
		return
	var available: Vector2 = size - Vector2.ONE * margin * 2.0
	var map_scale: float = minf(available.x / _bounds.size.x, available.y / _bounds.size.y)
	var offset: Vector2 = (size - _bounds.size * map_scale) * 0.5
	var line: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in _points:
		line.append((point - _bounds.position) * map_scale + offset)
	draw_polyline(line, road_color, road_width, true)
