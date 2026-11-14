class_name RaceHud
extends Control
## One player's race HUD (mockups/05_Peli.png): position, lap, standings,
## lap time and split badge, minimap, damage, speedometer and player tags.
## Laid out for the 1280x720 design resolution; anchors keep it on the edges.
## In compact mode (split screen, mockups/06_Jaettu.png) only position, lap,
## time and speedometer are shown; the minimap is shared by SplitScreen.

## Set before the HUD enters the tree.
@export var compact: bool = false

@export_group("Layout")
@export var edge_margin: Vector2 = Vector2(32.0, 28.0)
@export var standings_top: float = 150.0
@export var standings_width: float = 236.0
@export var standings_row_height: float = 38.0
@export var minimap_size: Vector2 = Vector2(220.0, 142.0)
@export var speedometer_size: float = 196.0
@export var speedometer_margin: Vector2 = Vector2(28.0, 20.0)
@export var damage_icon_size: Vector2 = Vector2(60.0, 66.0)
@export var time_label_width: float = 170.0
## How far above the screen centre the countdown / finish banner sits.
@export var banner_lift: float = 120.0
@export var banner_font_size: int = 110

@export_group("Compact layout")
@export var compact_edge_margin: Vector2 = Vector2(24.0, 24.0)
@export var compact_speedometer_size: float = 136.0
@export var compact_speedometer_margin: Vector2 = Vector2(20.0, 16.0)
@export var compact_time_label_width: float = 118.0
@export var compact_banner_font_size: int = 76

@export_group("Behaviour")
## How long a split badge stays on screen (s).
@export var split_display_seconds: float = 3.0
## How long "AJA!" stays on screen after the start (s).
@export var go_display_seconds: float = 1.0
## Own row tint strength in the standings.
@export_range(0.0, 1.0, 0.01) var own_row_alpha: float = 0.22
## Zones below this damage are not listed by name.
@export_range(0.0, 1.0, 0.01) var zone_listing_threshold: float = 0.05

var _manager: RaceManager
var _racer: RacerState
var _camera: Camera3D

var _position_label: Label
var _position_total_label: Label
var _lap_label: Label
var _lap_total_label: Label
var _standings_box: VBoxContainer
var _standing_rows: Array[Dictionary] = []
var _time_label: Label
var _best_label: Label
var _split_badge: ChamferPanel
var _split_label: Label
var _minimap: Minimap
var _track_name_label: Label
var _track_length_label: Label
var _damage_icon: DamageIcon
var _damage_percent_label: Label
var _damage_zones_label: Label
var _speedometer: Speedometer
var _banner_label: Label
var _banner_hint_label: Label
var _tags_layer: Control
var _tags: Array[PlayerTag] = []

## SubViewport pixels per HUD unit; set by PlayerView so tags line up with the 3D view.
var view_scale: Vector2 = Vector2.ONE

var _top_left_row: HBoxContainer
var _player_chip: ChamferPanel
var _player_chip_label: Label
var _split_time_left: float = 0.0
var _banner_time_left: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_tags_layer()
	if compact:
		_build_compact_position_and_lap()
		_build_compact_time()
	else:
		_build_position_and_lap()
		_build_standings()
		_build_time()
		_build_minimap()
		_build_damage()
	_build_speedometer()
	_build_banner()


func setup(manager: RaceManager, racer: RacerState, track: Track, camera: Camera3D) -> void:
	_manager = manager
	_racer = racer
	_camera = camera
	var accent: Color = GameState.get_player_color(racer.player_index)

	_speedometer.accent_color = accent
	_speedometer.max_speed = racer.car.get_base_top_speed() * 3.6
	if compact:
		_player_chip.fill_color = accent
		_player_chip_label.text = "P%d" % (racer.player_index + 1)
	else:
		_minimap.setup(track, manager.racers, racer.player_index)
		_track_name_label.text = tr(track.track_name).to_upper()
		_track_length_label.text = tr("%d m") % roundi(track.get_length())
		_damage_icon.damage = racer.car.damage
		_rebuild_standings()
	for other: RacerState in manager.racers:
		if other == racer:
			continue
		var tag: PlayerTag = PlayerTag.new()
		tag.racer = other
		_tags_layer.add_child(tag)
		_tags.append(tag)

	manager.split_recorded.connect(_on_split_recorded)
	manager.countdown_tick.connect(_on_countdown_tick)
	manager.racer_finished.connect(_on_racer_finished)
	manager.state_changed.connect(_on_state_changed)


## Moves the top-left panels sideways, e.g. to clear the shared minimap in split screen.
func set_top_left_x(x: float) -> void:
	_top_left_row.position.x = x


func _process(delta: float) -> void:
	if _manager == null:
		return
	_position_label.text = str(_racer.position)
	_position_total_label.text = "/%d" % _manager.racers.size()
	_lap_label.text = str(_manager.get_display_lap(_racer))
	_lap_total_label.text = "/%d" % _manager.lap_count
	_time_label.text = RaceFormat.lap_time(_manager.get_display_time(_racer))

	var car: Car = _racer.car
	_speedometer.speed = car.get_speed_kmh()
	_speedometer.gear_text = _get_gear_text(car.get_gear())
	for tag: PlayerTag in _tags:
		tag.update_position(_camera, view_scale)

	if compact:
		# The delta line replaces this text once there is a reference lap.
		if not _racer.has_best_lap():
			_best_label.text = tr("Paras %s") % RaceFormat.lap_time(_racer.best_lap_time)
	else:
		_best_label.text = tr("PARAS %s") % RaceFormat.lap_time(_racer.best_lap_time)
		_update_damage(car.damage)
		_update_standings()
		if _split_time_left > 0.0:
			_split_time_left -= delta
			_split_badge.visible = _split_time_left > 0.0
	if _banner_time_left > 0.0:
		_banner_time_left -= delta
		if _banner_time_left <= 0.0:
			_banner_label.visible = false


# --- Building blocks -----------------------------------------------------

func _build_tags_layer() -> void:
	_tags_layer = Control.new()
	_tags_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tags_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_tags_layer)


func _build_position_and_lap() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.position = edge_margin
	add_child(row)
	_top_left_row = row

	var position_panel: ChamferPanel = ChamferPanel.create_panel(Vector4(20.0, 10.0, 20.0, 8.0))
	row.add_child(position_panel)
	var position_parts: Array[Label] = _add_big_number(position_panel, tr("SIJA"), 64, 26)
	_position_label = position_parts[0]
	_position_total_label = position_parts[1]

	var lap_panel: ChamferPanel = ChamferPanel.create_panel(Vector4(20.0, 10.0, 20.0, 8.0))
	row.add_child(lap_panel)
	var lap_parts: Array[Label] = _add_big_number(lap_panel, tr("KIERROS"), 40, 22)
	_lap_label = lap_parts[0]
	_lap_total_label = lap_parts[1]


## Compact: [P chip + position] and [lap] panels (mockups/06_Jaettu.png).
func _build_compact_position_and_lap() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.position = compact_edge_margin
	add_child(row)
	_top_left_row = row

	var position_panel: ChamferPanel = ChamferPanel.create_panel(Vector4(16.0, 4.0, 16.0, 4.0))
	row.add_child(position_panel)
	var position_row: HBoxContainer = HBoxContainer.new()
	position_row.add_theme_constant_override("separation", 12)
	position_panel.add_child(position_row)
	_player_chip = ChamferPanel.create_chip(UiStyle.ACCENT, 5.0, Vector4(8.0, 2.0, 8.0, 2.0))
	_player_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	position_row.add_child(_player_chip)
	_player_chip_label = UiStyle.make_label("P1", UiStyle.FONT_DISPLAY, 16, UiStyle.TEXT_ON_ACCENT)
	_player_chip.add_child(_player_chip_label)
	var position_parts: Array[Label] = _add_big_number(position_row, "", 46, 20)
	_position_label = position_parts[0]
	_position_total_label = position_parts[1]

	var lap_panel: ChamferPanel = ChamferPanel.create_panel(Vector4(16.0, 8.0, 16.0, 4.0))
	row.add_child(lap_panel)
	var lap_parts: Array[Label] = _add_big_number(lap_panel, tr("KIERROS"), 28, 16)
	_lap_label = lap_parts[0]
	_lap_total_label = lap_parts[1]


## Compact: lap time with the delta to the best lap underneath, bottom left.
func _build_compact_time() -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(16.0, 6.0, 16.0, 8.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = compact_edge_margin.x
	panel.offset_bottom = -compact_edge_margin.y
	panel.offset_top = -compact_edge_margin.y
	add_child(panel)
	var texts: VBoxContainer = VBoxContainer.new()
	texts.add_theme_constant_override("separation", -2)
	panel.add_child(texts)
	_time_label = UiStyle.make_label(RaceFormat.lap_time(0.0), UiStyle.FONT_DISPLAY, 26)
	_time_label.custom_minimum_size.x = compact_time_label_width
	texts.add_child(_time_label)
	_best_label = UiStyle.make_label("", UiStyle.FONT_BOLD, 14, UiStyle.TEXT_SECONDARY)
	texts.add_child(_best_label)


## Optional caption with a large number and a smaller "/total" after it. Returns [number, total].
func _add_big_number(parent: Control, caption: String, number_size: int, total_size: int) -> Array[Label]:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", -4)
	parent.add_child(column)
	if not caption.is_empty():
		column.add_child(UiStyle.make_caption(caption))

	var numbers: HBoxContainer = HBoxContainer.new()
	numbers.add_theme_constant_override("separation", 0)
	numbers.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	column.add_child(numbers)
	var number: Label = UiStyle.make_label("1", UiStyle.FONT_DISPLAY, number_size)
	number.size_flags_vertical = Control.SIZE_SHRINK_END
	numbers.add_child(number)
	var total: Label = UiStyle.make_label("/1", UiStyle.FONT_DISPLAY, total_size, UiStyle.TEXT_SECONDARY)
	total.size_flags_vertical = Control.SIZE_SHRINK_END
	# Line the smaller text up with the big number's baseline.
	var font: Font = UiStyle.FONT_DISPLAY
	var lift: float = font.get_descent(number_size) - font.get_descent(total_size)
	var wrapper: MarginContainer = MarginContainer.new()
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_END
	wrapper.add_theme_constant_override("margin_bottom", roundi(lift))
	wrapper.add_child(total)
	numbers.add_child(wrapper)
	return [number, total]


func _build_standings() -> void:
	_standings_box = VBoxContainer.new()
	_standings_box.add_theme_constant_override("separation", 4)
	_standings_box.position = Vector2(edge_margin.x, standings_top)
	_standings_box.custom_minimum_size.x = standings_width
	add_child(_standings_box)


func _rebuild_standings() -> void:
	for child: Node in _standings_box.get_children():
		child.queue_free()
	_standing_rows.clear()
	for i: int in _manager.racers.size():
		var row_panel: ChamferPanel = ChamferPanel.create_chip(UiStyle.ROW, 6.0, Vector4(12.0, 0.0, 12.0, 0.0))
		row_panel.custom_minimum_size = Vector2(standings_width, standings_row_height)
		_standings_box.add_child(row_panel)

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row_panel.add_child(row)

		var place: Label = UiStyle.make_label(str(i + 1), UiStyle.FONT_DISPLAY, 17)
		place.custom_minimum_size.x = 16.0
		row.add_child(place)

		var chip: ChamferPanel = ChamferPanel.create_chip(UiStyle.ACCENT, 5.0, Vector4(6.0, 1.0, 6.0, 1.0))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		var chip_label: Label = UiStyle.make_label("P1", UiStyle.FONT_DISPLAY, 13, UiStyle.TEXT_ON_ACCENT)
		chip.add_child(chip_label)

		var name_label: Label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)

		var gap: Label = UiStyle.make_label("", UiStyle.FONT_SEMIBOLD, 14, UiStyle.TEXT_SECONDARY)
		row.add_child(gap)

		_standing_rows.append({
			"panel": row_panel, "chip": chip, "chip_label": chip_label, "name": name_label, "gap": gap,
		})


func _update_standings() -> void:
	var standings: Array[RacerState] = _manager.get_standings()
	for i: int in mini(standings.size(), _standing_rows.size()):
		var entry: RacerState = standings[i]
		var row: Dictionary = _standing_rows[i]
		var color: Color = GameState.get_player_color(entry.player_index)
		var is_own: bool = entry == _racer
		var panel: ChamferPanel = row["panel"]
		panel.fill_color = Color(color, own_row_alpha) if is_own else UiStyle.ROW
		var chip: ChamferPanel = row["chip"]
		chip.fill_color = color
		var chip_label: Label = row["chip_label"]
		chip_label.text = "P%d" % (entry.player_index + 1)
		var name_label: Label = row["name"]
		name_label.text = entry.display_name
		name_label.add_theme_font_override("font", UiStyle.FONT_BOLD if is_own else UiStyle.FONT_MEDIUM)
		var gap: Label = row["gap"]
		gap.text = tr("Kärki") if i == 0 else RaceFormat.delta(entry.gap_to_leader, 1)


func _build_time() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.offset_top = edge_margin.y
	add_child(column)

	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(26.0, 8.0, 26.0, 8.0))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)
	var texts: VBoxContainer = VBoxContainer.new()
	texts.add_theme_constant_override("separation", -2)
	panel.add_child(texts)
	_time_label = UiStyle.make_label(RaceFormat.lap_time(0.0), UiStyle.FONT_DISPLAY, 38)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Fixed width so the panel does not twitch as digits change.
	_time_label.custom_minimum_size.x = time_label_width
	texts.add_child(_time_label)
	_best_label = UiStyle.make_label("", UiStyle.FONT_SEMIBOLD, 14, UiStyle.TEXT_SECONDARY)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	texts.add_child(_best_label)

	_split_badge = ChamferPanel.create_chip(UiStyle.INFO, 6.0, Vector4(16.0, 5.0, 16.0, 5.0))
	_split_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_split_badge.visible = false
	column.add_child(_split_badge)
	var badge_row: HBoxContainer = HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 10)
	_split_badge.add_child(badge_row)
	badge_row.add_child(UiStyle.make_caption(tr("VÄLIAIKA"), UiStyle.TEXT_ON_ACCENT))
	_split_label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, 20, UiStyle.TEXT_ON_ACCENT)
	badge_row.add_child(_split_label)


func _build_minimap() -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(10.0, 10.0, 10.0, 8.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -edge_margin.x
	panel.offset_left = -edge_margin.x
	panel.offset_top = edge_margin.y
	add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	_minimap = Minimap.new()
	_minimap.custom_minimum_size = minimap_size
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_minimap)

	var footer: HBoxContainer = HBoxContainer.new()
	column.add_child(footer)
	_track_name_label = UiStyle.make_caption("")
	_track_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_track_name_label)
	_track_length_label = UiStyle.make_caption("")
	footer.add_child(_track_length_label)


func _build_damage() -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(18.0, 14.0, 18.0, 14.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = edge_margin.x
	panel.offset_bottom = -edge_margin.y
	panel.offset_top = -edge_margin.y
	add_child(panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	_damage_icon = DamageIcon.new()
	_damage_icon.custom_minimum_size = damage_icon_size
	_damage_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_damage_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_damage_icon)

	var texts: VBoxContainer = VBoxContainer.new()
	texts.add_theme_constant_override("separation", -4)
	row.add_child(texts)
	texts.add_child(UiStyle.make_caption(tr("VAURIOT")))
	_damage_percent_label = UiStyle.make_label("0 %", UiStyle.FONT_DISPLAY, 30)
	texts.add_child(_damage_percent_label)
	_damage_zones_label = UiStyle.make_label("", UiStyle.FONT_SEMIBOLD, 14, UiStyle.WARNING)
	texts.add_child(_damage_zones_label)


func _build_speedometer() -> void:
	var panel: ChamferPanel = ChamferPanel.create_panel(Vector4(6.0, 6.0, 6.0, 6.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var margin: Vector2 = compact_speedometer_margin if compact else speedometer_margin
	panel.offset_right = -margin.x
	panel.offset_left = -margin.x
	panel.offset_bottom = -margin.y
	panel.offset_top = -margin.y
	if compact:
		panel.set_padding(Vector4(4.0, 4.0, 4.0, 4.0))
	add_child(panel)
	_speedometer = Speedometer.new()
	_speedometer.custom_minimum_size = Vector2.ONE * (compact_speedometer_size if compact else speedometer_size)
	_speedometer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_speedometer)


func _build_banner() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.offset_top -= banner_lift
	column.offset_bottom -= banner_lift
	add_child(column)

	var banner_size: int = compact_banner_font_size if compact else banner_font_size
	_banner_label = UiStyle.make_label("", UiStyle.FONT_DISPLAY, banner_size)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_color_override("font_outline_color", UiStyle.BASE)
	_banner_label.add_theme_constant_override("outline_size", 14)
	_banner_label.visible = false
	column.add_child(_banner_label)

	_banner_hint_label = UiStyle.make_label("", UiStyle.FONT_BOLD, 20)
	_banner_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_hint_label.add_theme_color_override("font_outline_color", UiStyle.BASE)
	_banner_hint_label.add_theme_constant_override("outline_size", 8)
	_banner_hint_label.visible = false
	column.add_child(_banner_hint_label)


# --- Updates -------------------------------------------------------------

func _get_gear_text(gear: int) -> String:
	if gear < 0:
		return tr("R")
	if gear == 0:
		return tr("N")
	return str(gear)


func _update_damage(damage: CarDamage) -> void:
	var total: float = damage.get_total()
	_damage_percent_label.text = tr("%d %%") % roundi(total * 100.0)
	var zone_names: Dictionary = {
		CarDamage.Zone.FRONT: tr("Etupää"),
		CarDamage.Zone.MIDDLE: tr("Keskiosa"),
		CarDamage.Zone.REAR: tr("Takapää"),
		CarDamage.Zone.TIRES: tr("Renkaat"),
	}
	var damaged: PackedStringArray = PackedStringArray()
	var worst: float = 0.0
	for zone: CarDamage.Zone in zone_names:
		var amount: float = damage.get_zone(zone)
		worst = maxf(worst, amount)
		if amount >= zone_listing_threshold:
			damaged.append(zone_names[zone])
	if damaged.is_empty():
		_damage_zones_label.text = tr("Ei vaurioita")
		_damage_zones_label.add_theme_color_override("font_color", UiStyle.TEXT_SECONDARY)
	else:
		_damage_zones_label.text = " · ".join(damaged)
		_damage_zones_label.add_theme_color_override("font_color", _damage_icon.get_zone_color(worst))


func _on_split_recorded(racer: RacerState, delta: float) -> void:
	if racer != _racer:
		return
	if compact:
		_best_label.text = tr("%s paras kierros") % RaceFormat.delta(delta)
		_best_label.add_theme_color_override("font_color", UiStyle.INFO if delta <= 0.0 else UiStyle.WARNING)
		return
	_split_label.text = RaceFormat.delta(delta)
	# Cyan when faster than the best lap, orange when slower.
	_split_badge.fill_color = UiStyle.INFO if delta <= 0.0 else UiStyle.ACCENT
	_split_badge.visible = true
	_split_time_left = split_display_seconds


func _on_countdown_tick(seconds_left: int) -> void:
	_banner_label.visible = true
	if seconds_left > 0:
		_banner_label.text = str(seconds_left)
		_banner_time_left = 0.0
	else:
		_banner_label.text = tr("AJA!")
		_banner_time_left = go_display_seconds


## Once everybody has finished, tell the players how to go again.
func _on_state_changed(state: RaceManager.State) -> void:
	if state == RaceManager.State.FINISHED:
		_banner_hint_label.text = tr("%s · Enter: uusi kisa") % RaceFormat.lap_time(_racer.finish_time)


func _on_racer_finished(racer: RacerState) -> void:
	if racer != _racer:
		return
	_banner_label.text = tr("MAALI")
	_banner_label.visible = true
	_banner_time_left = 0.0
	_banner_hint_label.text = RaceFormat.lap_time(racer.finish_time)
	_banner_hint_label.visible = true
