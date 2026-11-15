class_name UiGlyph
extends Control
## Small vector icons drawn in code: gamepad prompts (a letter in a ring or
## pill), keyboard keys (a keycap), chevrons, a plus and a padlock.

enum Kind { BUTTON, CHEVRON_LEFT, CHEVRON_RIGHT, PLUS, LOCK, KEY }

## Corner radius of a keycap as a share of its height.
const KEY_CORNER: float = 0.22

@export var kind: Kind = Kind.BUTTON:
	set(value):
		kind = value
		_update_size()
## Letter(s) inside a BUTTON glyph, e.g. "A" or "LB RB".
@export var text: String = "":
	set(value):
		text = value
		_update_size()
@export var color: Color = UiStyle.TEXT:
	set(value):
		color = value
		queue_redraw()
@export var glyph_size: float = 30.0:
	set(value):
		glyph_size = value
		_update_size()
@export var line_width: float = 2.0
@export var font_size: int = 13


static func create(glyph_kind: Kind, glyph_text: String = "", size_px: float = 30.0) -> UiGlyph:
	var glyph: UiGlyph = UiGlyph.new()
	glyph.kind = glyph_kind
	glyph.glyph_size = size_px
	glyph.text = glyph_text
	return glyph


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_size()


func _update_size() -> void:
	var width: float = glyph_size
	if kind == Kind.KEY:
		var key_text_width: float = UiStyle.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		width = maxf(glyph_size, key_text_width + glyph_size * 0.6)
	elif kind == Kind.BUTTON and text.length() > 1:
		# Wide pill for prompts like "LB RB" or "START".
		var text_width: float = UiStyle.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		width = text_width + glyph_size * 0.8
	custom_minimum_size = Vector2(width, glyph_size)
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var unit: float = glyph_size
	match kind:
		Kind.BUTTON:
			_draw_button(center, unit)
		Kind.KEY:
			_draw_key()
		Kind.CHEVRON_LEFT, Kind.CHEVRON_RIGHT:
			var direction: float = -1.0 if kind == Kind.CHEVRON_LEFT else 1.0
			var reach: Vector2 = Vector2(unit * 0.16 * direction, unit * 0.26)
			draw_polyline(PackedVector2Array([
				center + Vector2(-reach.x, -reach.y), center + Vector2(reach.x, 0.0),
				center + Vector2(-reach.x, reach.y),
			]), color, line_width * 1.5, true)
		Kind.PLUS:
			var arm: float = unit * 0.2
			draw_arc(center, unit * 0.5 - line_width, 0.0, TAU, 32, color, line_width, true)
			draw_line(center - Vector2(arm, 0.0), center + Vector2(arm, 0.0), color, line_width, true)
			draw_line(center - Vector2(0.0, arm), center + Vector2(0.0, arm), color, line_width, true)
		Kind.LOCK:
			var body: Rect2 = Rect2(center + Vector2(-unit * 0.25, -unit * 0.05), Vector2(unit * 0.5, unit * 0.4))
			draw_rect(body, color, false, line_width)
			draw_arc(body.position + Vector2(body.size.x * 0.5, 0.0), unit * 0.16, PI, TAU, 12, color, line_width, true)


## Keycap: rounded rectangle with a thicker bottom edge.
func _draw_key() -> void:
	var inset: float = line_width * 0.5
	var rect: Rect2 = Rect2(Vector2.ONE * inset, size - Vector2.ONE * line_width)
	var radius: float = rect.size.y * KEY_CORNER
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = color
	box.set_border_width_all(roundi(line_width))
	box.border_width_bottom = roundi(line_width * 2.0)
	box.set_corner_radius_all(roundi(radius))
	box.anti_aliasing = true
	draw_style_box(box, rect)
	var font: Font = UiStyle.FONT_BOLD
	var baseline: float = size.y * 0.5 + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5 - line_width * 0.5
	draw_string(font, Vector2(0.0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


func _draw_button(center: Vector2, unit: float) -> void:
	var radius: float = unit * 0.5 - line_width
	var half_span: float = size.x * 0.5 - unit * 0.5
	if half_span <= 0.5:
		draw_arc(center, radius, 0.0, TAU, 32, color, line_width, true)
	else:
		# Pill: two half circles joined by straight edges.
		var left: Vector2 = center - Vector2(half_span, 0.0)
		var right: Vector2 = center + Vector2(half_span, 0.0)
		draw_arc(left, radius, PI * 0.5, PI * 1.5, 16, color, line_width, true)
		draw_arc(right, radius, -PI * 0.5, PI * 0.5, 16, color, line_width, true)
		draw_line(left - Vector2(0.0, radius), right - Vector2(0.0, radius), color, line_width, true)
		draw_line(left + Vector2(0.0, radius), right + Vector2(0.0, radius), color, line_width, true)
	var font: Font = UiStyle.FONT_BOLD
	var baseline: float = center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(0.0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)
