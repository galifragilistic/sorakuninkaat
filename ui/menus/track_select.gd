extends MenuScreen
## Track select (mockups/04_Ratavalinta.png): surface filters, track cards and
## a preview panel with weather, time of day and the track record.
## Context: "start_race" (bool) starts the race after confirming.

@export_group("Layout")
@export var filters_position: Vector2 = Vector2(56.0, 110.0)
@export var grid_position: Vector2 = Vector2(56.0, 172.0)
@export var card_size: Vector2 = Vector2(232.0, 206.0)
@export var card_gap: int = 14
@export var panel_position: Vector2 = Vector2(826.0, 110.0)
@export var panel_width: float = 398.0
@export var preview_height: float = 196.0

## Filter label -> surface kinds it shows (empty = everything).
var _filters: Array = []
var _filter_buttons: Array[ChamferButton] = []
var _cards: Array[ChamferButton] = []
var _card_tracks: Array[TrackInfo] = []
var _card_tags: Array[ChamferPanel] = []
var _focused_track: TrackInfo
var _world_preview: WorldPreview
var _name_label: Label
var _description_label: Label
var _record_label: Label
var _confirm_button: ChamferButton


func _build() -> void:
	_filters = [
		[tr("Kaikki"), []],
		[tr("Sora"), [SurfaceData.Kind.GRAVEL]],
		[tr("Asfaltti"), [SurfaceData.Kind.ASPHALT]],
		[tr("Lumi"), [SurfaceData.Kind.SNOW]],
		[tr("Jää"), [SurfaceData.Kind.ICE]],
	]
	MenuKit.add_header(self, tr("VALITSE RATA"))
	_build_filters()
	_build_grid()
	_build_panel()
	MenuKit.add_hints(self, [["A", tr("Valitse")], ["B", tr("Takaisin")]])


func _enter() -> void:
	_world_preview.show_track(GameState.selected_track)
	_show_track(GameState.selected_track)
	_update_tags()
	_confirm_button.label.text = tr("ALOITA KISA") if context.get("start_race", false) else tr("VALITSE RATA")


func _get_initial_focus() -> Control:
	var index: int = _card_tracks.find(GameState.selected_track)
	return _cards[maxi(index, 0)]


func _build_filters() -> void:
	var row: HBoxContainer = MenuKit.make_hbox(8)
	row.position = filters_position
	add_child(row)
	for i: int in _filters.size():
		var filter_name: String = _filters[i][0]
		var button: ChamferButton = ChamferButton.create(filter_name, 15, Vector4(18.0, 10.0, 18.0, 10.0))
		button.selected = i == 0
		button.pressed.connect(_apply_filter.bind(i))
		row.add_child(button)
		_filter_buttons.append(button)


func _build_grid() -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", card_gap)
	grid.add_theme_constant_override("v_separation", card_gap)
	grid.position = grid_position
	add_child(grid)
	for track: TrackInfo in Catalog.TRACKS:
		var card: ChamferButton = ChamferButton.new()
		card.outline_focus = true
		card.chamfer = 14.0
		card.normal_color = UiStyle.PANEL
		card.set_padding(Vector4(13.0, 13.0, 13.0, 12.0))
		card.custom_minimum_size = card_size
		grid.add_child(card)

		var column: VBoxContainer = MenuKit.make_vbox(6)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.row.add_child(column)
		var outline: TrackOutline = TrackOutline.new()
		outline.placeholder_text = tr("TULOSSA")
		outline.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outline.track = track
		column.add_child(outline)
		var name_label: Label = UiStyle.make_label(track.display_name, UiStyle.FONT_DISPLAY, 18)
		column.add_child(name_label)
		card.register_label(name_label)

		var footer: HBoxContainer = MenuKit.make_hbox(8)
		column.add_child(footer)
		footer.add_child(MenuKit.make_chip(track.surface_label, _get_surface_color(track.surface)))
		footer.add_child(MenuKit.make_spacer())
		var tag: ChamferPanel = MenuKit.make_chip(tr("VALITTU"), UiStyle.ACCENT)
		tag.visible = false
		footer.add_child(tag)

		card.disabled = not track.is_available()
		card.focused.connect(_show_track.bind(track))
		card.pressed.connect(_confirm.bind(track))
		_cards.append(card)
		_card_tracks.append(track)
		_card_tags.append(tag)


func _build_panel() -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(14.0, 14.0, 14.0, 16.0))
	panel.position = panel_position
	panel.custom_minimum_size.x = panel_width
	add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(8)
	panel.add_child(column)

	var preview_holder: Control = Control.new()
	preview_holder.custom_minimum_size.y = preview_height
	preview_holder.clip_contents = true
	preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(preview_holder)
	_world_preview = WorldPreview.new()
	_world_preview.camera_mode = WorldPreview.CameraMode.OVERVIEW
	_world_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_holder.add_child(_world_preview)
	var preview_tag: ChamferPanel = MenuKit.make_chip(tr("ESIKATSELU"), UiStyle.INFO)
	preview_tag.position = Vector2(10.0, preview_height - 32.0)
	preview_holder.add_child(preview_tag)

	_name_label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 26)
	column.add_child(_name_label)
	_description_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 15, UiStyle.TEXT_SECONDARY)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.custom_minimum_size.y = 44.0
	column.add_child(_description_label)

	# Only the evening / clear preset exists so far; the rest unlock with the weather phase.
	_add_option_row(column, tr("SÄÄ"), [tr("Aurinko"), tr("Sade"), tr("Lumi"), tr("Sumu")], 0)
	_add_option_row(column, tr("VUOROKAUDENAIKA"), [tr("Aamu"), tr("Päivä"), tr("Ilta"), tr("Yö")], 2)

	var record_row: HBoxContainer = MenuKit.make_hbox(0)
	column.add_child(record_row)
	var record_title: Label = UiStyle.make_label(tr("Ratatietue"), UiStyle.FONT_MEDIUM, 16, UiStyle.TEXT_SECONDARY)
	record_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_row.add_child(record_title)
	_record_label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 18)
	record_row.add_child(_record_label)

	_confirm_button = ChamferButton.create(tr("VALITSE RATA"), 20, Vector4(20.0, 0.0, 16.0, 0.0))
	_confirm_button.primary = true
	_confirm_button.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_button.add_glyph(UiGlyph.Kind.CHEVRON_RIGHT)
	_confirm_button.custom_minimum_size.y = 54.0
	_confirm_button.pressed.connect(func() -> void: _confirm(_focused_track))
	column.add_child(_confirm_button)


func _add_option_row(column: VBoxContainer, caption: String, options: Array, active: int) -> void:
	column.add_child(UiStyle.make_caption(caption))
	var row: HBoxContainer = MenuKit.make_hbox(6)
	column.add_child(row)
	for i: int in options.size():
		var option_text: String = options[i]
		var chip: ChamferButton = ChamferButton.create(option_text, 14, Vector4(6.0, 9.0, 6.0, 9.0))
		chip.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.selected_color = UiStyle.TEXT
		chip.selected = i == active
		chip.disabled = i != active
		row.add_child(chip)


func _get_surface_color(kind: SurfaceData.Kind) -> Color:
	match kind:
		SurfaceData.Kind.GRAVEL:
			return UiStyle.ACCENT
		SurfaceData.Kind.SAND:
			return Color("#ffc832")
		SurfaceData.Kind.ICE:
			return UiStyle.INFO
		SurfaceData.Kind.ASPHALT:
			return UiStyle.MAP_ROAD
	return UiStyle.TEXT


func _apply_filter(filter_index: int) -> void:
	var kinds: Array = _filters[filter_index][1]
	for i: int in _filter_buttons.size():
		_filter_buttons[i].selected = i == filter_index
	for i: int in _cards.size():
		_cards[i].visible = kinds.is_empty() or kinds.has(_card_tracks[i].surface)


func _show_track(track: TrackInfo) -> void:
	_focused_track = track
	_name_label.text = track.display_name
	_description_label.text = track.description
	_record_label.text = RaceFormat.lap_time(GameState.get_track_record(track))


func _update_tags() -> void:
	for i: int in _card_tags.size():
		_card_tags[i].visible = _card_tracks[i] == GameState.selected_track


func _confirm(track: TrackInfo) -> void:
	if track == null or not track.is_available():
		return
	GameState.selected_track = track
	if context.get("start_race", false):
		GameState.start_race()
	else:
		_on_back()
