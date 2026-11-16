class_name CarAudio
extends Node
## Engine, tyre and surface sounds for one car. Player cars are heard at full
## volume; computer cars fade with their distance to the nearest player.

@export_group("Engine")
## Pitch at idle (revs 0) and at the shift point (revs 1).
@export var engine_pitch_range: Vector2 = Vector2(0.65, 2.1)
## Extra pitch while the throttle is open.
@export var throttle_pitch: float = 0.08
@export var engine_volume_db_range: Vector2 = Vector2(-22.0, -11.0)
## Revs right after shifting up into second gear and above (0 idle .. 1 shift point).
@export_range(0.0, 1.0, 0.01) var shift_drop_revs: float = 0.42
## Revs never fall below this share of the throttle, so pulling away sounds busy.
@export_range(0.0, 1.0, 0.01) var throttle_floor_revs: float = 0.3
## Revs with the throttle open while standing still or in the air.
@export_range(0.0, 1.0, 0.01) var free_revs: float = 0.9
## How fast revs rise and fall (1/s). The fast fall makes each upshift audible.
@export var rev_rise_response: float = 8.0
@export var rev_fall_response: float = 20.0
## Throttle cut while changing up: its length (s) and how much quieter the engine is (dB).
@export var shift_time: float = 0.13
@export var shift_volume_db: float = -6.0

@export_group("Tyres and surface")
## Slip angle (degrees) where squeal starts and where it is loudest.
@export var skid_slip_range: Vector2 = Vector2(9.0, 35.0)
@export var skid_min_speed: float = 5.0
@export var skid_volume_db: float = -13.0
@export var rumble_volume_db: float = -15.0
## Speed (m/s) at which the surface rumble is loudest.
@export var rumble_full_speed: float = 25.0
## Slow random wandering of the tyre and surface loops, so they never sound
## like the same clip over and over: pitch (share of 1.0) and volume (dB).
@export_range(0.0, 0.3, 0.01) var wander_pitch: float = 0.08
@export var wander_volume_db: float = 2.0
## How fast the wandering changes (noise cycles per second).
@export var wander_speed: float = 0.7

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
var _gear: int = 0
## Seconds left of the current upshift's throttle cut.
var _shift_left: float = 0.0
var _wander: FastNoiseLite
var _time: float = 0.0


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
	_wander = FastNoiseLite.new()
	_wander.seed = randi()
	_wander.frequency = wander_speed
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
	# Every car starts its loops at a different point, so two cars side by
	# side do not play the same clip in step.
	player.play(randf() * player.stream.get_length())
	return player


func _process(delta: float) -> void:
	if _car == null:
		return
	_time += delta
	# Two independent wandering values in -1..1 for the skid, two for the rumble.
	var skid_pitch: float = _wander.get_noise_1d(_time)
	var skid_level: float = _wander.get_noise_1d(_time + 100.0)
	var rumble_pitch: float = _wander.get_noise_1d(_time + 200.0)
	var rumble_level: float = _wander.get_noise_1d(_time + 300.0)
	_skid.pitch_scale = 1.0 + skid_pitch * wander_pitch
	_rumble.pitch_scale = 1.0 + rumble_pitch * wander_pitch
	var presence_db: float = _get_presence_db()
	var speed: float = _car.get_velocity().length()

	var grounded: bool = _car.is_grounded()
	_update_engine(delta, grounded, presence_db)

	var skid: float = 0.0
	if grounded and speed > skid_min_speed:
		skid = clampf(inverse_lerp(skid_slip_range.x, skid_slip_range.y, _car.get_slip_angle()), 0.0, 1.0)
	_skid.volume_db = _level_db(skid, skid_volume_db) + presence_db + skid_level * wander_volume_db

	var surface: SurfaceData = _car.get_current_surface()
	var rumble: float = 0.0
	if grounded and surface != null:
		# Loose surfaces rumble; smooth ones stay quiet.
		rumble = clampf(speed / rumble_full_speed, 0.0, 1.0) * surface.dust_amount
	_rumble.volume_db = _level_db(rumble, rumble_volume_db) + presence_db + rumble_level * wander_volume_db


## Revs follow the gearbox: they climb through each gear, drop when the car
## changes up (with a short throttle cut) and jump when it changes down.
func _update_engine(delta: float, grounded: bool, presence_db: float) -> void:
	var gear: int = _car.get_gear()
	if gear > _gear and _gear >= 1:
		_shift_left = shift_time
	_gear = gear
	_shift_left = maxf(0.0, _shift_left - delta)
	var shifting: bool = _shift_left > 0.0
	var throttle: float = 0.0 if shifting else clampf(_car.get_throttle(), 0.0, 1.0)

	var target_revs: float = 0.0
	if gear >= 1:
		var low: float = 0.0 if gear == 1 else shift_drop_revs
		target_revs = lerpf(low, 1.0, _car.get_gear_position())
	elif gear == -1:
		var reverse_top: float = _car.get_base_top_speed() * _car.reverse_speed_share
		target_revs = absf(_car.get_forward_speed()) / maxf(reverse_top, 0.1)
	target_revs = maxf(target_revs, throttle * throttle_floor_revs)
	if gear == 0 or not grounded:
		target_revs = maxf(target_revs, throttle * free_revs)
	target_revs = clampf(target_revs, 0.0, 1.0)

	var response: float = rev_rise_response if target_revs > _revs else rev_fall_response
	_revs = lerpf(_revs, target_revs, 1.0 - exp(-response * delta))
	_engine.pitch_scale = lerpf(engine_pitch_range.x, engine_pitch_range.y, _revs) + throttle * throttle_pitch
	var level: float = lerpf(engine_volume_db_range.x, engine_volume_db_range.y, maxf(throttle, _revs))
	_engine.volume_db = level + (shift_volume_db if shifting else 0.0) + presence_db


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
