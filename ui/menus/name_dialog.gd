class_name NameDialog
extends Control
## Name entry shown over a menu screen. Type on a physical keyboard, or pick
## letters from the on-screen keys with a gamepad, so the menus stay fully
## usable without a keyboard (SPEC.md section 5).

signal confirmed(player_name: String)
signal cancelled

## On-screen key rows. The last row (space, delete, done) is added separately.
const KEY_ROWS: Array[String] = ["1234567890", "QWERTYUIOPÅ", "ASDFGHJKLÖÄ", "ZXCVBNM-_."]
const CURSOR: String = "_"

@export var key_size: Vector2 = Vector2(46.0, 44.0)
@export var key_gap: int = 6
@export var key_font_size: int = 18
@export var field_font_size: int = 30
@export var cursor_blink_seconds: float = 0.5
@export var hint_glyph_size: float = 28.0

var text: String = ""

var _title: String = ""
var _field_label: Label
var _counter_label: Label
var _rows: Array = []
var _keyboard_hints: HBoxContainer
var _gamepad_hints: HBoxContainer
var _blink_time: float = 0.0
var _cursor_on: bool = true


## title names whose name this is, e.g. "PELAAJA 2".
static func create(title: String, start_text: String) -> NameDialog:
	var dialog: NameDialog = NameDialog.new()
	dialog._title = title
	dialog.text = start_text
	return dialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuKit.make_blur_backdrop())

	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(30.0, 24.0, 30.0, 24.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(14)
	panel.add_child(column)

	var header: HBoxContainer = MenuKit.make_hbox(16)
	column.add_child(header)
	header.add_child(UiStyle.make_label(tr("NIMI"), UiStyle.title_font(), 34))
	var subtitle: Label = UiStyle.make_caption(_title)
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(subtitle)

	var field: ChamferPanel = ChamferPanel.create_chip(UiStyle.BUTTON, 8.0, Vector4(18.0, 8.0, 18.0, 8.0))
	field.border_width = 2.0
	field.border_color = UiStyle.ACCENT
	column.add_child(field)
	var field_row: HBoxContainer = MenuKit.make_hbox(10)
	field.add_child(field_row)
	_field_label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, field_font_size)
	_field_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_row.add_child(_field_label)
	_counter_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 14, UiStyle.TEXT_SECONDARY)
	_counter_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	field_row.add_child(_counter_label)

	_build_keys(column)
	_build_hints(column)
	_wire_focus()
	InputManager.prompt_style_changed.connect(_on_prompt_style_changed)
	_update_hints()
	_update_field()
	(_rows[1][0] as Control).grab_focus.call_deferred()


func _exit_tree() -> void:
	InputManager.prompt_style_changed.disconnect(_on_prompt_style_changed)


func _process(delta: float) -> void:
	_blink_time += delta
	if _blink_time >= cursor_blink_seconds:
		_blink_time = 0.0
		_cursor_on = not _cursor_on
		_update_field()


## Physical keyboard: characters are typed straight in, arrow keys still move
## between the on-screen keys. Runs before the GUI so letters bound to menu
## actions (W A S D, X) type instead of navigating.
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_confirm()
		KEY_ESCAPE:
			cancelled.emit()
		KEY_BACKSPACE:
			_backspace()
		_:
			if key.unicode < 32:
				return
			_type(char(key.unicode))
	get_viewport().set_input_as_handled()


## Gamepad: A presses the focused key (handled by the button), X deletes,
## START confirms, B cancels.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		cancelled.emit()
	elif event.is_action_pressed(InputManager.ACTION_SECONDARY, true):
		_backspace()
	elif event.is_action_pressed(InputManager.ACTION_START):
		_confirm()
	else:
		return
	get_viewport().set_input_as_handled()


func _build_keys(column: VBoxContainer) -> void:
	var keys: VBoxContainer = MenuKit.make_vbox(key_gap)
	column.add_child(keys)
	for row_text: String in KEY_ROWS:
		var row: Array[ChamferButton] = []
		var box: HBoxContainer = MenuKit.make_hbox(key_gap)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		keys.add_child(box)
		for character: String in row_text:
			var key: ChamferButton = _make_key(character, key_size.x)
			key.pressed.connect(_type.bind(character))
			box.add_child(key)
			row.append(key)
		_rows.append(row)

	var last: Array[ChamferButton] = []
	var bottom: HBoxContainer = MenuKit.make_hbox(key_gap)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.add_child(bottom)
	var space: ChamferButton = _make_key(tr("Välilyönti"), key_size.x * 4.0)
	space.pressed.connect(_type.bind(" "))
	var delete: ChamferButton = _make_key(tr("Poista"), key_size.x * 2.5)
	delete.pressed.connect(_backspace)
	var done: ChamferButton = _make_key(tr("Valmis"), key_size.x * 2.5)
	done.primary = true
	done.pressed.connect(_confirm)
	for key: ChamferButton in [space, delete, done]:
		bottom.add_child(key)
		last.append(key)
	_rows.append(last)


func _make_key(label: String, width: float) -> ChamferButton:
	var key: ChamferButton = ChamferButton.create(label, key_font_size, Vector4.ZERO)
	key.chamfer = 6.0
	key.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.custom_minimum_size = Vector2(width, key_size.y)
	return key


## Explicit neighbours for every key, wrapping at the edges, so gamepad focus
## never leaves the dialog for the screen underneath.
func _wire_focus() -> void:
	var row_count: int = _rows.size()
	for r: int in row_count:
		var row: Array = _rows[r]
		for c: int in row.size():
			var key: ChamferButton = row[c]
			var left: ChamferButton = row[posmod(c - 1, row.size())]
			var right: ChamferButton = row[posmod(c + 1, row.size())]
			var up: ChamferButton = _column_match(_rows[posmod(r - 1, row_count)], c, row.size())
			var down: ChamferButton = _column_match(_rows[posmod(r + 1, row_count)], c, row.size())
			key.focus_neighbor_left = key.get_path_to(left)
			key.focus_neighbor_right = key.get_path_to(right)
			key.focus_neighbor_top = key.get_path_to(up)
			key.focus_neighbor_bottom = key.get_path_to(down)
			key.focus_next = key.get_path_to(right)
			key.focus_previous = key.get_path_to(left)


## The key in another row at the same relative position.
func _column_match(row: Array, column: int, row_length: int) -> ChamferButton:
	var share: float = float(column) / float(maxi(row_length - 1, 1))
	return row[roundi(share * float(row.size() - 1))]


func _build_hints(column: VBoxContainer) -> void:
	_keyboard_hints = MenuKit.make_hbox(22)
	column.add_child(_keyboard_hints)
	_keyboard_hints.add_child(UiStyle.make_label(tr("Kirjoita nimi näppäimistöllä"), UiStyle.FONT_MEDIUM, 15, UiStyle.TEXT_SECONDARY))
	_add_hint(_keyboard_hints, UiGlyph.Kind.KEY, "Enter", tr("Valmis"))
	_add_hint(_keyboard_hints, UiGlyph.Kind.KEY, "Esc", tr("Peruuta"))

	_gamepad_hints = MenuKit.make_hbox(22)
	column.add_child(_gamepad_hints)
	_add_hint(_gamepad_hints, UiGlyph.Kind.BUTTON, "A", tr("Valitse"))
	_add_hint(_gamepad_hints, UiGlyph.Kind.BUTTON, "X", tr("Poista"))
	_add_hint(_gamepad_hints, UiGlyph.Kind.BUTTON, "START", tr("Valmis"))
	_add_hint(_gamepad_hints, UiGlyph.Kind.BUTTON, "B", tr("Peruuta"))


func _add_hint(row: HBoxContainer, kind: UiGlyph.Kind, glyph_text: String, text_label: String) -> void:
	var hint: HBoxContainer = MenuKit.make_hbox(9)
	var glyph: UiGlyph = UiGlyph.create(kind, "", hint_glyph_size)
	glyph.text = glyph_text
	hint.add_child(glyph)
	hint.add_child(UiStyle.make_label(text_label, UiStyle.FONT_MEDIUM, 15, UiStyle.TEXT_SECONDARY))
	row.add_child(hint)


func _on_prompt_style_changed(_style: InputManager.PromptStyle) -> void:
	_update_hints()


func _update_hints() -> void:
	var keyboard: bool = InputPrompts.is_keyboard()
	_keyboard_hints.visible = keyboard
	_gamepad_hints.visible = not keyboard


func _type(character: String) -> void:
	if text.length() >= GameState.MAX_NAME_LENGTH:
		return
	# No leading spaces; the name is trimmed anyway.
	if character == " " and text.is_empty():
		return
	text += character
	_restart_blink()


func _backspace() -> void:
	text = text.left(maxi(text.length() - 1, 0))
	_restart_blink()


func _confirm() -> void:
	confirmed.emit(GameState.sanitize_name(text))


func _restart_blink() -> void:
	_blink_time = 0.0
	_cursor_on = true
	_update_field()


func _update_field() -> void:
	var full: bool = text.length() >= GameState.MAX_NAME_LENGTH
	_field_label.text = text + (CURSOR if _cursor_on and not full else "")
	_counter_label.text = "%d/%d" % [text.length(), GameState.MAX_NAME_LENGTH]
