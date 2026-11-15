class_name ResultsScreen
extends Control
## Results overlay shown over the blurred race view (mockups/07_Tulokset.png):
## podium, result table with points and the next-step buttons.

signal rematch_requested
signal change_track_requested
signal leave_requested

@export_group("Layout")
@export var title_position: Vector2 = Vector2(56.0, 40.0)
@export var title_font_size: int = 60
@export var podium_position: Vector2 = Vector2(56.0, 210.0)
@export var podium_box_width: float = 128.0
@export var podium_gap: float = 10.0
## Box heights for places 1, 2 and 3.
@export var podium_heights: PackedFloat32Array = PackedFloat32Array([210.0, 150.0, 110.0])
@export var podium_car_size: Vector2 = Vector2(150.0, 110.0)
@export var table_position: Vector2 = Vector2(522.0, 150.0)
@export var table_width: float = 702.0
@export var row_height: float = 56.0
## Column widths: place, driver, car, time, best lap. Points take the rest.
@export var column_widths: PackedFloat32Array = PackedFloat32Array([56.0, 190.0, 130.0, 100.0, 150.0])

var _first_button: ChamferButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(manager: RaceManager, track: TrackInfo) -> void:
	add_child(MenuKit.make_blur_backdrop())
	var standings: Array[RacerState] = manager.get_standings()

	var caption: Label = UiStyle.make_caption(
		tr("%s · %d KIERROSTA · %s · %s") % [
			track.display_name.to_upper(), manager.lap_count,
			GameState.get_time_preset().display_name.to_upper(), GameState.get_weather().display_name.to_upper(),
		], UiStyle.INFO
	)
	caption.position = title_position
	add_child(caption)
	var title: Label = UiStyle.make_label(tr("KISA PÄÄTTYI"), UiStyle.title_font(), title_font_size)
	title.position = title_position + Vector2(0.0, 18.0)
	add_child(title)

	_build_podium(standings)
	_build_table(standings)
	_build_buttons()
	MenuKit.add_hints(self, [["A", tr("Valitse")]])
	_first_button.grab_focus.call_deferred()


func _build_podium(standings: Array[RacerState]) -> void:
	# Left to right: 2nd, 1st, 3rd.
	var order: Array[int] = [1, 0, 2]
	var base_y: float = podium_position.y + podium_heights[0] + podium_car_size.y
	var slot: int = 0
	for place_index: int in order:
		if place_index >= standings.size():
			slot += 1
			continue
		var racer: RacerState = standings[place_index]
		var height: float = podium_heights[place_index]
		var x: float = podium_position.x + float(slot) * (podium_box_width + podium_gap)
		slot += 1

		var box: ChamferPanel = ChamferPanel.create_chip(
			GameState.get_player_color(racer.player_index), 12.0, Vector4(0.0, 14.0, 0.0, 0.0)
		)
		box.position = Vector2(x, base_y - height)
		box.size = Vector2(podium_box_width, height)
		add_child(box)
		var number: Label = UiStyle.make_label(str(place_index + 1), UiStyle.FONT_DISPLAY, 48, UiStyle.TEXT_ON_ACCENT)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.add_child(number)

		var car: CarPreview = CarPreview.new()
		car.show_stage = false
		car.view_size = 5.6
		car.spin_degrees_per_second = 0.0
		car.start_angle_degrees = -30.0
		car.size = podium_car_size
		car.position = Vector2(x + (podium_box_width - podium_car_size.x) * 0.5, base_y - height - podium_car_size.y + 18.0)
		add_child(car)
		car.show_setup(racer.setup)


func _build_table(standings: Array[RacerState]) -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(18.0, 22.0, 18.0, 22.0))
	panel.position = table_position
	panel.custom_minimum_size.x = table_width
	add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(6)
	panel.add_child(column)

	var header: HBoxContainer = MenuKit.make_hbox(0)
	column.add_child(header)
	var titles: Array[String] = [tr("SIJA"), tr("KUSKI"), tr("AUTO"), tr("AIKA"), tr("PARAS KIERROS"), tr("PISTEET")]
	for i: int in titles.size():
		header.add_child(_sized(UiStyle.make_caption(titles[i]), i, true))

	var fastest: RacerState = null
	for racer: RacerState in standings:
		if racer.has_best_lap() and (fastest == null or racer.best_lap_time < fastest.best_lap_time):
			fastest = racer

	for i: int in standings.size():
		var racer: RacerState = standings[i]
		var is_winner: bool = i == 0
		var row_color: Color = Color(UiStyle.INFO, 0.14) if is_winner else UiStyle.ROW
		var row_panel: ChamferPanel = ChamferPanel.create_chip(row_color, 6.0, Vector4(12.0, 0.0, 12.0, 0.0))
		row_panel.custom_minimum_size.y = row_height
		column.add_child(row_panel)
		var row: HBoxContainer = MenuKit.make_hbox(0)
		row_panel.add_child(row)

		row.add_child(_sized(UiStyle.make_label("%d." % (i + 1), UiStyle.FONT_DISPLAY, 22), 0))
		var driver: HBoxContainer = MenuKit.make_hbox(10)
		driver.add_child(MenuKit.make_chip(racer.get_tag(), GameState.get_player_color(racer.player_index)))
		driver.add_child(UiStyle.make_label(racer.display_name, UiStyle.FONT_MEDIUM, 17))
		row.add_child(_sized(driver, 1))
		row.add_child(_sized(UiStyle.make_label(
			racer.car.stats.display_name, UiStyle.FONT_MEDIUM, 16, UiStyle.TEXT_SECONDARY
		), 2))
		var time_text: String = tr("Kesken") if racer.did_not_finish else RaceFormat.lap_time(racer.finish_time)
		row.add_child(_sized(UiStyle.make_label(time_text, UiStyle.FONT_MEDIUM, 17), 3))

		var best: HBoxContainer = MenuKit.make_hbox(8)
		best.add_child(UiStyle.make_label(RaceFormat.lap_time(racer.best_lap_time), UiStyle.FONT_MEDIUM, 17))
		if racer == fastest:
			best.add_child(MenuKit.make_chip(tr("NOPEIN"), UiStyle.INFO))
		row.add_child(_sized(best, 4))

		var points: Label = UiStyle.make_label(
			"+%d" % Catalog.get_points(i + 1), UiStyle.FONT_DISPLAY, 18, UiStyle.SUCCESS
		)
		row.add_child(_sized(points, 5, true))


## Gives a table cell its column width. The last column expands and is right-aligned.
func _sized(cell: Control, column: int, is_text: bool = false) -> Control:
	if column < column_widths.size():
		cell.custom_minimum_size.x = column_widths[column]
	else:
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_text:
			(cell as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return cell


func _build_buttons() -> void:
	var row: HBoxContainer = MenuKit.make_hbox(10)
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_right = -MenuKit.SCREEN_MARGIN
	row.offset_left = -MenuKit.SCREEN_MARGIN
	row.offset_bottom = -MenuKit.HINTS_BOTTOM
	row.offset_top = -MenuKit.HINTS_BOTTOM
	add_child(row)

	var is_multi: bool = GameState.mode == GameState.Mode.MULTI
	var leave: ChamferButton = _add_button(row, tr("AULAAN") if is_multi else tr("VALIKKOON"), false)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	var change: ChamferButton = _add_button(row, tr("VAIHDA RATA"), false)
	change.pressed.connect(func() -> void: change_track_requested.emit())
	_first_button = _add_button(row, tr("UUSINTAKISA"), true)
	_first_button.pressed.connect(func() -> void: rematch_requested.emit())


func _add_button(row: HBoxContainer, text: String, is_primary: bool) -> ChamferButton:
	var button: ChamferButton = ChamferButton.create(text, 19, Vector4(26.0, 0.0, 26.0, 0.0))
	button.primary = is_primary
	button.custom_minimum_size.y = 56.0
	row.add_child(button)
	return button
