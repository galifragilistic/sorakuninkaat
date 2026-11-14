class_name ColorSwatch
extends Control
## Round, focusable paint sample (mockups/03_Autovalinta.png).

signal pressed

@export var swatch_size: float = 40.0
@export var ring_gap: float = 3.0
@export var ring_width: float = 2.5

var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2.ONE * (swatch_size + (ring_gap + ring_width) * 2.0)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(grab_focus)


func _gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	var clicked: bool = mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	if clicked or event.is_action_pressed("ui_accept"):
		accept_event()
		pressed.emit()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = swatch_size * 0.5
	draw_circle(center, radius, color)
	draw_arc(center, radius, 0.0, TAU, 40, UiStyle.LINE, 1.5, true)
	# Focus is the accent ring; the chosen colour keeps a white ring.
	if has_focus():
		draw_arc(center, radius + ring_gap + ring_width * 0.5, 0.0, TAU, 40, UiStyle.ACCENT, ring_width + 1.0, true)
	elif selected:
		draw_arc(center, radius + ring_gap + ring_width * 0.5, 0.0, TAU, 40, UiStyle.TEXT, ring_width, true)
