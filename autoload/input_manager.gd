extends Node
## Routes raw device input to per-player PlayerInput objects.
## Player control code reads only InputManager.get_input(player_index).
## Defaults: P1 keyboard (WASD), P2 keyboard (arrows). While join_enabled is
## set (in the lobby), a gamepad that presses A takes over the first free or
## arrow-key player slot.

signal device_changed(player_index: int)
## The kind of device last used changed; button prompts follow it.
signal prompt_style_changed(style: PromptStyle)

## Which button prompts the menus show.
enum PromptStyle { KEYBOARD, GAMEPAD }

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
		# The right Shift only (see _right_shift_held).
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
## A stick has to move this far before prompts switch to the gamepad.
const PROMPT_STICK_THRESHOLD: float = 0.5
## Mouse movement (pixels per event) that switches prompts back to the keyboard.
const PROMPT_MOUSE_THRESHOLD: float = 4.0

## Extra menu and race actions on top of Godot's built-in ui_* actions.
const ACTION_SECONDARY: StringName = &"menu_secondary"
const ACTION_START: StringName = &"menu_start"
const ACTION_PAUSE: StringName = &"pause"
## Y on a gamepad, N on the keyboard: edit your name in the lobby.
const ACTION_TERTIARY: StringName = &"menu_tertiary"
## Lobby tabs (LB / RB on a gamepad, Q / E on the keyboard).
const ACTION_TAB_PREVIOUS: StringName = &"menu_tab_previous"
const ACTION_TAB_NEXT: StringName = &"menu_tab_next"
## Opens the car tuning panel in a race (F1).
const ACTION_DEBUG_TUNING: StringName = &"debug_tuning"
## Opens the audio tuning panel in a race (F2).
const ACTION_DEBUG_AUDIO: StringName = &"debug_audio"
## Matches a button on every connected gamepad.
const ALL_DEVICES: int = -1

## With a single driver there is nobody to tell apart, so player 1 may use
## the keyboard and any connected gamepad at the same time.
var solo_mode: bool = false
## Lets unassigned gamepads claim a player slot with the A button.
var join_enabled: bool = false
## Keyboard and mouse until a gamepad is used.
var prompt_style: PromptStyle = PromptStyle.KEYBOARD

var _devices: Array[Device] = []
var _joy_ids: Array[int] = []
var _inputs: Array[PlayerInput] = []
## The arrow-key player's handbrake is the right Shift only. Polling cannot
## tell the two Shift keys apart, so the right one is followed from events.
var _right_shift_held: bool = false


func _ready() -> void:
	# Run before any car reads its input on the same tick.
	process_physics_priority = -100
	for i: int in GameState.MAX_LOCAL_PLAYERS:
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
	_add_action(ACTION_TERTIARY, [KEY_N], [JOY_BUTTON_Y])
	_add_action(ACTION_START, [], [JOY_BUTTON_START])
	_add_action(ACTION_PAUSE, [KEY_ESCAPE], [JOY_BUTTON_START])
	_add_action(ACTION_TAB_PREVIOUS, [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action(ACTION_TAB_NEXT, [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action(ACTION_DEBUG_TUNING, [KEY_F1], [])
	_add_action(ACTION_DEBUG_AUDIO, [KEY_F2], [])
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
	_update_prompt_style(event)
	var key: InputEventKey = event as InputEventKey
	if key != null and _get_physical_key(key) == KEY_SHIFT and key.location == KEY_LOCATION_RIGHT:
		_right_shift_held = key.pressed
	if not join_enabled:
		return
	var button: InputEventJoypadButton = event as InputEventJoypadButton
	if button != null and button.pressed and button.button_index == JOY_JOIN_BUTTON:
		if _join_joypad(button.device):
			# The press joined the game; it should not also click a menu button.
			get_viewport().set_input_as_handled()


func _update_prompt_style(event: InputEvent) -> void:
	var style: PromptStyle = prompt_style
	if event is InputEventJoypadButton and event.is_pressed():
		style = PromptStyle.GAMEPAD
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > PROMPT_STICK_THRESHOLD:
		style = PromptStyle.GAMEPAD
	elif event is InputEventKey and event.is_pressed():
		style = PromptStyle.KEYBOARD
	elif event is InputEventMouseButton and event.is_pressed():
		style = PromptStyle.KEYBOARD
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > PROMPT_MOUSE_THRESHOLD:
		style = PromptStyle.KEYBOARD
	if style != prompt_style:
		prompt_style = style
		prompt_style_changed.emit(style)


## Gives an unassigned gamepad to the first slot that has no device or uses
## the arrow keys. Returns true if the gamepad got a slot.
func _join_joypad(joy_id: int) -> bool:
	if _joy_ids.has(joy_id):
		return false
	for i: int in range(FIRST_JOYPAD_SLOT, GameState.MAX_LOCAL_PLAYERS):
		if _devices[i] == Device.NONE or _devices[i] == Device.KEYBOARD_ARROWS:
			assign_device(i, Device.JOYPAD, joy_id)
			return true
	return false


## Makes sure a slot has something to drive with, handing it the arrow keys
## if nobody uses them. Returns false if the slot still has no device.
func ensure_device(player_index: int) -> bool:
	if _devices[player_index] != Device.NONE:
		return true
	if _devices.has(Device.KEYBOARD_ARROWS):
		return false
	assign_device(player_index, Device.KEYBOARD_ARROWS)
	return true


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
	for i: int in GameState.MAX_LOCAL_PLAYERS:
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
	input.handbrake = _is_key_held(layout[Action.HANDBRAKE])
	var reset_held: bool = Input.is_physical_key_pressed(layout[Action.RESET])
	input.aim = _key_aim(layout)
	input.aim_from_keys = true
	for joy_id: int in Input.get_connected_joypads():
		input.throttle = maxf(input.throttle, Input.get_joy_axis(joy_id, JOY_AXIS_TRIGGER_RIGHT))
		input.brake = maxf(input.brake, Input.get_joy_axis(joy_id, JOY_AXIS_TRIGGER_LEFT))
		var steer: float = Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X)
		if absf(steer) >= JOY_STEER_DEADZONE and absf(steer) > absf(input.steer):
			input.steer = steer
		input.handbrake = input.handbrake or Input.is_joy_button_pressed(joy_id, JOY_HANDBRAKE_BUTTON)
		reset_held = reset_held or Input.is_joy_button_pressed(joy_id, JOY_RESET_BUTTON)
		var stick: Vector2 = _stick_aim(joy_id)
		if stick != Vector2.ZERO:
			input.aim = stick
			input.aim_from_keys = false
	input.update_reset(reset_held)


func _read_keyboard(input: PlayerInput, layout: Dictionary) -> void:
	input.throttle = _key_strength(layout[Action.THROTTLE])
	input.brake = _key_strength(layout[Action.BRAKE])
	input.steer = _key_strength(layout[Action.RIGHT]) - _key_strength(layout[Action.LEFT])
	input.handbrake = _is_key_held(layout[Action.HANDBRAKE])
	input.update_reset(_is_key_held(layout[Action.RESET]))
	input.aim = _key_aim(layout)
	input.aim_from_keys = true


func _read_joypad(input: PlayerInput, joy_id: int) -> void:
	input.throttle = clampf(Input.get_joy_axis(joy_id, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
	input.brake = clampf(Input.get_joy_axis(joy_id, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0)
	var steer: float = Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X)
	input.steer = 0.0 if absf(steer) < JOY_STEER_DEADZONE else steer
	input.handbrake = Input.is_joy_button_pressed(joy_id, JOY_HANDBRAKE_BUTTON)
	input.update_reset(Input.is_joy_button_pressed(joy_id, JOY_RESET_BUTTON))
	input.aim = _stick_aim(joy_id)
	input.aim_from_keys = false


## Screen direction from the throttle, brake and turn keys (up = throttle key).
func _key_aim(layout: Dictionary) -> Vector2:
	var aim: Vector2 = Vector2(
		_key_strength(layout[Action.RIGHT]) - _key_strength(layout[Action.LEFT]),
		_key_strength(layout[Action.THROTTLE]) - _key_strength(layout[Action.BRAKE])
	)
	return aim.normalized()


## Left stick direction on screen (y up), or zero inside the dead zone.
func _stick_aim(joy_id: int) -> Vector2:
	var stick: Vector2 = Vector2(Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X), -Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_Y))
	return Vector2.ZERO if stick.length() < JOY_STEER_DEADZONE else stick.limit_length(1.0)


func _key_strength(key: Key) -> float:
	return 1.0 if _is_key_held(key) else 0.0


## Shift in a layout means the right Shift (see _right_shift_held).
func _is_key_held(key: Key) -> bool:
	return _right_shift_held if key == KEY_SHIFT else Input.is_physical_key_pressed(key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_right_shift_held = false


## The player slot whose device sent this event: a key of a slot's keyboard
## layout or a button or stick of a slot's gamepad. -1 if no slot uses it.
func get_event_slot(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		for i: int in GameState.MAX_LOCAL_PLAYERS:
			if _devices[i] == Device.JOYPAD and _joy_ids[i] == event.device:
				return i
		return -1
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return -1
	var physical: Key = _get_physical_key(key)
	for i: int in GameState.MAX_LOCAL_PLAYERS:
		if not KEYBOARD_LAYOUTS.has(_devices[i]):
			continue
		var layout: Dictionary = KEYBOARD_LAYOUTS[_devices[i]]
		for action: Action in layout:
			var bound: Key = layout[action]
			if bound != physical:
				continue
			# Shift belongs to the arrow keys only on the right-hand side.
			if bound == KEY_SHIFT and key.location != KEY_LOCATION_RIGHT:
				continue
			return i
	return -1


## The slot's handbrake key or button, which also accepts in the lobby.
func is_slot_accept(event: InputEvent, slot: int) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).button_index == JOY_JOIN_BUTTON
	var key: InputEventKey = event as InputEventKey
	if key == null or not KEYBOARD_LAYOUTS.has(_devices[slot]):
		return false
	return _get_physical_key(key) == KEYBOARD_LAYOUTS[_devices[slot]][Action.HANDBRAKE]


## The slot's reset key (Enter for the arrow keys).
func is_slot_reset_key(event: InputEvent, slot: int) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key == null or not KEYBOARD_LAYOUTS.has(_devices[slot]):
		return false
	return _get_physical_key(key) == KEYBOARD_LAYOUTS[_devices[slot]][Action.RESET]


func _get_physical_key(key: InputEventKey) -> Key:
	return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
