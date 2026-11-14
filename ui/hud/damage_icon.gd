class_name DamageIcon
extends Control
## Top-down car outline coloured by zone damage (mockups/05_Peli.png).
## Drawn in the mockup's 80x108 design space and scaled to the control size.

const DESIGN_ORIGIN: Vector2 = Vector2(10.0, 0.0)
const DESIGN_SIZE: Vector2 = Vector2(80.0, 108.0)
const WHEEL_RECTS: Array[Rect2] = [
	Rect2(20.0, 14.0, 8.0, 18.0), Rect2(72.0, 14.0, 8.0, 18.0),
	Rect2(20.0, 78.0, 8.0, 18.0), Rect2(72.0, 78.0, 8.0, 18.0),
]
const FRONT_RECT: Rect2 = Rect2(30.0, 6.0, 40.0, 26.0)
const MIDDLE_RECT: Rect2 = Rect2(30.0, 32.0, 40.0, 40.0)
const REAR_RECT: Rect2 = Rect2(30.0, 72.0, 40.0, 30.0)

## Zone damage (0..1) from which a zone is shown as worn / badly damaged.
@export_range(0.0, 1.0, 0.01) var warning_level: float = 0.15
@export_range(0.0, 1.0, 0.01) var danger_level: float = 0.5
@export var outline_width: float = 2.0

var damage: CarDamage:
	set(value):
		damage = value
		if damage != null:
			damage.changed.connect(queue_redraw)
		queue_redraw()


func get_zone_color(amount: float) -> Color:
	if amount >= danger_level:
		return UiStyle.DANGER
	if amount >= warning_level:
		return UiStyle.WARNING
	return UiStyle.NEUTRAL


func _draw() -> void:
	draw_set_transform(-DESIGN_ORIGIN * size / DESIGN_SIZE, 0.0, size / DESIGN_SIZE)
	var tires: Color = _zone_color(CarDamage.Zone.TIRES)
	for wheel: Rect2 in WHEEL_RECTS:
		draw_rect(wheel, tires)
	_draw_zone(FRONT_RECT, _zone_color(CarDamage.Zone.FRONT))
	_draw_zone(MIDDLE_RECT, _zone_color(CarDamage.Zone.MIDDLE))
	_draw_zone(REAR_RECT, _zone_color(CarDamage.Zone.REAR))


func _draw_zone(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color)
	draw_rect(rect, UiStyle.BASE, false, outline_width)


func _zone_color(zone: CarDamage.Zone) -> Color:
	return get_zone_color(damage.get_zone(zone) if damage != null else 0.0)
