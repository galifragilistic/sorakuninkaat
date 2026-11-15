extends MenuScreen
## Car select (mockups/03_Autovalinta.png): car list, turning preview, stat
## bars, paint and pattern for one player.
## Context: "player" (slot index), "next" / "next_context" (screen after confirming).

@export_group("Layout")
@export var list_position: Vector2 = Vector2(56.0, 118.0)
@export var list_width: float = 272.0
@export var list_row_height: float = 50.0
@export var preview_rect: Rect2 = Rect2(360.0, 96.0, 500.0, 430.0)
@export var name_font_size: int = 44
@export var panel_position: Vector2 = Vector2(894.0, 118.0)
@export var panel_width: float = 330.0
@export var confirm_size: Vector2 = Vector2(200.0, 56.0)

var _player: int = 0
var _car_index: int = 0
var _color: Color = Color.WHITE
var _pattern: PlayerSetup.Pattern = PlayerSetup.Pattern.STRIPE

var _car_buttons: Array[ChamferButton] = []
var _preview: CarPreview
var _name_label: Label
var _description_label: Label
var _owner_chip: ChamferPanel
var _stat_bars: Array[StatBar] = []
var _stat_values: Array[Label] = []
var _swatches: Array[ColorSwatch] = []
var _pattern_spinner: OptionSpinner


func _build() -> void:
	MenuKit.add_header(self, tr("VALITSE AUTO"))
	_build_owner_note()
	_build_list()
	_build_preview()
	_build_stats_panel()
	_build_confirm()
	MenuKit.add_hints(self, [
		[InputPrompts.Prompt.UP_DOWN, tr("Vaihda autoa")], [InputPrompts.Prompt.ACCEPT, tr("Vahvista")],
		[InputPrompts.Prompt.BACK, tr("Takaisin")],
	])


func _enter() -> void:
	_player = context.get("player", 0)
	var setup: PlayerSetup = GameState.players[_player]
	_car_index = maxi(0, Catalog.CARS.find(setup.stats))
	_color = setup.color
	_pattern = setup.pattern
	MenuKit.set_chip(_owner_chip, "P%d" % (_player + 1), GameState.get_player_color(_player))
	_pattern_spinner.index = _pattern
	_show_car(_car_index)
	_update_paint()


func _get_initial_focus() -> Control:
	return _car_buttons[_car_index]


func _build_owner_note() -> void:
	var row: HBoxContainer = MenuKit.make_hbox(12)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_right = -MenuKit.SCREEN_MARGIN
	row.offset_left = -MenuKit.SCREEN_MARGIN
	row.offset_top = MenuKit.HEADER_TOP + 12.0
	add_child(row)
	_owner_chip = MenuKit.make_player_chip(0, 15)
	row.add_child(_owner_chip)
	var total: int = Catalog.CARS.size() + Catalog.LOCKED_CAR_COUNT
	row.add_child(UiStyle.make_label(
		tr("Autotalli · %d/%d avattu") % [Catalog.CARS.size(), total], UiStyle.FONT_MEDIUM, 16, UiStyle.TEXT_SECONDARY
	))


func _build_list() -> void:
	var column: VBoxContainer = MenuKit.make_vbox(8)
	column.position = list_position
	add_child(column)
	for i: int in Catalog.CARS.size():
		var car: CarStats = Catalog.CARS[i]
		var button: ChamferButton = ChamferButton.create(car.display_name, 18, Vector4(16.0, 0.0, 16.0, 0.0))
		button.custom_minimum_size = Vector2(list_width, list_row_height)
		button.selected_color = UiStyle.ACCENT
		button.add_right_label(tr("LUOKKA %s") % car.car_class, UiStyle.caps_font(), UiStyle.MIN_FONT_SIZE)
		button.focused.connect(_show_car.bind(i))
		button.pressed.connect(_confirm)
		column.add_child(button)
		_car_buttons.append(button)

	var locked: ChamferButton = ChamferButton.create(
		tr("%d lukittua autoa") % Catalog.LOCKED_CAR_COUNT, 15, Vector4(16.0, 0.0, 12.0, 0.0)
	)
	locked.label.add_theme_font_override("font", UiStyle.FONT_MEDIUM)
	locked.custom_minimum_size = Vector2(list_width, list_row_height)
	locked.add_glyph(UiGlyph.Kind.LOCK)
	locked.disabled = true
	column.add_child(locked)


func _build_preview() -> void:
	_preview = CarPreview.new()
	_preview.position = preview_rect.position
	_preview.size = preview_rect.size
	add_child(_preview)

	_name_label = UiStyle.make_label("", UiStyle.title_font(), name_font_size)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.position = Vector2(preview_rect.position.x, preview_rect.end.y + 8.0)
	_name_label.size.x = preview_rect.size.x
	add_child(_name_label)
	_description_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 16, UiStyle.TEXT_SECONDARY)
	_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description_label.position = _name_label.position + Vector2(0.0, float(name_font_size) + 16.0)
	_description_label.size.x = preview_rect.size.x
	add_child(_description_label)


func _build_stats_panel() -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(22.0, 20.0, 22.0, 20.0))
	panel.position = panel_position
	panel.custom_minimum_size.x = panel_width
	add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(7)
	panel.add_child(column)
	column.add_child(UiStyle.make_caption(tr("OMINAISUUDET")))

	var stats: Array = [
		[tr("Huippunopeus"), UiStyle.ACCENT], [tr("Kiihtyvyys"), UiStyle.ACCENT],
		[tr("Pito soralla"), UiStyle.INFO], [tr("Pito asfaltilla"), UiStyle.INFO],
		[tr("Kestävyys"), UiStyle.SUCCESS],
	]
	for stat: Array in stats:
		var header: HBoxContainer = MenuKit.make_hbox(0)
		column.add_child(header)
		var stat_name: String = stat[0]
		var title: Label = UiStyle.make_label(stat_name, UiStyle.FONT_MEDIUM, 15, UiStyle.TEXT_SECONDARY)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var value: Label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 15)
		header.add_child(value)
		_stat_values.append(value)
		var bar: StatBar = StatBar.new()
		bar.fill_color = stat[1]
		column.add_child(bar)
		_stat_bars.append(bar)

	column.add_child(UiStyle.make_caption(tr("VÄRI")))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for paint: Color in Catalog.CAR_COLORS:
		var swatch: ColorSwatch = ColorSwatch.new()
		swatch.color = paint
		swatch.pressed.connect(_on_color_picked.bind(paint))
		grid.add_child(swatch)
		_swatches.append(swatch)

	_pattern_spinner = OptionSpinner.create(
		tr("Kuvio"), PackedStringArray([tr("Kilparaita"), tr("Yksivärinen")]), 0
	)
	_pattern_spinner.value_width = 130.0
	_pattern_spinner.value_changed.connect(_on_pattern_changed)
	column.add_child(_pattern_spinner)


func _build_confirm() -> void:
	var button: ChamferButton = ChamferButton.create(tr("VAHVISTA"), 20, Vector4(24.0, 0.0, 16.0, 0.0))
	button.primary = true
	button.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_glyph(UiGlyph.Kind.CHEVRON_RIGHT)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.offset_right = -MenuKit.SCREEN_MARGIN
	button.offset_left = -MenuKit.SCREEN_MARGIN
	button.offset_bottom = -MenuKit.HINTS_BOTTOM
	button.offset_top = -MenuKit.HINTS_BOTTOM
	button.custom_minimum_size = confirm_size
	button.pressed.connect(_confirm)
	add_child(button)


func _show_car(index: int) -> void:
	_car_index = index
	var car: CarStats = Catalog.CARS[index]
	for i: int in _car_buttons.size():
		_car_buttons[i].selected = i == index
	_name_label.text = car.display_name.to_upper()
	_description_label.text = tr("%s · luokka %s") % [car.description, car.car_class]
	var values: Array[int] = [car.top_speed, car.acceleration, car.grip_gravel, car.grip_asphalt, car.durability]
	for i: int in values.size():
		_stat_bars[i].value = values[i]
		_stat_values[i].text = "%d/%d" % [values[i], CarStats.STAT_MAX]
	_preview.show_car(_color, _pattern, car)


func _update_paint() -> void:
	for swatch: ColorSwatch in _swatches:
		swatch.selected = swatch.color.is_equal_approx(_color)
	_preview.show_car(_color, _pattern, Catalog.CARS[_car_index])


func _on_color_picked(paint: Color) -> void:
	_color = paint
	_update_paint()


func _on_pattern_changed(index: int) -> void:
	_pattern = index as PlayerSetup.Pattern
	_update_paint()


func _confirm() -> void:
	var setup: PlayerSetup = GameState.players[_player]
	setup.stats = Catalog.CARS[_car_index]
	setup.color = _color
	setup.pattern = _pattern
	if context.has("next"):
		# Remember how to come back here from the next screen.
		var next_context: Dictionary = context.get("next_context", {}).duplicate()
		next_context["return_to"] = CAR_SELECT
		next_context["return_context"] = context
		go_to(context["next"], next_context)
	elif GameState.mode == GameState.Mode.NET and Network.is_online():
		# The host keeps the shared lobby; picking a car also means "ready".
		Network.submit_local_setup()
		Network.set_local_ready(true)
		_on_back()
	else:
		setup.is_ready = setup.joined
		_on_back()
