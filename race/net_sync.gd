class_name NetSync
extends Node
## Network side of a race (server architecture, SPEC.md section 4).
## Host: drives remote players' cars with the inputs they send, and sends
## everyone car snapshots, race state and race events.
## Client: sends its own input every tick, shows the cars from the host's
## snapshots slightly in the past (so it can interpolate smoothly) and mirrors
## the host's race state into its own RaceManager.
## The node must have the same path on every machine.

## Host: a remote player left the race; their car needs a new driver.
signal remote_player_left(slot: int)

## Pos (3), rotation (4), velocity (3), throttle, steer.
const FLOATS_PER_CAR: int = 12

## Physics ticks between car snapshots (2 = 30 per second at 60 Hz).
@export var snapshot_interval_ticks: int = 2
## Seconds between race state updates (positions, lap times).
@export var race_state_interval: float = 0.1
## How far in the past clients show the cars (s). Covers network jitter.
@export var interpolation_delay: float = 0.1
## Host: a remote input older than this counts as released (s).
@export var input_timeout: float = 0.5
## Host: start without players who have not loaded the race by then (s).
@export var start_wait_timeout: float = 10.0
## Client: how quickly the clock estimate follows the host (0..1 per snapshot).
@export_range(0.01, 1.0, 0.01) var clock_smoothing: float = 0.1
@export var max_snapshots: int = 30

var _manager: RaceManager
var _cars: Array[Car] = []
var _slots: Array[int] = []
var _is_host: bool = false
## Seconds since this node started, on this machine.
var _clock: float = 0.0

# Host
var _remote_inputs: Dictionary = {}
var _input_age: Dictionary = {}
var _expected_peers: Array[int] = []
var _ready_peers: Array[int] = []
var _started: bool = false
var _tick: int = 0
var _state_timer: float = 0.0

# Client
## [host_time, PackedFloat32Array] pairs, oldest first.
var _snapshots: Array = []
var _clock_offset: float = 0.0
var _has_clock: bool = false
var _puppet_inputs: Array[PlayerInput] = []
## True once anything has arrived from the host's race scene.
var _host_heard: bool = false


## cars and slots are in the same order on every machine (grid order).
func setup(manager: RaceManager, cars: Array[Car], slots: Array[int]) -> void:
	_manager = manager
	_cars = cars
	_slots = slots
	_is_host = Network.is_host()
	Network.race_sync = self
	if _is_host:
		_setup_host()
	else:
		_setup_client()


# --- Host ----------------------------------------------------------------

func _setup_host() -> void:
	for i: int in _slots.size():
		var setup: PlayerSetup = GameState.players[_slots[i]]
		if setup.is_ai or setup.peer_id == Network.HOST_PEER_ID:
			continue
		var input: PlayerInput = PlayerInput.new()
		_remote_inputs[_slots[i]] = input
		_input_age[_slots[i]] = 0.0
		_cars[i].input_source = input
		_expected_peers.append(setup.peer_id)
	for i: int in _cars.size():
		_cars[i].damage.changed.connect(_send_damage.bind(i))
	_manager.state_changed.connect(func(state: RaceManager.State) -> void: _send("_rx_state", [state]))
	_manager.countdown_tick.connect(func(left: int) -> void: _send("_rx_countdown", [left]))
	_manager.lap_completed.connect(_on_lap_completed)
	_manager.split_recorded.connect(func(racer: RacerState, delta: float) -> void:
		_send("_rx_split", [racer.player_index, delta]))
	_manager.racer_finished.connect(func(racer: RacerState) -> void:
		_send("_rx_finished", [racer.player_index, racer.finish_time, racer.did_not_finish]))
	_manager.overtake.connect(func(a: RacerState, b: RacerState) -> void:
		_send("_rx_overtake", [a.player_index, b.player_index]))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Clients faster than this machine have already reported in.
	for peer: int in Network.get_loaded_peers():
		_on_peer_loaded(peer)
	Network.race_loaded.connect(_on_peer_loaded)
	_check_start()


## Starts the countdown once every client has loaded the race.
func _check_start() -> void:
	if _started:
		return
	for peer: int in _expected_peers:
		if not _ready_peers.has(peer) and _clock < start_wait_timeout:
			return
	_started = true
	_manager.start_countdown()


func _physics_process(delta: float) -> void:
	_clock += delta
	if _is_host:
		_host_tick(delta)
	else:
		_client_tick()


func _host_tick(delta: float) -> void:
	_check_start()
	for slot: int in _input_age:
		_input_age[slot] += delta
		if _input_age[slot] > input_timeout:
			(_remote_inputs[slot] as PlayerInput).clear()
	_tick += 1
	if _tick % snapshot_interval_ticks == 0:
		_send("_rx_snapshot", [_clock, _build_snapshot()])
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = race_state_interval
		_send("_rx_race_state", [_manager.race_time, _manager.get_racer_data()])


func _build_snapshot() -> PackedFloat32Array:
	var data: PackedFloat32Array = PackedFloat32Array()
	for car: Car in _cars:
		var origin: Vector3 = car.global_position
		var rotation_quat: Quaternion = car.global_basis.get_rotation_quaternion()
		var velocity: Vector3 = car.get_velocity()
		data.append_array([
			origin.x, origin.y, origin.z, rotation_quat.x, rotation_quat.y, rotation_quat.z, rotation_quat.w,
			velocity.x, velocity.y, velocity.z, car.get_throttle(), car.get_steer(),
		])
	return data


## Sends an RPC to every client that has the race loaded. Reliability comes
## from the receiving method's @rpc annotation.
func _send(method: StringName, args: Array) -> void:
	# A client that just vanished stays listed until ENet notices; skip it.
	var connected: PackedInt32Array = multiplayer.get_peers()
	for peer: int in _ready_peers:
		if connected.has(peer):
			callv("rpc_id", [peer, method] + args)


func _send_damage(index: int) -> void:
	_send("_rx_damage", [index, _cars[index].damage.get_zones()])


func _on_lap_completed(racer: RacerState, lap_time: float, is_best: bool) -> void:
	_send("_rx_lap", [
		racer.player_index, lap_time, is_best, racer.laps_completed, racer.best_lap_time, racer.lap_start_time,
	])


func _on_peer_disconnected(peer_id: int) -> void:
	_drop_peer(peer_id)


func _drop_peer(peer_id: int) -> void:
	_ready_peers.erase(peer_id)
	_expected_peers.erase(peer_id)
	for i: int in _slots.size():
		var setup: PlayerSetup = GameState.players[_slots[i]]
		if _remote_inputs.has(_slots[i]) and setup.peer_id in [peer_id, 0]:
			_remote_inputs.erase(_slots[i])
			_input_age.erase(_slots[i])
			remote_player_left.emit(_slots[i])


## A client has the race loaded (reported through Network, which exists even
## while this machine is still loading). From now on it gets race updates.
func _on_peer_loaded(peer: int) -> void:
	if _ready_peers.has(peer):
		return
	_ready_peers.append(peer)
	# A late joiner still needs the current state and damage.
	callv("rpc_id", [peer, "_rx_state", _manager.state])
	for i: int in _cars.size():
		callv("rpc_id", [peer, "_rx_damage", i, _cars[i].damage.get_zones()])


## Host: a client went back to the lobby; the computer takes over its car.
## Called by Network, which receives the message.
func receive_left(peer: int) -> void:
	var slot: int = Network.get_slot_of_peer(peer)
	if slot >= 0:
		GameState.players[slot].is_ai = true
		GameState.players[slot].peer_id = 0
	_drop_peer(peer)


## Host: one tick of a client's driving input, passed on by Network.
func receive_input(peer: int, throttle: float, brake: float, steer: float, handbrake: bool, reset_held: bool) -> void:
	var slot: int = Network.get_slot_of_peer(peer)
	if not _remote_inputs.has(slot):
		return
	var input: PlayerInput = _remote_inputs[slot]
	input.throttle = clampf(throttle, 0.0, 1.0)
	input.brake = clampf(brake, 0.0, 1.0)
	input.steer = clampf(steer, -1.0, 1.0)
	input.handbrake = handbrake
	input.update_reset(reset_held)
	_input_age[slot] = 0.0


# --- Client --------------------------------------------------------------

func _setup_client() -> void:
	for car: Car in _cars:
		var input: PlayerInput = PlayerInput.new()
		_puppet_inputs.append(input)
		car.make_puppet(input)
	Network.report_race_loaded()


## Client: leave the race while it goes on; the host hands the car to the computer.
func leave_race() -> void:
	if not _is_host and Network.is_online():
		Network.send_left_race()


func _client_tick() -> void:
	# Until the host has spoken, its race scene may not exist yet to receive inputs.
	if not Network.is_online() or not _host_heard:
		return
	Network.send_race_input(InputManager.get_input(0))
	_apply_snapshots()


func _apply_snapshots() -> void:
	if _snapshots.is_empty():
		return
	var render_time: float = _clock + _clock_offset - interpolation_delay
	# Newest snapshot not after render_time, and the one after it.
	var older: Array = _snapshots[0]
	var newer: Array = _snapshots[0]
	for snapshot: Array in _snapshots:
		newer = snapshot
		if snapshot[0] > render_time:
			break
		older = snapshot
	var span: float = newer[0] - older[0]
	var weight: float = clampf((render_time - older[0]) / span, 0.0, 1.0) if span > 0.0 else 1.0
	var a: PackedFloat32Array = older[1]
	var b: PackedFloat32Array = newer[1]
	var car_count: int = mini(_cars.size(), mini(a.size(), b.size()) / FLOATS_PER_CAR)
	for i: int in car_count:
		var base: int = i * FLOATS_PER_CAR
		var origin: Vector3 = _vec3(a, base).lerp(_vec3(b, base), weight)
		var rotation_quat: Quaternion = _quat(a, base + 3).slerp(_quat(b, base + 3), weight)
		var car: Car = _cars[i]
		car.global_transform = Transform3D(Basis(rotation_quat), origin)
		car.puppet_velocity = _vec3(a, base + 7).lerp(_vec3(b, base + 7), weight)
		_puppet_inputs[i].throttle = lerpf(a[base + 10], b[base + 10], weight)
		_puppet_inputs[i].steer = lerpf(a[base + 11], b[base + 11], weight)
	# Snapshots older than the one in use are no longer needed.
	while _snapshots.size() > 2 and _snapshots[1][0] < render_time:
		_snapshots.pop_front()


func _vec3(data: PackedFloat32Array, index: int) -> Vector3:
	return Vector3(data[index], data[index + 1], data[index + 2])


func _quat(data: PackedFloat32Array, index: int) -> Quaternion:
	return Quaternion(data[index], data[index + 1], data[index + 2], data[index + 3]).normalized()


@rpc("authority", "call_remote", "unreliable_ordered")
func _rx_snapshot(host_time: float, data: PackedFloat32Array) -> void:
	_host_heard = true
	var offset: float = host_time - _clock
	_clock_offset = lerpf(_clock_offset, offset, clock_smoothing) if _has_clock else offset
	_has_clock = true
	_snapshots.append([host_time, data])
	if _snapshots.size() > max_snapshots:
		_snapshots.pop_front()


@rpc("authority", "call_remote", "unreliable_ordered")
func _rx_race_state(race_time: float, data: PackedFloat32Array) -> void:
	_manager.apply_remote_racers(race_time, data)


@rpc("authority", "call_remote", "reliable")
func _rx_state(state: int) -> void:
	# The host sends its state first thing after hearing we have loaded.
	_host_heard = true
	_manager.apply_remote_state(state as RaceManager.State)


@rpc("authority", "call_remote", "reliable")
func _rx_countdown(seconds_left: int) -> void:
	_manager.countdown_tick.emit(seconds_left)


@rpc("authority", "call_remote", "reliable")
func _rx_lap(slot: int, lap_time: float, is_best: bool, laps: int, best: float, lap_start: float) -> void:
	var racer: RacerState = _manager.find_racer_by_slot(slot)
	if racer == null:
		return
	racer.laps_completed = laps
	racer.best_lap_time = best
	racer.last_lap_time = lap_time
	racer.lap_start_time = lap_start
	_manager.lap_completed.emit(racer, lap_time, is_best)


@rpc("authority", "call_remote", "reliable")
func _rx_split(slot: int, delta: float) -> void:
	var racer: RacerState = _manager.find_racer_by_slot(slot)
	if racer != null:
		_manager.split_recorded.emit(racer, delta)


@rpc("authority", "call_remote", "reliable")
func _rx_finished(slot: int, finish_time: float, did_not_finish: bool) -> void:
	var racer: RacerState = _manager.find_racer_by_slot(slot)
	if racer == null:
		return
	racer.finished = true
	racer.finish_time = finish_time
	racer.did_not_finish = did_not_finish
	_manager.racer_finished.emit(racer)


@rpc("authority", "call_remote", "reliable")
func _rx_overtake(overtaker_slot: int, overtaken_slot: int) -> void:
	var overtaker: RacerState = _manager.find_racer_by_slot(overtaker_slot)
	var overtaken: RacerState = _manager.find_racer_by_slot(overtaken_slot)
	if overtaker != null and overtaken != null:
		_manager.overtake.emit(overtaker, overtaken)


@rpc("authority", "call_remote", "reliable")
func _rx_damage(index: int, zones: PackedFloat32Array) -> void:
	if index < _cars.size():
		_cars[index].damage.set_zones(zones)
