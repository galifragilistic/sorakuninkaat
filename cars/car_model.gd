class_name CarModel
extends Node3D
## Builds a car's low-poly body from a CarLook: a lofted, chamfered hull, a
## cabin with glass, lights, trim details and the paint pattern.
## Forward is -Z. Paint takes the player's colour; everything else is vertex-coloured.

## Cross-section corners, see _ring().
const RING_SIZE: int = 8
const WHEEL_SIDES: int = 12
const LAMP_SIDES: int = 10
## Sections closer than this along Z are pushed apart so the loft never folds.
const MIN_SECTION_GAP: float = 0.05
## Chamfers never take more than these shares of a section's height.
const MAX_SHOULDER_SHARE: float = 0.4
const MAX_SILL_SHARE: float = 0.3

## Painted decals and glass sit this far off the surface they are drawn on.
@export var decal_offset: float = 0.012

@export_group("Paint")
@export_range(0.0, 1.0, 0.01) var paint_roughness: float = 0.6
@export_range(0.0, 1.0, 0.01) var detail_roughness: float = 0.55
## Pattern colour on dark paint and on light paint.
@export var pattern_light: Color = Color(0.95, 0.95, 0.92)
@export var pattern_dark: Color = Color(0.08, 0.09, 0.13)
## Paint brighter than this gets the dark pattern colour.
@export_range(0.0, 1.0, 0.01) var light_paint_luminance: float = 0.6
@export var stripe_width: float = 0.18
## Gap between the two racing stripes.
@export var stripe_gap: float = 0.1
## Side band, as shares of the side face height (0 = sill, 1 = shoulder).
@export var band_range: Vector2 = Vector2(0.38, 0.66)
## Lower body colour of the two-tone paint, same scale as band_range.
@export var two_tone_range: Vector2 = Vector2(0.0, 0.45)
@export var checker_size: float = 0.13

@export_group("Lights")
@export var head_light_color: Color = Color(1.0, 0.9, 0.62)
@export var head_light_energy: float = 4.0
@export var tail_light_color: Color = Color(1.0, 0.15, 0.1)
@export var tail_light_energy: float = 2.5
@export var rect_lamp_size: Vector2 = Vector2(0.34, 0.14)
@export var round_lamp_radius: float = 0.11
@export var tail_lamp_size: Vector2 = Vector2(0.36, 0.13)
@export var aux_lamp_radius: float = 0.07
## Bumper driving lights sit this far from the centre line (inner pair, outer pair).
@export var aux_lamp_spread: Vector2 = Vector2(0.22, 0.5)
## Lamp centre height as a share of the front and rear faces.
@export_range(0.0, 1.0, 0.01) var lamp_height: float = 0.6
## Lamp centre distance from the body side.
@export var lamp_inset: float = 0.3
@export var lamp_depth: float = 0.05
## Spotlights start this far in front of the lamp glass.
@export var spotlight_lead: float = 0.1

@export_group("Details")
@export var bumper_height: float = 0.16
## Thickness of bars, rails and other tubes.
@export var tube: float = 0.05
@export var mirror_size: Vector3 = Vector3(0.14, 0.09, 0.08)
@export var grille_depth: float = 0.02
@export var exhaust_radius: float = 0.045
@export var exhaust_offset: float = 0.45
@export var flare_thickness: float = 0.07
## Gap between the tyre and the flare above it.
@export var flare_gap: float = 0.04
@export var flap_size: Vector2 = Vector2(0.24, 0.26)
@export var spare_radius: float = 0.28
@export var spare_depth: float = 0.2
@export var scoop_size: Vector3 = Vector3(0.5, 0.1, 0.4)
@export var wing_height: float = 0.2
@export var wing_chord: float = 0.34
@export var lip_size: Vector2 = Vector2(0.05, 0.16)
## Rim and hub disc thickness, and hub size as a share of the tyre radius.
@export var rim_thickness: float = 0.02
@export_range(0.0, 1.0, 0.01) var hub_ratio: float = 0.22
## Height of the wheel centres when the car stands still (for flares and flaps).
@export var wheel_centre_height: float = 0.3

## Lamp positions for the headlight spotlights (left, right), set by build().
var head_lamp_positions: PackedVector3Array = PackedVector3Array()

var _look: CarLook
var _sections: Array[Section] = []
var _paint_color: Color = Color.WHITE
var _pattern: PlayerSetup.Pattern = PlayerSetup.Pattern.STRIPE
var _roof_y: float = 0.0
var _roof_front: float = 0.0
var _roof_rear: float = 0.0
var _roof_half: float = 0.0

var _paint_material: StandardMaterial3D
var _paint_mesh: MeshInstance3D
var _pattern_mesh: MeshInstance3D
var _detail_mesh: MeshInstance3D
var _head_mesh: MeshInstance3D
var _tail_mesh: MeshInstance3D


## One cross-section of the body loft.
class Section:
	var z: float
	var half_width: float
	var top: float
	var bottom: float

	func _init(at_z: float, half: float, top_y: float, bottom_y: float) -> void:
		z = at_z
		half_width = half
		top = top_y
		bottom = bottom_y


## wheel_mounts are the four wheel positions (x and z are used), radius is the tyre radius.
func build(look: CarLook, wheel_mounts: Array[Vector3], radius: float) -> void:
	_look = look
	_ensure_nodes()
	_sections = _make_sections()

	var paint: SurfaceTool = LowPoly.begin()
	var detail: SurfaceTool = LowPoly.begin()
	var head: SurfaceTool = LowPoly.begin()
	var tail: SurfaceTool = LowPoly.begin()
	_add_hull(paint)
	_add_cabin(paint, detail)
	_add_front(detail, head)
	_add_rear(paint, detail, tail)
	_add_extras(detail, head, wheel_mounts, radius)
	_paint_mesh.mesh = paint.commit()
	_detail_mesh.mesh = detail.commit()
	_head_mesh.mesh = head.commit()
	_tail_mesh.mesh = tail.commit()
	_rebuild_pattern()


func set_paint(color: Color, pattern: PlayerSetup.Pattern) -> void:
	_paint_color = color
	_pattern = pattern
	_ensure_nodes()
	_paint_material.albedo_color = color
	_rebuild_pattern()


## A tyre with rims and hubs, its axle along Y (the wheel node turns it sideways).
func build_wheel_mesh(look: CarLook, radius: float) -> ArrayMesh:
	var tool: SurfaceTool = LowPoly.begin()
	_add_cylinder(tool, Vector3.ZERO, Vector3.UP, radius, look.wheel_width, WHEEL_SIDES, look.tire_color)
	for side: float in [-1.0, 1.0]:
		var rim_center: Vector3 = Vector3.UP * side * (look.wheel_width + rim_thickness) * 0.5
		_add_cylinder(tool, rim_center, Vector3.UP, radius * look.rim_ratio, rim_thickness, WHEEL_SIDES, look.rim_color)
		var hub_center: Vector3 = rim_center + Vector3.UP * side * rim_thickness
		_add_cylinder(tool, hub_center, Vector3.UP, radius * hub_ratio, rim_thickness, LAMP_SIDES, look.trim_color)
	return tool.commit()


func make_wheel_material() -> StandardMaterial3D:
	return LowPoly.vertex_color_material(detail_roughness)


func _ensure_nodes() -> void:
	if _paint_mesh != null:
		return
	_paint_material = StandardMaterial3D.new()
	_paint_material.roughness = paint_roughness
	_paint_material.albedo_color = _paint_color
	_paint_mesh = _add_mesh_node("Paint", _paint_material)
	_pattern_mesh = _add_mesh_node("Pattern", LowPoly.vertex_color_material(paint_roughness))
	_detail_mesh = _add_mesh_node("Detail", LowPoly.vertex_color_material(detail_roughness))
	_head_mesh = _add_mesh_node("HeadLamps", LowPoly.emissive_material(head_light_color, head_light_energy))
	_tail_mesh = _add_mesh_node("TailLamps", LowPoly.emissive_material(tail_light_color, tail_light_energy))


func _add_mesh_node(node_name: String, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.material_override = material
	add_child(node)
	return node


# --- Body ---------------------------------------------------------------------

func _make_sections() -> Array[Section]:
	var look: CarLook = _look
	var half_length: float = look.length * 0.5
	var half_width: float = look.width * 0.5
	var hood_front: float = look.hood_height - look.hood_slope
	var zs: PackedFloat32Array = PackedFloat32Array([
		-half_length, -half_length + look.nose_length, look.cabin_start,
		look.cabin_end, half_length - look.tail_length, half_length,
	])
	for i: int in range(1, zs.size()):
		zs[i] = maxf(zs[i], zs[i - 1] + MIN_SECTION_GAP)
	var sections: Array[Section] = [
		Section.new(zs[0], half_width - look.nose_pinch, hood_front - look.nose_drop, look.clearance + look.nose_lift),
		Section.new(zs[1], half_width, hood_front, look.clearance),
		Section.new(zs[2], half_width, look.hood_height, look.clearance),
		Section.new(zs[3], half_width, look.deck_height, look.clearance),
		Section.new(zs[4], half_width, look.deck_height, look.clearance),
		Section.new(zs[5], half_width - look.tail_pinch, look.deck_height - look.tail_drop, look.clearance + look.tail_lift),
	]
	return sections


func _section_at(z: float) -> Section:
	var last: int = _sections.size() - 1
	if z <= _sections[0].z:
		return _sections[0]
	for i: int in last:
		var a: Section = _sections[i]
		var b: Section = _sections[i + 1]
		if z <= b.z:
			var t: float = (z - a.z) / (b.z - a.z)
			return Section.new(
				z, lerpf(a.half_width, b.half_width, t), lerpf(a.top, b.top, t), lerpf(a.bottom, b.bottom, t)
			)
	return _sections[last]


func _shoulder(section: Section) -> float:
	return minf(_look.shoulder, (section.top - section.bottom) * MAX_SHOULDER_SHARE)


func _sill(section: Section) -> float:
	return minf(_look.sill, (section.top - section.bottom) * MAX_SILL_SHARE)


## Octagon around the section, starting at the bottom left and going up the left side.
func _ring(section: Section) -> PackedVector3Array:
	var w: float = section.half_width
	var shoulder: float = _shoulder(section)
	var sill: float = _sill(section)
	var z: float = section.z
	return PackedVector3Array([
		Vector3(-w + sill, section.bottom, z), Vector3(-w, section.bottom + sill, z),
		Vector3(-w, section.top - shoulder, z), Vector3(-w + shoulder, section.top, z),
		Vector3(w - shoulder, section.top, z), Vector3(w, section.top - shoulder, z),
		Vector3(w, section.bottom + sill, z), Vector3(w - sill, section.bottom, z),
	])


## Height on the vertical side face: share 0 is the top of the sill, 1 the shoulder.
func _side_y(section: Section, share: float) -> float:
	return lerpf(section.bottom + _sill(section), section.top - _shoulder(section), share)


func _add_hull(paint: SurfaceTool) -> void:
	for i: int in _sections.size() - 1:
		var a: PackedVector3Array = _ring(_sections[i])
		var b: PackedVector3Array = _ring(_sections[i + 1])
		var axis_y: float = (_sections[i].top + _sections[i].bottom) * 0.5
		for k: int in RING_SIZE:
			var next: int = (k + 1) % RING_SIZE
			var middle: Vector3 = (a[k] + a[next] + b[k] + b[next]) * 0.25
			var outward: Vector3 = Vector3(middle.x, middle.y - axis_y, 0.0)
			LowPoly.add_quad(paint, a[k], a[next], b[next], b[k], Color.WHITE, outward)
	_add_cap(paint, _sections[0], Vector3.FORWARD)
	_add_cap(paint, _sections[_sections.size() - 1], Vector3.BACK)


func _add_cap(paint: SurfaceTool, section: Section, facing: Vector3) -> void:
	var ring: PackedVector3Array = _ring(section)
	var center: Vector3 = Vector3(0.0, (section.top + section.bottom) * 0.5, section.z)
	for k: int in RING_SIZE:
		LowPoly.add_triangle(paint, center, ring[k], ring[(k + 1) % RING_SIZE], Color.WHITE, facing)


func _add_cabin(paint: SurfaceTool, detail: SurfaceTool) -> void:
	var look: CarLook = _look
	var front: Section = _sections[2]
	var rear: Section = _sections[3]
	var base_half: float = front.half_width - _shoulder(front)
	_roof_half = minf(look.width * 0.5 - look.roof_inset, base_half)
	_roof_y = maxf(front.top, rear.top) + look.cabin_height
	_roof_front = front.z + look.windscreen_run
	_roof_rear = maxf(rear.z - look.rear_window_run, _roof_front + MIN_SECTION_GAP)

	var base_fl: Vector3 = Vector3(-base_half, front.top, front.z)
	var base_fr: Vector3 = Vector3(base_half, front.top, front.z)
	var base_rl: Vector3 = Vector3(-base_half, rear.top, rear.z)
	var base_rr: Vector3 = Vector3(base_half, rear.top, rear.z)
	var roof_fl: Vector3 = Vector3(-_roof_half, _roof_y, _roof_front)
	var roof_fr: Vector3 = Vector3(_roof_half, _roof_y, _roof_front)
	var roof_rl: Vector3 = Vector3(-_roof_half, _roof_y, _roof_rear)
	var roof_rr: Vector3 = Vector3(_roof_half, _roof_y, _roof_rear)
	var screen_out: Vector3 = Vector3(0.0, 1.0, -1.0)
	var rear_out: Vector3 = Vector3(0.0, 1.0, 1.0)
	LowPoly.add_quad(paint, base_fl, base_fr, roof_fr, roof_fl, Color.WHITE, screen_out)
	LowPoly.add_quad(paint, base_rl, base_rr, roof_rr, roof_rl, Color.WHITE, rear_out)
	LowPoly.add_quad(paint, base_fl, base_rl, roof_rl, roof_fl, Color.WHITE, Vector3.LEFT)
	LowPoly.add_quad(paint, base_fr, base_rr, roof_rr, roof_fr, Color.WHITE, Vector3.RIGHT)
	LowPoly.add_quad(paint, roof_fl, roof_fr, roof_rr, roof_rl, Color.WHITE, Vector3.UP)

	var glass: Color = look.glass_color
	var pillar: float = look.pillar
	_add_window(detail, base_fl, base_fr, roof_fr, roof_fl, Vector2(pillar, pillar), Vector2(pillar, pillar), glass, screen_out)
	_add_window(detail, base_rl, base_rr, roof_rr, roof_rl, Vector2(pillar, pillar), Vector2(pillar, pillar), glass, rear_out)
	for side: float in [-1.0, 1.0]:
		var base_front: Vector3 = base_fr if side > 0.0 else base_fl
		var base_rear: Vector3 = base_rr if side > 0.0 else base_rl
		var roof_front: Vector3 = roof_fr if side > 0.0 else roof_fl
		var roof_rear: Vector3 = roof_rr if side > 0.0 else roof_rl
		var outward: Vector3 = Vector3(side, 0.0, 0.0)
		# Two side windows split by the B pillar.
		var middle_base: Vector3 = (base_front + base_rear) * 0.5
		var middle_roof: Vector3 = (roof_front + roof_rear) * 0.5
		var half_pillar: float = pillar * 0.5
		_add_window(detail, base_front, middle_base, middle_roof, roof_front, Vector2(pillar, half_pillar), Vector2(pillar, pillar), glass, outward)
		_add_window(detail, middle_base, base_rear, roof_rear, middle_roof, Vector2(half_pillar, pillar), Vector2(pillar, pillar), glass, outward)
		# Door mirror at the base of the A pillar.
		var mirror_center: Vector3 = Vector3(
			side * (base_half + mirror_size.x * 0.5), front.top + mirror_size.y * 1.5, front.z + mirror_size.z * 2.0
		)
		LowPoly.add_box(paint, mirror_center, mirror_size, Color.WHITE)


## Inset patch on the quad a-b-c-d (a to b is "across", a to d is "up").
## inset_across and inset_up are frame widths in metres at the (start, end).
func _add_window(
	tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	inset_across: Vector2, inset_up: Vector2, color: Color, outward: Vector3
) -> void:
	var across: float = a.distance_to(b)
	var up: float = a.distance_to(d)
	if across <= inset_across.x + inset_across.y or up <= inset_up.x + inset_up.y:
		return
	_add_patch(
		tool, a, b, c, d,
		Vector2(inset_across.x / across, 1.0 - inset_across.y / across),
		Vector2(inset_up.x / up, 1.0 - inset_up.y / up),
		color, outward
	)


## Part of the quad a-b-c-d between the given shares, lifted off the surface.
func _add_patch(
	tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	across: Vector2, up: Vector2, color: Color, outward: Vector3
) -> void:
	var normal: Vector3 = (b - a).cross(d - a).normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	var lift: Vector3 = normal * decal_offset
	LowPoly.add_quad(
		tool,
		_bilinear(a, b, c, d, across.x, up.x) + lift, _bilinear(a, b, c, d, across.y, up.x) + lift,
		_bilinear(a, b, c, d, across.y, up.y) + lift, _bilinear(a, b, c, d, across.x, up.y) + lift,
		color, normal
	)


static func _bilinear(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float, v: float) -> Vector3:
	return a.lerp(b, u).lerp(d.lerp(c, u), v)


# --- Front and rear -----------------------------------------------------------

func _add_front(detail: SurfaceTool, head: SurfaceTool) -> void:
	var look: CarLook = _look
	var nose: Section = _sections[0]
	var trim: Color = look.trim_color
	# Bumper straddling the bottom edge of the nose.
	LowPoly.add_box(
		detail,
		Vector3(0.0, nose.bottom, nose.z - look.bumper_depth * 0.5 + tube),
		Vector3(nose.half_width * 2.0 + tube * 2.0, bumper_height, look.bumper_depth + tube * 2.0),
		trim
	)
	var lamp_y: float = lerpf(nose.bottom, nose.top, lamp_height)
	var lamp_x: float = nose.half_width - lamp_inset
	head_lamp_positions = PackedVector3Array()
	for side: float in [-1.0, 1.0]:
		var lamp: Vector3 = Vector3(side * lamp_x, lamp_y, nose.z)
		if look.lamps == CarLook.Lamps.ROUND:
			_add_cylinder(head, lamp, Vector3.FORWARD, round_lamp_radius, lamp_depth, LAMP_SIDES, head_light_color)
		else:
			LowPoly.add_box(head, lamp, Vector3(rect_lamp_size.x, rect_lamp_size.y, lamp_depth), head_light_color)
		head_lamp_positions.append(lamp + Vector3.FORWARD * spotlight_lead)
	# Grille between the lamps.
	var lamp_half: float = round_lamp_radius if look.lamps == CarLook.Lamps.ROUND else rect_lamp_size.x * 0.5
	var grille_half: float = lamp_x - lamp_half - tube
	if grille_half > 0.0:
		LowPoly.add_box(
			detail, Vector3(0.0, lamp_y, nose.z - grille_depth * 0.5),
			Vector3(grille_half * 2.0, rect_lamp_size.y, grille_depth), trim
		)
	# Driving lights on the bumper.
	var bumper_top: float = nose.bottom + bumper_height * 0.5
	var lights_z: float = nose.z - look.bumper_depth * 0.5
	var spreads: Array[float] = []
	if look.bumper_lights >= 2:
		spreads.append(aux_lamp_spread.x)
	if look.bumper_lights >= 4:
		spreads.append(aux_lamp_spread.y)
	for spread: float in spreads:
		for side: float in [-1.0, 1.0]:
			_add_cylinder(
				head, Vector3(side * spread, bumper_top + aux_lamp_radius, lights_z),
				Vector3.FORWARD, aux_lamp_radius, lamp_depth, LAMP_SIDES, head_light_color
			)


func _add_rear(paint: SurfaceTool, detail: SurfaceTool, tail: SurfaceTool) -> void:
	var look: CarLook = _look
	var back: Section = _sections[_sections.size() - 1]
	var trim: Color = look.trim_color
	LowPoly.add_box(
		detail,
		Vector3(0.0, back.bottom, back.z + look.bumper_depth * 0.5 - tube),
		Vector3(back.half_width * 2.0 + tube * 2.0, bumper_height, look.bumper_depth + tube * 2.0),
		trim
	)
	var lamp_y: float = lerpf(back.bottom, back.top, lamp_height)
	for side: float in [-1.0, 1.0]:
		LowPoly.add_box(
			tail, Vector3(side * (back.half_width - lamp_inset), lamp_y, back.z),
			Vector3(tail_lamp_size.x, tail_lamp_size.y, lamp_depth), tail_light_color
		)
	_add_cylinder(
		detail, Vector3(exhaust_offset, back.bottom, back.z + look.bumper_depth + tube),
		Vector3.BACK, exhaust_radius, tube * 2.0, LAMP_SIDES, trim
	)
	if look.spare_wheel:
		var spare_y: float = (back.bottom + back.top) * 0.5 + tube
		var spare: Vector3 = Vector3(0.0, spare_y, back.z + spare_depth * 0.5)
		_add_cylinder(detail, spare, Vector3.BACK, spare_radius, spare_depth, WHEEL_SIDES, look.tire_color)
		_add_cylinder(
			detail, spare + Vector3.BACK * (spare_depth + rim_thickness) * 0.5,
			Vector3.BACK, spare_radius * look.rim_ratio, rim_thickness, WHEEL_SIDES, look.rim_color
		)
	match look.spoiler:
		CarLook.Spoiler.LIP:
			LowPoly.add_box(
				detail, Vector3(0.0, back.top + lip_size.x * 0.5, back.z - lip_size.y * 0.5),
				Vector3((back.half_width - tube) * 2.0, lip_size.x, lip_size.y), trim
			)
		CarLook.Spoiler.WING:
			var wing_z: float = back.z - wing_chord * 0.5
			if wing_z - wing_chord * 0.5 < _sections[3].z:
				# Hatchback: no boot lid to stand on, so the wing goes on the roof edge.
				LowPoly.add_box(
					paint, Vector3(0.0, _roof_y + tube, _roof_rear + wing_chord * 0.25),
					Vector3(_roof_half * 2.0, tube, wing_chord), Color.WHITE
				)
				return
			var deck: Section = _section_at(wing_z)
			var wing_y: float = deck.top + wing_height
			for side: float in [-1.0, 1.0]:
				LowPoly.add_box(
					detail, Vector3(side * deck.half_width * 0.5, deck.top + wing_height * 0.5, wing_z),
					Vector3(tube, wing_height, wing_chord * 0.5), trim
				)
			LowPoly.add_box(
				paint, Vector3(0.0, wing_y, wing_z),
				Vector3((deck.half_width - tube) * 2.0, tube, wing_chord), Color.WHITE
			)


# --- Extras -------------------------------------------------------------------

func _add_extras(
	detail: SurfaceTool, head: SurfaceTool, wheel_mounts: Array[Vector3], radius: float
) -> void:
	var look: CarLook = _look
	var trim: Color = look.trim_color
	if look.hood_scoop:
		var scoop_z: float = (_sections[1].z + _sections[2].z) * 0.5
		var hood: Section = _section_at(scoop_z)
		LowPoly.add_box(detail, Vector3(0.0, hood.top + scoop_size.y * 0.25, scoop_z), scoop_size, trim)
	if look.roof_rack:
		var rack_y: float = _roof_y + tube * 1.5
		var rack_length: float = _roof_rear - _roof_front
		var rack_z: float = (_roof_front + _roof_rear) * 0.5
		for side: float in [-1.0, 1.0]:
			LowPoly.add_box(
				detail, Vector3(side * (_roof_half - tube), rack_y, rack_z),
				Vector3(tube, tube * 2.0, rack_length), trim
			)
		for share: float in [0.15, 0.5, 0.85]:
			LowPoly.add_box(
				detail, Vector3(0.0, rack_y + tube, lerpf(_roof_front, _roof_rear, share)),
				Vector3(_roof_half * 2.0, tube, tube), trim
			)
	if look.roof_lights:
		var pod_y: float = _roof_y + tube + aux_lamp_radius
		var pod_z: float = _roof_front + aux_lamp_radius * 2.0
		var pod_half: float = _roof_half * 0.8
		LowPoly.add_box(
			detail, Vector3(0.0, _roof_y + tube * 0.5, pod_z),
			Vector3(pod_half * 2.0 + aux_lamp_radius * 2.0, tube, aux_lamp_radius * 3.0), trim
		)
		for i: int in 4:
			var x: float = lerpf(-pod_half, pod_half, float(i) / 3.0)
			_add_cylinder(
				head, Vector3(x, pod_y, pod_z - aux_lamp_radius),
				Vector3.FORWARD, aux_lamp_radius, lamp_depth, LAMP_SIDES, head_light_color
			)
			LowPoly.add_box(
				detail, Vector3(x, pod_y, pod_z),
				Vector3(aux_lamp_radius * 2.0, aux_lamp_radius * 2.0, aux_lamp_radius * 2.0), trim
			)
	if look.bull_bar:
		var nose: Section = _sections[0]
		var bar_z: float = nose.z - look.bumper_depth - tube * 2.0
		var bar_top: float = nose.top + tube
		var bar_bottom: float = nose.bottom - bumper_height * 0.5
		var post_x: float = nose.half_width - lamp_inset - rect_lamp_size.x * 0.5 - tube
		for side: float in [-1.0, 1.0]:
			LowPoly.add_box(
				detail, Vector3(side * post_x, (bar_top + bar_bottom) * 0.5, bar_z),
				Vector3(tube, bar_top - bar_bottom, tube), trim
			)
		for bar_y: float in [bar_top, (bar_top + bar_bottom) * 0.5]:
			LowPoly.add_box(detail, Vector3(0.0, bar_y, bar_z), Vector3(post_x * 2.0 + tube, tube, tube), trim)
	for mount: Vector3 in wheel_mounts:
		var side: float = signf(mount.x)
		var body: Section = _section_at(mount.z)
		if look.fender_flares:
			var inner: float = body.half_width - tube
			var outer: float = absf(mount.x) + look.wheel_width * 0.5 + tube
			LowPoly.add_box(
				detail,
				Vector3(side * (inner + outer) * 0.5, wheel_centre_height + radius + flare_gap, mount.z),
				Vector3(outer - inner, flare_thickness, radius * 2.4), trim
			)
		if look.mud_flaps:
			LowPoly.add_box(
				detail,
				Vector3(mount.x, body.bottom - flap_size.y * 0.5 + tube, mount.z + radius + tube * 2.0),
				Vector3(flap_size.x, flap_size.y, tube * 0.5), trim
			)


# --- Pattern ------------------------------------------------------------------

func _rebuild_pattern() -> void:
	if _pattern_mesh == null or _look == null or _sections.is_empty():
		return
	var tool: SurfaceTool = LowPoly.begin()
	var color: Color = pattern_dark if _paint_color.get_luminance() > light_paint_luminance else pattern_light
	var length: Vector2 = Vector2(_sections[0].z, _sections[_sections.size() - 1].z)
	var empty: bool = false
	match _pattern:
		PlayerSetup.Pattern.STRIPE:
			for side: float in [-1.0, 1.0]:
				var inner: float = side * stripe_gap * 0.5
				var outer: float = side * (stripe_gap * 0.5 + stripe_width)
				_add_top_strip(tool, inner, outer, color)
				LowPoly.add_quad(
					tool,
					Vector3(inner, _roof_y + decal_offset, _roof_front), Vector3(outer, _roof_y + decal_offset, _roof_front),
					Vector3(outer, _roof_y + decal_offset, _roof_rear), Vector3(inner, _roof_y + decal_offset, _roof_rear),
					color, Vector3.UP
				)
		PlayerSetup.Pattern.SIDE_BAND:
			for side: float in [-1.0, 1.0]:
				_add_side_strip(tool, side, band_range, length, color)
		PlayerSetup.Pattern.TWO_TONE:
			for side: float in [-1.0, 1.0]:
				_add_side_strip(tool, side, two_tone_range, length, color)
			var lift: float = _roof_y + decal_offset
			var half: float = _roof_half
			LowPoly.add_quad(
				tool,
				Vector3(-half, lift, _roof_front), Vector3(half, lift, _roof_front),
				Vector3(half, lift, _roof_rear), Vector3(-half, lift, _roof_rear),
				color, Vector3.UP
			)
		PlayerSetup.Pattern.CHECKER:
			for side: float in [-1.0, 1.0]:
				_add_checkers(tool, side, color)
		_:
			empty = true
	_pattern_mesh.mesh = null if empty else tool.commit()


## Strip along the flat top of the body between x0 and x1.
func _add_top_strip(tool: SurfaceTool, x0: float, x1: float, color: Color) -> void:
	for i: int in _sections.size() - 1:
		var a: Section = _sections[i]
		var b: Section = _sections[i + 1]
		LowPoly.add_quad(
			tool,
			Vector3(x0, a.top + decal_offset, a.z), Vector3(x1, a.top + decal_offset, a.z),
			Vector3(x1, b.top + decal_offset, b.z), Vector3(x0, b.top + decal_offset, b.z),
			color, Vector3.UP
		)


func _side_point(section: Section, side: float, share: float) -> Vector3:
	return Vector3(side * (section.half_width + decal_offset), _side_y(section, share), section.z)


## Strip on one side face between the height shares, from z_range.x to z_range.y.
func _add_side_strip(tool: SurfaceTool, side: float, shares: Vector2, z_range: Vector2, color: Color) -> void:
	var stops: Array[float] = [z_range.x]
	for section: Section in _sections:
		if section.z > z_range.x and section.z < z_range.y:
			stops.append(section.z)
	stops.append(z_range.y)
	for i: int in stops.size() - 1:
		var a: Section = _section_at(stops[i])
		var b: Section = _section_at(stops[i + 1])
		LowPoly.add_quad(
			tool,
			_side_point(a, side, shares.x), _side_point(b, side, shares.x),
			_side_point(b, side, shares.y), _side_point(a, side, shares.y),
			color, Vector3(side, 0.0, 0.0)
		)


## Two rows of chequered squares along the straight part of the side.
func _add_checkers(tool: SurfaceTool, side: float, color: Color) -> void:
	var start: float = _sections[1].z
	var end: float = _sections[_sections.size() - 2].z
	var size: float = checker_size
	for section: Section in _sections.slice(1, _sections.size() - 1):
		size = minf(size, (_side_y(section, 1.0) - _side_y(section, 0.0)) * 0.5)
	var columns: int = ceili((end - start) / size)
	for column: int in columns:
		var z0: float = start + float(column) * size
		var z1: float = minf(z0 + size, end)
		var a: Section = _section_at(z0)
		var b: Section = _section_at(z1)
		var a_mid: float = _side_y(a, 0.5)
		var b_mid: float = _side_y(b, 0.5)
		var row: int = column % 2
		var a_low: float = a_mid - size + size * float(row)
		var b_low: float = b_mid - size + size * float(row)
		var ax: float = side * (a.half_width + decal_offset)
		var bx: float = side * (b.half_width + decal_offset)
		LowPoly.add_quad(
			tool,
			Vector3(ax, a_low, z0), Vector3(bx, b_low, z1),
			Vector3(bx, b_low + size, z1), Vector3(ax, a_low + size, z0),
			color, Vector3(side, 0.0, 0.0)
		)


# --- Shapes -------------------------------------------------------------------

## Closed cylinder centred on center with its axis along axis.
static func _add_cylinder(
	tool: SurfaceTool, center: Vector3, axis: Vector3, radius: float, length: float, sides: int, color: Color
) -> void:
	var direction: Vector3 = axis.normalized()
	var helper: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u: Vector3 = direction.cross(helper).normalized()
	var v: Vector3 = direction.cross(u)
	var front: Vector3 = center + direction * length * 0.5
	var back: Vector3 = center - direction * length * 0.5
	for i: int in sides:
		var angle_a: float = TAU * float(i) / float(sides)
		var angle_b: float = TAU * float(i + 1) / float(sides)
		var offset_a: Vector3 = (u * cos(angle_a) + v * sin(angle_a)) * radius
		var offset_b: Vector3 = (u * cos(angle_b) + v * sin(angle_b)) * radius
		LowPoly.add_quad(tool, back + offset_a, back + offset_b, front + offset_b, front + offset_a, color, offset_a + offset_b)
		LowPoly.add_triangle(tool, front, front + offset_a, front + offset_b, color, direction)
		LowPoly.add_triangle(tool, back, back + offset_a, back + offset_b, color, -direction)
