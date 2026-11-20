class_name TrackEditorCanvas
extends Control
## Handles of the track editor, drawn over the live race map. The road itself
## is the 3D track; this control places, moves and draws the edit points.
##
## Mouse: left click on empty ground adds a point after the selected one,
## left click on the road inserts a point there, dragging moves a point,
## right click removes one, the wheel over a point changes its height and
## elsewhere zooms. The middle button pans. In props mode a drag on empty
## ground selects every object inside the box.

signal selection_changed(index: int)
## The selected placed object changed (-1 = none).
signal prop_selection_changed(index: int)
## Something in the design changed (shape, height, points or objects).
signal design_changed
## The picture of the track should be rebuilt (also while a drag is in progress).
signal preview_changed

## ROAD edits the control points, PROPS places objects.
enum Mode { ROAD, PROPS }

@export_group("View")
## Orthographic vertical size of the race camera (metres).
@export var view_size_range: Vector2 = Vector2(12.0, 2000.0)
@export var zoom_step: float = 1.15
@export var fit_margin: float = 28.0
## Curve sampling for hit tests and arrows (metres).
@export var draw_sample_spacing: float = 1.5
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
@export var area_color: Color = Color(1.0, 1.0, 1.0, 0.55)
@export var road_low_color: Color = Color("#3f7bff")
@export var road_color: Color = Color("#c9cfde")
@export var road_high_color: Color = Color("#ff7a1a")
@export var warning_color: Color = Color("#ff5a3d")
@export var warning_radius: float = 12.0
@export var road_edge_width: float = 2.0
@export var jump_color: Color = Color("#ff7a1a")
@export var arrow_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var point_color: Color = Color("#f2f4fa")
@export var selected_color: Color = Color("#3fd8ff")
@export var start_color: Color = Color("#b6f03c")
@export var label_color: Color = Color("#f2f4fa")
@export var label_font_size: int = 13
## Objects smaller than this on screen are still easy to grab (pixels).
@export var min_prop_pick_radius: float = 9.0
## A press shorter than this stays a click; a longer one draws a selection box (pixels).
@export var marquee_slop: float = 6.0

static var _box_faces: PackedInt32Array = PackedInt32Array([
	0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 5, 4, 1, 2, 6, 5, 2, 3, 7, 6, 3, 0, 4, 7,
])

var world: TrackEditorWorld
var mode: Mode = Mode.ROAD:
	set(value):
		mode = value
		_dragging = -1
		_wheel_point = -1
		_wheel_prop = -1
		_dragging_prop = -1
		_marquee = false
		_hovered = -1
		queue_redraw()
## TrackDesign.Prop added by a click in PROPS mode.
var prop_kind: int = TrackDesign.Prop.TREE
## Primary selected object, or -1. The whole selection is selected_props.
var selected_prop: int = -1
var selected_props: Array[int] = []
var _dragging_prop: int = -1
## Prop the rotation wheel stays on after a group turns out from under the cursor.
var _wheel_prop: int = -1
## Grab point of each selected object, in the same order as selected_props (metres).
var _group_grabs: PackedVector2Array = PackedVector2Array()
var _marquee: bool = false
var _marquee_start: Vector2 = Vector2.ZERO
var _marquee_end: Vector2 = Vector2.ZERO
## Set by the height wheel so the editor can wait until scrolling stops.
var _defer_terrain: bool = false

var design: TrackDesign:
	set(value):
		design = value
		selected = clampi(selected, 0, design.points.size() - 1)
		refresh()
var selected: int = 0

var _view_size: float = 80.0
var _focus: Vector2 = Vector2.ZERO
var _dragging: int = -1
## Point the height wheel stays on after the point moves out from under the cursor.
var _wheel_point: int = -1
var _panning: bool = false
var _hovered: int = -1
var _curve: Curve3D
var _length: float = 0.0
var _offsets: PackedFloat32Array = PackedFloat32Array()
## Lap offset ranges drawn as bridges and tunnels.
var _bridge_ranges: Array[Vector2] = []
var _tunnel_ranges: Array[Vector2] = []
var _low_crossings: PackedVector3Array = PackedVector3Array()


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _ready() -> void:
	resized.connect(fit_view)
	if world != null:
		world.view_changed.connect(queue_redraw)


## Re-reads the design after it was changed from outside.
func refresh() -> void:
	if design == null:
		return
	_curve = design.make_curve(draw_sample_spacing)
	_length = _curve.get_baked_length()
	_offsets = design.get_point_offsets(_curve)
	# Marked bridges plus the automatic ones where the road passes over itself.
	_bridge_ranges = design.get_bridge_ranges(_curve, _offsets)
	_low_crossings = design.find_crossings(_curve)["low"]
	_tunnel_ranges.clear()
	for i: int in design.points.size():
		if design.features[i] == TrackDesign.Feature.TUNNEL:
			_tunnel_ranges.append(design.get_structure_range(i, _offsets, _length) + Vector2.ONE * _offsets[i])
	queue_redraw()
	preview_changed.emit()


## Index of the control point whose stretch contains the lap offset.
func get_point_at_offset(offset: float) -> int:
	var index: int = 0
	for i: int in _offsets.size():
		if _offsets[i] <= offset:
			index = i
	return index


## Number of crossings too low to drive under (shown as warnings).
func get_low_crossing_count() -> int:
	return _low_crossings.size()


func is_drawing() -> bool:
	return _dragging >= 0


func is_dragging_prop() -> bool:
	return _dragging_prop >= 0


## Zooms so the whole editable area fits.
func fit_view() -> void:
	if design == null or world == null or size.x <= 1.0 or size.y <= 1.0:
		return
	var half: Vector2 = design.get_half_area()
	var basis: Basis = world.get_camera_basis()
	var max_x: float = 0.0
	var max_y: float = 0.0
	var corners: PackedVector2Array = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	for corner: Vector2 in corners:
		var local: Vector3 = basis.inverse() * Vector3(corner.x, 0.0, corner.y)
		max_x = maxf(max_x, absf(local.x))
		max_y = maxf(max_y, absf(local.y))
	var aspect: float = size.x / size.y
	var needed: float = 2.0 * maxf(max_y, max_x / aspect)
	var usable: float = maxf(size.y - fit_margin * 2.0, 1.0)
	_view_size = clampf(needed * size.y / usable, view_size_range.x, view_size_range.y)
	_focus = Vector2.ZERO
	_apply_view()


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


func to_screen(world_point: Vector3) -> Vector2:
	if world == null:
		return Vector2.ZERO
	return world.project(world_point)


func _to_ground(screen: Vector2, height: float) -> Vector2:
	if world == null:
		return Vector2.ZERO
	return world.ground_at(screen, height)


func _apply_view() -> void:
	if world != null:
		world.set_view(_focus, _view_size)
	queue_redraw()


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
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		_wheel_point = -1
		_wheel_prop = -1
	if mode == Mode.PROPS and event.button_index != MOUSE_BUTTON_MIDDLE:
		_on_prop_mouse_button(event)
		return
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
			var index: int = _wheel_point if _wheel_point >= 0 and _wheel_point < design.points.size() else _pick_point(event.position)
			if index >= 0:
				_wheel_point = index
				var steps: int = direction * (fast_height_multiplier if event.shift_pressed else 1)
				change_height(index, steps)
			else:
				_zoom_at(event.position, zoom_step if direction > 0 else 1.0 / zoom_step)


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	if event.relative != Vector2.ZERO:
		_wheel_point = -1
		_wheel_prop = -1
	if _panning:
		var before: Vector2 = _to_ground(event.position - event.relative, 0.0)
		var after: Vector2 = _to_ground(event.position, 0.0)
		_focus += before - after
		_apply_view()
		return
	if _marquee:
		_marquee_end = event.position
		queue_redraw()
		return
	if _dragging_prop >= 0:
		_move_selected(world.pick_xz(event.position))
		return
	if _dragging >= 0:
		var point: Vector3 = design.points[_dragging]
		var flat: Vector2 = _to_ground(event.position, point.y)
		design.points[_dragging] = design.clamp_point(Vector3(flat.x, point.y, flat.y))
		refresh()
		return
	var hovered: int = _pick_prop(event.position) if mode == Mode.PROPS else _pick_point(event.position)
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
	var offset: float = _road_offset_at(position_on_canvas)
	var index: int = selected + 1
	var height: float = design.points[selected].y
	if offset >= 0.0:
		index = design.points.size()
		for i: int in range(1, _offsets.size()):
			if offset < _offsets[i]:
				index = i
				break
		height = _curve.sample_baked(offset).y
	var flat: Vector2 = _to_ground(position_on_canvas, height)
	design.add_point(index, Vector3(flat.x, height, flat.y))
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


func consume_terrain_defer() -> bool:
	var defer: bool = _defer_terrain
	_defer_terrain = false
	return defer


func change_height(index: int, steps: int) -> void:
	var point: Vector3 = design.points[index]
	point.y += float(steps) * TrackDesign.HEIGHT_STEP
	design.points[index] = design.clamp_point(point)
	_defer_terrain = true
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


## Lap offset under the cursor when it is on the road, otherwise -1.
func _road_offset_at(screen: Vector2) -> float:
	if _curve == null or _length <= 0.0 or world == null:
		return -1.0
	var count: int = maxi(8, ceili(_length / draw_sample_spacing))
	var best_offset: float = -1.0
	var best_distance: float = INF
	for i: int in count:
		var offset: float = _length * float(i) / float(count)
		var at: Vector3 = _curve.sample_baked(offset)
		var ahead: Vector3 = _curve.sample_baked(minf(offset + draw_sample_spacing, _length))
		var forward: Vector3 = ahead - at
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			continue
		forward = forward.normalized()
		var side: Vector3 = Vector3(-forward.z, 0.0, forward.x)
		var center: Vector2 = to_screen(at)
		var limit: float = center.distance_to(to_screen(at + side * design.road_width * 0.5)) + road_pick_margin
		var distance: float = center.distance_to(screen)
		if distance <= limit and distance < best_distance:
			best_distance = distance
			best_offset = offset
	return best_offset


func _zoom_at(position_on_canvas: Vector2, factor: float) -> void:
	var before: Vector2 = _to_ground(position_on_canvas, 0.0)
	_view_size = clampf(_view_size / factor, view_size_range.x, view_size_range.y)
	_apply_view()
	_focus += before - _to_ground(position_on_canvas, 0.0)
	_apply_view()


# --- Placed objects ----------------------------------------------------------

func _on_prop_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if not event.pressed:
				if _marquee:
					_finish_marquee()
				elif _dragging_prop >= 0:
					_dragging_prop = -1
					design_changed.emit()
				return
			var index: int = _pick_prop(event.position)
			if index < 0:
				_marquee = true
				_marquee_start = event.position
				_marquee_end = event.position
				return
			if not selected_props.has(index):
				select_prop(index)
			_begin_group_drag(event.position)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				var index: int = _pick_prop(event.position)
				if index < 0:
					return
				if selected_props.has(index):
					remove_selected()
				else:
					remove_prop(index)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not event.pressed:
				return
			var direction: int = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			var index: int = _wheel_prop if _wheel_prop >= 0 and _wheel_prop < design.props.size() else _pick_prop(event.position)
			if index < 0:
				_zoom_at(event.position, zoom_step if direction > 0 else 1.0 / zoom_step)
			elif selected_props.has(index) and selected_props.size() > 1:
				_wheel_prop = index
				rotate_selected(direction * (fast_height_multiplier if event.shift_pressed else 1))
			else:
				_wheel_prop = index
				rotate_prop(index, direction * (fast_height_multiplier if event.shift_pressed else 1))


func _begin_group_drag(screen: Vector2) -> void:
	_dragging_prop = selected_props[0]
	var cursor: Vector2 = world.pick_xz(screen)
	_group_grabs = PackedVector2Array()
	for index: int in selected_props:
		var prop: Vector4 = design.props[index]
		_group_grabs.append(cursor - Vector2(prop.y, prop.z))


func _move_selected(cursor: Vector2) -> void:
	if _group_grabs.size() != selected_props.size():
		return
	for n: int in selected_props.size():
		var prop: Vector4 = design.props[selected_props[n]]
		var flat: Vector2 = cursor - _group_grabs[n]
		design.props[selected_props[n]] = design.clamp_prop(Vector4(prop.x, flat.x, flat.y, prop.w))
	preview_changed.emit()
	queue_redraw()


func _finish_marquee() -> void:
	var start: Vector2 = _marquee_start
	var end: Vector2 = _marquee_end
	_marquee = false
	if start.distance_to(end) < marquee_slop:
		var world_at: Vector2 = world.pick_xz(start)
		var index: int = design.add_prop(prop_kind as TrackDesign.Prop, world_at.x, world_at.y, 0.0)
		if index < 0:
			queue_redraw()
			return
		select_prop(index)
		design_changed.emit()
		return
	select_props(_props_in_rect(start, end))


func _props_in_rect(a: Vector2, b: Vector2) -> Array[int]:
	var rect: Rect2 = Rect2(a, b - a).abs()
	var found: Array[int] = []
	for i: int in design.props.size():
		var prop: Vector4 = design.props[i]
		if rect.has_point(to_screen(Vector3(prop.y, 0.0, prop.z))):
			found.append(i)
	return found


func select_prop(index: int) -> void:
	if index < 0 or index >= design.props.size():
		select_props([])
	else:
		select_props([index])


func select_props(indices: Array[int]) -> void:
	selected_props.clear()
	selected_props.append_array(indices)
	selected_prop = selected_props[0] if not selected_props.is_empty() else -1
	prop_selection_changed.emit(selected_prop)
	queue_redraw()


func remove_prop(index: int) -> void:
	if index < 0 or index >= design.props.size():
		return
	design.props.remove_at(index)
	_hovered = -1
	select_prop(mini(index, design.props.size() - 1))
	design_changed.emit()


## Deletes every selected object. One selected object keeps the old neighbour selection.
func remove_selected() -> void:
	if selected_props.is_empty():
		return
	if selected_props.size() == 1:
		remove_prop(selected_props[0])
		return
	var indices: Array[int] = []
	indices.assign(selected_props)
	indices.sort()
	indices.reverse()
	for index: int in indices:
		design.props.remove_at(index)
	_hovered = -1
	select_props([])
	design_changed.emit()


## Turns an object by steps of TrackDesign.PROP_ROTATION_STEP.
func rotate_prop(index: int, steps: int) -> void:
	if index < 0 or index >= design.props.size():
		return
	var prop: Vector4 = design.props[index]
	prop.w += float(steps) * TrackDesign.PROP_ROTATION_STEP
	design.props[index] = design.clamp_prop(prop)
	if index != selected_prop or selected_props.size() != 1:
		select_prop(index)
	queue_redraw()
	design_changed.emit()


## Turns the selection around its centre. Each object keeps its own facing.
func rotate_selected(steps: int) -> void:
	if selected_props.is_empty():
		return
	if selected_props.size() == 1:
		rotate_prop(selected_props[0], steps)
		return
	var delta: float = float(steps) * TrackDesign.PROP_ROTATION_STEP
	var center: Vector2 = Vector2.ZERO
	for index: int in selected_props:
		var prop: Vector4 = design.props[index]
		center += Vector2(prop.y, prop.z)
	center /= float(selected_props.size())
	for index: int in selected_props:
		var prop: Vector4 = design.props[index]
		var offset: Vector2 = (Vector2(prop.y, prop.z) - center).rotated(delta)
		prop.y = center.x + offset.x
		prop.z = center.y + offset.y
		design.props[index] = design.clamp_prop(prop)
	queue_redraw()
	design_changed.emit()


## Topmost object under the cursor, or -1.
func _pick_prop(position_on_canvas: Vector2) -> int:
	for i: int in range(design.props.size() - 1, -1, -1):
		if _prop_hit(design.props[i], position_on_canvas):
			return i
	return -1


func _prop_hit(prop: Vector4, screen: Vector2) -> bool:
	var kind: int = roundi(prop.x)
	var prop_size: Vector3 = TrackDesign.PROP_SIZES[kind]
	var base: Vector3 = Vector3(prop.y, _surface_height(Vector2(prop.y, prop.z)), prop.z)
	if kind == TrackDesign.Prop.TREE or kind == TrackDesign.Prop.ROCK or kind == TrackDesign.Prop.TIRES:
		return _hits_column(screen, base, prop_size.x * 0.5, prop_size.y)
	return _hits_box(screen, base, prop_size, prop.w)


func _surface_height(flat: Vector2) -> float:
	var track: Track = world.get_track() if world != null else null
	if track == null:
		return 0.0
	return track.get_ground_height(Vector3(flat.x, 0.0, flat.y))


func _hits_column(screen: Vector2, base: Vector3, radius: float, height: float) -> bool:
	var ground: Vector2 = to_screen(base)
	var top: Vector2 = to_screen(base + Vector3(0.0, height, 0.0))
	var edge: float = maxf(
		to_screen(base + Vector3(radius, 0.0, 0.0)).distance_to(ground),
		to_screen(base + Vector3(0.0, 0.0, radius)).distance_to(ground)
	)
	return _distance_to_segment(screen, ground, top) <= maxf(edge, min_prop_pick_radius)


func _hits_box(screen: Vector2, base: Vector3, prop_size: Vector3, yaw: float) -> bool:
	var screen_pts: PackedVector2Array = _box_screen_points(base, prop_size, yaw)
	var middle: Vector2 = to_screen(base + Vector3(0.0, prop_size.y * 0.5, 0.0))
	if middle.distance_to(screen) <= min_prop_pick_radius:
		return true
	for face: int in _box_faces.size() / 4:
		var i: int = face * 4
		if _point_in_quad(screen, screen_pts[_box_faces[i]], screen_pts[_box_faces[i + 1]], screen_pts[_box_faces[i + 2]], screen_pts[_box_faces[i + 3]]):
			return true
	return false


func _box_corners(base: Vector3, prop_size: Vector3, yaw: float) -> PackedVector3Array:
	var corners: PackedVector3Array = PackedVector3Array()
	var signs: PackedVector2Array = PackedVector2Array([
		Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1),
	])
	for level: int in 2:
		var height: float = prop_size.y if level == 1 else 0.0
		for corner: Vector2 in signs:
			var flat: Vector2 = Vector2(corner.x * prop_size.x, corner.y * prop_size.z).rotated(-yaw) * 0.5
			corners.append(base + Vector3(flat.x, height, flat.y))
	return corners


func _box_screen_points(base: Vector3, prop_size: Vector3, yaw: float) -> PackedVector2Array:
	var screen_pts: PackedVector2Array = PackedVector2Array()
	for corner: Vector3 in _box_corners(base, prop_size, yaw):
		screen_pts.append(to_screen(corner))
	return screen_pts


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var span: Vector2 = b - a
	var length_sq: float = span.length_squared()
	if length_sq < 0.001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(span) / length_sq, 0.0, 1.0)
	return point.distance_to(a + span * t)


func _point_in_quad(point: Vector2, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	return _point_in_triangle(point, a, b, c) or _point_in_triangle(point, a, c, d)


func _point_in_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab: float = _cross(b - a, point - a)
	var bc: float = _cross(c - b, point - b)
	var ca: float = _cross(a - c, point - c)
	return (ab >= 0.0 and bc >= 0.0 and ca >= 0.0) or (ab <= 0.0 and bc <= 0.0 and ca <= 0.0)


func _cross(u: Vector2, v: Vector2) -> float:
	return u.x * v.y - u.y * v.x


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	if design == null or world == null:
		return
	_draw_area()
	if mode != Mode.PROPS:
		_draw_arrows()
		_draw_points()
		_draw_warnings()
	_draw_props()
	_draw_marquee()


func _draw_marquee() -> void:
	if not _marquee:
		return
	var rect: Rect2 = Rect2(_marquee_start, _marquee_end - _marquee_start).abs()
	if rect.size.x < marquee_slop and rect.size.y < marquee_slop:
		return
	draw_rect(rect, Color(selected_color, 0.18), true)
	draw_rect(rect, selected_color, false, road_edge_width)


## Red rings where the road crosses itself too low to drive under.
func _draw_warnings() -> void:
	for crossing: Vector3 in _low_crossings:
		var at: Vector2 = to_screen(crossing)
		draw_arc(at, warning_radius + 1.5, 0.0, TAU, 24, Color(0.0, 0.0, 0.0, 0.7), road_edge_width * 2.0, true)
		draw_arc(at, warning_radius, 0.0, TAU, 24, warning_color, road_edge_width * 1.5, true)


func _draw_props() -> void:
	if mode != Mode.PROPS:
		return
	for i: int in design.props.size():
		var chosen: bool = selected_props.has(i)
		if not chosen and i != _hovered:
			continue
		var prop: Vector4 = design.props[i]
		var kind: int = roundi(prop.x)
		var prop_size: Vector3 = TrackDesign.PROP_SIZES[kind]
		var base: Vector3 = Vector3(prop.y, _surface_height(Vector2(prop.y, prop.z)), prop.z)
		var color: Color = selected_color
		var width: float = road_edge_width * (2.0 if chosen else 1.0)
		if kind == TrackDesign.Prop.TREE or kind == TrackDesign.Prop.ROCK or kind == TrackDesign.Prop.TIRES:
			_draw_column(base, prop_size.x * 0.5, prop_size.y, color, width)
		else:
			_draw_box(base, prop_size, prop.w, color, width)


func _draw_column(base: Vector3, radius: float, height: float, color: Color, width: float) -> void:
	var ring: PackedVector2Array = PackedVector2Array()
	var top_ring: PackedVector2Array = PackedVector2Array()
	for i: int in 12:
		var angle: float = TAU * float(i) / 12.0
		var flat: Vector3 = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		ring.append(to_screen(base + flat))
		top_ring.append(to_screen(base + flat + Vector3(0.0, height, 0.0)))
	ring.append(ring[0])
	top_ring.append(top_ring[0])
	draw_polyline(ring, color, width)
	draw_polyline(top_ring, color, width)
	draw_line(to_screen(base), to_screen(base + Vector3(0.0, height, 0.0)), color, width)


func _draw_box(base: Vector3, prop_size: Vector3, yaw: float, color: Color, width: float) -> void:
	var screen_pts: PackedVector2Array = _box_screen_points(base, prop_size, yaw)
	for level: int in 2:
		var start: int = level * 4
		var loop: PackedVector2Array = PackedVector2Array()
		for k: int in 4:
			loop.append(screen_pts[start + k])
		loop.append(loop[0])
		draw_polyline(loop, color, width)
	for k: int in 4:
		draw_line(screen_pts[k], screen_pts[k + 4], color, width)


func _draw_area() -> void:
	var half: Vector2 = design.get_half_area()
	var corners: PackedVector2Array = PackedVector2Array([
		to_screen(Vector3(-half.x, 0.0, -half.y)), to_screen(Vector3(half.x, 0.0, -half.y)),
		to_screen(Vector3(half.x, 0.0, half.y)), to_screen(Vector3(-half.x, 0.0, half.y)),
	])
	corners.append(corners[0])
	draw_polyline(corners, Color(0.0, 0.0, 0.0, 0.65), road_edge_width + 1.5)
	draw_polyline(corners, area_color, road_edge_width)


func _draw_arrows() -> void:
	var offset: float = arrow_spacing * 0.5
	while offset < _length:
		var at: Vector2 = to_screen(_curve.sample_baked(offset))
		var ahead: Vector2 = to_screen(_curve.sample_baked(minf(offset + draw_sample_spacing, _length)))
		var forward: Vector2 = ahead - at
		if forward.length_squared() < 0.001:
			offset += arrow_spacing
			continue
		forward = forward.normalized()
		var side: Vector2 = Vector2(-forward.y, forward.x)
		var poly: PackedVector2Array = PackedVector2Array([
			at + forward * arrow_size, at - forward * arrow_size + side * arrow_size,
			at - forward * arrow_size - side * arrow_size,
		])
		draw_colored_polygon(poly, arrow_color)
		poly.append(poly[0])
		draw_polyline(poly, Color(0.0, 0.0, 0.0, 0.8), 1.5)
		offset += arrow_spacing


func _draw_points() -> void:
	var font: Font = UiStyle.FONT_SEMIBOLD
	for i: int in design.points.size():
		var point: Vector3 = design.points[i]
		var at: Vector2 = to_screen(point)
		var color: Color = start_color if i == 0 else point_color
		var radius: float = point_radius
		if mode == Mode.PROPS:
			radius *= 0.6
		elif i == selected:
			radius = selected_point_radius
			draw_circle(at, radius + road_edge_width * 2.0, selected_color)
		elif i == _hovered:
			draw_circle(at, radius + road_edge_width, selected_color)
		draw_circle(at, radius + 1.5, Color(0.0, 0.0, 0.0, 0.75))
		draw_circle(at, radius, color)
		draw_circle(at, radius * 0.5, get_height_color(point.y))
		if design.features[i] == TrackDesign.Feature.JUMP:
			draw_colored_polygon(PackedVector2Array([
				at + Vector2(0.0, -radius * 2.2), at + Vector2(radius, -radius * 1.2),
				at + Vector2(-radius, -radius * 1.2),
			]), jump_color)
		var picked: bool = mode == Mode.ROAD and (i == selected or i == _hovered)
		if picked or not is_zero_approx(point.y):
			var text: String = tr("%+.1f m") % point.y
			var text_at: Vector2 = at + Vector2(radius + 4.0, -radius)
			draw_string(
				font, text_at + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				label_font_size, Color(0.0, 0.0, 0.0, 0.85)
			)
			draw_string(
				font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_font_size, label_color
			)
