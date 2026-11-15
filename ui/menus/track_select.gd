extends MenuScreen
## Track select (mockups/04_Ratavalinta.png): surface filters, track cards and
## a preview panel with weather, time of day and the track record.
## Context: "start_race" (bool) starts the race after confirming.

@export_group("Layout")
@export var filters_position: Vector2 = Vector2(56.0, 110.0)
@export var grid_position: Vector2 = Vector2(56.0, 172.0)
## Visible part of the scrolling card grid.
@export var grid_view_size: Vector2 = Vector2(740.0, 470.0)
@export var card_size: Vector2 = Vector2(232.0, 206.0)
@export var card_gap: int = 14
@export var panel_position: Vector2 = Vector2(826.0, 110.0)
@export var panel_width: float = 398.0
@export var preview_height: float = 196.0

## Filter label -> surface kinds it shows (empty = everything), and
## optionally true to show only tracks made in the track editor.
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
var _opponents_spinner: OptionSpinner


func _build() -> void:
	_filters = [
		[tr("Kaikki"), []],
		[tr("Sora"), [SurfaceData.Kind.GRAVEL]],
		[tr("Asfaltti"), [SurfaceData.Kind.ASPHALT]],
		[tr("Lumi"), [SurfaceData.Kind.SNOW]],
		[tr("Jää"), [SurfaceData.Kind.ICE]],
		[tr("Omat"), [], true],
	]
	MenuKit.add_header(self, tr("VALITSE RATA"))
	_build_filters()
	_build_grid()
	_build_panel()
	MenuKit.add_hints(self, [[InputPrompts.Prompt.ACCEPT, tr("Valitse")], [InputPrompts.Prompt.BACK, tr("Takaisin")]])


func _enter() -> void:
	_show_track(GameState.selected_track)
	_update_tags()
	var starts_race: bool = context.get("start_race", false)
	_confirm_button.label.text = tr("ALOITA KISA") if starts_race else tr("VALITSE RATA")
	# Opponents are chosen here only for a single player race; the lobby has its own slots.
	_opponents_spinner.visible = starts_race and GameState.mode == GameState.Mode.SINGLE


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
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Tracks made in the editor can fill more rows than fit on screen.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = grid_position
	scroll.custom_minimum_size = grid_view_size
	scroll.size = grid_view_size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	scroll.add_child(grid)
	var tracks: Array[TrackInfo] = Catalog.TRACKS.duplicate()
	tracks.append_array(CustomTracks.get_tracks())
	for track: TrackInfo in tracks:
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

	_add_option_row(
		column, tr("SÄÄ"), [tr("Aurinko"), tr("Sade"), tr("Lumi"), tr("Sumu")], GameState.weather,
		func(index: int) -> void: GameState.weather = index
	)
	_add_option_row(
		column, tr("VUOROKAUDENAIKA"), [tr("Aamu"), tr("Päivä"), tr("Ilta"), tr("Yö")], GameState.time_of_day,
		func(index: int) -> void: GameState.time_of_day = index
	)

	_opponents_spinner = OptionSpinner.create(
		tr("Tekoälykuskit"), PackedStringArray(["0", "1", "2", "3"]), GameState.ai_opponents
	)
	_opponents_spinner.value_width = 110.0
	_opponents_spinner.value_changed.connect(func(index: int) -> void: GameState.ai_opponents = index)
	column.add_child(_opponents_spinner)

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


## Row of option chips; picking one calls on_pick with its index.
func _add_option_row(column: VBoxContainer, caption: String, options: Array, active: int, on_pick: Callable) -> void:
	column.add_child(UiStyle.make_caption(caption))
	var row: HBoxContainer = MenuKit.make_hbox(6)
	column.add_child(row)
	var chips: Array[ChamferButton] = []
	for i: int in options.size():
		var option_text: String = options[i]
		var chip: ChamferButton = ChamferButton.create(option_text, 14, Vector4(6.0, 9.0, 6.0, 9.0))
		chip.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.selected_color = UiStyle.TEXT
		chip.selected = i == active
		row.add_child(chip)
		chips.append(chip)
	for i: int in chips.size():
		chips[i].pressed.connect(func() -> void:
			on_pick.call(i)
			for other: int in chips.size():
				chips[other].selected = other == i)


## In a network game the host's choices (track, weather, time) go to everyone.
func _exit_tree() -> void:
	if GameState.mode == GameState.Mode.NET:
		Network.broadcast_lobby()


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
	var custom_only: bool = _filters[filter_index].size() > 2 and _filters[filter_index][2]
	for i: int in _filter_buttons.size():
		_filter_buttons[i].selected = i == filter_index
	for i: int in _cards.size():
		var track: TrackInfo = _card_tracks[i]
		if custom_only:
			_cards[i].visible = track.is_custom()
		else:
			_cards[i].visible = kinds.is_empty() or kinds.has(track.surface)


func _show_track(track: TrackInfo) -> void:
	# Building a preview world takes a moment, so only do it when the track changes.
	if track != _focused_track:
		_world_preview.show_track(track)
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
