class_name DebugHud
extends Label
## Temporary phase 1 readout: speed and current surface. Replaced by the real HUD in phase 3.

var car: Car


func _process(_delta: float) -> void:
	if car == null:
		return
	var surface: SurfaceData = car.get_current_surface()
	var surface_name: String = tr(surface.display_name) if surface != null else "-"
	var state: String = surface_name if car.is_grounded() else tr("Ilmassa")
	text = tr("%d km/h · %s") % [roundi(car.get_speed_kmh()), state]
