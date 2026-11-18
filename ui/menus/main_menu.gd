extends MenuScreen
## Main menu (mockups/01_Main.png): logo, menu column on a slanted dark panel
## and the controller status box, over the living 3D backdrop.

@export_group("Layout")
## Width of the dark side panel at the top and bottom edge.
@export var panel_top_width: float = 540.0
@export var panel_bottom_width: float = 455.0
@export_range(0.0, 1.0, 0.01) var panel_alpha: float = 0.93
@export var logo_position: Vector2 = Vector2(64.0, 44.0)
@export var logo_font_size: int = 62
@export var menu_position: Vector2 = Vector2(64.0, 236.0)
@export var item_width: float = 340.0
@export var item_height: float = 46.0
@export var item_gap: int = 6
## Size of the item that has focus.
@export var focused_item_size: Vector2 = Vector2(372.0, 76.0)
@export var controllers_box_width: float = 400.0

var _first_item: ChamferButton
var _device_labels: Array[Label] = []


func get_backdrop() -> Backdrop:
	return Backdrop.FULL


func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2.ZERO, Vector2(panel_top_width, 0.0), Vector2(panel_bottom_width, size.y), Vector2(0.0, size.y),
	]), Color(UiStyle.BASE, panel_alpha))


func _build() -> void:
	resized.connect(queue_redraw)
	_build_logo()
	var column: VBoxContainer = MenuKit.make_vbox(item_gap)
	column.position = menu_position
	add_child(column)
	_first_item = _add_item(column, tr("YKSINPELI"), tr("Aja kisa yksin kelloa vastaan"), _on_single_player)
	_add_item(column, tr("MONINPELI"), tr("Jaettu ruutu tai verkko · 1–4 pelaajaa"), go_to.bind(LOBBY))
	_add_item(column, tr("AUTOTALLI"), tr("Autot, värit ja kuviot"), go_to.bind(CAR_SELECT, {"player": 0}))
	_add_item(column, tr("RADAT"), tr("Selaa ja valitse rata"), go_to.bind(TRACK_SELECT))
	_add_item(column, tr("RATAEDITORI"), tr("Piirrä oma rata"), go_to.bind(TRACK_EDITOR))
	_add_item(column, tr("ASETUKSET"), tr("Grafiikka ja pelisäännöt"), go_to.bind(SETTINGS))
	_add_item(column, tr("LOPETA"), tr("Sulje peli"), _on_quit)
	_build_controllers_box()
	MenuKit.add_hints(self, [[InputPrompts.Prompt.ACCEPT, tr("Valitse")]])


func _enter() -> void:
	InputManager.device_changed.connect(_update_devices.unbind(1))
	_update_devices()


func _get_initial_focus() -> Control:
	return _first_item


## There is nowhere to go back to from the main menu.
func _on_back() -> void:
	pass


func _build_logo() -> void:
	var lines: Array[String] = [tr("SORALLI")]
	for i: int in lines.size():
		var line: Label = UiStyle.make_label(lines[i], UiStyle.title_font(), logo_font_size, UiStyle.ACCENT)
		line.add_theme_color_override("font_shadow_color", Color("#a8420a"))
		line.add_theme_constant_override("shadow_offset_x", 0)
		line.add_theme_constant_override("shadow_offset_y", 4)
		line.position = logo_position + Vector2(-8.0 * float(i), float(logo_font_size - 6) * float(i))
		add_child(line)

	var tagline: HBoxContainer = MenuKit.make_hbox(10)
	tagline.position = logo_position + Vector2(0.0, float(logo_font_size) * float(lines.size()) + 14.0)
	add_child(tagline)
	var dash: ColorRect = ColorRect.new()
	dash.color = UiStyle.INFO
	dash.custom_minimum_size = Vector2(40.0, 3.0)
	dash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tagline.add_child(dash)
	tagline.add_child(UiStyle.make_caption(tr("ISOMETRINEN RALLI · 1–4 PELAAJAA"), UiStyle.INFO))


func _add_item(column: VBoxContainer, title: String, subtitle: String, action: Callable) -> ChamferButton:
	var item: ChamferButton = ChamferButton.new()
	item.set_padding(Vector4(20.0, 6.0, 18.0, 6.0))
	item.custom_minimum_size = Vector2(item_width, item_height)
	item.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(item)

	var texts: VBoxContainer = MenuKit.make_vbox(-2)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.row.add_child(texts)
	var title_label: Label = UiStyle.make_label(title, UiStyle.FONT_DISPLAY, 20)
	texts.add_child(title_label)
	item.register_label(title_label)
	var subtitle_label: Label = UiStyle.make_label(subtitle, UiStyle.FONT_SEMIBOLD, 14)
	subtitle_label.visible = false
	texts.add_child(subtitle_label)
	item.register_label(subtitle_label)
	var chevron: UiGlyph = item.add_glyph(UiGlyph.Kind.CHEVRON_RIGHT)
	chevron.visible = false

	# The focused item grows and reveals its description.
	item.focus_entered.connect(func() -> void:
		item.custom_minimum_size = focused_item_size
		subtitle_label.visible = true
		chevron.visible = true)
	item.focus_exited.connect(func() -> void:
		item.custom_minimum_size = Vector2(item_width, item_height)
		subtitle_label.visible = false
		chevron.visible = false)
	item.pressed.connect(action)
	return item


func _build_controllers_box() -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(20.0, 16.0, 20.0, 18.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -MenuKit.SCREEN_MARGIN
	panel.offset_left = -MenuKit.SCREEN_MARGIN
	panel.offset_bottom = -MenuKit.HINTS_BOTTOM
	panel.offset_top = -MenuKit.HINTS_BOTTOM
	panel.custom_minimum_size.x = controllers_box_width
	add_child(panel)

	var column: VBoxContainer = MenuKit.make_vbox(10)
	panel.add_child(column)
	column.add_child(UiStyle.make_caption(tr("OHJAIMET")))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for i: int in GameState.MAX_PLAYERS:
		var cell: ChamferPanel = ChamferPanel.create_chip(UiStyle.BUTTON, 6.0, Vector4(8.0, 6.0, 8.0, 6.0))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var row: HBoxContainer = MenuKit.make_hbox(10)
		cell.add_child(row)
		row.add_child(MenuKit.make_player_chip(i))
		var device: Label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 14)
		row.add_child(device)
		_device_labels.append(device)


func _update_devices() -> void:
	for i: int in _device_labels.size():
		# Gamepads claim a slot with A in the lobby, not here, so A keeps selecting menu items.
		var has_device: bool = InputManager.get_device(i) != InputManager.Device.NONE
		_device_labels[i].text = InputManager.get_device_name(i) if has_device else tr("Liity aulassa")
		_device_labels[i].add_theme_color_override(
			"font_color", UiStyle.TEXT if has_device else UiStyle.TEXT_SECONDARY
		)


func _on_single_player() -> void:
	GameState.mode = GameState.Mode.SINGLE
	go_to(CAR_SELECT, {"player": 0, "next": TRACK_SELECT, "next_context": {"start_race": true}})


func _on_quit() -> void:
	get_tree().quit()
