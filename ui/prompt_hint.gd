class_name PromptHint
extends HBoxContainer
## One button hint ("(A) Valitse"). Shows a keycap or a gamepad button
## depending on the device used last, and hides itself when the keyboard
## has no key for the action.

var prompt: InputPrompts.Prompt = InputPrompts.Prompt.ACCEPT

var _glyph: UiGlyph
var _label: Label


static func create(hint_prompt: InputPrompts.Prompt, text: String, font_size: int) -> PromptHint:
	var hint: PromptHint = PromptHint.new()
	hint.prompt = hint_prompt
	hint._label.text = text
	hint._label.add_theme_font_size_override("font_size", maxi(font_size, UiStyle.MIN_FONT_SIZE))
	hint._update_style()
	return hint


func _init() -> void:
	add_theme_constant_override("separation", 9)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph = UiGlyph.create(UiGlyph.Kind.BUTTON, "")
	add_child(_glyph)
	_label = UiStyle.make_label("", UiStyle.FONT_MEDIUM, UiStyle.MIN_FONT_SIZE, UiStyle.TEXT_SECONDARY)
	add_child(_label)


func _enter_tree() -> void:
	InputManager.prompt_style_changed.connect(_on_prompt_style_changed)
	_update_style()


func _exit_tree() -> void:
	InputManager.prompt_style_changed.disconnect(_on_prompt_style_changed)


func _on_prompt_style_changed(_style: InputManager.PromptStyle) -> void:
	_update_style()


func _update_style() -> void:
	var label: String = InputPrompts.get_label(prompt)
	visible = not label.is_empty()
	_glyph.kind = UiGlyph.Kind.KEY if InputPrompts.is_keyboard() else UiGlyph.Kind.BUTTON
	_glyph.text = label
