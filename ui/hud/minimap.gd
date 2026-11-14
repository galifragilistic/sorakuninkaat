class_name Minimap
extends Control
## Track outline with a dot per racer, drawn in the same isometric
## orientation as the game camera.

@export var margin: float = 14.0
@export var sample_spacing: float = 4.0
@export var outline_width: float = 9.0
@export var road_width: float = 5.0
@export var start_marker_length: float = 12.0
@export var start_marker_width: float = 3.0
@export var dot_radius: float = 4.5
@export var own_dot_radius: float = 6.5
@export var own_ring_radius: float = 11.0
@export var dot_outline_width: float = 1.5
## Camera angles used for the projection, in degrees.
@export var view_yaw_degrees: float = 45.0
@export var view_pitch_degrees: float = 35.0

var track: Track
var racers: Array[RacerState] = []
var own_player_index: int = 0

var _points: PackedVector2Array = PackedVector2Array()
var _bounds: Rect2 = Rect2()


func setup(race_track: Track, race_racers: Array[RacerState], player_index: int) -> void:
	track = race_track
	racers = race_racers
	own_player_index = player_index
	_points.clear()
	var length: float = track.get_length()
	var steps: int = ceili(length / sample_spacing)
	for i: int in steps + 1:
		_points.append(_project(track.get_position_at(length * float(i) / float(steps))))
	_bounds = Rect2(_points[0], Vector2.ZERO)
	for point: Vector2 in _points:
		_bounds = _bounds.expand(point)
	queue_redraw()


func _process(_delta: float) -> void:
	if track != null:
		queue_redraw()


func _draw() -> void:
	if track == null or _points.is_empty():
		return
	var line: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in _points:
		line.append(_to_map(point))
	draw_polyline(line, UiStyle.MAP_OUTLINE, outline_width, true)
	draw_polyline(line, UiStyle.MAP_ROAD, road_width, true)

	# Start line: a short accent stroke across the road.
	var across: Vector2 = (line[1] - line[0]).normalized().orthogonal() * start_marker_length * 0.5
	draw_line(line[0] - across, line[0] + across, UiStyle.ACCENT, start_marker_width, true)

	# The own dot is drawn last so it stays on top.
	var own: RacerState = null
	for racer: RacerState in racers:
		if racer.player_index == own_player_index:
			own = racer
		else:
			_draw_dot(racer, dot_radius)
	if own != null:
		var center: Vector2 = _to_map(_project(own.car.global_position))
		var color: Color = GameState.get_player_color(own.player_index)
		draw_arc(center, own_ring_radius, 0.0, TAU, 24, Color(color, 0.6), 1.5, true)
		_draw_dot(own, own_dot_radius)


func _draw_dot(racer: RacerState, radius: float) -> void:
	var center: Vector2 = _to_map(_project(racer.car.global_position))
	draw_circle(center, radius + dot_outline_width, UiStyle.BASE)
	draw_circle(center, radius, GameState.get_player_color(racer.player_index))


## World position to unscaled view-plane coordinates (x right, y down).
func _project(world: Vector3) -> Vector2:
	var yaw: float = deg_to_rad(view_yaw_degrees)
	var right: Vector2 = Vector2(cos(yaw), -sin(yaw))
	var down: Vector2 = Vector2(sin(yaw), cos(yaw))
	var flat: Vector2 = Vector2(world.x, world.z)
	return Vector2(flat.dot(right), flat.dot(down) * sin(deg_to_rad(view_pitch_degrees)))


func _to_map(projected: Vector2) -> Vector2:
	var available: Vector2 = size - Vector2.ONE * margin * 2.0
	var map_scale: float = minf(available.x / _bounds.size.x, available.y / _bounds.size.y)
	var used: Vector2 = _bounds.size * map_scale
	return (projected - _bounds.position) * map_scale + (size - used) * 0.5
