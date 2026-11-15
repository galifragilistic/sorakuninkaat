extends MenuScreen
## Multiplayer lobby (mockups/02_Moninpeli.png). Three tabs:
## - Jaettu ruutu: four local slots for players or computer drivers.
## - Lähiverkko: create a game or join one found on the LAN.
## - Verkko: create a game or join one by IP address.
## Once connected, the network tabs show the same player cards and race
## settings, shared through the Network autoload. The host decides the race
## settings and starts the race; each player picks their own car and readiness.

enum Tab { SPLIT, LAN, INTERNET }

@export_group("Layout")
@export var cards_position: Vector2 = Vector2(56.0, 110.0)
@export var card_size: Vector2 = Vector2(382.0, 236.0)
@export var card_gap: int = 16
@export var card_bar_height: float = 5.0
@export var card_preview_size: Vector2 = Vector2(190.0, 150.0)
@export var settings_position: Vector2 = Vector2(852.0, 110.0)
@export var settings_width: float = 372.0
@export var track_thumb_size: Vector2 = Vector2(104.0, 72.0)
@export var address_field_size: Vector2 = Vector2(330.0, 50.0)

var _tab: Tab = Tab.SPLIT
var _tab_buttons: Array[ChamferButton] = []
var _session_label: Label

var _cards_grid: GridContainer
var _cards: Array[ChamferButton] = []
var _joined_views: Array[Control] = []
var _empty_views: Array[Control] = []
var _empty_titles: Array[Label] = []
var _empty_notes: Array[Label] = []
var _name_labels: Array[Label] = []
var _device_labels: Array[Label] = []
var _car_labels: Array[Label] = []
var _status_chips: Array[ChamferPanel] = []
var _previews: Array[CarPreview] = []

var _settings_panel: ChamferPanel
var _track_button: ChamferButton
var _track_outline: TrackOutline
var _track_name_label: Label
var _track_summary_label: Label
var _laps_spinner: OptionSpinner
var _weather_spinner: OptionSpinner
var _time_spinner: OptionSpinner
var _damage_spinner: OptionSpinner
var _layout_spinner: OptionSpinner
var _status_label: Label
var _start_button: ChamferButton

var _net_panel: ChamferPanel
var _net_title: Label
var _net_description: Label
var _host_button: ChamferButton
var _lan_section: VBoxContainer
var _server_list: VBoxContainer
var _no_servers_label: Label
var _ip_section: VBoxContainer
var _address_field: LineEdit
var _join_button: ChamferButton
var _own_address_label: Label
var _net_status_label: Label
var _name_dialog: NameDialog
var _name_dialog_player: int = -1


func get_backdrop() -> Backdrop:
	return Backdrop.DIMMED


func _build() -> void:
	MenuKit.add_header(self, tr("MONINPELI"))
	_build_tabs()
	_build_cards()
	_build_settings()
	_build_net_panel()
	MenuKit.add_hints(self, [
		[InputPrompts.Prompt.ACCEPT, tr("Liity / valmis")], [InputPrompts.Prompt.SECONDARY, tr("Auto / tekoäly")],
		[InputPrompts.Prompt.TERTIARY, tr("Nimi")],
		[InputPrompts.Prompt.TABS, tr("Välilehti")], [InputPrompts.Prompt.START, tr("Aloita")],
		[InputPrompts.Prompt.BACK, tr("Takaisin")],
	])


func _enter() -> void:
	Network.session_changed.connect(_on_session_changed)
	Network.lobby_updated.connect(_refresh)
	Network.servers_changed.connect(_rebuild_server_list)
	InputManager.device_changed.connect(_on_device_changed)
	# Texts on the cards name buttons, so they follow the device in use.
	InputManager.prompt_style_changed.connect(_refresh.unbind(1))
	if Network.role != Network.Role.OFFLINE:
		_tab = (int(Network.kind) + 1) as Tab
	else:
		_tab = clampi(context.get("tab", Tab.SPLIT), Tab.SPLIT, Tab.INTERNET) as Tab
	if _tab == Tab.SPLIT and Network.role == Network.Role.OFFLINE:
		GameState.mode = GameState.Mode.MULTI
		GameState.players[0].joined = true
		GameState.players[0].is_ai = false
	_apply_tab()


func _exit_tree() -> void:
	InputManager.join_enabled = false
	Network.stop_discovery()


func _get_initial_focus() -> Control:
	if _net_panel.visible:
		return _host_button
	return _cards[clampi(context.get("focus_player", _get_own_slot()), 0, _cards.size() - 1)]


func _unhandled_input(event: InputEvent) -> void:
	# The name dialog handles its own input while it is open.
	if _name_dialog != null:
		return
	if event.is_action_pressed(InputManager.ACTION_TAB_PREVIOUS):
		get_viewport().set_input_as_handled()
		_select_tab(wrapi(_tab - 1, 0, Tab.size()) as Tab)
	elif event.is_action_pressed(InputManager.ACTION_TAB_NEXT):
		get_viewport().set_input_as_handled()
		_select_tab(wrapi(_tab + 1, 0, Tab.size()) as Tab)
	else:
		super._unhandled_input(event)


## Y / N: choose your name.
func _on_tertiary() -> void:
	var player: int = _cards.find(get_viewport().gui_get_focus_owner() as ChamferButton)
	if player < 0 or not _cards_grid.visible:
		return
	var setup: PlayerSetup = GameState.players[player]
	if not setup.joined or setup.is_ai:
		return
	# Online, only your own name is yours to change.
	if _is_online() and player != Network.local_slot:
		return
	_name_dialog_player = player
	_name_dialog = NameDialog.create(tr("PELAAJA %d") % (player + 1), setup.display_name)
	_name_dialog.confirmed.connect(_on_name_confirmed)
	_name_dialog.cancelled.connect(_close_name_dialog)
	add_child(_name_dialog)


func _on_name_confirmed(player_name: String) -> void:
	var player: int = _name_dialog_player
	if _is_online():
		# This machine's name lives in slot 1's setting, whatever slot it plays in.
		Settings.set_player_name(0, player_name)
		GameState.players[player].display_name = player_name
		Network.submit_local_setup()
	else:
		Settings.set_player_name(player, player_name)
	_close_name_dialog()
	_refresh()


func _close_name_dialog() -> void:
	if _name_dialog == null:
		return
	_name_dialog.queue_free()
	_name_dialog = null
	if _name_dialog_player >= 0:
		_cards[_name_dialog_player].grab_focus.call_deferred()
	_name_dialog_player = -1


## X: change your car, or (for whoever runs the lobby) add or remove a computer driver.
func _on_secondary() -> void:
	var player: int = _cards.find(get_viewport().gui_get_focus_owner() as ChamferButton)
	if player < 0 or not _cards_grid.visible:
		return
	var setup: PlayerSetup = GameState.players[player]
	if _is_online():
		if player == Network.local_slot:
			_open_car_select(player)
		elif Network.is_host():
			Network.set_slot_ai(player, not setup.joined)
		return
	if not setup.joined:
		_add_ai(player)
	elif setup.is_ai:
		_leave(player)
	else:
		_open_car_select(player)
	_refresh()


func _on_start() -> void:
	if _cards_grid.visible:
		_try_start()


func _on_back() -> void:
	if Network.role != Network.Role.OFFLINE:
		# First B leaves the network game, the next one leaves the lobby.
		Network.leave()
		return
	# Leaving the lobby empties the other slots, so single player stays single.
	for i: int in range(1, GameState.MAX_PLAYERS):
		_leave(i)
	go_to(MAIN)


# --- Tabs ----------------------------------------------------------------

func _build_tabs() -> void:
	var column: VBoxContainer = MenuKit.make_vbox(6)
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.offset_right = -MenuKit.SCREEN_MARGIN
	column.offset_left = -MenuKit.SCREEN_MARGIN
	column.offset_top = MenuKit.HEADER_TOP + 2.0
	add_child(column)
	var row: HBoxContainer = MenuKit.make_hbox(8)
	column.add_child(row)
	var tabs: Array[String] = [tr("Jaettu ruutu"), tr("Lähiverkko"), tr("Verkko")]
	for i: int in tabs.size():
		var tab: ChamferButton = ChamferButton.create(tabs[i], 16, Vector4(20.0, 11.0, 20.0, 11.0))
		# Tabs are switched with LB / RB or the mouse; focus stays on the page.
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_select_tab.bind(i))
		row.add_child(tab)
		_tab_buttons.append(tab)
	_session_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 14, UiStyle.TEXT_SECONDARY)
	_session_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_session_label)


func _select_tab(tab: Tab) -> void:
	if tab == _tab:
		return
	if Network.role != Network.Role.OFFLINE:
		# A network game keeps its tab until it is left.
		var message: String = tr("Poistu ensin pelistä (%s)") % InputPrompts.get_button_name(InputPrompts.Prompt.BACK)
		_net_status_label.text = message
		_status_label.text = message
		_status_label.add_theme_color_override("font_color", UiStyle.WARNING)
		return
	_tab = tab
	_apply_tab()
	var target: Control = _get_initial_focus()
	if target != null:
		target.grab_focus()


func _apply_tab() -> void:
	InputManager.join_enabled = _tab == Tab.SPLIT
	if _tab == Tab.LAN:
		Network.start_discovery()
	else:
		Network.stop_discovery()
	if _tab == Tab.SPLIT and Network.role == Network.Role.OFFLINE:
		GameState.mode = GameState.Mode.MULTI
	_rebuild_server_list()
	_refresh()


func _is_online() -> bool:
	return _tab != Tab.SPLIT and Network.is_online()


func _get_own_slot() -> int:
	return maxi(Network.local_slot, 0) if _is_online() else 0


# --- Player cards --------------------------------------------------------

func _build_cards() -> void:
	_cards_grid = GridContainer.new()
	_cards_grid.columns = 2
	_cards_grid.add_theme_constant_override("h_separation", card_gap)
	_cards_grid.add_theme_constant_override("v_separation", card_gap)
	_cards_grid.position = cards_position
	add_child(_cards_grid)
	for i: int in GameState.MAX_PLAYERS:
		var card: ChamferButton = ChamferButton.new()
		card.outline_focus = true
		card.chamfer = 14.0
		card.normal_color = UiStyle.PANEL
		card.set_padding(Vector4.ZERO)
		card.custom_minimum_size = card_size
		card.pressed.connect(_on_card_pressed.bind(i))
		_cards_grid.add_child(card)
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
	var title: Label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(title)
	_empty_titles.append(title)
	var note: Label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 14, UiStyle.TEXT_SECONDARY)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view.add_child(note)
	_empty_notes.append(note)
	return view


# --- Race settings -------------------------------------------------------

func _build_settings() -> void:
	_settings_panel = ChamferPanel.create_panel(Vector4(22.0, 20.0, 22.0, 18.0))
	_settings_panel.position = settings_position
	_settings_panel.custom_minimum_size = Vector2(settings_width, card_size.y * 2.0 + float(card_gap))
	add_child(_settings_panel)
	var column: VBoxContainer = MenuKit.make_vbox(8)
	_settings_panel.add_child(column)
	column.add_child(UiStyle.make_caption(tr("KISAN ASETUKSET")))

	_track_button = ChamferButton.new()
	_track_button.set_padding(Vector4(10.0, 10.0, 12.0, 10.0))
	_track_button.row.add_theme_constant_override("separation", 14)
	column.add_child(_track_button)
	_track_outline = TrackOutline.new()
	_track_outline.custom_minimum_size = track_thumb_size
	_track_outline.margin = 10.0
	_track_outline.road_width = 4.0
	_track_button.row.add_child(_track_outline)
	var track_texts: VBoxContainer = MenuKit.make_vbox(0)
	track_texts.alignment = BoxContainer.ALIGNMENT_CENTER
	track_texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_button.row.add_child(track_texts)
	_track_name_label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 20)
	track_texts.add_child(_track_name_label)
	_track_button.register_label(_track_name_label)
	_track_summary_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 14, UiStyle.TEXT_SECONDARY)
	track_texts.add_child(_track_summary_label)
	_track_button.register_label(_track_summary_label, true)
	_track_button.add_glyph(UiGlyph.Kind.CHEVRON_RIGHT)
	_track_button.pressed.connect(func() -> void:
		go_to(TRACK_SELECT, {"return_to": LOBBY, "return_context": {"tab": _tab}}))

	var lap_texts: PackedStringArray = PackedStringArray()
	for laps: int in Catalog.LAP_OPTIONS:
		lap_texts.append(str(laps))
	_laps_spinner = OptionSpinner.create(tr("Kierrokset"), lap_texts, 0)
	_laps_spinner.value_changed.connect(func(index: int) -> void:
		GameState.lap_count = Catalog.LAP_OPTIONS[index]
		_on_settings_changed())
	column.add_child(_laps_spinner)

	_weather_spinner = OptionSpinner.create(tr("Sää"), Catalog.get_weather_names(), 0)
	_weather_spinner.value_changed.connect(func(index: int) -> void:
		GameState.weather = index
		_on_settings_changed())
	column.add_child(_weather_spinner)
	_time_spinner = OptionSpinner.create(tr("Aika"), Catalog.get_time_names(), 0)
	_time_spinner.value_changed.connect(func(index: int) -> void:
		GameState.time_of_day = index
		_on_settings_changed())
	column.add_child(_time_spinner)

	var on_off: PackedStringArray = PackedStringArray([tr("Pois"), tr("Päällä")])
	_damage_spinner = OptionSpinner.create(tr("Vauriot"), on_off, 0)
	_damage_spinner.value_changed.connect(func(index: int) -> void:
		Settings.damage_enabled = index == 1
		_on_settings_changed())
	column.add_child(_damage_spinner)

	var layouts: PackedStringArray = PackedStringArray([tr("Pysty"), tr("Vaaka")])
	_layout_spinner = OptionSpinner.create(tr("Ruudunjako"), layouts, GameState.split_layout)
	_layout_spinner.value_changed.connect(
		func(index: int) -> void: GameState.split_layout = index as GameState.SplitLayout
	)
	column.add_child(_layout_spinner)

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
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)


func _on_settings_changed() -> void:
	if _is_online():
		Network.broadcast_lobby()


# --- Network panel -------------------------------------------------------

func _build_net_panel() -> void:
	_net_panel = ChamferPanel.create_panel(Vector4(28.0, 24.0, 28.0, 24.0))
	_net_panel.position = cards_position
	_net_panel.custom_minimum_size = Vector2(card_size.x * 2.0 + float(card_gap), card_size.y * 2.0 + float(card_gap))
	add_child(_net_panel)
	var column: VBoxContainer = MenuKit.make_vbox(14)
	_net_panel.add_child(column)

	_net_title = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 26)
	column.add_child(_net_title)
	_net_description = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 16, UiStyle.TEXT_SECONDARY)
	_net_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_net_description)

	_host_button = ChamferButton.create(tr("LUO PELI"), 20, Vector4(24.0, 0.0, 16.0, 0.0))
	_host_button.primary = true
	_host_button.add_glyph(UiGlyph.Kind.CHEVRON_RIGHT)
	_host_button.custom_minimum_size = Vector2(300.0, 54.0)
	_host_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_host_button.pressed.connect(_host)
	column.add_child(_host_button)

	_lan_section = MenuKit.make_vbox(8)
	column.add_child(_lan_section)
	_lan_section.add_child(UiStyle.make_caption(tr("PELIT LÄHIVERKOSSA")))
	_server_list = MenuKit.make_vbox(8)
	_lan_section.add_child(_server_list)
	_no_servers_label = UiStyle.make_label(tr("Etsitään pelejä…"), UiStyle.FONT_MEDIUM, 16, UiStyle.TEXT_SECONDARY)
	_lan_section.add_child(_no_servers_label)

	_ip_section = MenuKit.make_vbox(10)
	column.add_child(_ip_section)
	_ip_section.add_child(UiStyle.make_caption(tr("LIITY OSOITTEESEEN")))
	var join_row: HBoxContainer = MenuKit.make_hbox(10)
	_ip_section.add_child(join_row)
	_address_field = LineEdit.new()
	_address_field.placeholder_text = tr("esim. 192.168.1.20")
	_address_field.custom_minimum_size = address_field_size
	_address_field.add_theme_font_override("font", UiStyle.FONT_MEDIUM)
	_address_field.add_theme_font_size_override("font_size", 18)
	_address_field.add_theme_stylebox_override("normal", _make_field_style(UiStyle.LINE))
	_address_field.add_theme_stylebox_override("focus", _make_field_style(UiStyle.ACCENT))
	_address_field.text_submitted.connect(func(_text: String) -> void: _join_address())
	join_row.add_child(_address_field)
	_join_button = ChamferButton.create(tr("LIITY"), 18, Vector4(24.0, 0.0, 24.0, 0.0))
	_join_button.custom_minimum_size.y = address_field_size.y
	_join_button.pressed.connect(_join_address)
	join_row.add_child(_join_button)
	_own_address_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 15, UiStyle.TEXT_SECONDARY)
	_own_address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ip_section.add_child(_own_address_label)

	column.add_child(MenuKit.make_spacer(false))
	_net_status_label = UiStyle.make_label("", UiStyle.FONT_SEMIBOLD, 16, UiStyle.WARNING)
	_net_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_net_status_label)


func _make_field_style(border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = UiStyle.BUTTON
	style.border_color = border
	style.set_border_width_all(2)
	style.set_content_margin_all(12.0)
	return style


func _rebuild_server_list() -> void:
	var had_focus: bool = _has_focus_inside(_server_list)
	for child: Node in _server_list.get_children():
		_server_list.remove_child(child)
		child.queue_free()
	var first: ChamferButton = null
	for key: String in Network.servers:
		var server: Dictionary = Network.servers[key]
		var text: String = tr("%s · %d/%d pelaajaa") % [server["track"], server["players"], GameState.MAX_PLAYERS]
		var button: ChamferButton = ChamferButton.create(text, 17, Vector4(18.0, 0.0, 18.0, 0.0))
		button.custom_minimum_size.y = 50.0
		var detail: String = tr("kisa käynnissä") if server["racing"] else server["address"]
		button.add_right_label(detail, UiStyle.FONT_MEDIUM, 15)
		button.disabled = server["racing"] or server["players"] >= GameState.MAX_PLAYERS
		button.pressed.connect(_join.bind(server["address"], server["port"]))
		_server_list.add_child(button)
		if first == null and not button.disabled:
			first = button
	_no_servers_label.visible = Network.servers.is_empty()
	if had_focus:
		var target: ChamferButton = first if first != null else _host_button
		if not target.disabled:
			target.grab_focus.call_deferred()


func _host() -> void:
	var kind: Network.Kind = Network.Kind.LAN if _tab == Tab.LAN else Network.Kind.INTERNET
	if Network.host_game(kind) == OK:
		_cards[0].grab_focus.call_deferred()
	_refresh()


func _join_address() -> void:
	var address: String = _address_field.text.strip_edges()
	if address.is_empty():
		_net_status_label.text = tr("Kirjoita isännän osoite")
		return
	var port: int = Network.DEFAULT_PORT
	# "address:port" picks another port.
	if address.count(":") == 1:
		port = int(address.get_slice(":", 1))
		address = address.get_slice(":", 0)
	_join(address, port)


func _join(address: String, port: int) -> void:
	var kind: Network.Kind = Network.Kind.LAN if _tab == Tab.LAN else Network.Kind.INTERNET
	Network.join_game(address, port, kind)
	_refresh()


func _on_session_changed() -> void:
	# Look for games again after leaving one.
	if _tab == Tab.LAN and Network.role == Network.Role.OFFLINE:
		Network.start_discovery()
	_refresh()
	if _is_online():
		var target: Control = _cards[_get_own_slot()]
		target.grab_focus.call_deferred()
	elif _net_panel.visible and not _has_focus_inside(_net_panel) and not _host_button.disabled:
		_host_button.grab_focus.call_deferred()


func _has_focus_inside(container: Control) -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused != null and container.is_ancestor_of(focused)


# --- State ---------------------------------------------------------------

func _refresh() -> void:
	for i: int in _tab_buttons.size():
		_tab_buttons[i].selected = i == _tab
		_tab_buttons[i].disabled = Network.role != Network.Role.OFFLINE and i != _tab
		_tab_buttons[i].focus_mode = Control.FOCUS_NONE
	var show_lobby: bool = _tab == Tab.SPLIT or _is_online()
	_cards_grid.visible = show_lobby
	_settings_panel.visible = show_lobby
	_net_panel.visible = not show_lobby
	_refresh_session_label()
	if show_lobby:
		_refresh_cards()
		_refresh_settings()
	else:
		_refresh_net_panel()


func _refresh_session_label() -> void:
	_session_label.text = ""
	if not _is_online():
		return
	if Network.is_host():
		var addresses: PackedStringArray = Network.get_local_addresses()
		var address: String = addresses[0] if not addresses.is_empty() else "127.0.0.1"
		_session_label.text = tr("Isäntä · %s : %d") % [address, Network.DEFAULT_PORT]
	else:
		_session_label.text = tr("Yhdistetty isäntään · %s poistuu") % InputPrompts.get_button_name(InputPrompts.Prompt.BACK)


func _refresh_net_panel() -> void:
	var is_lan: bool = _tab == Tab.LAN
	_net_title.text = tr("LÄHIVERKKO") if is_lan else tr("VERKKO")
	if is_lan:
		_net_description.text = tr("Pelaa saman verkon koneiden kesken. Luo peli tai valitse listasta peli, johon liityt.")
	else:
		_net_description.text = tr("Pelaa suoralla IP-osoitteella. Internetin yli isännän on avattava reitittimestään UDP-portti %d.") % Network.DEFAULT_PORT
	_lan_section.visible = is_lan
	_ip_section.visible = not is_lan
	var addresses: PackedStringArray = Network.get_local_addresses()
	_own_address_label.text = tr("Oma osoitteesi: %s") % (", ".join(addresses) if not addresses.is_empty() else "–")
	var busy: bool = Network.connecting
	_host_button.disabled = busy
	_join_button.disabled = busy
	if busy:
		_net_status_label.text = tr("Yhdistetään…")
		_net_status_label.add_theme_color_override("font_color", UiStyle.INFO)
	else:
		_net_status_label.text = Network.last_error
		_net_status_label.add_theme_color_override("font_color", UiStyle.WARNING)


func _refresh_cards() -> void:
	var online: bool = _is_online()
	for i: int in GameState.MAX_PLAYERS:
		var setup: PlayerSetup = GameState.players[i]
		_joined_views[i].visible = setup.joined
		_empty_views[i].visible = not setup.joined
		if not setup.joined:
			var accept: String = InputPrompts.get_button_name(InputPrompts.Prompt.ACCEPT)
			var secondary: String = InputPrompts.get_button_name(InputPrompts.Prompt.SECONDARY)
			if online:
				_empty_titles[i].text = tr("P%d · Vapaa paikka") % (i + 1)
			else:
				_empty_titles[i].text = tr("P%d · Paina %s liittyäksesi") % [i + 1, accept]
			if not online:
				_empty_notes[i].text = tr("tai lisää tekoälykuski painamalla %s") % secondary
			elif Network.is_host():
				_empty_notes[i].text = tr("Odotetaan pelaajaa · %s lisää tekoälykuskin") % secondary
			else:
				_empty_notes[i].text = tr("Odotetaan pelaajaa")
			continue
		_car_labels[i].text = setup.stats.display_name
		_previews[i].show_setup(setup)
		if setup.is_ai:
			_name_labels[i].text = tr("Tekoäly")
			_device_labels[i].text = tr("Tietokone")
			MenuKit.set_chip(_status_chips[i], tr("TEKOÄLY"), UiStyle.INFO)
			continue
		_name_labels[i].text = GameState.get_player_name(i)
		_device_labels[i].text = _get_device_text(i, setup)
		if setup.is_ready:
			MenuKit.set_chip(_status_chips[i], tr("VALMIS"), UiStyle.SUCCESS)
		else:
			MenuKit.set_chip(_status_chips[i], tr("EI VALMIS"), UiStyle.WARNING)


func _get_device_text(slot: int, setup: PlayerSetup) -> String:
	if not _is_online():
		return InputManager.get_device_name(slot)
	if slot == Network.local_slot:
		return tr("Sinä")
	if setup.peer_id == Network.HOST_PEER_ID:
		return tr("Isäntä")
	return tr("Verkkopelaaja")


func _refresh_settings() -> void:
	var online: bool = _is_online()
	var can_edit: bool = not online or Network.is_host()
	_laps_spinner.index = maxi(0, Catalog.LAP_OPTIONS.find(GameState.lap_count))
	_weather_spinner.index = GameState.weather
	_time_spinner.index = GameState.time_of_day
	_damage_spinner.index = int(Network.remote_damage if online and not Network.is_host() else Settings.damage_enabled)
	for spinner: OptionSpinner in [_laps_spinner, _weather_spinner, _time_spinner, _damage_spinner]:
		spinner.editable = can_edit
	# Every machine shows one player full screen online.
	_layout_spinner.visible = not online
	_track_button.disabled = not can_edit

	var track: TrackInfo = GameState.selected_track
	_track_outline.track = track
	_track_name_label.text = track.display_name
	_track_summary_label.text = track.summary

	_start_button.disabled = not can_edit
	_start_button.label.text = tr("ALOITA KISA") if can_edit else tr("ISÄNTÄ ALOITTAA")
	_status_label.add_theme_color_override("font_color", UiStyle.TEXT_SECONDARY)
	var waiting_for: String = _get_first_unready()
	var counts: Vector2i = _count_ready()
	if waiting_for.is_empty():
		_status_label.text = tr("Kaikki valmiina")
	else:
		_status_label.text = tr("%d/%d valmiina · odotetaan: %s") % [counts.x, counts.y, waiting_for]
	# A client that left the race early waits here while the others finish.
	if online and Network.is_client() and Network.in_race:
		_status_label.text = tr("Muut ajavat vielä kisaa loppuun")


## Name of the first human player who is not ready, or "".
func _get_first_unready() -> String:
	for i: int in GameState.MAX_PLAYERS:
		var setup: PlayerSetup = GameState.players[i]
		if setup.joined and not setup.is_ai and not setup.is_ready:
			return GameState.get_player_name(i)
	return ""


## x = ready humans, y = all humans.
func _count_ready() -> Vector2i:
	var counts: Vector2i = Vector2i.ZERO
	for setup: PlayerSetup in GameState.players:
		if setup.joined and not setup.is_ai:
			counts.y += 1
			if setup.is_ready:
				counts.x += 1
	return counts


## A: join an empty slot, toggle ready, or remove a computer driver.
func _on_card_pressed(player: int) -> void:
	var setup: PlayerSetup = GameState.players[player]
	if _is_online():
		if player == Network.local_slot:
			Network.set_local_ready(not setup.is_ready)
		elif Network.is_host() and setup.is_ai:
			Network.set_slot_ai(player, false)
		elif Network.is_host() and not setup.joined:
			Network.set_slot_ai(player, true)
		return
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
	go_to(CAR_SELECT, {
		"player": player, "return_to": LOBBY, "return_context": {"focus_player": player, "tab": _tab},
	})


func _on_device_changed(player_index: int) -> void:
	# A gamepad that just claimed a slot joins straight away, replacing a computer driver.
	if _tab == Tab.SPLIT and InputManager.get_device(player_index) == InputManager.Device.JOYPAD:
		var setup: PlayerSetup = GameState.players[player_index]
		if not setup.joined or setup.is_ai:
			setup.joined = true
			setup.is_ai = false
			setup.is_ready = false
	_refresh()


func _try_start() -> void:
	if _start_button.disabled:
		return
	if not _get_first_unready().is_empty():
		_status_label.add_theme_color_override("font_color", UiStyle.WARNING)
		return
	if _is_online():
		Network.start_race()
	else:
		GameState.start_race()
