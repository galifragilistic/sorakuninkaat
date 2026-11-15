class_name MenuScreen
extends Control
## Base class for the screens shown by MenuRoot. A screen builds its controls
## in _build(), reads its context in _enter() and asks MenuRoot to navigate
## with go_to() / go_back().

signal screen_requested(screen: StringName, context: Dictionary)

enum Backdrop { FULL, DIMMED, HIDDEN }

## Screen names understood by MenuRoot.
const MAIN: StringName = &"main"
const LOBBY: StringName = &"lobby"
const CAR_SELECT: StringName = &"car_select"
const TRACK_SELECT: StringName = &"track_select"
const SETTINGS: StringName = &"settings"

## Values passed by the screen that opened this one.
var context: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


## Called by MenuRoot once the screen is in the tree.
func open(screen_context: Dictionary) -> void:
	context = screen_context
	_enter()
	var target: Control = _get_initial_focus()
	if target != null:
		target.grab_focus.call_deferred()


func go_to(screen: StringName, screen_context: Dictionary = {}) -> void:
	screen_requested.emit(screen, screen_context)


## How much of the 3D backdrop shows behind this screen.
func get_backdrop() -> Backdrop:
	return Backdrop.HIDDEN


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()
	elif event.is_action_pressed("menu_secondary"):
		get_viewport().set_input_as_handled()
		_on_secondary()
	elif event.is_action_pressed("menu_tertiary"):
		get_viewport().set_input_as_handled()
		_on_tertiary()
	elif event.is_action_pressed("menu_start"):
		get_viewport().set_input_as_handled()
		_on_start()


# --- Overridables --------------------------------------------------------

func _build() -> void:
	pass


func _enter() -> void:
	pass


func _get_initial_focus() -> Control:
	return null


func _on_back() -> void:
	go_to(context.get("return_to", MAIN), context.get("return_context", {}))


## X on a gamepad.
func _on_secondary() -> void:
	pass


## Y on a gamepad, N on the keyboard.
func _on_tertiary() -> void:
	pass


## START on a gamepad.
func _on_start() -> void:
	pass
