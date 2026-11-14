extends MenuScreen
## Settings screen: graphics quality, fullscreen, damage and a controls reference.

@export var panel_position: Vector2 = Vector2(56.0, 120.0)
@export var panel_width: float = 520.0
@export var controls_position: Vector2 = Vector2(620.0, 120.0)
@export var controls_width: float = 604.0

var _settings: SettingsPanel


func get_backdrop() -> Backdrop:
	return Backdrop.DIMMED


func _build() -> void:
	MenuKit.add_header(self, tr("ASETUKSET"))

	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(24.0, 22.0, 24.0, 24.0))
	panel.position = panel_position
	panel.custom_minimum_size.x = panel_width
	add_child(panel)
	var column: VBoxContainer = MenuKit.make_vbox(14)
	panel.add_child(column)
	column.add_child(UiStyle.make_caption(tr("PELI JA GRAFIIKKA")))
	_settings = SettingsPanel.new()
	column.add_child(_settings)

	var controls: ChamferPanel = ChamferPanel.create_panel(Vector4(24.0, 22.0, 24.0, 24.0))
	controls.position = controls_position
	controls.custom_minimum_size.x = controls_width
	add_child(controls)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	var controls_column: VBoxContainer = MenuKit.make_vbox(14)
	controls.add_child(controls_column)
	controls_column.add_child(UiStyle.make_caption(tr("OHJAIMET")))
	controls_column.add_child(grid)
	var rows: Array = [
		["", tr("P1"), tr("P2"), tr("Ohjain")],
		[tr("Kaasu / jarru"), "W / S", "↑ / ↓", "RT / LT"],
		[tr("Ohjaus"), "A / D", "← / →", tr("Vasen tikku")],
		[tr("Käsijarru"), tr("Välilyönti"), "Shift", "X"],
		[tr("Pyörilleen"), "R", "Enter", "Back"],
		[tr("Tauko"), "Esc", "Esc", "Start"],
	]
	for row_index: int in rows.size():
		var row: Array = rows[row_index]
		for column_index: int in row.size():
			var is_heading: bool = row_index == 0 or column_index == 0
			var cell_text: String = row[column_index]
			var cell: Label = UiStyle.make_label(
				cell_text, UiStyle.FONT_SEMIBOLD if is_heading else UiStyle.FONT_MEDIUM, 15,
				UiStyle.TEXT_SECONDARY if is_heading else UiStyle.TEXT
			)
			grid.add_child(cell)
	controls_column.add_child(UiStyle.make_label(
		tr("Yksin ajaessa käyvät näppäimistö ja ohjain. Kaksinpelissä ohjain on pelaaja 2."),
		UiStyle.FONT_MEDIUM, 14, UiStyle.TEXT_SECONDARY
	))
	MenuKit.add_hints(self, [["◀ ▶", tr("Muuta")], ["B", tr("Takaisin")]])


func _get_initial_focus() -> Control:
	return _settings.get_first_control()
