class_name SoundBank
extends RefCounted
## All sounds are synthesised in code on first use (there are no audio files):
## engine layers, tyre and surface loops, crashes, gear and exhaust effects,
## countdown beeps and UI ticks.
##
## Loops are rendered twice over and the second pass is kept, so every filter
## has settled into the loop's own repeating state and the loop point is
## seamless. Everything random inside a loop repeats with the loop.

enum Sound {
	ENGINE_LOW, ENGINE_HIGH, ENGINE_OFF, TRANSMISSION,
	ROLL_ASPHALT, ROLL_GRAVEL, ROLL_SNOW, SKID_ASPHALT, SKID_LOOSE,
	CRASH, CRASH_2, CRASH_3, SHIFT, BACKFIRE,
	BEEP, GO, UI_MOVE, UI_ACCEPT,
}

const MIX_RATE: int = 22050
const NOISE_SEED: int = 1234
const DUMMY_DRIVER: String = "Dummy"
const CRASH_VARIANTS: Array[Sound] = [Sound.CRASH, Sound.CRASH_2, Sound.CRASH_3]

## Engine layers: samples between two firings (MIX_RATE / that = firing
## frequency), firings per loop, and the sound of the layer.
## A four-cylinder four-stroke fires twice per revolution: 30 Hz is 900 rpm.
const ENGINE_LOW_PULSE: int = 490      # 45 Hz, 1350 rpm
const ENGINE_HIGH_PULSE: int = 147     # 150 Hz, 4500 rpm
const ENGINE_OFF_PULSE: int = 245      # 90 Hz, 2700 rpm
const ENGINE_LOOP_FIRINGS: Array[int] = [24, 80, 40]
## Firing strength of the four cylinders: small differences give the growl.
const CYLINDER_BALANCE: Array[float] = [1.0, 0.86, 0.94, 0.8]
## Exhaust resonances (Hz) and their share for the low, high and off layers.
## The `static var`s below are the synthesis settings: the audio debug panel
## (F2) changes them and calls rebuild().
static var exhaust_formants: PackedFloat32Array = PackedFloat32Array([140.0, 420.0, 1250.0])
const LAYER_FORMANT_MIX: Array = [[1.0, 0.45, 0.12], [0.75, 0.7, 0.35], [0.8, 0.25, 0.05]]
## Combustion noise mixed into each firing, per layer.
static var layer_noise: PackedFloat32Array = PackedFloat32Array([0.25, 0.5, 0.12])
## How uneven the cylinders are (0 = all equal, 1 = CYLINDER_BALANCE as is).
static var cylinder_spread: float = 1.0
## Firing loudness per layer (the off-throttle layer is soft).
const LAYER_FORCE: Array[float] = [1.0, 1.0, 0.45]
## Gearbox whine: samples per cycle and cycles per loop.
const WHINE_PERIOD: int = 21           # 1050 Hz
const WHINE_CYCLES: int = 210
## Noise loops are long so the ear does not pick up the repeat.
const NOISE_LOOP_SECONDS: float = 4.0
## Stone hits per second in the gravel and snow loops, and in the loose skid.
static var gravel_hits: float = 700.0
static var snow_hits: float = 260.0
static var scrub_hits: float = 1100.0
## Pitch of the tyre squeal (Hz).
static var squeal_frequency: float = 880.0
## Partials of the bent-metal clang, as ratios of its base frequency.
const CLANG_RATIOS: Array[float] = [1.0, 2.76, 5.4, 8.93]
const OUTPUT_PEAK: float = 0.9
## Average loudness (RMS) of the engine layers and of the tyre and surface loops.
static var engine_rms: float = 0.3
static var surface_rms: float = 0.25

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


## Throws away every built sound and makes them again with the current
## settings. Players keep their old streams until they are handed the new ones.
static func rebuild() -> void:
	_cache.clear()
	warm_up()


## Builds the race sounds ahead of time so the first crash does not stutter.
static func warm_up() -> void:
	if not is_audio_available():
		return
	for sound: int in Sound.values():
		get_stream(sound as Sound)


## Base firing frequency (Hz) of an engine layer, for turning revs into pitch.
static func get_engine_frequency(sound: Sound) -> float:
	match sound:
		Sound.ENGINE_LOW:
			return float(MIX_RATE) / float(ENGINE_LOW_PULSE)
		Sound.ENGINE_HIGH:
			return float(MIX_RATE) / float(ENGINE_HIGH_PULSE)
		Sound.ENGINE_OFF:
			return float(MIX_RATE) / float(ENGINE_OFF_PULSE)
	return float(MIX_RATE) / float(WHINE_PERIOD)


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
		Sound.ENGINE_LOW:
			return _to_stream(_engine(ENGINE_LOW_PULSE, 0), true)
		Sound.ENGINE_HIGH:
			return _to_stream(_engine(ENGINE_HIGH_PULSE, 1), true)
		Sound.ENGINE_OFF:
			return _to_stream(_engine(ENGINE_OFF_PULSE, 2), true)
		Sound.TRANSMISSION:
			return _to_stream(_whine(), true)
		Sound.ROLL_ASPHALT:
			return _to_stream(_asphalt_roll(), true)
		Sound.ROLL_GRAVEL:
			return _to_stream(_crunch_loop(gravel_hits, [1300.0, 2600.0, 4300.0], 0.45, 1), true)
		Sound.ROLL_SNOW:
			return _to_stream(_crunch_loop(snow_hits, [420.0, 780.0, 1500.0], 0.3, 2), true)
		Sound.SKID_ASPHALT:
			return _to_stream(_squeal(), true)
		Sound.SKID_LOOSE:
			return _to_stream(_crunch_loop(scrub_hits, [900.0, 1900.0, 3600.0], 0.8, 3), true)
		Sound.CRASH, Sound.CRASH_2, Sound.CRASH_3:
			return _to_stream(_crash(CRASH_VARIANTS.find(sound)), false)
		Sound.SHIFT:
			return _to_stream(_shift(), false)
		Sound.BACKFIRE:
			return _to_stream(_backfire(), false)
		Sound.BEEP:
			return _to_stream(_beep(660.0, 0.16, 0.5), false)
		Sound.GO:
			return _to_stream(_beep(990.0, 0.5, 0.5), false)
		Sound.UI_MOVE:
			return _to_stream(_tone(880.0, 0.035, 0.25), false)
	return _to_stream(_tone(1175.0, 0.09, 0.3), false)


# --- Filters -------------------------------------------------------------------

## Two-pole band-pass resonator (constant peak gain). State lives in `state`
## (two floats) so one set of coefficients can run several voices.
class Resonator:
	var a1: float
	var a2: float
	var gain: float
	var y1: float = 0.0
	var y2: float = 0.0

	func _init(frequency: float, q: float) -> void:
		var r: float = exp(-PI * frequency / (q * float(MIX_RATE)))
		a1 = 2.0 * r * cos(TAU * frequency / float(MIX_RATE))
		a2 = -r * r
		gain = 1.0 - r

	func process(x: float) -> float:
		var y: float = gain * x + a1 * y1 + a2 * y2
		y2 = y1
		y1 = y
		return y


## Renders a loop of `length` samples by calling render(index) twice over and
## keeping the second pass.
static func _settled_loop(length: int, render: Callable) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(length)
	for i: int in length * 2:
		var value: float = render.call(i % length)
		if i >= length:
			samples[i - length] = value
	return samples


## Sets the average loudness (RMS) and rounds off the peaks so nothing clips.
static func _finish(samples: PackedFloat32Array, rms: float) -> PackedFloat32Array:
	var total: float = 0.0
	for value: float in samples:
		total += value * value
	var gain: float = rms / maxf(0.0001, sqrt(total / float(samples.size())))
	for i: int in samples.size():
		samples[i] = tanh(samples[i] * gain)
	return samples


static func _normalise(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var gain: float = peak / maxf(0.0001, _peak(samples))
	for i: int in samples.size():
		samples[i] *= gain
	return samples


static func _noise_table(length: int, noise_seed: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = noise_seed
	var table: PackedFloat32Array = PackedFloat32Array()
	table.resize(length)
	for i: int in length:
		table[i] = rng.randf_range(-1.0, 1.0)
	return table


## Soft clipping: rounds off peaks and adds a little grit.
static func _saturate(value: float, drive: float) -> float:
	return tanh(value * drive) / tanh(drive)


# --- Engine --------------------------------------------------------------------

## Combustion pulses through exhaust resonances. Each firing is a short
## decaying kick plus noise; the four cylinders fire a little unevenly.
static func _engine(pulse: int, layer: int) -> PackedFloat32Array:
	var firings: int = ENGINE_LOOP_FIRINGS[layer]
	var length: int = pulse * firings
	var noise: PackedFloat32Array = _noise_table(length, NOISE_SEED + layer)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = NOISE_SEED + 10 + layer
	var jitter: PackedFloat32Array = PackedFloat32Array()
	for k: int in firings:
		jitter.append(1.0 + rng.randf_range(-0.08, 0.08))
	var formants: Array[Resonator] = []
	for frequency: float in exhaust_formants:
		formants.append(Resonator.new(frequency, 3.5))
	var mix: Array = LAYER_FORMANT_MIX[layer]
	var noise_share: float = layer_noise[layer]
	var force: float = LAYER_FORCE[layer]
	# The kick decays within about a third of the firing interval.
	var decay: float = 3.0 / float(pulse) * 3.0
	var body: Resonator = Resonator.new(float(MIX_RATE) / float(pulse), 1.2)
	return _finish(_settled_loop(length, func(i: int) -> float:
		var firing: int = int(float(i) / float(pulse))
		var phase: int = i % pulse
		var strength: float = (1.0 - (1.0 - CYLINDER_BALANCE[firing % CYLINDER_BALANCE.size()]) * cylinder_spread) * jitter[firing] * force
		var kick: float = exp(-float(phase) * decay) * strength
		var excitation: float = kick * (1.0 - noise_share + noise[i] * noise_share)
		var value: float = body.process(excitation) * 0.8
		for f: int in formants.size():
			value += formants[f].process(excitation) * float(mix[f]) * 4.0
		return value), engine_rms)


## Gearbox whine: a thin tone with a little second harmonic.
static func _whine() -> PackedFloat32Array:
	var length: int = WHINE_PERIOD * WHINE_CYCLES
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(length)
	for i: int in length:
		var phase: float = TAU * float(i) / float(WHINE_PERIOD)
		samples[i] = sin(phase) + 0.3 * sin(phase * 2.0) + 0.1 * sin(phase * 3.0)
	return _normalise(samples, OUTPUT_PEAK)


# --- Tyres and surfaces -------------------------------------------------------

## Smooth tyre roar on tarmac: low, soft noise with a gentle hum.
static func _asphalt_roll() -> PackedFloat32Array:
	var length: int = roundi(NOISE_LOOP_SECONDS * float(MIX_RATE))
	var noise: PackedFloat32Array = _noise_table(length, NOISE_SEED + 20)
	var hum: Resonator = Resonator.new(180.0, 1.5)
	var hiss: Resonator = Resonator.new(900.0, 0.8)
	var state: Array[float] = [0.0]
	return _finish(_settled_loop(length, func(i: int) -> float:
		state[0] = lerpf(state[0], noise[i], 0.08)
		return state[0] * 0.6 + hum.process(noise[i]) * 1.5 + hiss.process(noise[i]) * 0.5), surface_rms)


## Stones and grit: random sharp hits rung through a few bright resonances,
## over a low rumble. hits per second, resonance frequencies, rumble share.
static func _crunch_loop(hits: float, bands: Array, rumble: float, seed_offset: int) -> PackedFloat32Array:
	var length: int = roundi(NOISE_LOOP_SECONDS * float(MIX_RATE))
	var noise: PackedFloat32Array = _noise_table(length, NOISE_SEED + 30 + seed_offset)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = NOISE_SEED + 40 + seed_offset
	# Sparse impulses with random strength; most hits are small.
	var impulses: PackedFloat32Array = PackedFloat32Array()
	impulses.resize(length)
	var chance: float = hits / float(MIX_RATE)
	for i: int in length:
		if rng.randf() < chance:
			var size: float = rng.randf()
			impulses[i] = size * size * (1.0 if rng.randf() < 0.5 else -1.0)
	var resonators: Array[Resonator] = []
	for frequency: float in bands:
		resonators.append(Resonator.new(frequency, 2.5))
	var low: Array[float] = [0.0]
	return _finish(_settled_loop(length, func(i: int) -> float:
		var value: float = 0.0
		for r: Resonator in resonators:
			value += r.process(impulses[i])
		low[0] = lerpf(low[0], noise[i], 0.04)
		return value * 6.0 + low[0] * rumble * 2.0), surface_rms)


## Tyre squeal on tarmac: a wavering tone with a rough edge. Its wobble repeats
## a whole number of times per loop so the loop stays seamless.
static func _squeal() -> PackedFloat32Array:
	var length: int = roundi(NOISE_LOOP_SECONDS * float(MIX_RATE))
	var noise: PackedFloat32Array = _noise_table(length, NOISE_SEED + 50)
	var edge: Resonator = Resonator.new(squeal_frequency * 2.3, 6.0)
	var seconds: float = float(length) / float(MIX_RATE)
	# A whole number of cycles per loop, so the loop stays seamless at any setting.
	var frequency: float = maxf(1.0, roundf(squeal_frequency * seconds)) / seconds
	# The tone makes a whole number of cycles per loop, and its wobble is a
	# phase swing that also repeats with the loop: slow (3 per loop, about 5 %
	# in pitch) and quick (23 per loop, about 2 %).
	var slow_swing: float = frequency * 0.05 * seconds / 3.0
	var quick_swing: float = frequency * 0.02 * seconds / 23.0
	return _finish(_settled_loop(length, func(i: int) -> float:
		var t: float = float(i) / float(MIX_RATE)
		var phase: float = TAU * frequency * t + slow_swing * sin(TAU * 3.0 * t / seconds) + quick_swing * sin(TAU * 23.0 * t / seconds)
		var level: float = 0.75 + 0.25 * sin(TAU * 7.0 * t / seconds)
		var tone: float = sin(phase) + 0.35 * sin(phase * 2.0)
		return tone * level + edge.process(noise[i]) * 3.0), surface_rms)


# --- One-shots -----------------------------------------------------------------

## A crash: low thump, clang of bent metal, crunch and a rattle of debris.
static func _crash(variant: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = NOISE_SEED + 60 + variant
	var length: int = roundi(0.9 * float(MIX_RATE))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(length)
	var clang_base: float = rng.randf_range(210.0, 360.0)
	var clang_decays: Array[float] = []
	for k: int in CLANG_RATIOS.size():
		clang_decays.append(rng.randf_range(4.0, 9.0) * (1.0 + float(k) * 0.6))
	var crunch: Resonator = Resonator.new(rng.randf_range(1400.0, 2400.0), 1.2)
	var debris: Resonator = Resonator.new(rng.randf_range(2800.0, 4200.0), 3.0)
	var thump_phase: float = 0.0
	for i: int in length:
		var t: float = float(i) / float(MIX_RATE)
		thump_phase += TAU * lerpf(95.0, 42.0, minf(1.0, t / 0.18)) / float(MIX_RATE)
		var thump: float = sin(thump_phase) * exp(-t * 16.0)
		var clang: float = 0.0
		for k: int in CLANG_RATIOS.size():
			clang += sin(TAU * clang_base * CLANG_RATIOS[k] * t) * exp(-t * clang_decays[k]) / float(k + 1)
		var white: float = rng.randf_range(-1.0, 1.0)
		var burst: float = crunch.process(white) * 6.0 * exp(-t * 22.0)
		# Bits keep falling for a while after the hit.
		var bit: float = 0.0
		if rng.randf() < 0.012 * exp(-t * 4.0):
			bit = rng.randf_range(-1.0, 1.0)
		var rattle: float = debris.process(bit) * 8.0
		samples[i] = _saturate(thump * 1.1 + clang * 0.35 + burst + rattle, 1.4)
	return _normalise(samples, OUTPUT_PEAK)


## Gear change: a short mechanical clunk.
static func _shift() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = NOISE_SEED + 70
	var length: int = roundi(0.12 * float(MIX_RATE))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(length)
	var knock: Resonator = Resonator.new(1600.0, 4.0)
	for i: int in length:
		var t: float = float(i) / float(MIX_RATE)
		var clunk: float = sin(TAU * 130.0 * t) * exp(-t * 45.0)
		var click: float = knock.process(rng.randf_range(-1.0, 1.0) * exp(-t * 300.0)) * 5.0
		samples[i] = clunk + click
	return _normalise(samples, OUTPUT_PEAK)


## Exhaust backfire: a sharp, low pop.
static func _backfire() -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = NOISE_SEED + 80
	var length: int = roundi(0.16 * float(MIX_RATE))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(length)
	var bark: Resonator = Resonator.new(320.0, 1.5)
	for i: int in length:
		var t: float = float(i) / float(MIX_RATE)
		var bang: float = bark.process(rng.randf_range(-1.0, 1.0)) * 5.0 * exp(-t * 38.0)
		var boom: float = sin(TAU * 68.0 * t) * exp(-t * 26.0)
		samples[i] = _saturate(bang + boom, 2.0)
	return _normalise(samples, OUTPUT_PEAK)


## Countdown beep: a soft square-ish tone that rings out.
static func _beep(frequency: float, seconds: float, volume: float) -> PackedFloat32Array:
	var count: int = roundi(seconds * float(MIX_RATE))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for i: int in count:
		var t: float = float(i) / float(MIX_RATE)
		var envelope: float = minf(1.0, t * 300.0) * exp(-t * 4.0 / seconds)
		var phase: float = TAU * frequency * t
		samples[i] = (sin(phase) + sin(phase * 3.0) / 3.0 + sin(phase * 5.0) / 6.0) * envelope * volume
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
