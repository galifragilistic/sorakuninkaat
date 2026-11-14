extends SceneTree
## Regenerates res://ui/theme.tres from the UiStyle constants.
## Run with: godot --headless -s tools/build_theme.gd

const OUTPUT_PATH: String = "res://ui/theme.tres"
const DEFAULT_FONT_SIZE: int = 15
const BUTTON_FONT_SIZE: int = 18
const CORNER_PADDING: float = 12.0
const BORDER_WIDTH: int = 2


func _initialize() -> void:
	var theme: Theme = Theme.new()
	theme.default_font = UiStyle.FONT_MEDIUM
	theme.default_font_size = DEFAULT_FONT_SIZE

	theme.set_color("font_color", "Label", UiStyle.TEXT)
	theme.set_color("font_color", "Button", UiStyle.TEXT)
	theme.set_color("font_hover_color", "Button", UiStyle.TEXT)
	theme.set_color("font_focus_color", "Button", UiStyle.TEXT_ON_ACCENT)
	theme.set_color("font_pressed_color", "Button", UiStyle.TEXT_ON_ACCENT)
	theme.set_color("font_disabled_color", "Button", UiStyle.TEXT_DISABLED)
	theme.set_font("font", "Button", UiStyle.FONT_DISPLAY)
	theme.set_font_size("font_size", "Button", BUTTON_FONT_SIZE)
	theme.set_stylebox("normal", "Button", _flat(UiStyle.BUTTON))
	theme.set_stylebox("hover", "Button", _flat(UiStyle.BUTTON.lightened(0.08)))
	theme.set_stylebox("pressed", "Button", _flat(UiStyle.ACCENT))
	theme.set_stylebox("focus", "Button", _flat(UiStyle.ACCENT))
	theme.set_stylebox("disabled", "Button", _flat(UiStyle.BUTTON_DISABLED))

	var panel: StyleBoxFlat = _flat(UiStyle.PANEL)
	panel.set_border_width_all(BORDER_WIDTH)
	panel.border_color = UiStyle.LINE
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var error: Error = ResourceSaver.save(theme, OUTPUT_PATH)
	print("theme saved: ", error_string(error))
	quit()


func _flat(color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(CORNER_PADDING)
	return box
