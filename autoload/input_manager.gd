extends Node
## Routes raw device input to per-player PlayerInput objects.
## Player control code reads only InputManager.get_input(player_index).

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

const JOY_HANDBRAKE_BUTTON: JoyButton = JOY_BUTTON_X
const JOY_RESET_BUTTON: JoyButton = JOY_BUTTON_BACK
const JOY_STEER_DEADZONE: float = 0.15

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
	assign_device(0, Device.KEYBOARD_WASD)


func assign_device(player_index: int, device: Device, joy_id: int = -1) -> void:
	_devices[player_index] = device
	_joy_ids[player_index] = joy_id
	_inputs[player_index].clear()


func get_device(player_index: int) -> Device:
	return _devices[player_index]


func get_input(player_index: int) -> PlayerInput:
	return _inputs[player_index]


func _physics_process(_delta: float) -> void:
	for i: int in GameState.MAX_PLAYERS:
		match _devices[i]:
			Device.KEYBOARD_WASD, Device.KEYBOARD_ARROWS:
				_read_keyboard(_inputs[i], KEYBOARD_LAYOUTS[_devices[i]])
			Device.JOYPAD:
				_read_joypad(_inputs[i], _joy_ids[i])


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
