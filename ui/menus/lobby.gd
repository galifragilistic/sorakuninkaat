extends MenuScreen
## Multiplayer lobby (mockups/02_Moninpeli.png): four slots that can hold a
## player or a computer driver, race settings and the start button. Local
## split screen only; the network tabs are placeholders until the network phase.

@export_group("Layout")
@export var cards_position: Vector2 = Vector2(56.0, 110.0)
@export var card_size: Vector2 = Vector2(382.0, 236.0)
@export var card_gap: int = 16
@export var card_bar_height: float = 5.0
@export var card_preview_size: Vector2 = Vector2(190.0, 150.0)
@export var settings_position: Vector2 = Vector2(852.0, 110.0)
@export var settings_width: float = 372.0
@export var track_thumb_size: Vector2 = Vector2(104.0, 72.0)

var _cards: Array[ChamferButton] = []
var _joined_views: Array[Control] = []
var _empty_views: Array[Control] = []
var _name_labels: Array[Label] = []
var _device_labels: Array[Label] = []
var _car_labels: Array[Label] = []
var _status_chips: Array[ChamferPanel] = []
var _previews: Array[CarPreview] = []
var _track_outline: TrackOutline
var _track_name_label: Label
var _track_summary_label: Label
var _status_label: Label
var _start_button: ChamferButton


func get_backdrop() -> Backdrop:
	return Backdrop.DIMMED


func _build() -> void:
	MenuKit.add_header(self, tr("MONINPELI"))
	_build_tabs()
	_build_cards()
	_build_settings()
	MenuKit.add_hints(self, [
		["A", tr("Liity / valmis")], ["X", tr("Auto / tekoäly")], ["START", tr("Aloita")], ["B", tr("Takaisin")],
	])


func _enter() -> void:
	GameState.mode = GameState.Mode.MULTI
	GameState.players[0].joined = true
	GameState.players[0].is_ai = false
	InputManager.join_enabled = true
	InputManager.device_changed.connect(_on_device_changed)
	_refresh()


func _exit_tree() -> void:
	InputManager.join_enabled = false


func _get_initial_focus() -> Control:
	return _cards[context.get("focus_player", 0)]


## X: change car for a player, add a computer driver to an empty slot, or remove one.
func _on_secondary() -> void:
	var player: int = _cards.find(get_viewport().gui_get_focus_owner() as ChamferButton)
	if player < 0:
		return
	var setup: PlayerSetup = GameState.players[player]
	if not setup.joined:
		_add_ai(player)
	elif setup.is_ai:
		_leave(player)
	else:
		_open_car_select(player)
	_refresh()


func _on_start() -> void:
	_try_start()


# --- Building ------------------------------------------------------------

func _build_tabs() -> void:
	var row: HBoxContainer = MenuKit.make_hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_right = -MenuKit.SCREEN_MARGIN
	row.offset_left = -MenuKit.SCREEN_MARGIN
	row.offset_top = MenuKit.HEADER_TOP + 2.0
	add_child(row)
	var tabs: Array[String] = [tr("Jaettu ruutu"), tr("Lähiverkko"), tr("Verkko")]
	for i: int in tabs.size():
		var tab: ChamferButton = ChamferButton.create(tabs[i], 16, Vector4(20.0, 11.0, 20.0, 11.0))
		tab.selected = i == 0
		# Only split screen exists; a selected tab needs no focus of its own.
		tab.disabled = i != 0
		tab.focus_mode = Control.FOCUS_NONE
		row.add_child(tab)


func _build_cards() -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", card_gap)
	grid.add_theme_constant_override("v_separation", card_gap)
	grid.position = cards_position
	add_child(grid)
	for i: int in GameState.MAX_PLAYERS:
		var card: ChamferButton = ChamferButton.new()
		card.outline_focus = true
		card.chamfer = 14.0
		card.normal_color = UiStyle.PANEL
		card.set_padding(Vector4.ZERO)
		card.custom_minimum_size = card_size
		card.pressed.connect(_on_card_pressed.bind(i))
		grid.add_child(card)
		_cards.append(card)

		var stack: Control = Control.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.row.add_child(stack)
		_joined_views.append(_build_joined_view(stack, i))
		_empty_views.append(_build_empty_view(stack, i))


func _build_joined_view(parent: Control, player: int) -> Control:
	var view: VBoxContainer = MenuKit.make_vbox(0)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(view)

	var bar: ColorRect = ColorRect.new()
	bar.color = GameState.get_player_color(player)
	bar.custom_minimum_size.y = card_bar_height
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(bar)

	var content: MarginContainer = MarginContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["margin_left", "margin_right"]:
		content.add_theme_constant_override(side, 20)
	content.add_theme_constant_override("margin_top", 14)
	content.add_theme_constant_override("margin_bottom", 12)
	view.add_child(content)
	var column: VBoxContainer = MenuKit.make_vbox(0)
	content.add_child(column)

	var header: HBoxContainer = MenuKit.make_hbox(10)
	column.add_child(header)
	header.add_child(MenuKit.make_player_chip(player, 15))
	var name_label: Label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 20)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	_name_labels.append(name_label)
	var device: Label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 14, UiStyle.TEXT_SECONDARY)
	header.add_child(device)
	_device_labels.append(device)

	var body: HBoxContainer = MenuKit.make_hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var preview: CarPreview = CarPreview.new()
	preview.show_stage = false
	preview.view_size = 5.4
	# A still three-quarter view reads better than a spinning car on a small card.
	preview.spin_degrees_per_second = 0.0
	preview.start_angle_degrees = -30.0
	preview.custom_minimum_size = card_preview_size
	body.add_child(preview)
	_previews.append(preview)

	var details: VBoxContainer = MenuKit.make_vbox(4)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(details)
	var caption: Label = UiStyle.make_caption(tr("AUTO"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	details.add_child(caption)
	var car_label: Label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 20)
	car_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	details.add_child(car_label)
	_car_labels.append(car_label)
	var status: ChamferPanel = MenuKit.make_chip("", UiStyle.SUCCESS, 14)
	status.size_flags_horizontal = Control.SIZE_SHRINK_END
	status.set_padding(Vector4(12.0, 4.0, 12.0, 4.0))
	details.add_child(status)
	_status_chips.append(status)
	return view


func _build_empty_view(parent: Control, player: int) -> Control:
	var view: VBoxContainer = MenuKit.make_vbox(10)
	view.alignment = BoxContainer.ALIGNMENT_CENTER
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(view)

	var plus: UiGlyph = UiGlyph.create(UiGlyph.Kind.PLUS, "", 52.0)
	plus.color = GameState.get_player_color(player)
	plus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	view.add_child(plus)
	var title: Label = UiStyle.make_label(
		tr("P%d · Paina A liittyäksesi") % (player + 1), UiStyle.FONT_DISPLAY, 18
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(title)
	var note: Label = UiStyle.make_label(
		tr("tai lisää tekoälykuski painamalla X"), UiStyle.FONT_MEDIUM, 14, UiStyle.TEXT_SECONDARY
	)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(note)
	return view


func _build_settings() -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(22.0, 20.0, 22.0, 18.0))
	panel.position = settings_position
	panel.custom_minimum_size = Vector2(settings_width, card_size.y * 2.0 + float(card_gap))
	add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(8)
	panel.add_child(column)
	column.add_child(UiStyle.make_caption(tr("KISAN ASETUKSET")))

	var track_button: ChamferButton = ChamferButton.new()
	track_button.set_padding(Vector4(10.0, 10.0, 12.0, 10.0))
	track_button.row.add_theme_constant_override("separation", 14)
	column.add_child(track_button)
	_track_outline = TrackOutline.new()
	_track_outline.custom_minimum_size = track_thumb_size
	_track_outline.margin = 10.0
	_track_outline.road_width = 4.0
	track_button.row.add_child(_track_outline)
	var track_texts: VBoxContainer = MenuKit.make_vbox(0)
	track_texts.alignment = BoxContainer.ALIGNMENT_CENTER
	track_texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_button.row.add_child(track_texts)
	_track_name_label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 20)
	track_texts.add_child(_track_name_label)
	track_button.register_label(_track_name_label)
	_track_summary_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 14, UiStyle.TEXT_SECONDARY)
	track_texts.add_child(_track_summary_label)
	track_button.register_label(_track_summary_label, true)
	track_button.add_glyph(UiGlyph.Kind.CHEVRON_RIGHT)
	track_button.pressed.connect(func() -> void: go_to(TRACK_SELECT, {"return_to": LOBBY}))

	var lap_texts: PackedStringArray = PackedStringArray()
	for laps: int in Catalog.LAP_OPTIONS:
		lap_texts.append(str(laps))
	var laps_spinner: OptionSpinner = OptionSpinner.create(
		tr("Kierrokset"), lap_texts, maxi(0, Catalog.LAP_OPTIONS.find(GameState.lap_count))
	)
	laps_spinner.value_changed.connect(func(index: int) -> void: GameState.lap_count = Catalog.LAP_OPTIONS[index])
	column.add_child(laps_spinner)

	var weather: OptionSpinner = OptionSpinner.create(tr("Sää"), Catalog.get_weather_names(), GameState.weather)
	weather.value_changed.connect(func(index: int) -> void: GameState.weather = index)
	column.add_child(weather)
	var time: OptionSpinner = OptionSpinner.create(tr("Aika"), Catalog.get_time_names(), GameState.time_of_day)
	time.value_changed.connect(func(index: int) -> void: GameState.time_of_day = index)
	column.add_child(time)

	var on_off: PackedStringArray = PackedStringArray([tr("Pois"), tr("Päällä")])
	var damage: OptionSpinner = OptionSpinner.create(tr("Vauriot"), on_off, int(Settings.damage_enabled))
	damage.value_changed.connect(func(index: int) -> void: Settings.damage_enabled = index == 1)
	column.add_child(damage)

	var layouts: PackedStringArray = PackedStringArray([tr("Pysty"), tr("Vaaka")])
	var layout: OptionSpinner = OptionSpinner.create(tr("Ruudunjako"), layouts, GameState.split_layout)
	layout.value_changed.connect(
		func(index: int) -> void: GameState.split_layout = index as GameState.SplitLayout
	)
	column.add_child(layout)

	column.add_child(MenuKit.make_spacer(false))
	_start_button = ChamferButton.create(tr("ALOITA KISA"), 22, Vector4(20.0, 0.0, 16.0, 0.0))
	_start_button.primary = true
	_start_button.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_button.add_glyph(UiGlyph.Kind.CHEVRON_RIGHT)
	_start_button.custom_minimum_size.y = 58.0
	_start_button.pressed.connect(_try_start)
	column.add_child(_start_button)
	_status_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 14, UiStyle.TEXT_SECONDARY)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status_label)


# --- State ---------------------------------------------------------------

func _refresh() -> void:
	var ready_count: int = 0
	var human_count: int = 0
	var waiting_for: String = ""
	for i: int in GameState.MAX_PLAYERS:
		var setup: PlayerSetup = GameState.players[i]
		_joined_views[i].visible = setup.joined
		_empty_views[i].visible = not setup.joined
		if not setup.joined:
			continue
		_car_labels[i].text = setup.stats.display_name
		_previews[i].show_setup(setup)
		if setup.is_ai:
			_name_labels[i].text = tr("Tekoäly")
			_device_labels[i].text = tr("Tietokone")
			MenuKit.set_chip(_status_chips[i], tr("TEKOÄLY"), UiStyle.INFO)
			continue
		human_count += 1
		_name_labels[i].text = tr("Pelaaja %d") % (i + 1)
		_device_labels[i].text = InputManager.get_device_name(i)
		if setup.is_ready:
			ready_count += 1
			MenuKit.set_chip(_status_chips[i], tr("VALMIS"), UiStyle.SUCCESS)
		else:
			MenuKit.set_chip(_status_chips[i], tr("EI VALMIS"), UiStyle.WARNING)
			if waiting_for.is_empty():
				waiting_for = tr("Pelaaja %d") % (i + 1)

	var track: TrackInfo = GameState.selected_track
	_track_outline.track = track
	_track_name_label.text = track.display_name
	_track_summary_label.text = track.summary
	if waiting_for.is_empty():
		_status_label.text = tr("Kaikki valmiina")
	else:
		_status_label.text = tr("%d/%d valmiina · odotetaan: %s") % [ready_count, human_count, waiting_for]
	_status_label.add_theme_color_override("font_color", UiStyle.TEXT_SECONDARY)


## A: join an empty slot, toggle ready for a player, or remove a computer driver.
func _on_card_pressed(player: int) -> void:
	var setup: PlayerSetup = GameState.players[player]
	if not setup.joined:
		# Without a free device the slot can only be driven by the computer.
		if InputManager.ensure_device(player):
			setup.joined = true
			setup.is_ai = false
			setup.is_ready = false
		else:
			_add_ai(player)
	elif setup.is_ai:
		_leave(player)
	else:
		setup.is_ready = not setup.is_ready
	_refresh()


func _add_ai(player: int) -> void:
	var setup: PlayerSetup = GameState.players[player]
	setup.joined = true
	setup.is_ai = true
	setup.is_ready = true
	setup.stats = Catalog.CARS.pick_random()


func _leave(player: int) -> void:
	# Player 1 hosts the lobby and cannot leave it.
	if player == 0:
		return
	var setup: PlayerSetup = GameState.players[player]
	setup.joined = false
	setup.is_ai = false
	setup.is_ready = false


func _open_car_select(player: int) -> void:
	go_to(CAR_SELECT, {"player": player, "return_to": LOBBY, "return_context": {"focus_player": player}})


func _on_device_changed(player_index: int) -> void:
	# A gamepad that just claimed a slot joins the lobby straight away, replacing a computer driver.
	if InputManager.get_device(player_index) == InputManager.Device.JOYPAD:
		var setup: PlayerSetup = GameState.players[player_index]
		if not setup.joined or setup.is_ai:
			setup.joined = true
			setup.is_ai = false
			setup.is_ready = false
	_refresh()


func _on_back() -> void:
	# Leaving the lobby empties the other slots, so single player stays single.
	for i: int in range(1, GameState.MAX_PLAYERS):
		_leave(i)
	go_to(MAIN)


func _try_start() -> void:
	for i: int in GameState.get_joined_players():
		var setup: PlayerSetup = GameState.players[i]
		if not setup.is_ai and not setup.is_ready:
			_status_label.add_theme_color_override("font_color", UiStyle.WARNING)
			return
	GameState.start_race()
