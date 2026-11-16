class_name TuningPanel
extends PanelContainer
## Base for the debug tuning panels: a scrolling column of labelled sliders
## over the right edge of the screen, with KOPIOI ARVOT (changed values to the
## clipboard) and PALAUTA (back to the original values). Subclasses give the
## rows and read and write the values. Nothing takes keyboard focus, so the
## game keeps its controls while a panel is open.

@export var panel_width: float = 430.0
@export var margin: float = 12.0
@export var slider_width: float = 140.0
@export var value_width: float = 64.0
@export var font_size: int = 14
@export var background_color: Color = Color(0.04, 0.05, 0.09, 0.9)

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _telemetry: Label


# --- Overridables ----------------------------------------------------------

func _get_title() -> String:
	return ""


## Rows: a group caption ["#", caption] or [key, label, min, max, step, ...].
func _get_rows() -> Array:
	return []


func _read(_key: String) -> float:
	return 0.0


func _write(_key: String, _value: float) -> void:
	pass


## The value before any tuning, or null if it is not known.
func _get_default(_key: String) -> Variant:
	return null


## How a key is written in the copied text.
func _describe(key: String) -> String:
	return key


## First line of the copied text, e.g. which file the values belong to.
func _copy_header() -> String:
	return ""


## Called once every slider is back at its original value.
func _after_reset() -> void:
	pass


## Extra controls in the button area (before the copy and reset buttons).
func _add_options(_row: Container) -> void:
	pass


## Live info under the title; empty hides the line.
func _get_telemetry() -> String:
	return ""


# --- Panel -------------------------------------------------------------------

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
	column.add_child(UiStyle.make_label(_get_title(), UiStyle.FONT_DISPLAY, font_size + 4))
	_telemetry = UiStyle.make_label("", UiStyle.FONT_MEDIUM, font_size, UiStyle.INFO)
	_telemetry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_telemetry)

	# Buttons wrap onto more lines rather than widening the panel.
	var options: HFlowContainer = HFlowContainer.new()
	column.add_child(options)
	_add_options(options)
	options.add_child(_make_button(tr("KOPIOI ARVOT"), _copy_values))
	options.add_child(_make_button(tr("PALAUTA"), _reset_values))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for row_spec: Array in _get_rows():
		if row_spec[0] == "#":
			rows.add_child(UiStyle.make_caption(tr(row_spec[1])))
		else:
			_add_row(rows, row_spec)


func _make_button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	# Keyboard input keeps driving the car while the panel is open.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _add_row(rows: VBoxContainer, row: Array) -> void:
	var key: String = row[0]
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
	slider.value = _read(key)
	slider.value_changed.connect(_on_value_changed.bind(key))
	line.add_child(slider)
	var value_label: Label = UiStyle.make_label("", UiStyle.FONT_SEMIBOLD, font_size)
	value_label.custom_minimum_size.x = value_width
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value_label)
	_sliders[key] = slider
	_value_labels[key] = value_label
	_show_value(key, slider.value)


func _on_value_changed(value: float, key: String) -> void:
	_write(key, value)
	_show_value(key, value)


func _show_value(key: String, value: float) -> void:
	var label: Label = _value_labels[key]
	var slider: HSlider = _sliders[key]
	var decimals: int = 0 if slider.step >= 1.0 else (1 if slider.step >= 0.1 else 2)
	label.text = String.num(value, decimals)
	var original: Variant = _get_default(key)
	var changed: bool = original != null and not is_equal_approx(float(original), value)
	label.add_theme_color_override("font_color", UiStyle.ACCENT if changed else UiStyle.TEXT)


## Changed values as "name = value (oli old)" lines, ready to paste.
func _copy_values() -> void:
	var lines: PackedStringArray = PackedStringArray([_copy_header()])
	for key: String in _sliders:
		var value: float = (_sliders[key] as HSlider).value
		var original: Variant = _get_default(key)
		if original == null or is_equal_approx(float(original), value):
			continue
		lines.append("%s = %s (oli %s)" % [_describe(key), value, original])
	if lines.size() == 1:
		lines.append("# ei muutoksia")
	DisplayServer.clipboard_set("\n".join(lines))


func _reset_values() -> void:
	for key: String in _sliders:
		var original: Variant = _get_default(key)
		if original == null:
			continue
		(_sliders[key] as HSlider).set_value_no_signal(float(original))
		_write(key, float(original))
		_show_value(key, float(original))
	_after_reset()


func _process(_delta: float) -> void:
	var text: String = _get_telemetry()
	_telemetry.visible = not text.is_empty()
	_telemetry.text = text
