class_name AudioTuningPanel
extends TuningPanel
## Debug panel for the car sounds: F2 in a race. The mixing settings (CarAudio)
## change every car's sound at once; the synthesis settings (SoundBank) take
## effect with RAKENNA ÄÄNET, which makes the sounds again. The test buttons
## play the one-shot sounds. Changes last until the game is closed.

const CAR_PREFIX: String = "car:"
const BANK_PREFIX: String = "bank:"

## Rows: a group caption ["#", caption] or [key, label, min, max, step].
## "car:<property path>" is a CarAudio setting, "bank:<name>[:index]" a
## SoundBank synthesis setting.
const PARAMETERS: Array = [
	["#", "MOOTTORI"],
	["car:engine_volume_db_range:x", "Moottori hiljaa (dB)", -40.0, 0.0, 0.5],
	["car:engine_volume_db_range:y", "Moottori kovaa (dB)", -40.0, 6.0, 0.5],
	["car:overrun_volume_db", "Moottorijarrutus (dB)", -20.0, 10.0, 0.5],
	["car:idle_frequency", "Tyhjäkäynti (Hz)", 15.0, 60.0, 0.5],
	["car:redline_frequency", "Huippukierrokset (Hz)", 100.0, 400.0, 1.0],
	["car:throttle_frequency", "Kaasun lisä (Hz)", 0.0, 30.0, 0.5],
	["car:layer_blend_revs:x", "Korkea kerros alkaa", 0.0, 1.0, 0.01],
	["car:layer_blend_revs:y", "Korkea kerros täysin", 0.0, 1.0, 0.01],
	["car:load_response", "Kaasun häivytys (1/s)", 1.0, 40.0, 0.5],
	["car:rev_rise_response", "Kierrosten nousu (1/s)", 1.0, 40.0, 0.5],
	["car:rev_fall_response", "Kierrosten lasku (1/s)", 1.0, 60.0, 0.5],
	["car:shift_time", "Vaihteen katkos (s)", 0.0, 0.4, 0.01],
	["car:shift_volume_db", "Hiljennys vaihtaessa (dB)", -20.0, 0.0, 0.5],
	["car:shift_sound_db", "Vaihteen kolahdus (dB)", -40.0, 0.0, 0.5],
	["#", "PAKOPUTKI JA VAIHTEISTO"],
	["car:backfire_volume_db", "Paukahdus (dB)", -40.0, 6.0, 0.5],
	["car:backfire_chance", "Paukahduksen todennäköisyys", 0.0, 1.0, 0.01],
	["car:shift_backfire_chance", "Paukahdus vaihtaessa", 0.0, 1.0, 0.01],
	["car:backfire_min_revs", "Paukahduksen kierrokset", 0.0, 1.0, 0.01],
	["car:whine_volume_db", "Vaihteiston ulina (dB)", -60.0, -5.0, 0.5],
	["car:whine_pitch_range:x", "Ulinan sävel paikallaan", 0.1, 3.0, 0.05],
	["car:whine_pitch_range:y", "Ulinan sävel huipussa", 0.1, 3.0, 0.05],
	["#", "RENKAAT JA ALUSTA"],
	["car:roll_volume_db:x", "Vierintä asfaltilla (dB)", -40.0, 6.0, 0.5],
	["car:roll_volume_db:y", "Vierintä sorassa (dB)", -40.0, 6.0, 0.5],
	["car:roll_volume_db:z", "Vierintä lumessa (dB)", -40.0, 6.0, 0.5],
	["car:ice_roll_share", "Vierintä jäällä", 0.0, 1.0, 0.01],
	["car:roll_full_speed", "Vierintä täysillä (m/s)", 5.0, 60.0, 0.5],
	["car:roll_pitch_range:x", "Vierinnän sävel hiljaa", 0.3, 2.0, 0.05],
	["car:roll_pitch_range:y", "Vierinnän sävel kovaa", 0.3, 2.0, 0.05],
	["car:skid_asphalt_db", "Vinkuna asfaltilla (dB)", -40.0, 6.0, 0.5],
	["car:skid_loose_db", "Luisto sorassa (dB)", -40.0, 6.0, 0.5],
	["car:skid_slip_range:x", "Luisto alkaa (°)", 0.0, 60.0, 0.5],
	["car:skid_slip_range:y", "Luisto täysillä (°)", 0.0, 90.0, 0.5],
	["car:surface_response", "Alustan vaihto (1/s)", 1.0, 30.0, 0.5],
	["car:wander_pitch", "Sävelen vaeltelu", 0.0, 0.3, 0.01],
	["car:wander_volume_db", "Voimakkuuden vaeltelu (dB)", 0.0, 10.0, 0.1],
	["#", "TÖRMÄYS JA ETÄISYYS"],
	["car:crash_volume_db", "Törmäys (dB)", -40.0, 10.0, 0.5],
	["car:crash_full_impact", "Täysi törmäys (m/s)", 2.0, 40.0, 0.5],
	["car:other_car_offset_db", "Muut autot (dB)", -30.0, 0.0, 0.5],
	["car:half_distance", "Puolittumismatka (m)", 2.0, 60.0, 0.5],
	["#", "SYNTEESI · RAKENNA ÄÄNET"],
	["bank:exhaust_formants:0", "Pakoputken resonanssi 1 (Hz)", 40.0, 600.0, 5.0],
	["bank:exhaust_formants:1", "Pakoputken resonanssi 2 (Hz)", 100.0, 1500.0, 10.0],
	["bank:exhaust_formants:2", "Pakoputken resonanssi 3 (Hz)", 300.0, 4000.0, 10.0],
	["bank:layer_noise:0", "Kohina, matalat kierrokset", 0.0, 1.0, 0.01],
	["bank:layer_noise:1", "Kohina, korkeat kierrokset", 0.0, 1.0, 0.01],
	["bank:layer_noise:2", "Kohina, moottorijarrutus", 0.0, 1.0, 0.01],
	["bank:cylinder_spread", "Sylinterien epätasaisuus", 0.0, 3.0, 0.05],
	["bank:engine_rms", "Moottorin taso", 0.05, 0.7, 0.01],
	["bank:surface_rms", "Alustaäänten taso", 0.05, 0.7, 0.01],
	["bank:gravel_hits", "Kiviä sorassa (/s)", 50.0, 4000.0, 10.0],
	["bank:snow_hits", "Narinaa lumessa (/s)", 20.0, 2000.0, 10.0],
	["bank:scrub_hits", "Kiviä luistossa (/s)", 50.0, 4000.0, 10.0],
	["bank:squeal_frequency", "Vinkunan sävel (Hz)", 200.0, 2500.0, 10.0],
]
## One-shot sounds with a test button: [button text, sound].
const TEST_SOUNDS: Array = [
	["Törmäys", SoundBank.Sound.CRASH], ["Vaihde", SoundBank.Sound.SHIFT],
	["Paukahdus", SoundBank.Sound.BACKFIRE], ["Piippaus", SoundBank.Sound.BEEP],
]

## Changed CarAudio values (path -> value) for this session, applied to new races.
static var _overrides: Dictionary = {}
## Original values of every key, captured before the first change.
static var _defaults: Dictionary = {}

var _audios: Array[CarAudio] = []
## The local player's car sound, shown in the telemetry line.
var _own: CarAudio


## Race start: the session's mixing settings go onto the new cars' sounds.
static func apply_session(audios: Array[CarAudio]) -> void:
	if audios.is_empty():
		return
	_capture_defaults(audios[0])
	for path: String in _overrides:
		for audio: CarAudio in audios:
			audio.set_indexed(path, _overrides[path])


static func _capture_defaults(sample: CarAudio) -> void:
	for row: Array in PARAMETERS:
		var key: String = row[0]
		if key != "#" and not _defaults.has(key):
			_defaults[key] = _read_key(key, sample)


static func _read_key(key: String, sample: CarAudio) -> float:
	if key.begins_with(CAR_PREFIX):
		return float(sample.get_indexed(key.trim_prefix(CAR_PREFIX))) if sample != null else 0.0
	var parts: PackedStringArray = key.trim_prefix(BANK_PREFIX).split(":")
	match parts[0]:
		"exhaust_formants":
			return SoundBank.exhaust_formants[int(parts[1])]
		"layer_noise":
			return SoundBank.layer_noise[int(parts[1])]
		"cylinder_spread":
			return SoundBank.cylinder_spread
		"engine_rms":
			return SoundBank.engine_rms
		"surface_rms":
			return SoundBank.surface_rms
		"gravel_hits":
			return SoundBank.gravel_hits
		"snow_hits":
			return SoundBank.snow_hits
		"scrub_hits":
			return SoundBank.scrub_hits
		"squeal_frequency":
			return SoundBank.squeal_frequency
	return 0.0


static func _write_bank(name_and_index: String, value: float) -> void:
	var parts: PackedStringArray = name_and_index.split(":")
	match parts[0]:
		"exhaust_formants":
			SoundBank.exhaust_formants[int(parts[1])] = value
		"layer_noise":
			SoundBank.layer_noise[int(parts[1])] = value
		"cylinder_spread":
			SoundBank.cylinder_spread = value
		"engine_rms":
			SoundBank.engine_rms = value
		"surface_rms":
			SoundBank.surface_rms = value
		"gravel_hits":
			SoundBank.gravel_hits = value
		"snow_hits":
			SoundBank.snow_hits = value
		"scrub_hits":
			SoundBank.scrub_hits = value
		"squeal_frequency":
			SoundBank.squeal_frequency = value


## own is the local player's car sound (may be null); audios are all of them.
func setup(own: CarAudio, audios: Array[CarAudio]) -> void:
	_own = own
	_audios = audios
	_capture_defaults(own if own != null else (audios[0] if not audios.is_empty() else null))


func _sample() -> CarAudio:
	if is_instance_valid(_own):
		return _own
	for audio: CarAudio in _audios:
		if is_instance_valid(audio):
			return audio
	return null


func _get_title() -> String:
	return tr("ÄÄNTEN SÄÄTÖ · F2")


func _get_rows() -> Array:
	return PARAMETERS


func _read(key: String) -> float:
	return _read_key(key, _sample())


func _write(key: String, value: float) -> void:
	if key.begins_with(BANK_PREFIX):
		_write_bank(key.trim_prefix(BANK_PREFIX), value)
		return
	var path: String = key.trim_prefix(CAR_PREFIX)
	for audio: CarAudio in _audios:
		if is_instance_valid(audio):
			audio.set_indexed(path, value)
	_overrides[path] = value


func _get_default(key: String) -> Variant:
	return _defaults.get(key)


func _describe(key: String) -> String:
	if key.begins_with(BANK_PREFIX):
		return "sound_bank.gd " + key.trim_prefix(BANK_PREFIX)
	return "car_audio.gd " + key.trim_prefix(CAR_PREFIX)


func _copy_header() -> String:
	return "# Äänten säätö"


func _after_reset() -> void:
	_overrides.clear()
	_rebuild_sounds()


func _add_options(row: Container) -> void:
	row.add_child(_make_button(tr("RAKENNA ÄÄNET"), _rebuild_sounds))
	row.add_child(UiStyle.make_label(tr("Testaa:"), UiStyle.FONT_MEDIUM, font_size))
	for test: Array in TEST_SOUNDS:
		row.add_child(_make_button(tr(test[0]), _play_test.bind(test[1])))


func _play_test(sound: SoundBank.Sound) -> void:
	if sound == SoundBank.Sound.CRASH:
		sound = SoundBank.CRASH_VARIANTS[randi() % SoundBank.CRASH_VARIANTS.size()]
	SoundBank.play(self, sound)


## Makes every sound again with the synthesis settings and hands the new
## loops to the cars.
func _rebuild_sounds() -> void:
	SoundBank.rebuild()
	for audio: CarAudio in _audios:
		if is_instance_valid(audio):
			audio.reload_streams()


func _get_telemetry() -> String:
	return _own.get_debug_text() if is_instance_valid(_own) else ""
