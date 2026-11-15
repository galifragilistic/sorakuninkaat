class_name ChamferButton
extends ChamferPanel
## Focusable chamfered button. The focused element is drawn fully in the accent
## colour (SPEC.md section 6: "valittu tila = täysi väri"). A button can also be
## "selected" (the chosen tab, filter or option), shown in its selected colour.

signal pressed
signal focused

const UI_SOUND_DB: float = -14.0

## Fill while the button holds focus.
@export var accent_color: Color = UiStyle.ACCENT
## Fill while selected but not focused.
@export var selected_color: Color = UiStyle.INFO
@export var normal_color: Color = UiStyle.BUTTON
## Call-to-action look: tinted and outlined in the accent colour even without focus.
@export var primary: bool = false:
	set(value):
		primary = value
		_update_style()
## For large cards: focus is shown as an accent outline and tint instead of a
## solid fill, so the card's contents stay readable.
@export var outline_focus: bool = false:
	set(value):
		outline_focus = value
		_update_style()
@export_range(0.0, 1.0, 0.01) var tint_strength: float = 0.2
@export var outline_width: float = 3.0

var selected: bool = false:
	set(value):
		selected = value
		_update_style()
var disabled: bool = false:
	set(value):
		disabled = value
		focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
		_update_style()

## Layout box for the button's contents; add extra labels or glyphs here.
var row: HBoxContainer
var label: Label

var _labels: Array[Label] = []
var _secondary_labels: Array[Label] = []
var _glyphs: Array[UiGlyph] = []


## Standard text button.
static func create(text: String, font_size: int = 18, padding: Vector4 = Vector4(20.0, 10.0, 20.0, 10.0)) -> ChamferButton:
	var button: ChamferButton = ChamferButton.new()
	button.set_padding(padding)
	button.label = UiStyle.make_label(text, UiStyle.FONT_DISPLAY, font_size)
	button.label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.row.add_child(button.label)
	button.register_label(button.label)
	return button


func _init() -> void:
	super._init()
	chamfer = 10.0
	border_width = 0.0
	blur_amount = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	focus_entered.connect(_on_focus_changed)
	focus_exited.connect(_on_focus_changed)
	mouse_entered.connect(_on_mouse_entered)
	_update_style()


## Labels registered here follow the button's state colours.
func register_label(text_label: Label, secondary: bool = false) -> void:
	if secondary:
		_secondary_labels.append(text_label)
	else:
		_labels.append(text_label)
	_update_style()


func register_glyph(glyph: UiGlyph) -> void:
	_glyphs.append(glyph)
	_update_style()


## Adds a right-aligned secondary label (e.g. "LUOKKA B").
func add_right_label(text: String, font: Font, font_size: int) -> Label:
	var right: Label = UiStyle.make_label(text, font, font_size, UiStyle.TEXT_SECONDARY)
	row.add_child(right)
	register_label(right, true)
	return right


func add_glyph(kind: UiGlyph.Kind, glyph_size: float = 28.0) -> UiGlyph:
	var glyph: UiGlyph = UiGlyph.create(kind, "", glyph_size)
	row.add_child(glyph)
	register_glyph(glyph)
	return glyph


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	var clicked: bool = mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	if clicked or event.is_action_pressed("ui_accept"):
		accept_event()
		SoundBank.play(self, SoundBank.Sound.UI_ACCEPT, UI_SOUND_DB)
		pressed.emit()


func _on_mouse_entered() -> void:
	if not disabled:
		grab_focus()


func _on_focus_changed() -> void:
	_update_style()
	if has_focus():
		SoundBank.play(self, SoundBank.Sound.UI_MOVE, UI_SOUND_DB)
		focused.emit()


func _update_style() -> void:
	if row == null:
		return
	var has_fill: bool = false
	var tinted: Color = normal_color.lerp(Color(accent_color, normal_color.a), tint_strength)
	border_width = 0.0
	if disabled:
		fill_color = Color(normal_color, normal_color.a * 0.55)
	elif has_focus() and outline_focus:
		fill_color = tinted
		border_width = outline_width
		border_color = accent_color
	elif has_focus():
		fill_color = accent_color
		has_fill = true
	elif selected:
		fill_color = selected_color
		has_fill = true
	elif primary:
		fill_color = tinted
		border_width = outline_width - 1.0
		border_color = accent_color
	else:
		fill_color = normal_color
	if outline_focus and border_width == 0.0:
		# Cards keep the standard thin panel border when idle.
		border_width = 2.0
		border_color = UiStyle.LINE

	var text_color: Color = UiStyle.TEXT
	var secondary_color: Color = UiStyle.TEXT_SECONDARY
	if disabled:
		text_color = UiStyle.TEXT_DISABLED
		secondary_color = UiStyle.TEXT_DISABLED
	elif has_fill:
		text_color = UiStyle.TEXT_ON_ACCENT
		secondary_color = UiStyle.TEXT_ON_ACCENT
	elif primary:
		text_color = accent_color
	for text_label: Label in _labels:
		text_label.add_theme_color_override("font_color", text_color)
	for text_label: Label in _secondary_labels:
		text_label.add_theme_color_override("font_color", secondary_color)
	for glyph: UiGlyph in _glyphs:
		glyph.color = text_color
