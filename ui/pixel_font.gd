class_name PixelFont
extends RefCounted
## The retro style's bitmap font, drawn here pixel by pixel like the fonts of
## 16-bit era games. Each glyph sits in a cell CELL_HEIGHT pixels tall: rows
## 0-1 hold the dots of capital Ä/Ö/Å, capitals and digits fill rows 2-8,
## lower case letters rows 4-8, and descenders go down to row 10.
## The font is drawn at whole multiples of its pixel size (see build()).

const CELL_HEIGHT: int = 11
## Rows above the baseline.
const ASCENT: int = 9
const DESCENT: int = CELL_HEIGHT - ASCENT
## Empty pixel columns after each glyph.
const LETTER_GAP: int = 1
const SPACE_WIDTH: int = 3

## Character -> "first row:row,row,..." with '#' for a lit pixel.
const GLYPHS: Dictionary[String, String] = {
	"A": "2:.###.,#...#,#...#,#####,#...#,#...#,#...#",
	"B": "2:####.,#...#,#...#,####.,#...#,#...#,####.",
	"C": "2:.###.,#...#,#....,#....,#....,#...#,.###.",
	"D": "2:####.,#...#,#...#,#...#,#...#,#...#,####.",
	"E": "2:#####,#....,#....,####.,#....,#....,#####",
	"F": "2:#####,#....,#....,####.,#....,#....,#....",
	"G": "2:.###.,#...#,#....,#.###,#...#,#...#,.####",
	"H": "2:#...#,#...#,#...#,#####,#...#,#...#,#...#",
	"I": "2:###,.#.,.#.,.#.,.#.,.#.,###",
	"J": "2:..###,...#.,...#.,...#.,...#.,#..#.,.##..",
	"K": "2:#...#,#..#.,#.#..,##...,#.#..,#..#.,#...#",
	"L": "2:#....,#....,#....,#....,#....,#....,#####",
	"M": "2:#...#,##.##,#.#.#,#.#.#,#...#,#...#,#...#",
	"N": "2:#...#,#...#,##..#,#.#.#,#..##,#...#,#...#",
	"O": "2:.###.,#...#,#...#,#...#,#...#,#...#,.###.",
	"P": "2:####.,#...#,#...#,####.,#....,#....,#....",
	"Q": "2:.###.,#...#,#...#,#...#,#.#.#,#..#.,.##.#",
	"R": "2:####.,#...#,#...#,####.,#.#..,#..#.,#...#",
	"S": "2:.###.,#...#,#....,.###.,....#,#...#,.###.",
	"T": "2:#####,..#..,..#..,..#..,..#..,..#..,..#..",
	"U": "2:#...#,#...#,#...#,#...#,#...#,#...#,.###.",
	"V": "2:#...#,#...#,#...#,#...#,#...#,.#.#.,..#..",
	"W": "2:#...#,#...#,#...#,#.#.#,#.#.#,#.#.#,.#.#.",
	"X": "2:#...#,#...#,.#.#.,..#..,.#.#.,#...#,#...#",
	"Y": "2:#...#,#...#,.#.#.,..#..,..#..,..#..,..#..",
	"Z": "2:#####,....#,...#.,..#..,.#...,#....,#####",
	"Ä": "0:.#.#.,.....,.###.,#...#,#...#,#####,#...#,#...#,#...#",
	"Ö": "0:.#.#.,.....,.###.,#...#,#...#,#...#,#...#,#...#,.###.",
	"Å": "0:..#..,.#.#.,.###.,#...#,#...#,#####,#...#,#...#,#...#",
	"Ü": "0:.#.#.,.....,#...#,#...#,#...#,#...#,#...#,#...#,.###.",
	"É": "0:...#.,..#..,#####,#....,#....,####.,#....,#....,#####",
	"a": "4:.##.,...#,.###,#..#,.###",
	"b": "2:#...,#...,###.,#..#,#..#,#..#,###.",
	"c": "4:.##,#..,#..,#..,.##",
	"d": "2:...#,...#,.###,#..#,#..#,#..#,.###",
	"e": "4:.##.,#..#,####,#...,.###",
	"f": "2:..#,.#.,###,.#.,.#.,.#.,.#.",
	"g": "4:.###,#..#,#..#,#..#,.###,...#,.##.",
	"h": "2:#...,#...,###.,#..#,#..#,#..#,#..#",
	"i": "2:#,.,#,#,#,#,#",
	"j": "2:..#,...,..#,..#,..#,..#,..#,#.#,.#.",
	"k": "2:#..,#..,#.#,#.#,##.,#.#,#.#",
	"l": "2:#.,#.,#.,#.,#.,#.,.#",
	"m": "4:####.,#.#.#,#.#.#,#.#.#,#.#.#",
	"n": "4:###.,#..#,#..#,#..#,#..#",
	"o": "4:.##.,#..#,#..#,#..#,.##.",
	"p": "4:###.,#..#,#..#,#..#,###.,#...,#...",
	"q": "4:.###,#..#,#..#,#..#,.###,...#,...#",
	"r": "4:#.#,##.,#..,#..,#..",
	"s": "4:.###,#...,.##.,...#,###.",
	"t": "2:.#.,.#.,###,.#.,.#.,.#.,..#",
	"u": "4:#..#,#..#,#..#,#..#,.###",
	"v": "4:#...#,#...#,#...#,.#.#.,..#..",
	"w": "4:#...#,#.#.#,#.#.#,#.#.#,.#.#.",
	"x": "4:#...#,.#.#.,..#..,.#.#.,#...#",
	"y": "4:#..#,#..#,#..#,#..#,.###,...#,.##.",
	"z": "4:####,..#.,.#..,#...,####",
	"ä": "2:#..#,....,.##.,...#,.###,#..#,.###",
	"ö": "2:#..#,....,.##.,#..#,#..#,#..#,.##.",
	"å": "1:.##.,.##.,....,.##.,...#,.###,#..#,.###",
	"ü": "2:#..#,....,#..#,#..#,#..#,#..#,.###",
	"é": "2:..#.,.#..,.##.,#..#,####,#...,.###",
	"0": "2:.###.,#...#,#..##,#.#.#,##..#,#...#,.###.",
	"1": "2:..#..,.##..,..#..,..#..,..#..,..#..,.###.",
	"2": "2:.###.,#...#,....#,...#.,..#..,.#...,#####",
	"3": "2:.###.,#...#,....#,..##.,....#,#...#,.###.",
	"4": "2:...#.,..##.,.#.#.,#..#.,#####,...#.,...#.",
	"5": "2:#####,#....,####.,....#,....#,#...#,.###.",
	"6": "2:..##.,.#...,#....,####.,#...#,#...#,.###.",
	"7": "2:#####,....#,...#.,..#..,.#...,.#...,.#...",
	"8": "2:.###.,#...#,#...#,.###.,#...#,#...#,.###.",
	"9": "2:.###.,#...#,#...#,.####,....#,...#.,.##..",
	"!": "2:#,#,#,#,#,.,#",
	"\"": "2:#.#,#.#",
	"#": "2:.#.#.,.#.#.,#####,.#.#.,#####,.#.#.,.#.#.",
	"$": "1:..#..,.####,#.#..,.###.,..#.#,####.,..#..",
	"%": "2:##..#,##..#,...#.,..#..,.#...,#..##,#..##",
	"&": "2:.##..,#..#.,#.#..,.#...,#.#.#,#..#.,.##.#",
	"'": "2:#,#",
	"(": "2:.#,#.,#.,#.,#.,#.,.#",
	")": "2:#.,.#,.#,.#,.#,.#,#.",
	"*": "3:..#..,#.#.#,.###.,#.#.#,..#..",
	"+": "4:..#..,..#..,#####,..#..,..#..",
	",": "7:.#,.#,#.",
	"-": "6:####",
	".": "8:#",
	"/": "2:....#,....#,...#.,..#..,.#...,#....,#....",
	":": "4:#,.,.,.,#",
	";": "4:.#,..,..,..,.#,#.",
	"<": "2:...#,..#.,.#..,#...,.#..,..#.,...#",
	"=": "5:####,....,####",
	">": "2:#...,.#..,..#.,...#,..#.,.#..,#...",
	"?": "2:.###.,#...#,....#,...#.,..#..,.....,..#..",
	"@": "2:.###.,#...#,#.###,#.#.#,#.###,#....,.####",
	"[": "2:###,#..,#..,#..,#..,#..,###",
	"\\": "2:#....,#....,.#...,..#..,...#.,....#,....#",
	"]": "2:###,..#,..#,..#,..#,..#,###",
	"^": "2:..#..,.#.#.,#...#",
	"_": "9:#####",
	"`": "2:#.,.#",
	"{": "2:..#,.#.,.#.,#..,.#.,.#.,..#",
	"|": "2:#,#,#,#,#,#,#",
	"}": "2:#..,.#.,.#.,..#,.#.,.#.,#..",
	"~": "5:.#...,#.#.#,...#.",
	"·": "6:#",
	"–": "6:#####",
	"—": "6:#######",
	"−": "6:#####",
	"…": "8:#.#.#",
	"°": "2:.#.,#.#,.#.",
	"×": "4:#...#,.#.#.,..#..,.#.#.,#...#",
	"²": "1:##.,..#,.#.,###",
	"‘": "2:.#,#.",
	"’": "2:.#,#.",
	"“": "2:.#.#,#.#.",
	"”": "2:.#.#,#.#.",
	"◀": "2:...#,..##,.###,####,.###,..##,...#",
	"▶": "2:#...,##..,###.,####,###.,##..,#...",
	"▲": "4:...#...,..###..,.#####.,#######",
	"▼": "4:#######,.#####.,..###..,...#...",
	"←": "4:..#..,.#...,#####,.#...,..#..",
	"→": "4:..#..,...#.,#####,...#.,..#..",
}


## A bitmap font one glyph pixel = pixel_size font-size units: asked for a
## font size, it is drawn at the nearest whole multiple of pixel_size, so its
## pixels always line up. Bold doubles every pixel column. Characters it lacks
## come from fallback.
static func build(pixel_size: int, bold: bool, fallback: Font) -> FontFile:
	var font: FontFile = FontFile.new()
	font.fixed_size = pixel_size
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	font.multichannel_signed_distance_field = false
	if fallback != null:
		font.fallbacks = [fallback]

	var cache_size: Vector2i = Vector2i(pixel_size, 0)
	font.set_cache_ascent(0, pixel_size, ASCENT)
	font.set_cache_descent(0, pixel_size, DESCENT)
	font.set_cache_underline_position(0, pixel_size, 1.0)
	font.set_cache_underline_thickness(0, pixel_size, 1.0)

	var bitmaps: Dictionary[int, Array] = {}
	var atlas_width: int = 1
	for character: String in GLYPHS:
		var columns: Array[PackedByteArray] = _parse(GLYPHS[character], bold)
		bitmaps[character.unicode_at(0)] = columns
		atlas_width += columns.size() + 1

	var atlas: Image = Image.create_empty(atlas_width, CELL_HEIGHT, false, Image.FORMAT_LA8)
	var x: int = 1
	for code: int in bitmaps:
		var columns: Array = bitmaps[code]
		var width: int = columns.size()
		for column: int in width:
			var pixels: PackedByteArray = columns[column]
			for row: int in CELL_HEIGHT:
				if pixels[row] != 0:
					atlas.set_pixel(x + column, row, Color.WHITE)
		font.set_glyph_advance(0, pixel_size, code, Vector2(width + LETTER_GAP, 0.0))
		font.set_glyph_offset(0, cache_size, code, Vector2(0.0, -ASCENT))
		font.set_glyph_size(0, cache_size, code, Vector2(width, CELL_HEIGHT))
		font.set_glyph_uv_rect(0, cache_size, code, Rect2(x, 0.0, width, CELL_HEIGHT))
		font.set_glyph_texture_idx(0, cache_size, code, 0)
		x += width + 1

	var space: int = " ".unicode_at(0)
	font.set_glyph_advance(0, pixel_size, space, Vector2(SPACE_WIDTH + (1 if bold else 0) + LETTER_GAP, 0.0))
	font.set_glyph_size(0, cache_size, space, Vector2.ZERO)
	font.set_glyph_texture_idx(0, cache_size, space, -1)
	font.set_texture_image(0, cache_size, 0, atlas)
	return font


## One glyph as pixel columns, each CELL_HEIGHT long (1 = lit).
static func _parse(glyph: String, bold: bool) -> Array[PackedByteArray]:
	var first_row: int = glyph.get_slice(":", 0).to_int()
	var rows: PackedStringArray = glyph.get_slice(":", 1).split(",")
	var width: int = 0
	for row: String in rows:
		width = maxi(width, row.length())
	var columns: Array[PackedByteArray] = []
	for column: int in width + (1 if bold else 0):
		var pixels: PackedByteArray = PackedByteArray()
		pixels.resize(CELL_HEIGHT)
		columns.append(pixels)
	for i: int in rows.size():
		var row: String = rows[i]
		for column: int in row.length():
			if row[column] != "#":
				continue
			columns[column][first_row + i] = 1
			if bold:
				columns[column + 1][first_row + i] = 1
	return columns
