class_name ConfirmDialog
extends Control
## Yes / no question shown over a menu screen. Focus starts on the safe
## answer, and Esc / B answers no.

signal confirmed
signal cancelled

@export var panel_width: float = 420.0
@export var button_height: float = 52.0

var _title: String = ""
var _message: String = ""
var _confirm_text: String = ""


static func create(title: String, message: String, confirm_text: String) -> ConfirmDialog:
	var dialog: ConfirmDialog = ConfirmDialog.new()
	dialog._title = title
	dialog._message = message
	dialog._confirm_text = confirm_text
	return dialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuKit.make_blur_backdrop())

	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(26.0, 22.0, 26.0, 26.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size.x = panel_width
	add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(16)
	panel.add_child(column)
	column.add_child(UiStyle.make_label(_title, UiStyle.title_font(), 34))
	var message: Label = UiStyle.make_label(_message, UiStyle.FONT_MEDIUM, 16, UiStyle.TEXT_SECONDARY)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)

	var row: HBoxContainer = MenuKit.make_hbox(10)
	column.add_child(row)
	var cancel: ChamferButton = _add_button(row, tr("PERUUTA"))
	cancel.pressed.connect(func() -> void: cancelled.emit())
	var confirm: ChamferButton = _add_button(row, _confirm_text)
	confirm.primary = true
	confirm.pressed.connect(func() -> void: confirmed.emit())
	_link(cancel, confirm)
	_link(confirm, cancel)
	cancel.grab_focus()


## Focus never leaves the dialog for the screen underneath.
func _link(button: ChamferButton, other: ChamferButton) -> void:
	var to_other: NodePath = button.get_path_to(other)
	var to_self: NodePath = button.get_path_to(button)
	button.focus_neighbor_left = to_other
	button.focus_neighbor_right = to_other
	button.focus_next = to_other
	button.focus_previous = to_other
	button.focus_neighbor_top = to_self
	button.focus_neighbor_bottom = to_self


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()


func _add_button(parent: HBoxContainer, text: String) -> ChamferButton:
	var button: ChamferButton = ChamferButton.create(text, 19, Vector4(20.0, 0.0, 20.0, 0.0))
	button.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size.y = button_height
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button
