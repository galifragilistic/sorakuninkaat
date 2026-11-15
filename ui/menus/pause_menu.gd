class_name PauseMenu
extends Control
## Pause overlay (SPEC.md section 5): continue, restart, settings, quit race.
## Runs while the tree is paused.

signal resume_requested
signal restart_requested
signal quit_requested

@export var panel_width: float = 380.0
## Network clients cannot restart the race for everybody.
@export var show_restart: bool = true
## Optional line under the title, e.g. that a network race keeps running.
@export var note: String = ""
@export var button_height: float = 52.0

var _buttons: VBoxContainer
var _settings_view: VBoxContainer
var _settings: SettingsPanel
var _first_button: ChamferButton
var _settings_button: ChamferButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(MenuKit.make_blur_backdrop())

	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(26.0, 22.0, 26.0, 26.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size.x = panel_width
	add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(16)
	panel.add_child(column)
	column.add_child(UiStyle.make_label(tr("TAUKO"), UiStyle.title_font(), MenuKit.TITLE_FONT_SIZE))
	if not note.is_empty():
		var note_label: Label = UiStyle.make_label(note, UiStyle.FONT_MEDIUM, 14, UiStyle.WARNING)
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(note_label)

	_buttons = MenuKit.make_vbox(8)
	column.add_child(_buttons)
	_first_button = _add_button(_buttons, tr("JATKA"))
	_first_button.pressed.connect(func() -> void: resume_requested.emit())
	if show_restart:
		_add_button(_buttons, tr("ALOITA ALUSTA")).pressed.connect(func() -> void: restart_requested.emit())
	_settings_button = _add_button(_buttons, tr("ASETUKSET"))
	_settings_button.pressed.connect(_show_settings.bind(true))
	_add_button(_buttons, tr("LOPETA KISA")).pressed.connect(func() -> void: quit_requested.emit())

	_settings_view = MenuKit.make_vbox(12)
	_settings_view.visible = false
	column.add_child(_settings_view)
	_settings = SettingsPanel.new()
	_settings_view.add_child(_settings)
	_add_button(_settings_view, tr("TAKAISIN")).pressed.connect(_show_settings.bind(false))

	MenuKit.add_hints(self, [[InputPrompts.Prompt.ACCEPT, tr("Valitse")], [InputPrompts.Prompt.BACK, tr("Jatka")]])
	_first_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed(InputManager.ACTION_PAUSE):
		get_viewport().set_input_as_handled()
		if _settings_view.visible:
			_show_settings(false)
		else:
			resume_requested.emit()


func _add_button(parent: VBoxContainer, text: String) -> ChamferButton:
	var button: ChamferButton = ChamferButton.create(text, 19, Vector4(20.0, 0.0, 20.0, 0.0))
	button.custom_minimum_size.y = button_height
	parent.add_child(button)
	return button


func _show_settings(show_settings: bool) -> void:
	_buttons.visible = not show_settings
	_settings_view.visible = show_settings
	if show_settings:
		_settings.get_first_control().grab_focus()
	else:
		_settings_button.grab_focus()
