class_name InputPrompts
extends RefCounted
## What each menu action is called on the keyboard and on a gamepad, for the
## button hints and for texts that name a button. The style comes from
## InputManager.prompt_style (the device used last).

enum Prompt { ACCEPT, BACK, SECONDARY, TABS, START, LEFT_RIGHT, UP_DOWN }

## Gamepad labels (Xbox layout, as in the mockups).
const GAMEPAD_LABELS: Dictionary = {
	Prompt.ACCEPT: "A",
	Prompt.BACK: "B",
	Prompt.SECONDARY: "X",
	Prompt.TABS: "LB RB",
	Prompt.START: "START",
	Prompt.LEFT_RIGHT: "◀ ▶",
	Prompt.UP_DOWN: "▲ ▼",
}

## Keyboard labels. An empty label hides the hint: the keyboard has no key
## for that action (the lobby is started with its button instead).
const KEYBOARD_LABELS: Dictionary = {
	Prompt.ACCEPT: "Enter",
	Prompt.BACK: "Esc",
	Prompt.SECONDARY: "X",
	Prompt.TABS: "Q E",
	Prompt.START: "",
	# Triangles, not ← →: the UI fonts lack arrow glyphs and the fallback draws them tiny.
	Prompt.LEFT_RIGHT: "◀ ▶",
	Prompt.UP_DOWN: "▲ ▼",
}


static func is_keyboard() -> bool:
	return InputManager.prompt_style == InputManager.PromptStyle.KEYBOARD


## Label for the glyph, in the current style. "" = no such key.
static func get_label(prompt: Prompt) -> String:
	return KEYBOARD_LABELS[prompt] if is_keyboard() else GAMEPAD_LABELS[prompt]


## Name of the button for use inside a sentence, e.g. "Paina Enter".
static func get_button_name(prompt: Prompt) -> String:
	return get_label(prompt)
