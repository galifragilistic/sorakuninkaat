class_name MenuRoot
extends Control
## Main scene of the menus. Keeps the 3D backdrop alive while screens are
## swapped on top of it (SPEC.md section 5).

const SCREENS: Dictionary = {
	MenuScreen.MAIN: preload("res://ui/menus/main_menu.tscn"),
	MenuScreen.LOBBY: preload("res://ui/menus/lobby.tscn"),
	MenuScreen.CAR_SELECT: preload("res://ui/menus/car_select.tscn"),
	MenuScreen.TRACK_SELECT: preload("res://ui/menus/track_select.tscn"),
	MenuScreen.SETTINGS: preload("res://ui/menus/settings_screen.tscn"),
}

## Sideways shift of the backdrop so the road stays clear of the main menu column (m).
@export var backdrop_shift: float = -9.0

var _backdrop: WorldPreview
var _scrim: ColorRect
var _solid: ColorRect
var _screen: MenuScreen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_solid = _add_fill(UiStyle.BASE)

	_backdrop = WorldPreview.new()
	_backdrop.camera_mode = WorldPreview.CameraMode.FLYOVER
	_backdrop.flyover_shift = backdrop_shift
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_backdrop.show_track(Catalog.get_default_track())

	_scrim = _add_fill(UiStyle.SCRIM)

	var start: StringName = GameState.menu_start_screen
	var start_context: Dictionary = GameState.menu_start_context
	GameState.menu_start_screen = &""
	GameState.menu_start_context = {}
	if SCREENS.has(start):
		show_screen(start, start_context)
	else:
		show_screen(MenuScreen.MAIN, {})


func show_screen(screen_name: StringName, context: Dictionary) -> void:
	if _screen != null:
		_screen.queue_free()
	var scene: PackedScene = SCREENS[screen_name]
	_screen = scene.instantiate() as MenuScreen
	_screen.screen_requested.connect(show_screen)
	add_child(_screen)

	var backdrop: MenuScreen.Backdrop = _screen.get_backdrop()
	_backdrop.visible = backdrop != MenuScreen.Backdrop.HIDDEN
	_scrim.visible = backdrop == MenuScreen.Backdrop.DIMMED
	_solid.visible = backdrop == MenuScreen.Backdrop.HIDDEN
	_screen.open(context)


func _add_fill(color: Color) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	return rect
