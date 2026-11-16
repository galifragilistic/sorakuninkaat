class_name CarTuningPanel
extends PanelContainer
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

@export var panel_width: float = 430.0
@export var margin: float = 12.0
@export var slider_width: float = 140.0
@export var value_width: float = 64.0
@export var font_size: int = 14
@export var background_color: Color = Color(0.04, 0.05, 0.09, 0.9)

## Changed car values (path -> value) for this session, applied to new races.
static var _overrides: Dictionary = {}
## Original car values (path -> value), captured before the first change.
static var _defaults: Dictionary = {}
## Original stats ("resource path|property" -> value).
static var _stat_defaults: Dictionary = {}
## Apply the car values to every car (true) or only the player's (false).
static var _all_cars: bool = true

var _car: Car
var _cars: Array[Car] = []
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _telemetry: Label


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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -panel_width - margin
	offset_right = -margin
	offset_top = margin
	offset_bottom = -margin
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background_color
	style.set_content_margin_all(margin)
	add_theme_stylebox_override("panel", style)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	column.add_child(UiStyle.make_label(tr("AJOTUNTUMAN SÄÄTÖ · F1"), UiStyle.FONT_DISPLAY, font_size + 4))
	_telemetry = UiStyle.make_label("", UiStyle.FONT_MEDIUM, font_size, UiStyle.INFO)
	column.add_child(_telemetry)

	var options: HBoxContainer = HBoxContainer.new()
	column.add_child(options)
	var all_cars: CheckBox = CheckBox.new()
	all_cars.text = tr("Kaikki autot")
	all_cars.button_pressed = _all_cars
	all_cars.focus_mode = Control.FOCUS_NONE
	all_cars.toggled.connect(_on_all_cars_toggled)
	options.add_child(all_cars)
	options.add_child(_make_button(tr("KOPIOI ARVOT"), _copy_values))
	options.add_child(_make_button(tr("PALAUTA"), _reset_values))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for row: Array in PARAMETERS:
		if row[0] == "#":
			rows.add_child(UiStyle.make_caption(tr(row[1])))
		else:
			_add_row(rows, row)


func _make_button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	# Keyboard input keeps driving the car while the panel is open.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _add_row(rows: VBoxContainer, row: Array) -> void:
	var path: String = row[0]
	var line: HBoxContainer = HBoxContainer.new()
	rows.add_child(line)
	var name_label: Label = UiStyle.make_label(tr(row[1]), UiStyle.FONT_MEDIUM, font_size)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	line.add_child(name_label)
	var slider: HSlider = HSlider.new()
	slider.min_value = row[2]
	slider.max_value = row[3]
	slider.step = row[4]
	slider.custom_minimum_size.x = slider_width
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.value = _car.get_indexed(path)
	slider.value_changed.connect(_on_value_changed.bind(path, row[5]))
	line.add_child(slider)
	var value_label: Label = UiStyle.make_label("", UiStyle.FONT_SEMIBOLD, font_size)
	value_label.custom_minimum_size.x = value_width
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value_label)
	_sliders[path] = slider
	_value_labels[path] = value_label
	_show_value(path, slider.value)


func _on_value_changed(value: float, path: String, own_model_only: bool) -> void:
	_apply(path, value, own_model_only)
	if not own_model_only:
		_overrides[path] = value
	_show_value(path, value)


func _apply(path: String, value: float, own_model_only: bool) -> void:
	if path.begins_with(STATS_PREFIX):
		# Stats are whole numbers on the 1-10 scale.
		_car.set_indexed(path, roundi(value))
		return
	var targets: Array[Car] = _cars if _all_cars and not own_model_only else _only(_car)
	for car: Car in targets:
		if is_instance_valid(car):
			car.set_indexed(path, value)


func _show_value(path: String, value: float) -> void:
	var label: Label = _value_labels[path]
	var slider: HSlider = _sliders[path]
	var decimals: int = 0 if slider.step >= 1.0 else (1 if slider.step >= 0.1 else 2)
	label.text = String.num(value, decimals)
	var original: Variant = _get_default(path)
	var changed: bool = original != null and not is_equal_approx(float(original), value)
	label.add_theme_color_override("font_color", UiStyle.ACCENT if changed else UiStyle.TEXT)


func _get_default(path: String) -> Variant:
	if path.begins_with(STATS_PREFIX):
		return _stat_defaults.get(_stat_key(_car, path))
	return _defaults.get(path)


func _on_all_cars_toggled(enabled: bool) -> void:
	_all_cars = enabled
	# Bring every car in line with the choice right away.
	for path: String in _overrides:
		for car: Car in _cars:
			if is_instance_valid(car) and car != _car:
				car.set_indexed(path, _overrides[path] if enabled else _defaults[path])


## Changed values as "property = value" lines, ready to paste.
func _copy_values() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# car.gd / car.tscn")
	for path: String in _sliders:
		var value: float = (_sliders[path] as HSlider).value
		var original: Variant = _get_default(path)
		if original == null or is_equal_approx(float(original), value):
			continue
		if path.begins_with(STATS_PREFIX):
			lines.append("%s %s = %s (oli %s)" % [_car.stats.resource_path.get_file(), path.trim_prefix(STATS_PREFIX), value, original])
		else:
			lines.append("%s = %s (oli %s)" % [path, value, original])
	if lines.size() == 1:
		lines.append("# ei muutoksia")
	DisplayServer.clipboard_set("\n".join(lines))


func _reset_values() -> void:
	for path: String in _sliders:
		var original: Variant = _get_default(path)
		if original == null:
			continue
		var slider: HSlider = _sliders[path]
		slider.set_value_no_signal(float(original))
		var own_model_only: bool = path.begins_with(STATS_PREFIX)
		_apply(path, float(original), own_model_only)
		if not own_model_only:
			# Also undo it on cars left out by "Kaikki autot".
			for car: Car in _cars:
				if is_instance_valid(car):
					car.set_indexed(path, original)
		_show_value(path, float(original))
	_overrides.clear()


func _process(_delta: float) -> void:
	if not is_instance_valid(_car):
		return
	var surface: SurfaceData = _car.get_current_surface()
	_telemetry.text = tr("%.0f km/h · huippu %.0f · vaihde %d · luisto %.0f° · %s%s") % [
		_car.get_speed_kmh(), _car.get_top_speed() * 3.6, _car.get_gear(), _car.get_slip_angle(),
		surface.display_name if surface != null else "–",
		"" if _car.is_grounded() else tr(" · ilmassa"),
	]
