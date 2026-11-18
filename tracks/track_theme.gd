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
@export var tree_style: TrackScenery.TreeStyle = TrackScenery.TreeStyle.FOREST
