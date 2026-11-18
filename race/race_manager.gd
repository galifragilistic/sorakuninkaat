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
signal overtake(overtaker: RacerState, overtaken: RacerState)

enum State { WAITING, COUNTDOWN, RACING, FINISHED }

@export var countdown_seconds: int = 3
## No overtake messages during the start scramble (s).
@export var overtake_grace_time: float = 3.0
## Minimum time between overtake messages (s).
@export var overtake_cooldown: float = 1.0
## A pass only counts once the passing car is this far ahead (m).
@export var overtake_margin: float = 1.0
## Once the winner is in, the others have this long to finish (s).
@export var finish_timeout: float = 30.0
## A car this far past its next checkpoint without going through the gate
## is told to turn back (m).
@export var missed_checkpoint_margin: float = 6.0

## Values per racer in get_racer_data() / apply_remote_racers().
const FLOATS_PER_RACER: int = 15

var track: Track
var lap_count: int = 3
var state: State = State.WAITING
## Seconds since the start signal.
var race_time: float = 0.0
var racers: Array[RacerState] = []
## False on network clients: the host runs the rules and sends the results.
var is_authority: bool = true

var _countdown_left: float = 0.0
var _last_overtake_time: float = 0.0
var _first_finish_time: float = RacerState.NO_TIME
var _standings: Array[RacerState] = []
## Race time when the first car made each checkpoint passage (passage number -> time).
var _passage_times: Dictionary = {}


func setup(race_track: Track, laps: int, authority: bool = true) -> void:
	track = race_track
	lap_count = laps
	is_authority = authority
	if is_authority:
		for checkpoint: Checkpoint in track.checkpoints:
			checkpoint.car_passed.connect(_on_checkpoint_passed)


func add_racer(car: Car, player_index: int, display_name: String, setup: PlayerSetup) -> RacerState:
	var racer: RacerState = RacerState.new()
	racer.car = car
	racer.player_index = player_index
	racer.display_name = display_name
	racer.setup = setup
	racer.is_ai = setup.is_ai
	racer.track_offset = track.get_offset_at(car.global_position)
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


## Whole laps a racer is behind the leader, counted in checkpoint passages,
## so it too only changes when someone passes a checkpoint.
func get_laps_down(racer: RacerState) -> int:
	if _standings.is_empty() or racer.finished:
		return 0
	var behind: int = _standings[0].checkpoints_passed - racer.checkpoints_passed
	@warning_ignore("integer_division")
	return maxi(0, behind / maxi(track.checkpoint_count, 1))


func find_racer_by_slot(slot: int) -> RacerState:
	for racer: RacerState in racers:
		if racer.player_index == slot:
			return racer
	return null


## Host: everything a client needs to show positions and times, racers in add order.
func get_racer_data() -> PackedFloat32Array:
	var data: PackedFloat32Array = PackedFloat32Array()
	for racer: RacerState in racers:
		data.append_array([
			racer.laps_completed, racer.next_checkpoint, float(racer.crossed_start), racer.lap_start_time,
			racer.last_lap_time, racer.best_lap_time, racer.progress, racer.position, racer.gap_to_leader,
			float(racer.finished), racer.finish_time, float(racer.did_not_finish), racer.track_offset,
			racer.checkpoints_passed, float(racer.missed_checkpoint),
		])
	return data


## Client: takes over the host's race clock and racer fields.
func apply_remote_racers(remote_time: float, data: PackedFloat32Array) -> void:
	race_time = remote_time
	for i: int in mini(racers.size(), data.size() / FLOATS_PER_RACER):
		var racer: RacerState = racers[i]
		var base: int = i * FLOATS_PER_RACER
		racer.laps_completed = int(data[base])
		racer.next_checkpoint = int(data[base + 1])
		racer.crossed_start = data[base + 2] > 0.5
		racer.lap_start_time = data[base + 3]
		racer.last_lap_time = data[base + 4]
		racer.best_lap_time = data[base + 5]
		racer.progress = data[base + 6]
		racer.position = int(data[base + 7])
		racer.gap_to_leader = data[base + 8]
		racer.finished = racer.finished or data[base + 9] > 0.5
		racer.finish_time = data[base + 10]
		racer.did_not_finish = data[base + 11] > 0.5
		racer.track_offset = data[base + 12]
		racer.checkpoints_passed = int(data[base + 13])
		racer.missed_checkpoint = data[base + 14] > 0.5
	_standings.sort_custom(func(a: RacerState, b: RacerState) -> bool: return a.position < b.position)


## Client: follows the host's race state.
func apply_remote_state(new_state: State) -> void:
	if new_state == State.RACING and state != State.RACING:
		race_time = 0.0
	if new_state != state:
		_set_state(new_state)


func _physics_process(delta: float) -> void:
	if not is_authority:
		# Between updates from the host the clock keeps running locally.
		if state == State.RACING:
			race_time += delta
		return
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
			if _first_finish_time >= 0.0 and race_time - _first_finish_time >= finish_timeout:
				_end_race_for_stragglers()


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
	_record_passage(racer)

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


## Gap to the leader, as at a timing point: the time since the first car
## passed this same checkpoint on the same lap. It then stays as it is until
## the racer's next checkpoint.
func _record_passage(racer: RacerState) -> void:
	racer.checkpoints_passed += 1
	var passage: int = racer.checkpoints_passed
	if _passage_times.has(passage):
		racer.gap_to_leader = race_time - _passage_times[passage]
	else:
		_passage_times[passage] = race_time
		racer.gap_to_leader = 0.0


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


## Classifies everyone still driving by distance covered and ends the race.
func _end_race_for_stragglers() -> void:
	_update_standings()
	for racer: RacerState in _standings.duplicate():
		if not racer.finished:
			racer.did_not_finish = true
			_finish_racer(racer)


func _finish_racer(racer: RacerState) -> void:
	racer.finished = true
	racer.missed_checkpoint = false
	racer.finish_time = race_time
	racer.car.controls_enabled = false
	if _first_finish_time < 0.0:
		_first_finish_time = race_time
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
		var offset: float = track.get_offset_near(racer.car.global_position, racer.track_offset)
		racer.track_offset = offset
		# The closest-offset wraps at the start line; use the checkpoint state to unwrap it.
		var just_started_lap: bool = racer.next_checkpoint == 1 or not racer.crossed_start
		if just_started_lap and offset > length * 0.5:
			offset -= length
		elif racer.next_checkpoint == 0 and racer.crossed_start and offset < length * 0.5:
			offset += length
		racer.progress = float(racer.laps_completed) * length + offset
		racer.missed_checkpoint = state == State.RACING and racer.progress > _get_checkpoint_progress(racer) + missed_checkpoint_margin

	var previous: Array[RacerState] = _standings.duplicate()
	_standings.sort_custom(_is_ahead)
	_report_overtakes(previous)
	var leader: RacerState = _standings[0]
	for i: int in _standings.size():
		var racer: RacerState = _standings[i]
		racer.position = i + 1
		# Gaps of racers still driving change only at checkpoints (_record_passage).
		if racer.finished and leader.finished and not racer.did_not_finish:
			racer.gap_to_leader = racer.finish_time - leader.finish_time


## Distance along the race (as in RacerState.progress) of the racer's next checkpoint.
func _get_checkpoint_progress(racer: RacerState) -> float:
	var length: float = track.get_length()
	var checkpoint_progress: float = float(racer.laps_completed) * length + track.get_checkpoint_offset(racer.next_checkpoint)
	if racer.next_checkpoint == 0 and racer.crossed_start:
		checkpoint_progress += length
	return checkpoint_progress


func _report_overtakes(previous: Array[RacerState]) -> void:
	if race_time < overtake_grace_time or race_time - _last_overtake_time < overtake_cooldown:
		return
	for i: int in _standings.size():
		var racer: RacerState = _standings[i]
		var overtaken: RacerState = previous[i]
		if previous.find(racer) <= i or racer.finished or overtaken.finished:
			continue
		if racer.progress - overtaken.progress < overtake_margin:
			continue
		_last_overtake_time = race_time
		overtake.emit(racer, overtaken)
		return


func _is_ahead(a: RacerState, b: RacerState) -> bool:
	if a.finished != b.finished:
		return a.finished
	if a.finished and a.did_not_finish != b.did_not_finish:
		return b.did_not_finish
	if a.finished and not a.did_not_finish:
		return a.finish_time < b.finish_time
	if is_equal_approx(a.progress, b.progress):
		return a.player_index < b.player_index
	return a.progress > b.progress
