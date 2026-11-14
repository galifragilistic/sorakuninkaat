class_name OptionSpinner
extends HBoxContainer
## "Label  < value >" row. Focus it and press left/right to change the value;
## clicking the arrows works too (mockups/02_Moninpeli.png).

signal value_changed(index: int)

@export var arrow_size: float = 40.0
@export var value_width: float = 150.0

var options: PackedStringArray = PackedStringArray()
var index: int = 0:
	set(value):
		index = clampi(value, 0, maxi(0, options.size() - 1))
		_update_value()

var _value_label: Label
var _title_label: Label
var _arrows: Array[ChamferPanel] = []
var _glyphs: Array[UiGlyph] = []


static func create(title: String, option_texts: PackedStringArray, start_index: int) -> OptionSpinner:
	var spinner: OptionSpinner = OptionSpinner.new()
	spinner._title_label.text = title
	spinner.options = option_texts
	spinner.index = start_index
	return spinner


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_constant_override("separation", 0)
	_title_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 16, UiStyle.TEXT_SECONDARY)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_title_label)
	_add_arrow(UiGlyph.Kind.CHEVRON_LEFT)
	_value_label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 17)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.custom_minimum_size.x = value_width
	add_child(_value_label)
	_add_arrow(UiGlyph.Kind.CHEVRON_RIGHT)
	focus_entered.connect(_update_style)
	focus_exited.connect(_update_style)
	mouse_entered.connect(grab_focus)
	_update_style()


func step(direction: int) -> void:
	if options.size() < 2:
		return
	index = wrapi(index + direction, 0, options.size())
	value_changed.emit(index)


func _add_arrow(kind: UiGlyph.Kind) -> void:
	var box: ChamferPanel = ChamferPanel.create_chip(UiStyle.BUTTON, 8.0, Vector4.ZERO)
	box.custom_minimum_size = Vector2.ONE * arrow_size
	var glyph: UiGlyph = UiGlyph.create(kind, "", arrow_size)
	box.add_child(glyph)
	add_child(box)
	_arrows.append(box)
	_glyphs.append(glyph)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		accept_event()
		step(-1)
	elif event.is_action_pressed("ui_right", true) or event.is_action_pressed("ui_accept"):
		accept_event()
		step(1)
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		# The left arrow box steps back; anywhere else steps forward.
		var left_box: Rect2 = _arrows[0].get_rect()
		step(-1 if left_box.has_point(mouse.position) else 1)


func _update_value() -> void:
	if _value_label != null:
		_value_label.text = options[index] if index < options.size() else ""
	_update_style()


func _update_style() -> void:
	if _value_label == null:
		return
	var active: bool = has_focus()
	var can_change: bool = options.size() > 1
	_title_label.add_theme_color_override("font_color", UiStyle.TEXT if active else UiStyle.TEXT_SECONDARY)
	for i: int in _arrows.size():
		_arrows[i].fill_color = UiStyle.ACCENT if active and can_change else UiStyle.BUTTON
		var glyph_color: Color = UiStyle.TEXT_ON_ACCENT if active else UiStyle.TEXT
		_glyphs[i].color = glyph_color if can_change else UiStyle.TEXT_DISABLED
