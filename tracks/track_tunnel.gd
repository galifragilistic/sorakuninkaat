class_name TrackTunnel
extends Node3D
## A covered stretch of road: a rock mound over the road with walls, a ceiling
## and lights inside. Seen from the isometric camera it would hide the cars,
## so the mound fades out while any car is inside; its shadow stays, so the
## tunnel stays dark.

## Walls stand this far beyond the road edges (m).
@export var wall_margin: float = 1.2
@export var clearance: float = 4.6
@export var top_height: float = 6.5
## Half width of the flat top beyond the walls (m).
@export var top_extra_width: float = 1.5
## Half width of the mound at its foot, beyond the road edge (m).
@export var side_width: float = 9.0
## The mound's foot goes this far below the road or the ground.
@export var base_sink: float = 1.0
@export var rock_color: Color = Color(0.46, 0.44, 0.4)
@export var rock_dark_color: Color = Color(0.34, 0.33, 0.31)
@export var grass_top_color: Color = Color(0.36, 0.5, 0.24)
@export var wall_color: Color = Color(0.55, 0.55, 0.57)
@export var ceiling_color: Color = Color(0.3, 0.3, 0.33)
@export var light_spacing: float = 14.0
@export var light_color: Color = Color(1.0, 0.85, 0.6)
@export var light_energy: float = 2.5
@export var light_range: float = 11.0
@export var lamp_size: Vector3 = Vector3(1.2, 0.15, 0.5)
@export var lamp_emission: float = 5.0
## Opacity of the mound while a car is inside.
@export_range(0.0, 1.0, 0.01) var faded_alpha: float = 0.16
## Opacity change per second.
@export var fade_speed: float = 5.0
## Cars this close to either end already count as inside (m).
@export var detect_margin: float = 4.0

var _track: Track
var _start: float = 0.0
var _end: float = 0.0
var _inner_half: float = 0.0
var _material: StandardMaterial3D
var _alpha: float = 1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func build(track: Track, start_offset: float, end_offset: float) -> void:
	_track = track
	_start = start_offset
	_end = end_offset
	_rng.seed = int(start_offset * 10.0)
	var half: float = track.road_width * 0.5
	_inner_half = half + wall_margin
	var top_half: float = _inner_half + top_extra_width
	var foot_half: float = half + side_width
	var steps: int = maxi(1, ceili((end_offset - start_offset) / track.sample_spacing))

	var mesh_tool: SurfaceTool = LowPoly.begin()
	var sections: Array = []
	for i: int in steps + 1:
		sections.append(_section(lerpf(start_offset, end_offset, float(i) / float(steps)), top_half, foot_half))
	for i: int in steps:
		var a: Dictionary = sections[i]
		var b: Dictionary = sections[i + 1]
		var right: Vector3 = (a["right"] + b["right"]).normalized()
		var rock: Color = rock_color.darkened(_rng.randf_range(0.0, 0.12))
		# Inside: walls and ceiling face the road.
		LowPoly.add_quad(mesh_tool, a["A"], b["A"], b["B"], a["B"], wall_color, right)
		LowPoly.add_quad(mesh_tool, a["B"], b["B"], b["C"], a["C"], ceiling_color, Vector3.DOWN)
		LowPoly.add_quad(mesh_tool, a["C"], b["C"], b["D"], a["D"], wall_color, -right)
		# Outside: slopes and a grassy top.
		LowPoly.add_quad(mesh_tool, a["E"], b["E"], b["F"], a["F"], rock, -right + Vector3.UP)
		LowPoly.add_quad(mesh_tool, a["F"], b["F"], b["G"], a["G"], grass_top_color.darkened(_rng.randf_range(0.0, 0.1)), Vector3.UP)
		LowPoly.add_quad(mesh_tool, a["G"], b["G"], b["H"], a["H"], rock, right + Vector3.UP)
	_add_end_face(mesh_tool, sections[0], -track.get_direction_at(start_offset))
	_add_end_face(mesh_tool, sections[steps], track.get_direction_at(end_offset))
	var mesh: ArrayMesh = mesh_tool.commit()

	_material = LowPoly.vertex_color_material()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Mound"
	visual.mesh = mesh
	visual.material_override = _material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	# The shadow comes from a solid copy, so the tunnel stays dark while the mound is faded.
	var shadow: MeshInstance3D = MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = mesh
	shadow.material_override = LowPoly.vertex_color_material()
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(shadow)

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape.backface_collision = true
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	_build_lights()


## Profile points at one offset: inner A-B-C-D (left wall foot, left ceiling
## corner, right ceiling corner, right wall foot) and outer E-F-G-H.
func _section(offset: float, top_half: float, foot_half: float) -> Dictionary:
	var center: Vector3 = to_local(_track.get_position_at(offset))
	var right: Vector3 = _track.get_right_at(offset)
	var up: Vector3 = Vector3.UP
	var section: Dictionary = {"right": right}
	section["A"] = center - right * _inner_half + up * -0.3
	section["B"] = center - right * _inner_half + up * clearance
	section["C"] = center + right * _inner_half + up * clearance
	section["D"] = center + right * _inner_half + up * -0.3
	section["F"] = center - right * top_half + up * top_height
	section["G"] = center + right * top_half + up * top_height
	# The foot follows whichever is lower, the road or the ground beside it.
	for key: String in ["E", "H"]:
		var side: float = -1.0 if key == "E" else 1.0
		var foot: Vector3 = center + right * side * foot_half
		var ground: float = _track.get_ground_height(to_global(foot))
		foot.y = minf(center.y, ground) - base_sink
		section[key] = foot
	return section


## The portal face around the opening at one end.
func _add_end_face(tool: SurfaceTool, section: Dictionary, outward: Vector3) -> void:
	LowPoly.add_quad(tool, section["E"], section["F"], section["B"], section["A"], rock_dark_color, outward)
	LowPoly.add_quad(tool, section["F"], section["G"], section["C"], section["B"], rock_dark_color, outward)
	LowPoly.add_quad(tool, section["G"], section["H"], section["D"], section["C"], rock_dark_color, outward)


func _build_lights() -> void:
	var lamps: SurfaceTool = LowPoly.begin()
	var length: float = _end - _start
	var count: int = maxi(1, floori(length / light_spacing))
	for i: int in count:
		var offset: float = _start + (float(i) + 0.5) * length / float(count)
		var point: Vector3 = to_local(_track.get_position_at(offset)) + Vector3.UP * (clearance - lamp_size.y)
		LowPoly.add_box(lamps, point, lamp_size, light_color)
		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = light_color
		light.light_energy = light_energy
		light.omni_range = light_range
		light.position = point + Vector3.DOWN * 0.4
		add_child(light)
	var lamp_mesh: MeshInstance3D = MeshInstance3D.new()
	lamp_mesh.name = "Lamps"
	lamp_mesh.mesh = lamps.commit()
	lamp_mesh.material_override = LowPoly.emissive_material(light_color, lamp_emission)
	lamp_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lamp_mesh)


func _process(delta: float) -> void:
	var target: float = faded_alpha if _is_car_inside() else 1.0
	if is_equal_approx(_alpha, target):
		return
	_alpha = move_toward(_alpha, target, fade_speed * delta)
	_material.albedo_color.a = _alpha


func _is_car_inside() -> bool:
	for node: Node in get_tree().get_nodes_in_group(Car.GROUP):
		var car: Node3D = node as Node3D
		var offset: float = _track.get_offset_at(car.global_position)
		if offset < _start - detect_margin or offset > _end + detect_margin:
			continue
		var road: Vector3 = _track.get_position_at(offset)
		var sideways: float = Vector2(car.global_position.x - road.x, car.global_position.z - road.z).length()
		if sideways < _inner_half + 1.0 and absf(car.global_position.y - road.y) < clearance:
			return true
	return false
