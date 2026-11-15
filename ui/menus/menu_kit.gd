class_name MenuKit
extends RefCounted
## Builders for the pieces every menu screen shares: header, button hints,
## chips and section captions. Sizes are in 1280x720 design units.

const SCREEN_MARGIN: float = 56.0
const HEADER_TOP: float = 34.0
const HINTS_BOTTOM: float = 30.0
const TITLE_FONT_SIZE: int = 40
const HINT_FONT_SIZE: int = 15
const BLUR_SHADER: Shader = preload("res://ui/shaders/backdrop_blur.gdshader")


## "(B) Takaisin   TITLE" row at the top-left of a screen. The prompt follows
## the device in use (Esc on the keyboard).
static func add_header(screen: Control, title: String, with_back_hint: bool = true) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.position = Vector2(SCREEN_MARGIN, HEADER_TOP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(row)
	if with_back_hint:
		row.add_child(make_hint(InputPrompts.Prompt.BACK, screen.tr("Takaisin")))
	row.add_child(UiStyle.make_label(title, UiStyle.title_font(), TITLE_FONT_SIZE))
	return row


## Row of button prompts along the bottom edge. hints = [[InputPrompts.Prompt, text], ...].
static func add_hints(screen: Control, hints: Array) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = SCREEN_MARGIN
	row.offset_bottom = -HINTS_BOTTOM
	row.offset_top = -HINTS_BOTTOM
	screen.add_child(row)
	for hint: Array in hints:
		row.add_child(make_hint(hint[0], hint[1]))
	return row


static func make_hint(prompt: InputPrompts.Prompt, text: String) -> PromptHint:
	return PromptHint.create(prompt, text, HINT_FONT_SIZE)


## Small filled tag such as "P1", "VALMIS" or "SORA".
static func make_chip(text: String, color: Color, font_size: int = 13) -> ChamferPanel:
	var chip: ChamferPanel = ChamferPanel.create_chip(color, 5.0, Vector4(7.0, 1.0, 7.0, 1.0))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.add_child(UiStyle.make_label(text, UiStyle.FONT_DISPLAY, font_size, UiStyle.TEXT_ON_ACCENT))
	return chip


static func set_chip(chip: ChamferPanel, text: String, color: Color) -> void:
	chip.fill_color = color
	(chip.get_child(0) as Label).text = text


static func make_player_chip(player_index: int, font_size: int = 13) -> ChamferPanel:
	return make_chip("P%d" % (player_index + 1), GameState.get_player_color(player_index), font_size)


## Full-screen rect that blurs and darkens whatever is behind it.
static func make_blur_backdrop() -> ColorRect:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = BLUR_SHADER
	var rect: ColorRect = ColorRect.new()
	rect.material = material
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


static func make_vbox(separation: int) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func make_hbox(separation: int) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func make_spacer(expand_horizontal: bool = true) -> Control:
	var spacer: Control = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_horizontal:
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer
