extends MenuScreen
## Track editor: draw a closed road on the map, set road heights for hills and
## bridges, mark bridges, tunnels and jumps, then save the track or take it
## for a test drive. The design open here is kept as a draft between visits.

@export_group("Layout")
@export var map_rect: Rect2 = Rect2(56.0, 96.0, 820.0, 468.0)
@export var profile_gap: float = 10.0
@export var profile_height: float = 92.0
@export var panel_position: Vector2 = Vector2(896.0, 96.0)
@export var panel_width: float = 328.0
## Vertical gap between the rows of the side panel.
@export var panel_gap: int = 3
@export var spinner_value_width: float = 108.0
@export var open_list_size: Vector2 = Vector2(460.0, 360.0)
@export var help_font_size: int = 13
## KIERRÄ turns the selected object by this many rotation steps.
@export var prop_rotate_steps: int = 3
## Seconds a status message stays on screen.
@export var status_seconds: float = 3.0
@export_group("Undo")
## Most changes kept for undo.
@export var undo_limit: int = 100
## Changes this close together (s) undo as one, e.g. a turn of the mouse wheel.
@export var undo_merge_seconds: float = 0.4

const FEATURE_NAMES: Array[String] = ["Ei mitään", "Silta", "Tunneli", "Hyppyri"]

var _design: TrackDesign
var _canvas: TrackEditorCanvas
var _profile: TrackProfile
var _name_button: ChamferButton
var _theme_spinner: OptionSpinner
var _width_spinner: OptionSpinner
var _point_caption: Label
var _height_spinner: OptionSpinner
var _feature_spinner: OptionSpinner
var _span_spinner: OptionSpinner
var _start_button: ChamferButton
var _delete_button: ChamferButton
var _status_label: Label
var _status_time: float = 0.0
var _name_dialog: NameDialog
## Run after the name dialog is confirmed (saving needs a name first).
var _after_naming: Callable = Callable()
var _open_overlay: Control
var _delete_armed: String = ""
var _road_button: ChamferButton
var _props_button: ChamferButton
var _point_section: VBoxContainer
var _prop_section: VBoxContainer
var _prop_caption: Label
var _kind_spinner: OptionSpinner
var _forest_spinner: OptionSpinner
var _prop_buttons: Array[ChamferButton] = []
var _help_label: Label
var _area_spinner: OptionSpinner
var _surface_spinner: OptionSpinner
## Design snapshots (TrackDesign.to_dict()) to go back and forward to.
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
## Snapshot of the design as it is now.
var _current_snapshot: Dictionary = {}
var _last_change_msec: int = -1
var _undo_button: ChamferButton
var _redo_button: ChamferButton


func get_backdrop() -> Backdrop:
	return Backdrop.HIDDEN


func _build() -> void:
	MenuKit.add_header(self, tr("RATAEDITORI"))
	_build_map()
	_build_panel()
	MenuKit.add_hints(self, [
		[InputPrompts.Prompt.TABS, tr("Vaihda valintaa")], [InputPrompts.Prompt.BACK, tr("Takaisin")],
	])


func _enter() -> void:
	GameState.test_drive = false
	var design: TrackDesign = CustomTracks.load_draft()
	_set_design(design if design != null else TrackDesign.create_default())


func _get_initial_focus() -> Control:
	return _theme_spinner


func _process(delta: float) -> void:
	if _status_time > 0.0:
		_status_time -= delta
		if _status_time <= 0.0:
			_status_label.text = ""


# --- Building ------------------------------------------------------------

func _build_map() -> void:
	_canvas = TrackEditorCanvas.new()
	_canvas.position = map_rect.position
	_canvas.size = map_rect.size
	add_child(_canvas)
	_canvas.selection_changed.connect(_on_selection_changed)
	_canvas.prop_selection_changed.connect(_on_prop_selection_changed.unbind(1))
	_canvas.design_changed.connect(_on_design_changed)

	var help: Label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, help_font_size, UiStyle.TEXT_SECONDARY)
	_help_label = help
	help.position = Vector2(10.0, 8.0)
	help.size.x = map_rect.size.x - 20.0
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(help)

	_status_label = UiStyle.make_label("", UiStyle.FONT_SEMIBOLD, 16, UiStyle.WARNING)
	_status_label.position = Vector2(10.0, map_rect.size.y - 30.0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_status_label)

	_profile = TrackProfile.new()
	_profile.canvas = _canvas
	_profile.position = Vector2(map_rect.position.x, map_rect.end.y + profile_gap)
	_profile.size = Vector2(map_rect.size.x, profile_height)
	add_child(_profile)
	_profile.point_picked.connect(func(index: int) -> void: _canvas.select(index))


func _build_panel() -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(14.0, 12.0, 14.0, 14.0))
	panel.position = panel_position
	panel.custom_minimum_size.x = panel_width
	add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(panel_gap)
	panel.add_child(column)

	var mode_row: HBoxContainer = MenuKit.make_hbox(6)
	column.add_child(mode_row)
	_road_button = _add_button(mode_row, tr("TIE"), _set_mode.bind(TrackEditorCanvas.Mode.ROAD))
	_props_button = _add_button(mode_row, tr("ESINEET"), _set_mode.bind(TrackEditorCanvas.Mode.PROPS))

	_name_button = ChamferButton.create("", 17, Vector4(14.0, 8.0, 14.0, 8.0))
	_name_button.add_glyph(UiGlyph.Kind.CHEVRON_RIGHT)
	_name_button.pressed.connect(_open_name_dialog.bind(Callable()))
	column.add_child(_name_button)

	var theme_names: PackedStringArray = PackedStringArray()
	for theme: TrackTheme in TrackDesign.THEMES:
		theme_names.append(tr(theme.display_name))
	_theme_spinner = _add_spinner(column, tr("Maasto"), theme_names)
	_theme_spinner.value_changed.connect(func(index: int) -> void:
		_design.theme_index = index
		_on_design_changed())
	var widths: PackedStringArray = PackedStringArray()
	for width: int in range(int(TrackDesign.ROAD_WIDTH_RANGE.x), int(TrackDesign.ROAD_WIDTH_RANGE.y) + 1):
		widths.append(tr("%d m") % width)
	_width_spinner = _add_spinner(column, tr("Tien leveys"), widths)
	_width_spinner.value_changed.connect(func(index: int) -> void:
		_design.road_width = TrackDesign.ROAD_WIDTH_RANGE.x + float(index)
		_canvas.refresh()
		_on_design_changed())
	var areas: PackedStringArray = PackedStringArray()
	for i: int in TrackDesign.AREA_SIZES.size():
		var area_size: Vector2 = TrackDesign.AREA_SIZES[i] * 2.0
		areas.append(tr("%s %d×%d") % [tr(TrackDesign.AREA_NAMES[i]), roundi(area_size.x), roundi(area_size.y)])
	_area_spinner = _add_spinner(column, tr("Kartta"), areas)
	_area_spinner.value_changed.connect(_on_area_picked)

	_build_prop_section(column)
	# Point controls; swapped for the object controls in object mode.
	_point_section = MenuKit.make_vbox(panel_gap)
	column.add_child(_point_section)
	column = _point_section
	_point_caption = UiStyle.make_caption("")
	column.add_child(_point_caption)
	var heights: PackedStringArray = PackedStringArray()
	for i: int in _height_count():
		heights.append(tr("%+.1f m") % _height_at(i))
	_height_spinner = _add_spinner(column, tr("Korkeus"), heights)
	_height_spinner.value_changed.connect(_on_height_picked)
	var surface_names: PackedStringArray = PackedStringArray([tr("Maaston mukaan")])
	for surface: SurfaceData in TrackDesign.ROAD_SURFACES:
		surface_names.append(tr(surface.display_name))
	_surface_spinner = _add_spinner(column, tr("Pinta"), surface_names)
	_surface_spinner.value_changed.connect(func(index: int) -> void:
		_design.surfaces[_canvas.selected] = index
		_canvas.refresh()
		_on_design_changed())
	var features: PackedStringArray = PackedStringArray()
	for feature: String in FEATURE_NAMES:
		features.append(tr(feature))
	_feature_spinner = _add_spinner(column, tr("Kohde"), features)
	_feature_spinner.value_changed.connect(_on_feature_picked)
	var spans: PackedStringArray = PackedStringArray()
	for i: int in _span_count():
		spans.append(tr("%d m") % roundi(_span_at(i)))
	_span_spinner = _add_spinner(column, tr("Pituus"), spans)
	_span_spinner.value_changed.connect(func(index: int) -> void:
		_design.spans[_canvas.selected] = _span_at(index)
		_canvas.refresh()
		_on_design_changed())

	var point_row: HBoxContainer = MenuKit.make_hbox(6)
	column.add_child(point_row)
	_start_button = _add_button(point_row, tr("LÄHTÖ TÄHÄN"), _on_set_start)
	_add_button(point_row, tr("KÄÄNNÄ"), _on_reverse)
	_delete_button = _add_button(point_row, tr("POISTA"), func() -> void: _canvas.remove_point(_canvas.selected))

	column = _point_section.get_parent() as VBoxContainer
	var file_row: HBoxContainer = MenuKit.make_hbox(6)
	column.add_child(file_row)
	_add_button(file_row, tr("UUSI"), _on_new)
	_add_button(file_row, tr("AVAA"), _show_open_list)
	_add_button(file_row, tr("TALLENNA"), _on_save)
	var history_row: HBoxContainer = MenuKit.make_hbox(6)
	column.add_child(history_row)
	_undo_button = _add_button(history_row, tr("KUMOA"), _undo)
	_redo_button = _add_button(history_row, tr("TOISTA"), _redo)

	var drive: ChamferButton = ChamferButton.create(tr("KOEAJA"), 20, Vector4(20.0, 0.0, 16.0, 0.0))
	drive.primary = true
	drive.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drive.add_glyph(UiGlyph.Kind.CHEVRON_RIGHT)
	drive.custom_minimum_size.y = 50.0
	drive.pressed.connect(_on_test_drive)
	column.add_child(drive)


func _build_prop_section(column: VBoxContainer) -> void:
	_prop_section = MenuKit.make_vbox(panel_gap)
	column.add_child(_prop_section)
	_prop_caption = UiStyle.make_caption("")
	_prop_section.add_child(_prop_caption)
	var kinds: PackedStringArray = PackedStringArray()
	for prop_name: String in TrackDesign.PROP_NAMES:
		kinds.append(tr(prop_name))
	_kind_spinner = _add_spinner(_prop_section, tr("Esine"), kinds)
	_kind_spinner.value_changed.connect(func(index: int) -> void: _canvas.prop_kind = index)
	var forests: PackedStringArray = PackedStringArray()
	for forest_name: String in TrackDesign.FOREST_NAMES:
		forests.append(tr(forest_name))
	_forest_spinner = _add_spinner(_prop_section, tr("Puusto"), forests)
	_forest_spinner.value_changed.connect(func(index: int) -> void:
		_design.forest = index
		_on_design_changed())
	var row: HBoxContainer = MenuKit.make_hbox(6)
	_prop_section.add_child(row)
	_prop_buttons.append(_add_button(row, tr("KIERRÄ"), func() -> void:
		_canvas.rotate_prop(_canvas.selected_prop, prop_rotate_steps)))
	_prop_buttons.append(_add_button(row, tr("POISTA"), func() -> void:
		_canvas.remove_prop(_canvas.selected_prop)))


func _set_mode(mode: TrackEditorCanvas.Mode) -> void:
	_canvas.mode = mode
	var props: bool = mode == TrackEditorCanvas.Mode.PROPS
	_road_button.selected = not props
	_props_button.selected = props
	_point_section.visible = not props
	_prop_section.visible = props
	if props:
		_help_label.text = tr("Vasen: lisää ja siirrä esinettä · Oikea: poista · Rulla esineen päällä: kierrä (Shift nopeasti) · Rulla: zoomaa · Keskinappi: siirrä")
	else:
		_help_label.text = tr("Vasen: lisää ja siirrä · Oikea: poista · Rulla pisteen päällä: korkeus (Shift nopeasti) · Rulla: zoomaa · Keskinappi: siirrä")
	_on_prop_selection_changed()


func _on_prop_selection_changed() -> void:
	_prop_caption.text = tr("ESINEET %d / %d") % [_design.props.size(), TrackDesign.MAX_PROPS]
	for button: ChamferButton in _prop_buttons:
		button.disabled = _canvas.selected_prop < 0


func _add_spinner(column: VBoxContainer, title: String, options: PackedStringArray) -> OptionSpinner:
	var spinner: OptionSpinner = OptionSpinner.create(title, options, 0)
	spinner.value_width = spinner_value_width
	column.add_child(spinner)
	return spinner


func _add_button(row: HBoxContainer, text: String, action: Callable) -> ChamferButton:
	var button: ChamferButton = ChamferButton.create(text, 14, Vector4(6.0, 9.0, 6.0, 9.0))
	button.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	row.add_child(button)
	return button


# --- State -----------------------------------------------------------------

## Opens a design. A new or opened design starts a fresh undo history.
func _set_design(design: TrackDesign) -> void:
	_show_design(design, 0, true)
	_undo_stack.clear()
	_redo_stack.clear()
	_current_snapshot = design.to_dict()
	_last_change_msec = -1
	_update_history_buttons()


func _show_design(design: TrackDesign, selected: int, fit: bool) -> void:
	_design = design
	_canvas.selected = selected
	_canvas.design = design
	if fit:
		_canvas.fit_view()
	_theme_spinner.index = design.theme_index
	_width_spinner.index = roundi(design.road_width - TrackDesign.ROAD_WIDTH_RANGE.x)
	_forest_spinner.index = design.forest
	_area_spinner.index = design.area
	_canvas.select_prop(-1)
	_update_name()
	_on_selection_changed(_canvas.selected)
	_set_mode(_canvas.mode)


func _update_name() -> void:
	var shown: String = _design.display_name if not _design.display_name.is_empty() else tr("Nimetön rata")
	_name_button.label.text = shown


func _on_selection_changed(index: int) -> void:
	_point_caption.text = tr("PISTE %d / %d") % [index + 1, _design.points.size()]
	if index == 0:
		_point_caption.text += " · " + tr("LÄHTÖ")
	_height_spinner.index = _height_index(_design.points[index].y)
	_feature_spinner.index = _design.features[index]
	_span_spinner.index = _span_index(_design.spans[index])
	_surface_spinner.index = _design.surfaces[index]
	var has_span: bool = _design.features[index] == TrackDesign.Feature.BRIDGE \
		or _design.features[index] == TrackDesign.Feature.TUNNEL
	_span_spinner.editable = has_span
	_feature_spinner.editable = index != 0
	_start_button.disabled = index == 0
	_delete_button.disabled = _design.points.size() <= TrackDesign.MIN_POINTS
	_profile.queue_redraw()


func _on_design_changed() -> void:
	_record_change()
	_on_selection_changed(_canvas.selected)
	_on_prop_selection_changed()
	CustomTracks.save_draft(_design)
	var low: int = _canvas.get_low_crossing_count()
	if low > 0:
		_show_status(tr("Risteys on liian matala: nosta ylempää tietä vähintään %.1f m alemman yläpuolelle.") % TrackDesign.BRIDGE_CLEARANCE)


# --- Undo ------------------------------------------------------------------

## Remembers the design as it was before this change. Quick runs of changes
## (mouse wheel, held keys) are kept as one step.
func _record_change() -> void:
	var snapshot: Dictionary = _design.to_dict()
	if snapshot == _current_snapshot:
		return
	var now: int = Time.get_ticks_msec()
	var merge: bool = _last_change_msec >= 0 and not _undo_stack.is_empty() \
		and float(now - _last_change_msec) / 1000.0 < undo_merge_seconds
	if not merge:
		_undo_stack.append(_current_snapshot)
		if _undo_stack.size() > undo_limit:
			_undo_stack.pop_front()
	_redo_stack.clear()
	_current_snapshot = snapshot
	_last_change_msec = now
	_update_history_buttons()


func _undo() -> void:
	_step_history(_undo_stack, _redo_stack)


func _redo() -> void:
	_step_history(_redo_stack, _undo_stack)


func _step_history(from: Array[Dictionary], to: Array[Dictionary]) -> void:
	if from.is_empty() or _name_dialog != null or _open_overlay != null:
		return
	var snapshot: Dictionary = from.pop_back()
	var restored: TrackDesign = TrackDesign.from_dict(snapshot)
	if restored == null:
		return
	to.append(_current_snapshot)
	_current_snapshot = snapshot
	_last_change_msec = -1
	# The name and file belong to the track, not to an editing step.
	restored.display_name = _design.display_name
	restored.file_name = _design.file_name
	_show_design(restored, _canvas.selected, false)
	CustomTracks.save_draft(_design)
	_update_history_buttons()


func _update_history_buttons() -> void:
	_undo_button.disabled = _undo_stack.is_empty()
	_redo_button.disabled = _redo_stack.is_empty()


## Ctrl+Z (Cmd+Z on macOS) undoes; Ctrl+Shift+Z or Ctrl+Y redoes.
func _handle_history_input(event: InputEvent) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or not key.is_command_or_control_pressed():
		return false
	if key.keycode == KEY_Z:
		if key.shift_pressed:
			_redo()
		else:
			_undo()
		return true
	if key.keycode == KEY_Y:
		_redo()
		return true
	return false


## A bigger map is always fine; a smaller one only if the track fits in it.
func _on_area_picked(index: int) -> void:
	if not _design.fits_area(index):
		_area_spinner.index = _design.area
		_show_status(tr("Rata ja esineet eivät mahdu pienemmälle kartalle."))
		return
	_design.area = index
	_canvas.fit_view()
	_canvas.refresh()
	_on_design_changed()


func _on_height_picked(index: int) -> void:
	var point: Vector3 = _design.points[_canvas.selected]
	point.y = _height_at(index)
	_design.points[_canvas.selected] = point
	_canvas.refresh()
	_on_design_changed()


func _on_feature_picked(index: int) -> void:
	if _canvas.selected == 0:
		_feature_spinner.index = TrackDesign.Feature.NONE
		_show_status(tr("Lähtöpisteeseen ei voi tehdä siltaa, tunnelia tai hyppyriä."))
		return
	_design.features[_canvas.selected] = index
	_canvas.refresh()
	_on_design_changed()


func _on_set_start() -> void:
	_design.set_start(_canvas.selected)
	_canvas.refresh()
	_canvas.select(0)
	_on_design_changed()


func _on_reverse() -> void:
	_design.reverse()
	_canvas.refresh()
	_canvas.select(0)
	_on_design_changed()
	_show_status(tr("Ajosuunta käännetty."))


func _on_new() -> void:
	_set_design(TrackDesign.create_default())
	CustomTracks.save_draft(_design)
	_show_status(tr("Uusi rata aloitettu."))


func _on_save() -> void:
	if _design.display_name.is_empty():
		_open_name_dialog(_on_save)
		return
	var problem: String = _design.get_problem()
	if not problem.is_empty():
		_show_status(problem)
		return
	if CustomTracks.save(_design) == null:
		_show_status(tr("Tallennus epäonnistui."))
		return
	CustomTracks.save_draft(_design)
	_show_status(tr("Tallennettu: %s") % _design.display_name)


func _on_test_drive() -> void:
	var problem: String = _design.get_problem()
	if not problem.is_empty():
		_show_status(problem)
		return
	CustomTracks.save_draft(_design)
	var copy: TrackDesign = _design.duplicate_design()
	if copy.display_name.is_empty():
		copy.display_name = tr("Koeajo")
	GameState.selected_track = copy.make_info()
	GameState.mode = GameState.Mode.SINGLE
	GameState.test_drive = true
	GameState.start_race()


func _on_back() -> void:
	if _name_dialog != null:
		return
	if _open_overlay != null:
		_close_open_list()
		return
	CustomTracks.save_draft(_design)
	# A test drive leaves an unsaved track selected; don't keep it in the menus.
	if GameState.selected_track != null and GameState.selected_track.is_custom() \
			and GameState.selected_track.design.file_name.is_empty():
		GameState.selected_track = Catalog.get_default_track()
	super._on_back()


func _unhandled_input(event: InputEvent) -> void:
	if _name_dialog != null:
		return
	if _open_overlay == null and _handle_history_input(event):
		get_viewport().set_input_as_handled()
		return
	if _open_overlay == null and _canvas.mode == TrackEditorCanvas.Mode.PROPS:
		if _handle_prop_input(event):
			get_viewport().set_input_as_handled()
			return
	elif _open_overlay == null:
		if event.is_action_pressed(InputManager.ACTION_TAB_PREVIOUS):
			get_viewport().set_input_as_handled()
			_canvas.select(wrapi(_canvas.selected - 1, 0, _design.points.size()))
			return
		if event.is_action_pressed(InputManager.ACTION_TAB_NEXT):
			get_viewport().set_input_as_handled()
			_canvas.select(wrapi(_canvas.selected + 1, 0, _design.points.size()))
			return
		var key: InputEventKey = event as InputEventKey
		if key != null and key.pressed and not key.echo:
			match key.keycode:
				KEY_DELETE:
					get_viewport().set_input_as_handled()
					_canvas.remove_point(_canvas.selected)
					return
				KEY_PAGEUP, KEY_PAGEDOWN:
					get_viewport().set_input_as_handled()
					_canvas.change_height(_canvas.selected, 1 if key.keycode == KEY_PAGEUP else -1)
					return
	super._unhandled_input(event)


## Object mode keys: LB/RB (Q/E) pick an object, Delete removes it,
## PgUp/PgDn turn it. Returns true if the event was used.
func _handle_prop_input(event: InputEvent) -> bool:
	var count: int = _design.props.size()
	if event.is_action_pressed(InputManager.ACTION_TAB_PREVIOUS) or event.is_action_pressed(InputManager.ACTION_TAB_NEXT):
		if count > 0:
			var step: int = -1 if event.is_action_pressed(InputManager.ACTION_TAB_PREVIOUS) else 1
			var current: int = _canvas.selected_prop if _canvas.selected_prop >= 0 else (count - 1 if step > 0 else 0)
			_canvas.select_prop(wrapi(current + step, 0, count))
		return true
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	match key.keycode:
		KEY_DELETE:
			_canvas.remove_prop(_canvas.selected_prop)
			return true
		KEY_PAGEUP, KEY_PAGEDOWN:
			_canvas.rotate_prop(_canvas.selected_prop, 1 if key.keycode == KEY_PAGEUP else -1)
			return true
	return false


func _show_status(text: String) -> void:
	_status_label.text = text
	_status_time = status_seconds


# --- Name dialog -----------------------------------------------------------

func _open_name_dialog(after: Callable) -> void:
	_after_naming = after
	_name_dialog = NameDialog.create(tr("RADAN NIMI"), _design.display_name)
	_name_dialog.confirmed.connect(_on_name_confirmed)
	_name_dialog.cancelled.connect(_close_name_dialog)
	add_child(_name_dialog)


func _on_name_confirmed(track_name: String) -> void:
	_close_name_dialog()
	if track_name.is_empty():
		return
	if track_name != _design.display_name:
		# A renamed track is saved as a new file; the old one stays.
		_design.file_name = ""
	_design.display_name = track_name
	_update_name()
	CustomTracks.save_draft(_design)
	if _after_naming.is_valid():
		_after_naming.call()


func _close_name_dialog() -> void:
	if _name_dialog != null:
		_name_dialog.queue_free()
		_name_dialog = null
	_name_button.grab_focus.call_deferred()


# --- Open list -------------------------------------------------------------

func _show_open_list() -> void:
	_close_open_list()
	_delete_armed = ""
	_open_overlay = Control.new()
	_open_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_open_overlay)
	_open_overlay.add_child(MenuKit.make_blur_backdrop())

	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(24.0, 20.0, 24.0, 20.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_open_overlay.add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(12)
	panel.add_child(column)
	column.add_child(UiStyle.make_label(tr("AVAA RATA"), UiStyle.title_font(), 30))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = open_list_size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var rows: VBoxContainer = MenuKit.make_vbox(6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	var first: Control = null
	for track: TrackInfo in CustomTracks.get_tracks():
		var row: HBoxContainer = MenuKit.make_hbox(6)
		rows.add_child(row)
		var open: ChamferButton = ChamferButton.create(track.display_name, 17, Vector4(14.0, 8.0, 14.0, 8.0))
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.add_right_label(track.surface_label, UiStyle.caps_font(), UiStyle.MIN_FONT_SIZE)
		open.pressed.connect(_on_open_track.bind(track))
		row.add_child(open)
		var remove: ChamferButton = ChamferButton.create(tr("POISTA"), 14, Vector4(12.0, 8.0, 12.0, 8.0))
		remove.pressed.connect(_on_delete_track.bind(track, remove))
		row.add_child(remove)
		if first == null:
			first = open
	if first == null:
		var empty: Label = UiStyle.make_label(
			tr("Tallennettuja ratoja ei vielä ole."), UiStyle.FONT_MEDIUM, 16, UiStyle.TEXT_SECONDARY
		)
		rows.add_child(empty)
	var close: ChamferButton = ChamferButton.create(tr("SULJE"), 16)
	close.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.pressed.connect(_close_open_list)
	column.add_child(close)
	(first if first != null else close).grab_focus.call_deferred()


func _close_open_list() -> void:
	if _open_overlay != null:
		_open_overlay.queue_free()
		_open_overlay = null
		_theme_spinner.grab_focus.call_deferred()


func _on_open_track(track: TrackInfo) -> void:
	var design: TrackDesign = track.design.duplicate_design()
	design.file_name = track.design.file_name
	_close_open_list()
	_set_design(design)
	CustomTracks.save_draft(_design)
	_show_status(tr("Avattu: %s") % design.display_name)


## The first press asks again; the second one deletes the file.
func _on_delete_track(track: TrackInfo, button: ChamferButton) -> void:
	if _delete_armed != track.design.file_name:
		_delete_armed = track.design.file_name
		button.label.text = tr("VARMASTI?")
		return
	CustomTracks.delete(track.design.file_name)
	if _design.file_name == track.design.file_name:
		_design.file_name = ""
	if GameState.selected_track == track:
		GameState.selected_track = Catalog.get_default_track()
	_show_open_list()


# --- Value lists -------------------------------------------------------------

func _height_count() -> int:
	var span: Vector2 = TrackDesign.HEIGHT_RANGE
	return roundi((span.y - span.x) / TrackDesign.HEIGHT_STEP) + 1


func _height_at(index: int) -> float:
	return TrackDesign.HEIGHT_RANGE.x + float(index) * TrackDesign.HEIGHT_STEP


func _height_index(height: float) -> int:
	return clampi(roundi((height - TrackDesign.HEIGHT_RANGE.x) / TrackDesign.HEIGHT_STEP), 0, _height_count() - 1)


func _span_count() -> int:
	var span: Vector2 = TrackDesign.SPAN_RANGE
	return roundi((span.y - span.x) / TrackDesign.SPAN_STEP) + 1


func _span_at(index: int) -> float:
	return TrackDesign.SPAN_RANGE.x + float(index) * TrackDesign.SPAN_STEP


func _span_index(span: float) -> int:
	return clampi(roundi((span - TrackDesign.SPAN_RANGE.x) / TrackDesign.SPAN_STEP), 0, _span_count() - 1)
