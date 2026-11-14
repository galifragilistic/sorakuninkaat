class_name ChamferPanel
extends MarginContainer
## Container drawn with the chamfered panel shader. Children are laid out
## inside the padding like in a MarginContainer.

const PANEL_SHADER: Shader = preload("res://ui/shaders/panel.gdshader")

@export var chamfer: float = 14.0:
	set(value):
		chamfer = value
		_update_material()
@export var border_width: float = 2.0:
	set(value):
		border_width = value
		_update_material()
@export var fill_color: Color = UiStyle.PANEL:
	set(value):
		fill_color = value
		_update_material()
@export var border_color: Color = UiStyle.LINE:
	set(value):
		border_color = value
		_update_material()
## Backdrop blur strength (screen texture mip level). 0 = no blur.
@export var blur_amount: float = 2.5:
	set(value):
		blur_amount = value
		_update_material()

var _material: ShaderMaterial


## Standard HUD panel: 14 px chamfer, 2 px border, blurred backdrop.
static func create_panel(padding: Vector4) -> ChamferPanel:
	var panel: ChamferPanel = ChamferPanel.new()
	panel.set_padding(padding)
	return panel


## Flat chip or row without a border or blur.
static func create_chip(color: Color, chip_chamfer: float, padding: Vector4) -> ChamferPanel:
	var chip: ChamferPanel = ChamferPanel.new()
	chip.chamfer = chip_chamfer
	chip.border_width = 0.0
	chip.blur_amount = 0.0
	chip.fill_color = color
	chip.set_padding(padding)
	return chip


func _init() -> void:
	_material = ShaderMaterial.new()
	_material.shader = PANEL_SHADER
	material = _material
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_material()


## x = left, y = top, z = right, w = bottom (pixels).
func set_padding(padding: Vector4) -> void:
	add_theme_constant_override("margin_left", roundi(padding.x))
	add_theme_constant_override("margin_top", roundi(padding.y))
	add_theme_constant_override("margin_right", roundi(padding.z))
	add_theme_constant_override("margin_bottom", roundi(padding.w))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_material()
		queue_redraw()


func _draw() -> void:
	# Resize notifications are not sent outside the tree, so sync the size here too.
	_material.set_shader_parameter("rect_size", size)
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


func _update_material() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("rect_size", size)
	_material.set_shader_parameter("chamfer", chamfer)
	_material.set_shader_parameter("border_width", border_width)
	_material.set_shader_parameter("fill_color", fill_color)
	_material.set_shader_parameter("border_color", border_color)
	_material.set_shader_parameter("blur_amount", blur_amount)
