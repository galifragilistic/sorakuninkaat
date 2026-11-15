class_name TrackTheme
extends Resource
## Surfaces and scenery for a track made in the track editor.

@export var display_name: String = ""
## Short surface label for the track select card, e.g. "SORA".
@export var surface_label: String = ""
@export var road_surface: SurfaceData
@export var ground_surface: SurfaceData
@export var terrain_noise_height: float = 1.2
@export var tree_count: int = 120
@export var tree_color: Color = Color(0.3, 0.52, 0.22)
@export var tree_top_color: Color = Color(0.4, 0.62, 0.26)
