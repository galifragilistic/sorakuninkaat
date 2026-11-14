class_name UiStyle
extends RefCounted
## Colours and fonts from the style guide (SPEC.md section 6, mockups/08_Tyyliopas.png).
## The full Theme resource for menus is built on top of these in the menu phase.

const BASE: Color = Color("#0e1220")
const PANEL: Color = Color(0.055, 0.071, 0.125, 0.86)
const ROW: Color = Color(0.055, 0.071, 0.125, 0.82)
const LINE: Color = Color("#2e3654")
const TEXT: Color = Color("#f2f4fa")
const TEXT_SECONDARY: Color = Color("#a3acc7")
const TEXT_ON_ACCENT: Color = Color("#10131f")
const ACCENT: Color = Color("#ff7a1a")
const INFO: Color = Color("#3fd8ff")
const WARNING: Color = Color("#ffb43d")
const DANGER: Color = Color("#ff5a3d")
const NEUTRAL: Color = Color("#6b7799")
const GAUGE_TRACK: Color = Color("#252b42")
const MAP_OUTLINE: Color = Color("#0a0d18")
const MAP_ROAD: Color = Color("#d7dceb")

const FONT_DISPLAY: FontFile = preload("res://assets/fonts/russo-one-latin-400-normal.woff2")
const FONT_REGULAR: FontFile = preload("res://assets/fonts/chakra-petch-latin-400-normal.woff2")
const FONT_MEDIUM: FontFile = preload("res://assets/fonts/chakra-petch-latin-500-normal.woff2")
const FONT_SEMIBOLD: FontFile = preload("res://assets/fonts/chakra-petch-latin-600-normal.woff2")
const FONT_BOLD: FontFile = preload("res://assets/fonts/chakra-petch-latin-700-normal.woff2")

## Smallest text size allowed at the 1280x720 design resolution.
const MIN_FONT_SIZE: int = 13
const CAPS_LETTER_SPACING: int = 2

static var _caps_font: FontVariation


## Bold, letter-spaced font for small upper-case captions ("SIJA", "KIERROS").
static func caps_font() -> FontVariation:
	if _caps_font == null:
		_caps_font = FontVariation.new()
		_caps_font.base_font = FONT_BOLD
		_caps_font.spacing_glyph = CAPS_LETTER_SPACING
	return _caps_font


static func make_label(text: String, font: Font, font_size: int, color: Color = TEXT) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", maxi(font_size, MIN_FONT_SIZE))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func make_caption(text: String, color: Color = TEXT_SECONDARY) -> Label:
	return make_label(text, caps_font(), MIN_FONT_SIZE, color)
