class_name TrackProfile
extends Control
## Side view of the road height over one lap, under the editor's map.
## Bridges and tunnels are shaded; clicking near a point selects it.

signal point_picked(index: int)

@export var margin: Vector2 = Vector2(12.0, 10.0)
@export var sample_count: int = 160
@export var line_width: float = 2.5
@export var point_radius: float = 4.5
@export var background_color: Color = Color("#0a0d18")
@export var zero_line_color: Color = Color(0.3, 0.35, 0.52)
@export var bridge_color: Color = Color(1.0, 0.71, 0.24, 0.22)
@export var tunnel_color: Color = Color(0.35, 0.27, 0.2, 0.55)
@export var label_font_size: int = 13

var canvas: TrackEditorCanvas


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	var best: int = -1
	var best_distance: float = INF
	for i: int in canvas.design.points.size():
		var distance: float = absf(_x_at(canvas.get_point_offset(i)) - button.position.x)
		if distance < best_distance:
			best = i
			best_distance = distance
	if best >= 0:
		point_picked.emit(best)


func _x_at(offset: float) -> float:
	var length: float = maxf(canvas.get_length(), 1.0)
	return margin.x + (size.x - margin.x * 2.0) * offset / length


func _y_at(height: float) -> float:
	var span: Vector2 = TrackDesign.HEIGHT_RANGE
	var t: float = (height - span.x) / (span.y - span.x)
	return size.y - margin.y - (size.y - margin.y * 2.0) * t


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	if canvas == null or canvas.design == null or canvas.get_length() <= 0.0:
		return
	var length: float = canvas.get_length()
	var curve: Curve3D = canvas.design.make_curve(length / float(sample_count))
	var step: float = length / float(sample_count)
	# Shade each run of bridge or tunnel samples as one block.
	var run_start: int = 0
	var run_shade: Color = Color.TRANSPARENT
	for i: int in sample_count + 1:
		var shade: Color = Color.TRANSPARENT
		if i < sample_count:
			var offset: float = (float(i) + 0.5) * step
			if canvas.is_in_structure(offset, true):
				shade = bridge_color
			elif canvas.is_in_structure(offset, false):
				shade = tunnel_color
		if shade != run_shade:
			if run_shade.a > 0.0:
				var left: float = _x_at(float(run_start) * step)
				draw_rect(Rect2(left, 0.0, _x_at(float(i) * step) - left, size.y), run_shade)
			run_start = i
			run_shade = shade
	draw_line(Vector2(margin.x, _y_at(0.0)), Vector2(size.x - margin.x, _y_at(0.0)), zero_line_color)

	var line: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	for i: int in sample_count + 1:
		var height: float = curve.sample_baked(minf(float(i) * step, length)).y
		line.append(Vector2(_x_at(float(i) * step), _y_at(height)))
		colors.append(canvas.get_height_color(height))
	draw_polyline_colors(line, colors, line_width, true)

	for i: int in canvas.design.points.size():
		var at: Vector2 = Vector2(_x_at(canvas.get_point_offset(i)), _y_at(canvas.design.points[i].y))
		var color: Color = canvas.selected_color if i == canvas.selected else canvas.point_color
		draw_circle(at, point_radius * (1.5 if i == canvas.selected else 1.0), color)
	var font: Font = UiStyle.FONT_MEDIUM
	draw_string(
		font, Vector2(margin.x, margin.y + label_font_size), tr("KORKEUSPROFIILI"),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_font_size, UiStyle.TEXT_SECONDARY
	)
