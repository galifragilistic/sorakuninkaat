class_name TrackInfo
extends Resource
## Menu data for a track (SPEC.md section 7). Tracks without a scene are
## listed as "coming later" and cannot be selected.

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var surface: SurfaceData.Kind = SurfaceData.Kind.GRAVEL
## Short surface label for the card chip, e.g. "SORA".
@export var surface_label: String = ""
## One-line summary for the lobby, e.g. "Sora · 6 mutkaa · hyppyri".
@export var summary: String = ""
@export var scene: PackedScene


func is_available() -> bool:
	return scene != null
