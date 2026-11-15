class_name PlayerView
extends Control
## One player's pane: a SubViewport with its own CameraRig that renders the
## shared World3D, plus that player's vignette, HUD and coloured frame.

const HUD_SCENE: PackedScene = preload("res://ui/hud/race_hud.tscn")
const VIGNETTE_SHADER: Shader = preload("res://env/shaders/vignette.gdshader")

## Width of the player-coloured frame in split screen (HUD units).
@export var frame_width: int = 4
@export var camera_far: float = 250.0
@export var camera_near: float = 1.0
## Vertical view size in metres for a pane with the reference aspect ratio.
@export var view_size: float = 27.0
@export var reference_aspect: float = 16.0 / 9.0
## How strongly wide panes zoom in: 0 keeps the vertical size, 1 keeps the
## horizontal size, 0.5 splits the difference.
@export_range(0.0, 1.0, 0.05) var wide_zoom_compensation: float = 0.5

var racer: RacerState
var camera_rig: CameraRig
var hud: RaceHud

var _viewport: SubViewport
var _vignette_material: ShaderMaterial


## Call after the view is in the tree. compact picks the split-screen HUD,
## show_frame draws the player-coloured border, own_minimap adds a small map to the HUD.
func setup(
	manager: RaceManager, view_racer: RacerState, track: Track,
	compact: bool, show_frame: bool, own_minimap: bool = false
) -> void:
	racer = view_racer
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var main_viewport: Viewport = get_viewport()

	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	# Share the main scene's 3D world instead of creating a new one.
	_viewport.world_3d = main_viewport.find_world_3d()
	_viewport.msaa_3d = main_viewport.msaa_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	camera_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_rig.target = racer.car
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	camera.near = camera_near
	camera.far = camera_far
	camera.current = true
	camera_rig.add_child(camera)
	_viewport.add_child(camera_rig)

	var picture: TextureRect = TextureRect.new()
	picture.texture = _viewport.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(picture)

	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = VIGNETTE_SHADER
	var vignette: ColorRect = ColorRect.new()
	vignette.material = _vignette_material
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)

	hud = HUD_SCENE.instantiate() as RaceHud
	hud.compact = compact
	hud.compact_minimap = own_minimap
	add_child(hud)
	hud.setup(manager, racer, track, camera)

	if show_frame:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.draw_center = false
		style.set_border_width_all(frame_width)
		style.border_color = GameState.get_player_color(racer.player_index)
		var frame: Panel = Panel.new()
		frame.add_theme_stylebox_override("panel", style)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(frame)

	resized.connect(_update_viewport_size)
	get_window().size_changed.connect(_update_viewport_size)
	_update_viewport_size()


func apply_preset(preset: EnvPreset) -> void:
	_vignette_material.set_shader_parameter("strength", preset.vignette_strength)
	_vignette_material.set_shader_parameter("tint", preset.vignette_color)


## Renders at the pane's real pixel size, so the 3D view stays sharp when the
## window is larger than the 1280x720 design resolution.
func _update_viewport_size() -> void:
	var pixel_scale: Vector2 = Vector2(get_window().size) / get_viewport_rect().size
	var pixels: Vector2 = (size * pixel_scale).round()
	_viewport.size = Vector2i(maxi(2, int(pixels.x)), maxi(2, int(pixels.y)))
	hud.view_scale = Vector2(_viewport.size) / size.max(Vector2.ONE)
	# A wide, low pane (horizontal split) would otherwise show the cars far too small.
	var aspect: float = size.x / maxf(size.y, 1.0)
	var zoom: float = pow(minf(1.0, reference_aspect / aspect), wide_zoom_compensation)
	camera_rig.base_size = view_size * zoom
