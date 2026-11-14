class_name SplitScreen
extends Control
## Lays out one PlayerView per local player (SPEC.md section 4) and owns the
## widgets the players share in split screen: the minimap and overtake messages
## (mockups/06_Jaettu.png). Supports 1 and 2 players for now.

@export var gap: float = 4.0
@export var gap_color: Color = Color("#06080f")

@export_group("Shared minimap")
@export var minimap_size: Vector2 = Vector2(170.0, 110.0)
@export var minimap_top: float = 20.0
@export var minimap_padding: float = 8.0
## Free space kept between the shared minimap and a pane's own panels.
@export var minimap_clearance: float = 8.0

@export_group("Overtake message")
## Gap between the shared minimap and the message below it.
@export var message_gap: float = 8.0
@export var message_display_seconds: float = 2.5

var views: Array[PlayerView] = []

var _layout: GameState.SplitLayout = GameState.SplitLayout.VERTICAL
var _message_panel: ChamferPanel
var _overtaker_chip: ChamferPanel
var _overtaker_label: Label
var _overtaken_chip: ChamferPanel
var _overtaken_label: Label
var _message_time_left: float = 0.0


func setup(manager: RaceManager, track: Track, racers: Array[RacerState], layout: GameState.SplitLayout) -> void:
	_layout = layout
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = gap_color
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var is_split: bool = racers.size() > 1
	for racer: RacerState in racers:
		var view: PlayerView = PlayerView.new()
		view.name = "View%d" % (racer.player_index + 1)
		add_child(view)
		views.append(view)
	_layout_views()
	for i: int in views.size():
		views[i].setup(manager, racers[i], track, is_split, is_split)

	if is_split:
		_build_shared_minimap(manager, track)
		_build_message_panel()
		manager.overtake.connect(_on_overtake)
	resized.connect(_layout_views)


func apply_preset(preset: EnvPreset) -> void:
	for view: PlayerView in views:
		view.apply_preset(preset)


func _process(delta: float) -> void:
	if _message_time_left > 0.0:
		_message_time_left -= delta
		if _message_time_left <= 0.0:
			_message_panel.visible = false


func _layout_views() -> void:
	if views.size() == 1:
		views[0].position = Vector2.ZERO
		views[0].size = size
		return
	# Two panes with a gap between them.
	var vertical: bool = _layout == GameState.SplitLayout.VERTICAL
	var pane: Vector2 = size
	if vertical:
		pane.x = (size.x - gap) * 0.5
	else:
		pane.y = (size.y - gap) * 0.5
	for i: int in views.size():
		var step: Vector2 = Vector2(pane.x + gap, 0.0) if vertical else Vector2(0.0, pane.y + gap)
		views[i].position = step * float(i)
		views[i].size = pane


func _build_shared_minimap(manager: RaceManager, track: Track) -> void:
	var padding: Vector4 = Vector4(minimap_padding, minimap_padding, minimap_padding, minimap_padding)
	var panel: ChamferPanel = ChamferPanel.create_panel(padding)
	if _layout == GameState.SplitLayout.VERTICAL:
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		panel.offset_top = minimap_top
	else:
		# Stacked panes: sit on the divider, clear of both pane centres.
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var minimap: Minimap = Minimap.new()
	minimap.custom_minimum_size = minimap_size
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(minimap)
	# -1: nobody is "own" on the shared map, every dot is drawn the same way.
	minimap.setup(track, manager.racers, -1)

	# Side by side, the map sits on the divider and would cover the corner of the second pane.
	if _layout == GameState.SplitLayout.VERTICAL and views.size() == 2:
		var half_panel: float = minimap_size.x * 0.5 + minimap_padding
		views[1].hud.set_top_left_x(half_panel - gap * 0.5 + minimap_clearance)


func _build_message_panel() -> void:
	_message_panel = ChamferPanel.create_panel(Vector4(16.0, 8.0, 16.0, 8.0))
	# Directly under the shared minimap, where it covers neither player's panels.
	var map_height: float = minimap_size.y + minimap_padding * 2.0
	if _layout == GameState.SplitLayout.VERTICAL:
		_message_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_message_panel.offset_top = minimap_top + map_height + message_gap
	else:
		_message_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_message_panel.offset_top = map_height * 0.5 + message_gap
		_message_panel.offset_bottom = _message_panel.offset_top
	_message_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_panel.visible = false
	add_child(_message_panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_message_panel.add_child(row)
	_overtaker_chip = _add_player_chip(row)
	_overtaker_label = _overtaker_chip.get_child(0) as Label
	row.add_child(UiStyle.make_label(tr("ohitti"), UiStyle.FONT_SEMIBOLD, 14))
	_overtaken_chip = _add_player_chip(row)
	_overtaken_label = _overtaken_chip.get_child(0) as Label


func _add_player_chip(parent: Control) -> ChamferPanel:
	var chip: ChamferPanel = ChamferPanel.create_chip(UiStyle.ACCENT, 5.0, Vector4(6.0, 1.0, 6.0, 1.0))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(UiStyle.make_label("P1", UiStyle.FONT_DISPLAY, 13, UiStyle.TEXT_ON_ACCENT))
	parent.add_child(chip)
	return chip


func _on_overtake(overtaker: RacerState, overtaken: RacerState) -> void:
	_overtaker_chip.fill_color = GameState.get_player_color(overtaker.player_index)
	_overtaker_label.text = "P%d" % (overtaker.player_index + 1)
	_overtaken_chip.fill_color = GameState.get_player_color(overtaken.player_index)
	_overtaken_label.text = "P%d" % (overtaken.player_index + 1)
	_message_panel.visible = true
	_message_time_left = message_display_seconds
