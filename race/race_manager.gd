class_name RaceManager
extends Node
## Race rules: countdown, checkpoints in order, laps, lap and split times,
## running order and the finish (SPEC.md section 8, phase 3).

signal state_changed(state: State)
## seconds_left counts 3, 2, 1 and then 0 when the race starts.
signal countdown_tick(seconds_left: int)
## delta is seconds against the racer's best lap at the same point (negative = faster).
signal split_recorded(racer: RacerState, delta: float)
signal lap_completed(racer: RacerState, lap_time: float, is_best: bool)
signal racer_finished(racer: RacerState)

enum State { WAITING, COUNTDOWN, RACING, FINISHED }

@export var countdown_seconds: int = 3
## Gaps are distance divided by the leader's speed; this floor keeps them sane at low speed.
@export var gap_min_speed: float = 10.0

var track: Track
var lap_count: int = 3
var state: State = State.WAITING
## Seconds since the start signal.
var race_time: float = 0.0
var racers: Array[RacerState] = []

var _countdown_left: float = 0.0
var _standings: Array[RacerState] = []


func setup(race_track: Track, laps: int) -> void:
	track = race_track
	lap_count = laps
	for checkpoint: Checkpoint in track.checkpoints:
		checkpoint.car_passed.connect(_on_checkpoint_passed)


func add_racer(car: Car, player_index: int, display_name: String) -> RacerState:
	var racer: RacerState = RacerState.new()
	racer.car = car
	racer.player_index = player_index
	racer.display_name = display_name
	racer.position = racers.size() + 1
	racers.append(racer)
	_standings.append(racer)
	car.controls_enabled = false
	return racer


func start_countdown() -> void:
	_countdown_left = float(countdown_seconds)
	_set_state(State.COUNTDOWN)
	countdown_tick.emit(countdown_seconds)


## Racers in running order, leader first.
func get_standings() -> Array[RacerState]:
	return _standings


## Time on the racer's current lap, or the total race time once finished.
func get_display_time(racer: RacerState) -> float:
	if racer.finished:
		return racer.finish_time
	if state != State.RACING:
		return 0.0
	return race_time - racer.lap_start_time


## Lap number to show (1-based, capped at the race length).
func get_display_lap(racer: RacerState) -> int:
	return mini(racer.laps_completed + 1, lap_count)


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			var before: int = ceili(_countdown_left)
			_countdown_left -= delta
			var after: int = maxi(0, ceili(_countdown_left))
			if after != before:
				countdown_tick.emit(after)
			if _countdown_left <= 0.0:
				_start_race()
		State.RACING:
			race_time += delta
			_update_standings()


func _start_race() -> void:
	race_time = 0.0
	for racer: RacerState in racers:
		racer.lap_start_time = 0.0
		racer.car.controls_enabled = true
	_set_state(State.RACING)


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)


func _find_racer(car: Car) -> RacerState:
	for racer: RacerState in racers:
		if racer.car == car:
			return racer
	return null


func _on_checkpoint_passed(checkpoint: Checkpoint, car: Car) -> void:
	if state != State.RACING:
		return
	var racer: RacerState = _find_racer(car)
	if racer == null or racer.finished or checkpoint.index != racer.next_checkpoint:
		return
	racer.next_checkpoint = (checkpoint.index + 1) % track.checkpoints.size()

	if checkpoint.index == 0:
		if racer.crossed_start:
			_complete_lap(racer)
		else:
			racer.crossed_start = true
		return

	var elapsed: float = race_time - racer.lap_start_time
	racer.current_splits.append(elapsed)
	var split_index: int = racer.current_splits.size() - 1
	if split_index < racer.best_splits.size():
		split_recorded.emit(racer, elapsed - racer.best_splits[split_index])


func _complete_lap(racer: RacerState) -> void:
	var lap_time: float = race_time - racer.lap_start_time
	var had_best: bool = racer.has_best_lap()
	var delta_to_best: float = lap_time - racer.best_lap_time
	var is_best: bool = not had_best or lap_time < racer.best_lap_time
	if is_best:
		racer.best_lap_time = lap_time
		racer.best_splits = racer.current_splits.duplicate()
	racer.current_splits = []
	racer.last_lap_time = lap_time
	racer.lap_start_time = race_time
	racer.laps_completed += 1
	lap_completed.emit(racer, lap_time, is_best)
	if had_best:
		split_recorded.emit(racer, delta_to_best)
	if racer.laps_completed >= lap_count:
		_finish_racer(racer)


func _finish_racer(racer: RacerState) -> void:
	racer.finished = true
	racer.finish_time = race_time
	racer.car.controls_enabled = false
	_update_standings()
	racer_finished.emit(racer)
	for other: RacerState in racers:
		if not other.finished:
			return
	_set_state(State.FINISHED)


func _update_standings() -> void:
	var length: float = track.get_length()
	for racer: RacerState in racers:
		if racer.finished:
			continue
		var offset: float = track.get_offset_at(racer.car.global_position)
		# The closest-offset wraps at the start line; use the checkpoint state to unwrap it.
		var just_started_lap: bool = racer.next_checkpoint == 1 or not racer.crossed_start
		if just_started_lap and offset > length * 0.5:
			offset -= length
		elif racer.next_checkpoint == 0 and racer.crossed_start and offset < length * 0.5:
			offset += length
		racer.progress = float(racer.laps_completed) * length + offset

	_standings.sort_custom(_is_ahead)
	var leader: RacerState = _standings[0]
	var leader_speed: float = maxf(leader.car.linear_velocity.length(), gap_min_speed)
	for i: int in _standings.size():
		var racer: RacerState = _standings[i]
		racer.position = i + 1
		if racer.finished and leader.finished:
			racer.gap_to_leader = racer.finish_time - leader.finish_time
		elif not racer.finished:
			racer.gap_to_leader = maxf(0.0, leader.progress - racer.progress) / leader_speed


func _is_ahead(a: RacerState, b: RacerState) -> bool:
	if a.finished != b.finished:
		return a.finished
	if a.finished:
		return a.finish_time < b.finish_time
	return a.progress > b.progress
