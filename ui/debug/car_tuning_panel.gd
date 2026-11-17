class_name CarTuningPanel
extends TuningPanel
## Debug panel for tuning how the cars drive: F1 in a race (not in network
## games). Sliders change the cars' values on the fly; KOPIOI ARVOT puts the
## changed values on the clipboard so they can be written into the game.
## Changes last until the game is closed.

## Rows: a group caption ["#", caption] or
## [property path on Car, label, min, max, step, own car's model only].
## "stats:..." rows change the CarStats of the player's car model.
const PARAMETERS: Array = [
	["#", "AUTOMALLI (1–10)"],
	["stats:top_speed", "Huippunopeus", 1, 10, 1, true],
	["stats:acceleration", "Kiihtyvyys", 1, 10, 1, true],
	["stats:grip_gravel", "Pito soralla", 1, 10, 1, true],
	["stats:grip_asphalt", "Pito asfaltilla", 1, 10, 1, true],
	["#", "MOOTTORI"],
	["top_speed_range:x", "Huippunopeus, taso 1 (m/s)", 10.0, 80.0, 0.5, false],
	["top_speed_range:y", "Huippunopeus, taso 10 (m/s)", 10.0, 100.0, 0.5, false],
	["acceleration_range:x", "Kiihtyvyys, taso 1 (m/s²)", 1.0, 30.0, 0.25, false],
	["acceleration_range:y", "Kiihtyvyys, taso 10 (m/s²)", 1.0, 40.0, 0.25, false],
	["#", "RENKAAT"],
	["tire_friction", "Kitka", 0.3, 4.0, 0.05, false],
	["tire_response", "Sivuluiston vaimennus (1/s)", 2.0, 50.0, 0.5, false],
	["front_grip_scale", "Etupään pito", 0.3, 1.5, 0.01, false],
	["rear_grip_scale", "Takapään pito", 0.3, 1.5, 0.01, false],
	["max_longitudinal_share", "Veto-osuus pidosta, 4WD", 0.1, 1.0, 0.01, false],
	["two_wheel_drive_share", "Veto-osuus pidosta, 2WD", 0.1, 1.0, 0.01, false],
	["grip_multiplier_range:x", "Pitokerroin, taso 1", 0.3, 2.0, 0.01, false],
	["grip_multiplier_range:y", "Pitokerroin, taso 10", 0.3, 2.0, 0.01, false],
	["#", "OHJAUS"],
	["steer_angle_low_speed", "Ohjauskulma hitaasti (°)", 0.0, 60.0, 0.5, false],
	["steer_angle_high_speed", "Ohjauskulma kovaa (°)", 0.0, 60.0, 0.5, false],
	["steer_speed", "Ohjauksen nopeus (1/s)", 0.5, 20.0, 0.25, false],
	["countersteer_gain", "Vastaohjausapu", 0.0, 3.0, 0.05, false],
	["#", "JARRUT"],
	["brake_deceleration", "Jarru (m/s²)", 2.0, 40.0, 0.5, false],
	["handbrake_deceleration", "Käsijarru (m/s²)", 0.0, 30.0, 0.5, false],
	["handbrake_grip", "Takapään pito käsijarrulla", 0.0, 1.0, 0.01, false],
	["brake_response", "Jarrun vaste", 1.0, 60.0, 0.5, false],
	["#", "JOUSITUS JA RUNKO"],
	["spring_stiffness", "Jousen jäykkyys", 5000.0, 100000.0, 500.0, false],
	["spring_damping", "Iskunvaimennus", 500.0, 15000.0, 100.0, false],
	["mass", "Massa (kg)", 300.0, 3000.0, 10.0, false],
	["center_of_mass:y", "Painopisteen korkeus (m)", -0.5, 1.0, 0.01, false],
	["tire_force_height", "Rengasvoimien korkeus (m)", 0.0, 0.8, 0.01, false],
	["angular_damp", "Pyörimisen vaimennus", 0.0, 5.0, 0.05, false],
	["air_control_torque", "Ohjaus ilmassa", 0.0, 5000.0, 50.0, false],
]
const STATS_PREFIX: String = "stats:"

## Changed car values (path -> value) for this session, applied to new races.
static var _overrides: Dictionary = {}
## Original car values (path -> value), captured before the first change.
static var _defaults: Dictionary = {}
## Original stats ("resource path|property" -> value).
static var _stat_defaults: Dictionary = {}
## Apply the car values to every car (true) or only the player's (false).
static var _all_cars: bool = true
## True once the saved tuning has been read (load_saved()).
static var _loaded: bool = false

const STORE_SECTION: String = "car"
const STORE_STATS_SECTION: String = "car_stats"
const STORE_ALL_CARS: String = "_all_cars"

var _car: Car
var _cars: Array[Car] = []


## Reads the tuning saved by earlier sessions, once. Car values go onto every
## race's cars through apply_session(); model stats are set on the CarStats
## resources right away (their originals are kept for PALAUTA).
static func load_saved() -> void:
	if _loaded:
		return
	_loaded = true
	var saved: Dictionary = DebugTuningStore.load_section(STORE_SECTION)
	for path: String in saved:
		if path == STORE_ALL_CARS:
			_all_cars = bool(saved[path])
		else:
			_overrides[path] = float(saved[path])
	var stats: Dictionary = DebugTuningStore.load_section(STORE_STATS_SECTION)
	for key: String in stats:
		var resource_path: String = key.get_slice("|", 0)
		var stat_path: String = key.get_slice("|", 1)
		var car_stats: CarStats = load(resource_path) as CarStats
		if car_stats == null:
			continue
		var property: String = stat_path.trim_prefix(STATS_PREFIX)
		if not _stat_defaults.has(key):
			_stat_defaults[key] = car_stats.get(property)
		car_stats.set(property, roundi(float(stats[key])))


## Writes every changed value to the store.
static func _save() -> void:
	var values: Dictionary = _overrides.duplicate()
	values[STORE_ALL_CARS] = _all_cars
	DebugTuningStore.save_section(STORE_SECTION, values)
	var stats: Dictionary = {}
	for key: String in _stat_defaults:
		var car_stats: CarStats = load(key.get_slice("|", 0)) as CarStats
		if car_stats == null:
			continue
		var value: int = car_stats.get(key.get_slice("|", 1).trim_prefix(STATS_PREFIX))
		if value != int(_stat_defaults[key]):
			stats[key] = value
	DebugTuningStore.save_section(STORE_STATS_SECTION, stats)


## Race start: the session's tuning goes onto the new cars.
static func apply_session(cars: Array[Car], own_car: Car) -> void:
	if own_car == null:
		return
	_capture_defaults(own_car)
	var targets: Array[Car] = cars if _all_cars else _only(own_car)
	for path: String in _overrides:
		for car: Car in targets:
			car.set_indexed(path, _overrides[path])


static func _capture_defaults(car: Car) -> void:
	for row: Array in PARAMETERS:
		var path: String = row[0]
		if path == "#":
			continue
		if path.begins_with(STATS_PREFIX):
			var key: String = _stat_key(car, path)
			if not _stat_defaults.has(key):
				_stat_defaults[key] = car.get_indexed(path)
		elif not _defaults.has(path):
			_defaults[path] = car.get_indexed(path)


static func _only(car: Car) -> Array[Car]:
	var list: Array[Car] = [car]
	return list


static func _stat_key(car: Car, path: String) -> String:
	return "%s|%s" % [car.stats.resource_path, path]


func setup(own_car: Car, cars: Array[Car]) -> void:
	_car = own_car
	_cars = cars
	_capture_defaults(own_car)


func _get_title() -> String:
	return tr("AJOTUNTUMAN SÄÄTÖ · F1")


func _get_rows() -> Array:
	return PARAMETERS


func _read(path: String) -> float:
	return float(_car.get_indexed(path))


func _write(path: String, value: float) -> void:
	if path.begins_with(STATS_PREFIX):
		# Stats are whole numbers on the 1-10 scale.
		_car.set_indexed(path, roundi(value))
		_save()
		return
	var targets: Array[Car] = _cars if _all_cars else _only(_car)
	for car: Car in targets:
		if is_instance_valid(car):
			car.set_indexed(path, value)
	_overrides[path] = value
	_save()


func _get_default(path: String) -> Variant:
	if path.begins_with(STATS_PREFIX):
		return _stat_defaults.get(_stat_key(_car, path))
	return _defaults.get(path)


func _describe(path: String) -> String:
	if path.begins_with(STATS_PREFIX):
		return "%s %s" % [_car.stats.resource_path.get_file(), path.trim_prefix(STATS_PREFIX)]
	return path


func _copy_header() -> String:
	return "# car.gd / car.tscn"


## Also undo the values on cars left out by "Kaikki autot".
func _after_reset() -> void:
	for path: String in _overrides:
		for car: Car in _cars:
			if is_instance_valid(car):
				car.set_indexed(path, _defaults[path])
	_overrides.clear()
	_save()


func _add_options(row: Container) -> void:
	var all_cars: CheckBox = CheckBox.new()
	all_cars.text = tr("Kaikki autot")
	all_cars.button_pressed = _all_cars
	all_cars.focus_mode = Control.FOCUS_NONE
	all_cars.toggled.connect(_on_all_cars_toggled)
	row.add_child(all_cars)


func _on_all_cars_toggled(enabled: bool) -> void:
	_all_cars = enabled
	# Bring every car in line with the choice right away.
	for path: String in _overrides:
		for car: Car in _cars:
			if is_instance_valid(car) and car != _car:
				car.set_indexed(path, _overrides[path] if enabled else _defaults[path])
	_save()


func _get_telemetry() -> String:
	if not is_instance_valid(_car):
		return ""
	var surface: SurfaceData = _car.get_current_surface()
	return tr("%.0f km/h · huippu %.0f · vaihde %d · luisto %.0f° · %s%s") % [
		_car.get_speed_kmh(), _car.get_top_speed() * 3.6, _car.get_gear(), _car.get_slip_angle(),
		surface.display_name if surface != null else "–",
		"" if _car.is_grounded() else tr(" · ilmassa"),
	]
