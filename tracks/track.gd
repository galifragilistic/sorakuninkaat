class_name Track
extends Node3D
## Builds a closed graybox circuit from control points: road ribbon(s) with
## per-surface colliders, a ground plane and boundary walls.

const GRID_SHADER: Shader = preload("res://tracks/shaders/graybox_grid.gdshader")

@export var track_name: String = ""

@export_group("Layout")
## Closed loop, driven in the listed order. The first point is the start line.
@export var control_points: PackedVector3Array = PackedVector3Array()
@export var road_width: float = 10.0
## Distance between ribbon cross-sections (m).
@export var sample_spacing: float = 2.0
## Catmull-Rom style handle length as a fraction of the neighbour distance.
@export_range(0.05, 0.4, 0.005) var tangent_scale: float = 0.167
## Height of the road above the ground so wheel rays hit the road first.
@export var road_lift: float = 0.03

@export_group("Surfaces")
@export var road_surface: SurfaceData
## Optional second road surface used on part of the lap.
@export var alt_surface: SurfaceData
## Start and end of the alt surface as fractions of lap length (0..1).
@export var alt_surface_range: Vector2 = Vector2.ZERO
@export var ground_surface: SurfaceData
@export var road_cell_size: float = 2.5
@export var ground_cell_size: float = 5.0

@export_group("World bounds")
@export var ground_size: Vector2 = Vector2(280.0, 220.0)
@export var ground_thickness: float = 2.0
@export var wall_height: float = 3.0
@export var wall_thickness: float = 2.0
@export var wall_color: Color = Color(0.3, 0.32, 0.38)

@export_group("Start")
@export var start_height: float = 0.6

var curve: Curve3D
var path: Path3D


func _ready() -> void:
	_build_curve()
	_build_ground()
	_build_walls()
	_build_road()


func get_length() -> float:
	return curve.get_baked_length()


func get_position_at(offset: float) -> Vector3:
	return to_global(curve.sample_baked(fposmod(offset, get_length()), true))


func get_direction_at(offset: float) -> Vector3:
	var half_step: float = sample_spacing * 0.5
	var ahead: Vector3 = get_position_at(offset + half_step)
	var behind: Vector3 = get_position_at(offset - half_step)
	return (ahead - behind).normalized()


## Transform for a car on the start line, facing the driving direction (-Z forward).
func get_start_transform() -> Transform3D:
	var origin: Vector3 = get_position_at(0.0) + Vector3.UP * start_height
	return Transform3D(Basis.looking_at(get_direction_at(0.0), Vector3.UP), origin)


func _build_curve() -> void:
	curve = Curve3D.new()
	curve.bake_interval = sample_spacing * 0.25
	var count: int = control_points.size()
	# The first point is repeated at the end to close the loop.
	for i: int in count + 1:
		var point: Vector3 = control_points[i % count]
		var previous: Vector3 = control_points[(i - 1 + count) % count]
		var next: Vector3 = control_points[(i + 1) % count]
		var handle: Vector3 = (next - previous) * tangent_scale
		curve.add_point(point, -handle, handle)
	path = Path3D.new()
	path.name = "Path"
	path.curve = curve
	add_child(path)


func _build_road() -> void:
	var has_alt: bool = alt_surface != null and alt_surface_range.y > alt_surface_range.x
	if not has_alt:
		_build_ribbon(0.0, 1.0, road_surface)
		return
	if alt_surface_range.x > 0.0:
		_build_ribbon(0.0, alt_surface_range.x, road_surface)
	_build_ribbon(alt_surface_range.x, alt_surface_range.y, alt_surface)
	if alt_surface_range.y < 1.0:
		_build_ribbon(alt_surface_range.y, 1.0, road_surface)


func _build_ribbon(from_fraction: float, to_fraction: float, surface: SurfaceData) -> void:
	var length: float = get_length()
	var from_offset: float = from_fraction * length
	var to_offset: float = to_fraction * length
	var steps: int = maxi(1, ceili((to_offset - from_offset) / sample_spacing))
	var half_width: float = road_width * 0.5
	var lift: Vector3 = Vector3.UP * road_lift

	var lefts: PackedVector3Array = PackedVector3Array()
	var rights: PackedVector3Array = PackedVector3Array()
	for i: int in steps + 1:
		var offset: float = lerpf(from_offset, to_offset, float(i) / float(steps))
		var center: Vector3 = to_local(get_position_at(offset)) + lift
		var forward: Vector3 = global_basis.inverse() * get_direction_at(offset)
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		lefts.append(center - right * half_width)
		rights.append(center + right * half_width)

	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in steps:
		# Clockwise seen from above = front face up.
		for vertex: Vector3 in [
			lefts[i], lefts[i + 1], rights[i],
			rights[i], lefts[i + 1], rights[i + 1],
		]:
			tool.set_normal(Vector3.UP)
			tool.add_vertex(vertex)
	var mesh: ArrayMesh = tool.commit()

	var body: SurfaceBody = SurfaceBody.new()
	body.name = "Road_%s_%d" % [surface.display_name, get_child_count()]
	body.surface = surface
	add_child(body)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_grid_material(surface, road_cell_size)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_instance)

	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape.backface_collision = true
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _build_ground() -> void:
	var body: SurfaceBody = SurfaceBody.new()
	body.name = "Ground"
	body.surface = ground_surface
	add_child(body)

	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = ground_size
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = plane
	mesh_instance.material_override = _make_grid_material(ground_surface, ground_cell_size)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_instance)

	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(ground_size.x, ground_thickness, ground_size.y)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = box
	collision.position = Vector3.DOWN * ground_thickness * 0.5
	body.add_child(collision)


func _build_walls() -> void:
	var half: Vector2 = ground_size * 0.5
	var inset: float = wall_thickness * 0.5
	var y: float = wall_height * 0.5
	var long_x: Vector3 = Vector3(ground_size.x, wall_height, wall_thickness)
	var long_z: Vector3 = Vector3(wall_thickness, wall_height, ground_size.y)
	_add_wall(long_x, Vector3(0.0, y, -half.y + inset))
	_add_wall(long_x, Vector3(0.0, y, half.y - inset))
	_add_wall(long_z, Vector3(-half.x + inset, y, 0.0))
	_add_wall(long_z, Vector3(half.x - inset, y, 0.0))


func _add_wall(size: Vector3, wall_position: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Wall_%d" % get_child_count()
	body.position = wall_position
	add_child(body)

	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = wall_color
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = box
	body.add_child(collision)


func _make_grid_material(surface: SurfaceData, cell_size: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = GRID_SHADER
	material.set_shader_parameter("color_a", surface.color_a)
	material.set_shader_parameter("color_b", surface.color_b)
	material.set_shader_parameter("cell_size", cell_size)
	return material
