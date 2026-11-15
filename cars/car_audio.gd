class_name CarAudio
extends Node
## Engine, tyre and surface sounds for one car. Player cars are heard at full
## volume; computer cars fade with their distance to the nearest player.

@export_group("Engine")
@export var engine_pitch_range: Vector2 = Vector2(0.65, 2.1)
## Extra pitch while the throttle is open.
@export var throttle_pitch: float = 0.18
@export var engine_volume_db_range: Vector2 = Vector2(-22.0, -11.0)
## How fast revs follow the car (1/s).
@export var engine_response: float = 6.0

@export_group("Tyres and surface")
## Slip angle (degrees) where squeal starts and where it is loudest.
@export var skid_slip_range: Vector2 = Vector2(9.0, 35.0)
@export var skid_min_speed: float = 5.0
@export var skid_volume_db: float = -13.0
@export var rumble_volume_db: float = -15.0
## Speed (m/s) at which the surface rumble is loudest.
@export var rumble_full_speed: float = 25.0

@export_group("Crash")
@export var crash_volume_db: float = -5.0
## Speed change (m/s) that plays the crash at full volume.
@export var crash_full_impact: float = 14.0

@export_group("Distance")
## Computer cars are this many dB quieter than a player's own car.
@export var other_car_offset_db: float = -6.0
## Distance (m) at which another car's sound has halved.
@export var half_distance: float = 14.0
@export var silent_db: float = -60.0

## Cars whose drivers are listening. Set by the race scene.
var listeners: Array[Car] = []

var _car: Car
var _is_listener: bool = false
var _engine: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _revs: float = 0.0


func setup(car: Car, listener_cars: Array[Car]) -> void:
	_car = car
	listeners = listener_cars
	_is_listener = listener_cars.has(car)
	if not SoundBank.is_audio_available():
		set_process(false)
		return
	_engine = _add_loop(SoundBank.Sound.ENGINE)
	_skid = _add_loop(SoundBank.Sound.SKID)
	_rumble = _add_loop(SoundBank.Sound.RUMBLE)
	car.impact.connect(_on_impact)


## Loops are stopped explicitly so no playback outlives the car.
func _exit_tree() -> void:
	for player: AudioStreamPlayer in [_engine, _skid, _rumble]:
		if player != null:
			player.stop()


func _add_loop(sound: SoundBank.Sound) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = SoundBank.get_stream(sound)
	player.volume_db = silent_db
	add_child(player)
	player.play()
	return player


func _process(delta: float) -> void:
	if _car == null:
		return
	var presence_db: float = _get_presence_db()
	var speed: float = _car.linear_velocity.length()
	var throttle: float = _car.get_throttle()

	var target_revs: float = clampf(absf(_car.get_forward_speed()) / _car.get_base_top_speed(), 0.0, 1.0)
	_revs = lerpf(_revs, target_revs, 1.0 - exp(-engine_response * delta))
	_engine.pitch_scale = lerpf(engine_pitch_range.x, engine_pitch_range.y, _revs) + throttle * throttle_pitch
	_engine.volume_db = lerpf(engine_volume_db_range.x, engine_volume_db_range.y, maxf(throttle, _revs)) + presence_db

	var grounded: bool = _car.is_grounded()
	var skid: float = 0.0
	if grounded and speed > skid_min_speed:
		skid = clampf(inverse_lerp(skid_slip_range.x, skid_slip_range.y, _car.get_slip_angle()), 0.0, 1.0)
	_skid.volume_db = _level_db(skid, skid_volume_db) + presence_db

	var surface: SurfaceData = _car.get_current_surface()
	var rumble: float = 0.0
	if grounded and surface != null:
		# Loose surfaces rumble; smooth ones stay quiet.
		rumble = clampf(speed / rumble_full_speed, 0.0, 1.0) * surface.dust_amount
	_rumble.volume_db = _level_db(rumble, rumble_volume_db) + presence_db


## 0..1 loudness to decibels, silent at zero.
func _level_db(level: float, full_db: float) -> float:
	return full_db + linear_to_db(level) if level > 0.01 else silent_db


func _get_presence_db() -> float:
	if _is_listener:
		return 0.0
	var nearest: float = INF
	for listener: Car in listeners:
		nearest = minf(nearest, listener.global_position.distance_to(_car.global_position))
	if nearest == INF:
		return silent_db
	return other_car_offset_db + linear_to_db(half_distance / (half_distance + nearest))


func _on_impact(speed_change: float) -> void:
	var strength: float = clampf(speed_change / crash_full_impact, 0.15, 1.0)
	var volume: float = crash_volume_db + linear_to_db(strength) + _get_presence_db()
	if volume > silent_db:
		SoundBank.play(self, SoundBank.Sound.CRASH, volume, randf_range(0.85, 1.15))
