class_name CarAudio
extends Node
## Engine, gearbox, tyre and surface sounds for one car. Player cars are heard
## at full volume; computer cars fade with their distance to the nearest player.
##
## The engine is three synthesised layers (see SoundBank): low revs on the
## throttle, high revs on the throttle, and off the throttle. They cross-fade
## with revs and throttle, each pitched so its firing frequency matches the
## revs, so the engine never sounds like one clip sped up.

enum Ground { ASPHALT, LOOSE, SNOW }

@export_group("Engine")
## Firing frequency (Hz) at idle and at the shift point. A four-cylinder fires
## twice per revolution: 30 Hz is 900 rpm, 230 Hz about 6900 rpm.
@export var idle_frequency: float = 30.0
@export var redline_frequency: float = 230.0
## Extra firing frequency (Hz) while the throttle is open.
@export var throttle_frequency: float = 5.0
## Revs where the low layer hands over to the high one (start, end).
@export var layer_blend_revs: Vector2 = Vector2(0.3, 0.72)
@export var engine_volume_db_range: Vector2 = Vector2(-20.0, -9.0)
## Off-throttle layer level compared with the throttle layers (dB).
@export var overrun_volume_db: float = -3.0
## How fast the throttle layers fade in and out (1/s).
@export var load_response: float = 12.0
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
## Clunk of the gearbox on every change.
@export var shift_sound_db: float = -17.0

@export_group("Backfire")
## Lifting off above these revs may make the exhaust pop.
@export_range(0.0, 1.0, 0.01) var backfire_min_revs: float = 0.55
@export_range(0.0, 1.0, 0.01) var backfire_chance: float = 0.25
## Chance of a pop on an upshift.
@export_range(0.0, 1.0, 0.01) var shift_backfire_chance: float = 0.15
## Pops per lift (min, max) and the gap between them (s).
@export var backfire_count: Vector2i = Vector2i(1, 3)
@export var backfire_gap: Vector2 = Vector2(0.05, 0.14)
@export var backfire_volume_db: float = -13.0
@export var backfire_pitch_range: Vector2 = Vector2(0.85, 1.2)
## Throttle above this and then below release_throttle counts as lifting off.
@export var lift_throttle: Vector2 = Vector2(0.6, 0.1)

@export_group("Gearbox whine")
@export var whine_volume_db: float = -32.0
## Pitch at standstill and at top speed.
@export var whine_pitch_range: Vector2 = Vector2(0.25, 1.3)

@export_group("Tyres and surface")
## Rolling noise level on tarmac, loose ground and snow.
@export var roll_volume_db: Vector3 = Vector3(-22.0, -13.0, -15.0)
## Ice is smooth: its rolling noise is this share of the snow sound.
@export_range(0.0, 1.0, 0.01) var ice_roll_share: float = 0.35
## Speed (m/s) at which the rolling noise is loudest.
@export var roll_full_speed: float = 25.0
## Rolling noise pitch at standstill and at roll_full_speed.
@export var roll_pitch_range: Vector2 = Vector2(0.8, 1.25)
## Slip angle (degrees) where squeal starts and where it is loudest.
@export var skid_slip_range: Vector2 = Vector2(9.0, 35.0)
@export var skid_min_speed: float = 5.0
## Squeal on tarmac, scrubbing on loose ground and snow.
@export var skid_asphalt_db: float = -14.0
@export var skid_loose_db: float = -10.0
## How fast surface sounds fade when the ground changes (1/s).
@export var surface_response: float = 8.0
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
@export var crash_pitch_range: Vector2 = Vector2(0.85, 1.15)

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
var _engine_low: AudioStreamPlayer
var _engine_high: AudioStreamPlayer
var _engine_off: AudioStreamPlayer
var _whine: AudioStreamPlayer
## Rolling and skid loops per Ground.
var _rolls: Array[AudioStreamPlayer] = []
var _skids: Array[AudioStreamPlayer] = []
## Current loudness (0..1) of each rolling and skid loop, eased towards its target.
var _roll_levels: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
var _skid_levels: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _revs: float = 0.0
var _load: float = 0.0
var _gear: int = 0
var _armed_for_lift: bool = false
## Seconds left of the current upshift's throttle cut.
var _shift_left: float = 0.0
var _pops_left: int = 0
var _pop_timer: float = 0.0
## Every looping player and the sound it plays, for reload_streams().
var _loops: Dictionary = {}
var _wander: FastNoiseLite
var _time: float = 0.0


func setup(car: Car, listener_cars: Array[Car]) -> void:
	_car = car
	listeners = listener_cars
	_is_listener = listener_cars.has(car)
	if not SoundBank.is_audio_available():
		set_process(false)
		return
	_engine_low = _add_loop(SoundBank.Sound.ENGINE_LOW)
	_engine_high = _add_loop(SoundBank.Sound.ENGINE_HIGH)
	_engine_off = _add_loop(SoundBank.Sound.ENGINE_OFF)
	_whine = _add_loop(SoundBank.Sound.TRANSMISSION)
	for sound: SoundBank.Sound in [SoundBank.Sound.ROLL_ASPHALT, SoundBank.Sound.ROLL_GRAVEL, SoundBank.Sound.ROLL_SNOW]:
		_rolls.append(_add_loop(sound))
	for sound: SoundBank.Sound in [SoundBank.Sound.SKID_ASPHALT, SoundBank.Sound.SKID_LOOSE]:
		_skids.append(_add_loop(sound))
	_wander = FastNoiseLite.new()
	_wander.seed = randi()
	_wander.frequency = wander_speed
	car.impact.connect(_on_impact)


## Loops are stopped explicitly so no playback outlives the car.
func _exit_tree() -> void:
	for player: AudioStreamPlayer in [_engine_low, _engine_high, _engine_off, _whine] + _rolls + _skids:
		if player != null:
			player.stop()


func _add_loop(sound: SoundBank.Sound) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = SoundBank.get_stream(sound)
	player.volume_db = silent_db
	add_child(player)
	_loops[player] = sound
	# Every car starts its loops at a different point, so two cars side by
	# side do not play the same clip in step.
	player.play(randf() * player.stream.get_length())
	return player


## One line for the audio debug panel: what the engine and tyres are doing.
func get_debug_text() -> String:
	var surface: SurfaceData = _car.get_current_surface() if _car != null else null
	return tr("kierrokset %d %% · kaasu %d %% · vaihde %d · %s") % [
		roundi(_revs * 100.0), roundi(_load * 100.0), _gear, surface.display_name if surface != null else "–",
	]


## Hands every loop its newly built stream (after SoundBank.rebuild()),
## carrying on from about the same point.
func reload_streams() -> void:
	for player: AudioStreamPlayer in _loops:
		var position: float = player.get_playback_position()
		player.stream = SoundBank.get_stream(_loops[player])
		player.play(fmod(position, player.stream.get_length()))


func _process(delta: float) -> void:
	if _car == null:
		return
	_time += delta
	var presence_db: float = _get_presence_db()
	var grounded: bool = _car.is_grounded()
	_update_engine(delta, grounded, presence_db)
	_update_backfire(delta, presence_db)
	_update_surface(delta, grounded, presence_db)


## Revs follow the gearbox: they climb through each gear, drop when the car
## changes up (with a short throttle cut) and jump when it changes down.
func _update_engine(delta: float, grounded: bool, presence_db: float) -> void:
	var gear: int = _car.get_gear()
	if gear != _gear and _gear != 0 and gear != 0:
		_play_once(SoundBank.Sound.SHIFT, shift_sound_db, 1.0)
		if gear > _gear and _gear >= 1:
			_shift_left = shift_time
			if randf() < shift_backfire_chance and _revs > backfire_min_revs:
				_start_pops(1)
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
	_load = lerpf(_load, throttle, 1.0 - exp(-load_response * delta))

	var frequency: float = lerpf(idle_frequency, redline_frequency, _revs) + throttle * throttle_frequency
	_engine_low.pitch_scale = frequency / SoundBank.get_engine_frequency(SoundBank.Sound.ENGINE_LOW)
	_engine_high.pitch_scale = frequency / SoundBank.get_engine_frequency(SoundBank.Sound.ENGINE_HIGH)
	_engine_off.pitch_scale = frequency / SoundBank.get_engine_frequency(SoundBank.Sound.ENGINE_OFF)

	var level_db: float = lerpf(engine_volume_db_range.x, engine_volume_db_range.y, maxf(_load, _revs))
	level_db += (shift_volume_db if shifting else 0.0) + presence_db
	var high: float = smoothstep(layer_blend_revs.x, layer_blend_revs.y, _revs)
	# Equal-power blends: the layers are different sounds, not copies.
	var on: float = sqrt(_load)
	var off: float = sqrt(1.0 - _load)
	_set_level(_engine_low, on * sqrt(1.0 - high), level_db)
	_set_level(_engine_high, on * sqrt(high), level_db)
	_set_level(_engine_off, off, level_db + overrun_volume_db)

	var speed_ratio: float = clampf(absf(_car.get_forward_speed()) / maxf(_car.get_base_top_speed(), 0.1), 0.0, 1.0)
	_whine.pitch_scale = lerpf(whine_pitch_range.x, whine_pitch_range.y, speed_ratio)
	_set_level(_whine, speed_ratio, whine_volume_db + presence_db)

	# Lifting off sharply from high revs can make the exhaust pop.
	if throttle > lift_throttle.x:
		_armed_for_lift = true
	elif _armed_for_lift and throttle < lift_throttle.y and not shifting:
		_armed_for_lift = false
		if _revs > backfire_min_revs and randf() < backfire_chance:
			_start_pops(randi_range(backfire_count.x, backfire_count.y))


func _start_pops(count: int) -> void:
	_pops_left = maxi(_pops_left, count)
	_pop_timer = 0.0


func _update_backfire(delta: float, presence_db: float) -> void:
	if _pops_left <= 0:
		return
	_pop_timer -= delta
	if _pop_timer > 0.0:
		return
	_pops_left -= 1
	_pop_timer = randf_range(backfire_gap.x, backfire_gap.y)
	_play_once(SoundBank.Sound.BACKFIRE, backfire_volume_db, randf_range(backfire_pitch_range.x, backfire_pitch_range.y))


## Rolling noise and skids for the ground under the car, fading between
## grounds when the surface changes.
func _update_surface(delta: float, grounded: bool, presence_db: float) -> void:
	var speed: float = _car.get_velocity().length()
	var surface: SurfaceData = _car.get_current_surface()
	var ground: Ground = _get_ground(surface)
	var speed_share: float = clampf(speed / roll_full_speed, 0.0, 1.0)
	var roll: float = speed_share if grounded and surface != null else 0.0
	if surface != null and surface.kind == SurfaceData.Kind.ICE:
		roll *= ice_roll_share
	var skid: float = 0.0
	if grounded and speed > skid_min_speed:
		skid = clampf(inverse_lerp(skid_slip_range.x, skid_slip_range.y, _car.get_slip_angle()), 0.0, 1.0)
	var fade: float = 1.0 - exp(-surface_response * delta)

	var roll_pitch: float = lerpf(roll_pitch_range.x, roll_pitch_range.y, speed_share)
	var roll_db: Array[float] = [roll_volume_db.x, roll_volume_db.y, roll_volume_db.z]
	for i: int in _rolls.size():
		var target: float = roll if i == ground else 0.0
		_roll_levels[i] = lerpf(_roll_levels[i], target, fade)
		var wander_pitch_value: float = _wander.get_noise_1d(_time + 200.0 + 50.0 * float(i))
		var wander_level: float = _wander.get_noise_1d(_time + 300.0 + 50.0 * float(i))
		_rolls[i].pitch_scale = roll_pitch * (1.0 + wander_pitch_value * wander_pitch)
		_set_level(_rolls[i], _roll_levels[i], roll_db[i] + presence_db + wander_level * wander_volume_db)

	var skid_db: Array[float] = [skid_asphalt_db, skid_loose_db]
	var skid_index: int = 0 if ground == Ground.ASPHALT else 1
	for i: int in _skids.size():
		var target: float = skid if i == skid_index else 0.0
		_skid_levels[i] = lerpf(_skid_levels[i], target, fade)
		var wander_pitch_value: float = _wander.get_noise_1d(_time + 50.0 * float(i))
		var wander_level: float = _wander.get_noise_1d(_time + 100.0 + 50.0 * float(i))
		_skids[i].pitch_scale = 1.0 + wander_pitch_value * wander_pitch
		_set_level(_skids[i], _skid_levels[i], skid_db[i] + presence_db + wander_level * wander_volume_db)


func _get_ground(surface: SurfaceData) -> Ground:
	if surface == null:
		return Ground.LOOSE
	match surface.kind:
		SurfaceData.Kind.ASPHALT:
			return Ground.ASPHALT
		SurfaceData.Kind.SNOW, SurfaceData.Kind.ICE:
			return Ground.SNOW
	return Ground.LOOSE


## Sets a loop's loudness (0..1) on top of full_db; silent at zero.
func _set_level(player: AudioStreamPlayer, level: float, full_db: float) -> void:
	player.volume_db = full_db + linear_to_db(level) if level > 0.01 else silent_db


func _play_once(sound: SoundBank.Sound, volume_db: float, pitch: float) -> void:
	var volume: float = volume_db + _get_presence_db()
	if volume > silent_db:
		SoundBank.play(self, sound, volume, pitch)


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
	var sound: SoundBank.Sound = SoundBank.CRASH_VARIANTS[randi() % SoundBank.CRASH_VARIANTS.size()]
	_play_once(sound, crash_volume_db + linear_to_db(strength), randf_range(crash_pitch_range.x, crash_pitch_range.y))
