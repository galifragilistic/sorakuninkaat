extends Node
## Routes raw device input to per-player PlayerInput objects.
## Player control code reads only InputManager.get_input(player_index).
## Defaults: P1 keyboard (WASD), P2 keyboard (arrows). A gamepad that presses
## A takes over the first free or arrow-key player slot.

signal device_changed(player_index: int)

enum Device { NONE, KEYBOARD_WASD, KEYBOARD_ARROWS, JOYPAD }

enum Action { THROTTLE, BRAKE, LEFT, RIGHT, HANDBRAKE, RESET }

const KEYBOARD_LAYOUTS: Dictionary = {
	Device.KEYBOARD_WASD: {
		Action.THROTTLE: KEY_W,
		Action.BRAKE: KEY_S,
		Action.LEFT: KEY_A,
		Action.RIGHT: KEY_D,
		Action.HANDBRAKE: KEY_SPACE,
		Action.RESET: KEY_R,
	},
	Device.KEYBOARD_ARROWS: {
		Action.THROTTLE: KEY_UP,
		Action.BRAKE: KEY_DOWN,
		Action.LEFT: KEY_LEFT,
		Action.RIGHT: KEY_RIGHT,
		Action.HANDBRAKE: KEY_SHIFT,
		Action.RESET: KEY_ENTER,
	},
}

const JOY_JOIN_BUTTON: JoyButton = JOY_BUTTON_A
## First player slot a gamepad may claim (P1 keeps the keyboard).
const FIRST_JOYPAD_SLOT: int = 1
const JOY_HANDBRAKE_BUTTON: JoyButton = JOY_BUTTON_X
const JOY_RESET_BUTTON: JoyButton = JOY_BUTTON_BACK
const JOY_STEER_DEADZONE: float = 0.15

## Extra menu and race actions on top of Godot's built-in ui_* actions.
const ACTION_SECONDARY: StringName = &"menu_secondary"
const ACTION_START: StringName = &"menu_start"
const ACTION_PAUSE: StringName = &"pause"
## Matches a button on every connected gamepad.
const ALL_DEVICES: int = -1

## With a single driver there is nobody to tell apart, so player 1 may use
## the keyboard and any connected gamepad at the same time.
var solo_mode: bool = false

var _devices: Array[Device] = []
var _joy_ids: Array[int] = []
var _inputs: Array[PlayerInput] = []


func _ready() -> void:
	# Run before any car reads its input on the same tick.
	process_physics_priority = -100
	for i: int in GameState.MAX_PLAYERS:
		_devices.append(Device.NONE)
		_joy_ids.append(-1)
		_inputs.append(PlayerInput.new())
	_register_actions()
	assign_device(0, Device.KEYBOARD_WASD)
	assign_device(1, Device.KEYBOARD_ARROWS)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func assign_device(player_index: int, device: Device, joy_id: int = -1) -> void:
	_devices[player_index] = device
	_joy_ids[player_index] = joy_id
	_inputs[player_index].clear()
	device_changed.emit(player_index)


func get_device(player_index: int) -> Device:
	return _devices[player_index]


func get_joy_id(player_index: int) -> int:
	return _joy_ids[player_index]


## Human-readable device name for menus.
func get_device_name(player_index: int) -> String:
	match _devices[player_index]:
		Device.KEYBOARD_WASD:
			return tr("Näppäimistö (WASD)")
		Device.KEYBOARD_ARROWS:
			return tr("Näppäimistö (nuolet)")
		Device.JOYPAD:
			return tr("Ohjain %d") % (_joy_ids[player_index] + 1)
	return tr("Ei laitetta")


func _register_actions() -> void:
	_add_action(ACTION_SECONDARY, [KEY_X], [JOY_BUTTON_X])
	_add_action(ACTION_START, [], [JOY_BUTTON_START])
	_add_action(ACTION_PAUSE, [KEY_ESCAPE], [JOY_BUTTON_START])
	# Godot 4 binds ui_accept and ui_cancel to the keyboard only.
	_add_action(&"ui_accept", [], [JOY_BUTTON_A])
	_add_action(&"ui_cancel", [], [JOY_BUTTON_B])
	# P1 drives with WASD, so let the same keys move the menu cursor.
	var wasd: Dictionary = {&"ui_up": KEY_W, &"ui_down": KEY_S, &"ui_left": KEY_A, &"ui_right": KEY_D}
	for action: StringName in wasd:
		var key: Key = wasd[action]
		InputMap.action_add_event(action, _make_key_event(key))


func _add_action(action: StringName, keys: Array[Key], buttons: Array[JoyButton]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: Key in keys:
		InputMap.action_add_event(action, _make_key_event(key))
	for button: JoyButton in buttons:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = ALL_DEVICES
		event.button_index = button
		InputMap.action_add_event(action, event)


func _make_key_event(key: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	return event


func get_input(player_index: int) -> PlayerInput:
	return _inputs[player_index]


func _input(event: InputEvent) -> void:
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button != null and button.pressed and button.button_index == JOY_JOIN_BUTTON:
		_join_joypad(button.device)


## Gives an unassigned gamepad to the first slot that has no device or uses the arrow keys.
func _join_joypad(joy_id: int) -> void:
	if _joy_ids.has(joy_id):
		return
	for i: int in range(FIRST_JOYPAD_SLOT, GameState.MAX_PLAYERS):
		if _devices[i] == Device.NONE or _devices[i] == Device.KEYBOARD_ARROWS:
			assign_device(i, Device.JOYPAD, joy_id)
			return


## A player whose gamepad is unplugged falls back to the arrow keys if they are free.
func _on_joy_connection_changed(joy_id: int, connected: bool) -> void:
	if connected:
		return
	var slot: int = _joy_ids.find(joy_id)
	if slot < 0:
		return
	var arrows_free: bool = not _devices.has(Device.KEYBOARD_ARROWS)
	assign_device(slot, Device.KEYBOARD_ARROWS if arrows_free else Device.NONE)


func _physics_process(_delta: float) -> void:
	for i: int in GameState.MAX_PLAYERS:
		if solo_mode and i == 0:
			_read_solo(_inputs[i])
			continue
		match _devices[i]:
			Device.KEYBOARD_WASD, Device.KEYBOARD_ARROWS:
				_read_keyboard(_inputs[i], KEYBOARD_LAYOUTS[_devices[i]])
			Device.JOYPAD:
				_read_joypad(_inputs[i], _joy_ids[i])


## Player 1's keyboard combined with every connected gamepad.
func _read_solo(input: PlayerInput) -> void:
	var layout: Dictionary = KEYBOARD_LAYOUTS[Device.KEYBOARD_WASD]
	input.throttle = _key_strength(layout[Action.THROTTLE])
	input.brake = _key_strength(layout[Action.BRAKE])
	input.steer = _key_strength(layout[Action.RIGHT]) - _key_strength(layout[Action.LEFT])
	input.handbrake = Input.is_physical_key_pressed(layout[Action.HANDBRAKE])
	var reset_held: bool = Input.is_physical_key_pressed(layout[Action.RESET])
	for joy_id: int in Input.get_connected_joypads():
		input.throttle = maxf(input.throttle, Input.get_joy_axis(joy_id, JOY_AXIS_TRIGGER_RIGHT))
		input.brake = maxf(input.brake, Input.get_joy_axis(joy_id, JOY_AXIS_TRIGGER_LEFT))
		var steer: float = Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X)
		if absf(steer) >= JOY_STEER_DEADZONE and absf(steer) > absf(input.steer):
			input.steer = steer
		input.handbrake = input.handbrake or Input.is_joy_button_pressed(joy_id, JOY_HANDBRAKE_BUTTON)
		reset_held = reset_held or Input.is_joy_button_pressed(joy_id, JOY_RESET_BUTTON)
	input.update_reset(reset_held)


func _read_keyboard(input: PlayerInput, layout: Dictionary) -> void:
	input.throttle = _key_strength(layout[Action.THROTTLE])
	input.brake = _key_strength(layout[Action.BRAKE])
	input.steer = _key_strength(layout[Action.RIGHT]) - _key_strength(layout[Action.LEFT])
	input.handbrake = Input.is_physical_key_pressed(layout[Action.HANDBRAKE])
	input.update_reset(Input.is_physical_key_pressed(layout[Action.RESET]))


func _read_joypad(input: PlayerInput, joy_id: int) -> void:
	input.throttle = clampf(Input.get_joy_axis(joy_id, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
	input.brake = clampf(Input.get_joy_axis(joy_id, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0)
	var steer: float = Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X)
	input.steer = 0.0 if absf(steer) < JOY_STEER_DEADZONE else steer
	input.handbrake = Input.is_joy_button_pressed(joy_id, JOY_HANDBRAKE_BUTTON)
	input.update_reset(Input.is_joy_button_pressed(joy_id, JOY_RESET_BUTTON))


func _key_strength(key: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(key) else 0.0
