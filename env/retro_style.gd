class_name RetroStyle
extends Resource
## Tunable numbers of the retro graphics style (PS1 / N64 look): a small 3D
## picture shown with sharp pixels, few colours with dithering and small,
## blocky textures. See Retro for where they are applied.

## UI units (1280x720 design) per rendered 3D pixel. 720 / 270 = 270 lines
## for a full-screen view.
@export var pixel_size: float = 720.0 / 270.0
## Bits per colour channel after the picture is rendered (5 = 15-bit colour).
@export_range(2, 8) var color_bits: int = 5
## 0 = plain colour banding, 1 = full ordered dithering between the levels.
@export_range(0.0, 1.0, 0.05) var dither_strength: float = 1.0
## Ground and road detail textures are shrunk to this many pixels a side and
## sampled without filtering.
@export var texture_size: int = 32
## Font size units per pixel of the UI's bitmap font: text is drawn at the
## whole multiple of this nearest to its font size: with 8, sizes 13-19 get
## 2x2 pixels, 20-27 3x3 and so on.
@export_range(4, 16) var font_pixel_size: int = 8
