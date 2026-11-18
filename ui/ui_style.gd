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
const SUCCESS: Color = Color("#b6f03c")
## Resting fill of buttons, list rows and option chips.
const BUTTON: Color = Color(0.11, 0.125, 0.19, 0.92)
const BUTTON_DISABLED: Color = Color(0.11, 0.125, 0.19, 0.5)
const TEXT_DISABLED: Color = Color(0.64, 0.675, 0.78, 0.45)
## Dark wash drawn over the 3D backdrop behind menu screens.
const SCRIM: Color = Color(0.055, 0.071, 0.125, 0.78)

## The UI's fonts. They wrap the vector fonts below, and the retro style
## swaps them to the bitmap PixelFont (see use_pixel_fonts()).
const FONT_DISPLAY: FontVariation = preload("res://ui/fonts/display.tres")
const FONT_REGULAR: FontVariation = preload("res://ui/fonts/regular.tres")
const FONT_MEDIUM: FontVariation = preload("res://ui/fonts/medium.tres")
const FONT_SEMIBOLD: FontVariation = preload("res://ui/fonts/semibold.tres")
const FONT_BOLD: FontVariation = preload("res://ui/fonts/bold.tres")
const ALL_FONTS: Array[FontVariation] = [FONT_DISPLAY, FONT_REGULAR, FONT_MEDIUM, FONT_SEMIBOLD, FONT_BOLD]
## Which of ALL_FONTS take the bold bitmap font. The other weights share the
## regular one: bold pixels make small text too wide.
const PIXEL_BOLD_FONTS: Array[FontVariation] = [FONT_DISPLAY]

const VECTOR_DISPLAY: FontFile = preload("res://assets/fonts/russo-one-latin-400-normal.woff2")
const VECTOR_FONTS: Array[FontFile] = [
	VECTOR_DISPLAY,
	preload("res://assets/fonts/chakra-petch-latin-400-normal.woff2"),
	preload("res://assets/fonts/chakra-petch-latin-500-normal.woff2"),
	preload("res://assets/fonts/chakra-petch-latin-600-normal.woff2"),
	preload("res://assets/fonts/chakra-petch-latin-700-normal.woff2"),
]

## Smallest text size allowed at the 1280x720 design resolution.
const MIN_FONT_SIZE: int = 13
const CAPS_LETTER_SPACING: int = 2
## Headings lean 6 degrees (SPEC.md section 6): tan(6 deg).
const TITLE_SLANT: float = 0.105

static var _caps_font: FontVariation
static var _title_font: FontVariation
static var _pixel_regular: FontFile
static var _pixel_bold: FontFile


## Russo One slanted for screen titles and the logo.
static func title_font() -> FontVariation:
	if _title_font == null:
		_title_font = FontVariation.new()
		_title_font.base_font = FONT_DISPLAY
		_title_font.variation_transform = _title_transform()
	return _title_font


static func _title_transform() -> Transform2D:
	return Transform2D(Vector2(1.0, TITLE_SLANT), Vector2(0.0, 1.0), Vector2.ZERO)


## Bold, letter-spaced font for small upper-case captions ("SIJA", "KIERROS").
static func caps_font() -> FontVariation:
	if _caps_font == null:
		_caps_font = FontVariation.new()
		_caps_font.base_font = FONT_BOLD
		_caps_font.spacing_glyph = CAPS_LETTER_SPACING
	return _caps_font


## Draws all UI text with the bitmap PixelFont (retro style), whose pixels
## are pixel_size font-size units, or with the vector fonts. Vector fonts lose
## their smoothing in the retro style; they still draw what PixelFont lacks.
static func use_pixel_fonts(on: bool, pixel_size: int) -> void:
	if on and (_pixel_regular == null or _pixel_regular.fixed_size != pixel_size):
		_pixel_regular = PixelFont.build(pixel_size, false, VECTOR_FONTS[2])
		_pixel_bold = PixelFont.build(pixel_size, true, VECTOR_DISPLAY)
	for i: int in ALL_FONTS.size():
		var font: FontVariation = ALL_FONTS[i]
		var vector: FontFile = VECTOR_FONTS[i]
		vector.antialiasing = TextServer.FONT_ANTIALIASING_NONE if on else TextServer.FONT_ANTIALIASING_GRAY
		var pixel: FontFile = _pixel_bold if PIXEL_BOLD_FONTS.has(font) else _pixel_regular
		font.base_font = pixel if on else vector
	# Slanted pixels would break the pixel grid.
	title_font().variation_transform = Transform2D.IDENTITY if on else _title_transform()


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
