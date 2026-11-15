class_name SoundBank
extends RefCounted
## All sounds are synthesised in code on first use (there are no audio files
## yet): engine, tyre and surface loops, crash, countdown beeps and UI ticks.

enum Sound { ENGINE, SKID, RUMBLE, CRASH, BEEP, GO, UI_MOVE, UI_ACCEPT }

const MIX_RATE: int = 22050
const NOISE_SEED: int = 1234
## Engine loop: base frequency and length. Length * frequency must be a whole number.
const ENGINE_FREQUENCY: float = 80.0
const ENGINE_SECONDS: float = 0.25
const ENGINE_HARMONICS: int = 7
const LOOP_SECONDS: float = 0.6
## Share of a noise loop that is cross-faded so the loop point does not click.
const LOOP_FADE: float = 0.15
const DUMMY_DRIVER: String = "Dummy"

static var _cache: Dictionary = {}


## False when Godot runs without sound output (headless runs, the Dummy
## driver). Playbacks handed to that driver are never released, so nothing is
## played at all in that case.
static func is_audio_available() -> bool:
	return AudioServer.get_driver_name() != DUMMY_DRIVER


static func get_stream(sound: Sound) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _build(sound)
	return _cache[sound]


## Plays a sound once on a temporary player that frees itself. Works while paused.
static func play(context: Node, sound: Sound, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not context.is_inside_tree() or not is_audio_available():
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = get_stream(sound)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.finished.connect(player.queue_free)
	# Lives on the root so it outlasts the screen that triggered it; deferred
	# because the root may be busy adding a scene when a sound is requested.
	player.autoplay = true
	context.get_tree().root.add_child.call_deferred(player)


static func _build(sound: Sound) -> AudioStreamWAV:
	match sound:
		Sound.ENGINE:
			return _to_stream(_engine(), true)
		Sound.SKID:
			return _to_stream(_noise_loop(0.55, 0.25), true)
		Sound.RUMBLE:
			return _to_stream(_noise_loop(0.06, 0.0), true)
		Sound.CRASH:
			return _to_stream(_crash(), false)
		Sound.BEEP:
			return _to_stream(_tone(660.0, 0.16, 0.5), false)
		Sound.GO:
			return _to_stream(_tone(990.0, 0.45, 0.5), false)
		Sound.UI_MOVE:
			return _to_stream(_tone(880.0, 0.035, 0.25), false)
	return _to_stream(_tone(1175.0, 0.09, 0.3), false)


## Buzzy stack of harmonics; pitch_scale turns it into revs.
static func _engine() -> PackedFloat32Array:
	var count: int = roundi(ENGINE_SECONDS * float(MIX_RATE))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for i: int in count:
		var t: float = float(i) / float(MIX_RATE)
		var value: float = 0.0
		for harmonic: int in range(1, ENGINE_HARMONICS + 1):
			# Odd harmonics louder: a rough four-cylinder growl.
			var weight: float = (1.0 if harmonic % 2 == 1 else 0.55) / float(harmonic)
			value += sin(TAU * ENGINE_FREQUENCY * float(harmonic) * t) * weight
		# Half-speed wobble gives the exhaust its uneven pulse.
		value *= 0.8 + 0.2 * sin(TAU * ENGINE_FREQUENCY * 0.5 * t)
		samples[i] = value * 0.38
	return samples


## Filtered noise that loops cleanly. smoothing 0..1: lower = duller (rumble),
## higher = hissier (tyre squeal). highpass removes the low end.
static func _noise_loop(smoothing: float, highpass: float) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	var count: int = roundi(LOOP_SECONDS * float(MIX_RATE))
	var fade: int = roundi(float(count) * LOOP_FADE)
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(count + fade)
	var low: float = 0.0
	var previous: float = 0.0
	for i: int in count + fade:
		var white: float = rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, smoothing)
		raw[i] = low - previous * highpass
		previous = low
	var gain: float = 0.9 / maxf(0.001, _peak(raw))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for i: int in count:
		var value: float = raw[i]
		if i < fade:
			# Blend the tail of the take into its start.
			value = lerpf(raw[count + i], value, float(i) / float(fade))
		samples[i] = value * gain
	return samples


static func _crash() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = NOISE_SEED + 1
	var count: int = roundi(0.4 * float(MIX_RATE))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	var low: float = 0.0
	for i: int in count:
		var t: float = float(i) / float(MIX_RATE)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.35)
		var crunch: float = low * exp(-t * 14.0)
		var thump: float = sin(TAU * 58.0 * t) * exp(-t * 20.0)
		samples[i] = clampf(crunch * 0.9 + thump * 0.8, -1.0, 1.0)
	return samples


static func _tone(frequency: float, seconds: float, volume: float) -> PackedFloat32Array:
	var count: int = roundi(seconds * float(MIX_RATE))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for i: int in count:
		var t: float = float(i) / float(MIX_RATE)
		# Quick attack, smooth release.
		var envelope: float = minf(1.0, t * 400.0) * (1.0 - float(i) / float(count))
		samples[i] = sin(TAU * frequency * t) * envelope * volume
	return samples


static func _peak(samples: PackedFloat32Array) -> float:
	var peak: float = 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	return peak


static func _to_stream(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, roundi(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
