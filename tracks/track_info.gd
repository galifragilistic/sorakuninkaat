class_name TrackInfo
extends Resource
## Menu data for a track (SPEC.md section 7). Tracks without a scene are
## listed as "coming later" and cannot be selected. Tracks made in the track
## editor have a design instead of a scene.

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var surface: SurfaceData.Kind = SurfaceData.Kind.GRAVEL
## Short surface label for the card chip, e.g. "SORA".
@export var surface_label: String = ""
## One-line summary for the lobby, e.g. "Sora · 6 mutkaa · hyppyri".
@export var summary: String = ""
@export var scene: PackedScene

## Set for tracks made in the track editor.
var design: TrackDesign


func is_available() -> bool:
	return scene != null or design != null


func is_custom() -> bool:
	return design != null


## A new track node; it builds its world when it enters the tree.
func instantiate_track() -> Track:
	if design != null:
		return design.build_track()
	return scene.instantiate() as Track
