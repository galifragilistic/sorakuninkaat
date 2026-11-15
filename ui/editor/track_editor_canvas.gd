class_name TrackEditorCanvas
extends Control
## Top-down drawing area of the track editor. The road is drawn from the same
## spline the game uses, coloured by height; higher parts are drawn over lower
## ones so bridges show which road goes on top.
##
## Mouse: left click on empty ground adds a point after the selected one,
## left click on the road inserts a point there, dragging moves a point,
## right click removes one, the wheel over a point changes its height and
## elsewhere zooms. The middle button pans.

signal selection_changed(index: int)
## Something in the design changed (shape, height or point count).
signal design_changed

@export_group("View")
@export var zoom_range: Vector2 = Vector2(1.2, 12.0)
@export var zoom_step: float = 1.15
@export var fit_margin: float = 20.0
@export var grid_spacing: float = 10.0
@export var major_grid_every: int = 5
## Curve sampling for drawing (metres).
@export var draw_sample_spacing: float = 1.5
## Road parts within this height band are drawn together; higher bands on top.
@export var draw_layer_height: float = 2.0
@export var arrow_spacing: float = 30.0
@export var arrow_size: float = 7.0

@export_group("Picking")
@export var point_radius: float = 7.0
@export var selected_point_radius: float = 10.0
@export var pick_radius: float = 13.0
## Clicks this close to the road edge (pixels) count as on the road.
@export var road_pick_margin: float = 4.0
## Wheel steps with Shift held change the height this many times faster.
@export var fast_height_multiplier: int = 4

@export_group("Colours")
@export var background_color: Color = Color("#0a0d18")
@export var grid_color: Color = Color(0.18, 0.21, 0.32, 0.35)
@export var major_grid_color: Color = Color(0.25, 0.29, 0.43, 0.6)
@export var area_color: Color = Color(0.3, 0.35, 0.52)
@export var road_low_color: Color = Color("#3f7bff")
@export var road_color: Color = Color("#c9cfde")
@export var road_high_color: Color = Color("#ff7a1a")
@export var road_edge_color: Color = Color("#0e1220")
@export var bridge_edge_color: Color = Color("#ffe14d")
@export var tunnel_color: Color = Color("#5a4632")
@export var jump_color: Color = Color("#ff7a1a")
@export var arrow_color: Color = Color(0.06, 0.07, 0.12, 0.7)
@export var point_color: Color = Color("#f2f4fa")
@export var selected_color: Color = Color("#3fd8ff")
@export var start_color: Color = Color("#b6f03c")
@export var label_color: Color = Color("#f2f4fa")
@export var road_edge_width: float = 2.0
@export var label_font_size: int = 13

var design: TrackDesign:
	set(value):
		design = value
		selected = clampi(selected, 0, design.points.size() - 1)
		refresh()
var selected: int = 0

var _zoom: float = 3.0
var _view_center: Vector2 = Vector2.ZERO
var _dragging: int = -1
var _panning: bool = false
var _hovered: int = -1
var _curve: Curve3D
var _length: float = 0.0
var _offsets: PackedFloat32Array = PackedFloat32Array()
## Lap offset ranges drawn as bridges and tunnels.
var _bridge_ranges: Array[Vector2] = []
var _tunnel_ranges: Array[Vector2] = []


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _ready() -> void:
	resized.connect(fit_view)


## Re-reads the design after it was changed from outside.
func refresh() -> void:
	if design == null:
		return
	_curve = design.make_curve(draw_sample_spacing)
	_length = _curve.get_baked_length()
	_offsets = design.get_point_offsets(_curve)
	_bridge_ranges.clear()
	_tunnel_ranges.clear()
	for i: int in design.points.size():
		var kind: int = design.features[i]
		if kind != TrackDesign.Feature.BRIDGE and kind != TrackDesign.Feature.TUNNEL:
			continue
		var span: Vector2 = design.get_structure_range(i, _offsets, _length) + Vector2.ONE * _offsets[i]
		if kind == TrackDesign.Feature.BRIDGE:
			_bridge_ranges.append(span)
		else:
			_tunnel_ranges.append(span)
	queue_redraw()


## Zooms so the whole editable area fits.
func fit_view() -> void:
	var area: Vector2 = TrackDesign.HALF_AREA * 2.0
	var available: Vector2 = size - Vector2.ONE * fit_margin * 2.0
	if available.x <= 0.0 or available.y <= 0.0:
		return
	_zoom = clampf(minf(available.x / area.x, available.y / area.y), zoom_range.x, zoom_range.y)
	_view_center = Vector2.ZERO
	queue_redraw()


func select(index: int) -> void:
	selected = clampi(index, 0, design.points.size() - 1)
	selection_changed.emit(selected)
	queue_redraw()


func get_point_offset(index: int) -> float:
	return _offsets[index] if index < _offsets.size() else 0.0


func get_length() -> float:
	return _length


func is_in_structure(offset: float, bridges: bool) -> bool:
	for span: Vector2 in (_bridge_ranges if bridges else _tunnel_ranges):
		if offset >= span.x and offset <= span.y:
			return true
	return false


## Colour of the road at a height.
func get_height_color(height: float) -> Color:
	if height >= 0.0:
		return road_color.lerp(road_high_color, height / TrackDesign.HEIGHT_RANGE.y)
	return road_color.lerp(road_low_color, height / TrackDesign.HEIGHT_RANGE.x)


func to_screen(world: Vector3) -> Vector2:
	return (Vector2(world.x, world.z) - _view_center) * _zoom + size * 0.5


func to_world(screen: Vector2) -> Vector2:
	return (screen - size * 0.5) / _zoom + _view_center


# --- Input -----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		_on_mouse_button(button)
		accept_event()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_on_mouse_motion(motion)
		accept_event()


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_press(event.position)
			elif _dragging >= 0:
				_dragging = -1
				design_changed.emit()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				var index: int = _pick_point(event.position)
				if index >= 0:
					remove_point(index)
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not event.pressed:
				return
			var direction: int = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			var index: int = _pick_point(event.position)
			if index >= 0:
				var steps: int = direction * (fast_height_multiplier if event.shift_pressed else 1)
				change_height(index, steps)
			else:
				_zoom_at(event.position, zoom_step if direction > 0 else 1.0 / zoom_step)


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		_view_center -= event.relative / _zoom
		queue_redraw()
		return
	if _dragging >= 0:
		var world: Vector2 = to_world(event.position)
		var point: Vector3 = design.points[_dragging]
		design.points[_dragging] = design.clamp_point(Vector3(world.x, point.y, world.y))
		refresh()
		return
	var hovered: int = _pick_point(event.position)
	if hovered != _hovered:
		_hovered = hovered
		queue_redraw()


func _on_left_press(position_on_canvas: Vector2) -> void:
	var index: int = _pick_point(position_on_canvas)
	if index < 0:
		index = _add_point_at(position_on_canvas)
		if index < 0:
			return
	select(index)
	_dragging = index


## Inserts a point where the road is clicked, or after the selected point when
## the click is on empty ground. Returns its index, or -1 if the track is full.
func _add_point_at(position_on_canvas: Vector2) -> int:
	if design.points.size() >= TrackDesign.MAX_POINTS:
		return -1
	var world: Vector2 = to_world(position_on_canvas)
	var flat: Vector3 = Vector3(world.x, 0.0, world.y)
	var offset: float = _curve.get_closest_offset(flat)
	var on_road: Vector3 = _curve.sample_baked(offset)
	var road_distance: float = Vector2(on_road.x - flat.x, on_road.z - flat.z).length() * _zoom
	var index: int = selected + 1
	var height: float = design.points[selected].y
	if road_distance <= design.road_width * 0.5 * _zoom + road_pick_margin:
		index = design.points.size()
		for i: int in range(1, _offsets.size()):
			if offset < _offsets[i]:
				index = i
				break
		height = on_road.y
	design.add_point(index, Vector3(world.x, height, world.y))
	refresh()
	design_changed.emit()
	return index


func remove_point(index: int) -> void:
	if design.points.size() <= TrackDesign.MIN_POINTS:
		return
	design.remove_point(index)
	design.features[0] = TrackDesign.Feature.NONE
	_hovered = -1
	refresh()
	select(mini(index, design.points.size() - 1) if index > 0 else 0)
	design_changed.emit()


func change_height(index: int, steps: int) -> void:
	var point: Vector3 = design.points[index]
	point.y += float(steps) * TrackDesign.HEIGHT_STEP
	design.points[index] = design.clamp_point(point)
	refresh()
	if index != selected:
		select(index)
	design_changed.emit()


func _pick_point(position_on_canvas: Vector2) -> int:
	var best: int = -1
	var best_distance: float = pick_radius
	for i: int in design.points.size():
		var distance: float = to_screen(design.points[i]).distance_to(position_on_canvas)
		if distance <= best_distance:
			best = i
			best_distance = distance
	return best


func _zoom_at(position_on_canvas: Vector2, factor: float) -> void:
	var before: Vector2 = to_world(position_on_canvas)
	_zoom = clampf(_zoom * factor, zoom_range.x, zoom_range.y)
	_view_center += before - to_world(position_on_canvas)
	queue_redraw()


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	if design == null:
		return
	_draw_grid()
	_draw_road()
	_draw_start_line()
	_draw_arrows()
	_draw_points()


func _draw_grid() -> void:
	var top_left: Vector2 = to_world(Vector2.ZERO)
	var bottom_right: Vector2 = to_world(size)
	var first: Vector2i = Vector2i((top_left / grid_spacing).floor())
	var last: Vector2i = Vector2i((bottom_right / grid_spacing).ceil())
	for x: int in range(first.x, last.x + 1):
		var screen_x: float = to_screen(Vector3(float(x) * grid_spacing, 0.0, 0.0)).x
		var color: Color = major_grid_color if x % major_grid_every == 0 else grid_color
		draw_line(Vector2(screen_x, 0.0), Vector2(screen_x, size.y), color)
	for z: int in range(first.y, last.y + 1):
		var screen_y: float = to_screen(Vector3(0.0, 0.0, float(z) * grid_spacing)).y
		var color: Color = major_grid_color if z % major_grid_every == 0 else grid_color
		draw_line(Vector2(0.0, screen_y), Vector2(size.x, screen_y), color)
	var half: Vector2 = TrackDesign.HALF_AREA
	var corner: Vector2 = to_screen(Vector3(-half.x, 0.0, -half.y))
	draw_rect(Rect2(corner, half * 2.0 * _zoom), area_color, false, road_edge_width)


## Road segments grouped into height layers, lowest first. Each layer draws
## all its edges and then all its fills, so the upper road of a crossing covers
## the lower one without the road looking striped.
func _draw_road() -> void:
	var count: int = maxi(2, ceili(_length / draw_sample_spacing))
	var layers: Dictionary = {}
	for i: int in count:
		var from_offset: float = _length * float(i) / float(count)
		var to_offset: float = _length * float(i + 1) / float(count)
		var a: Vector3 = _curve.sample_baked(from_offset)
		var b: Vector3 = _curve.sample_baked(to_offset)
		var layer: int = floori(maxf(a.y, b.y) / draw_layer_height)
		if not layers.has(layer):
			layers[layer] = []
		(layers[layer] as Array).append([a, b, (from_offset + to_offset) * 0.5])
	var order: Array = layers.keys()
	order.sort()
	var width: float = design.road_width * _zoom
	for layer: int in order:
		var segments: Array = layers[layer]
		for segment: Array in segments:
			var edge: Color = bridge_edge_color if is_in_structure(segment[2], true) else road_edge_color
			_draw_thick(segment[0], segment[1], width + road_edge_width * 2.0, edge)
		for segment: Array in segments:
			var a: Vector3 = segment[0]
			var b: Vector3 = segment[1]
			var fill: Color = get_height_color((a.y + b.y) * 0.5)
			if is_in_structure(segment[2], false):
				fill = tunnel_color
			_draw_thick(a, b, width, fill)


func _draw_thick(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var a_screen: Vector2 = to_screen(a)
	var b_screen: Vector2 = to_screen(b)
	draw_line(a_screen, b_screen, color, width)
	draw_circle(b_screen, width * 0.5, color)


func _draw_start_line() -> void:
	var start: Vector3 = _curve.sample_baked(0.0)
	var ahead: Vector3 = _curve.sample_baked(minf(draw_sample_spacing, _length))
	var forward: Vector2 = (to_screen(ahead) - to_screen(start)).normalized()
	var side: Vector2 = Vector2(-forward.y, forward.x) * design.road_width * 0.5 * _zoom
	var center: Vector2 = to_screen(start)
	draw_line(center - side, center + side, start_color, road_edge_width * 2.0)


func _draw_arrows() -> void:
	var offset: float = arrow_spacing * 0.5
	while offset < _length:
		var at: Vector2 = to_screen(_curve.sample_baked(offset))
		var ahead: Vector2 = to_screen(_curve.sample_baked(minf(offset + draw_sample_spacing, _length)))
		var forward: Vector2 = (ahead - at).normalized()
		var side: Vector2 = Vector2(-forward.y, forward.x)
		draw_colored_polygon(PackedVector2Array([
			at + forward * arrow_size, at - forward * arrow_size + side * arrow_size,
			at - forward * arrow_size - side * arrow_size,
		]), arrow_color)
		offset += arrow_spacing


func _draw_points() -> void:
	var font: Font = UiStyle.FONT_SEMIBOLD
	for i: int in design.points.size():
		var point: Vector3 = design.points[i]
		var at: Vector2 = to_screen(point)
		var color: Color = start_color if i == 0 else point_color
		var radius: float = point_radius
		if i == selected:
			radius = selected_point_radius
			draw_circle(at, radius + road_edge_width * 2.0, selected_color)
		elif i == _hovered:
			draw_circle(at, radius + road_edge_width, selected_color)
		draw_circle(at, radius, color)
		draw_circle(at, radius * 0.5, get_height_color(point.y))
		if design.features[i] == TrackDesign.Feature.JUMP:
			draw_colored_polygon(PackedVector2Array([
				at + Vector2(0.0, -radius * 2.2), at + Vector2(radius, -radius * 1.2),
				at + Vector2(-radius, -radius * 1.2),
			]), jump_color)
		if i == selected or i == _hovered or not is_zero_approx(point.y):
			var text: String = tr("%+.1f m") % point.y
			draw_string(
				font, at + Vector2(radius + 4.0, -radius), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				label_font_size, label_color
			)
