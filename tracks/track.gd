class_name Track
extends Node3D
## Builds a closed circuit from control points: low-poly road ribbon(s) with
## per-surface colliders, a patchwork terrain and boundary walls.
## A TrackScenery child, if present, is built afterwards.

const CHECKER_SHADER: Shader = preload("res://tracks/shaders/checker.gdshader")

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
## Width of the darker shoulder strip on both road edges (m).
@export var shoulder_width: float = 0.9
## Raises the second half of the lap slightly. Use on tracks that cross
## themselves so the two road ribbons do not flicker at the crossing.
@export var second_half_extra_lift: float = 0.0

@export_group("Surfaces")
@export var road_surface: SurfaceData
## Optional second road surface used on part of the lap.
@export var alt_surface: SurfaceData
## Start and end of the alt surface as fractions of lap length (0..1).
@export var alt_surface_range: Vector2 = Vector2.ZERO
@export var ground_surface: SurfaceData

@export_group("Terrain")
@export var ground_size: Vector2 = Vector2(280.0, 220.0)
@export var ground_thickness: float = 2.0
## Edge length of the terrain triangles (m).
@export var terrain_cell_size: float = 9.0
## Lower = larger light and dark areas.
@export var terrain_noise_frequency: float = 0.018
## Random per-triangle tint on top of the noise (0..1).
@export_range(0.0, 1.0, 0.01) var terrain_color_jitter: float = 0.22
@export var look_seed: int = 7

@export_group("World bounds")
@export var wall_height: float = 3.0
@export var wall_thickness: float = 2.0
@export var wall_color: Color = Color(0.16, 0.2, 0.16)

@export_group("Start")
@export var start_height: float = 0.6
## Distance from the start line back to the first grid row (m).
@export var grid_first_row_distance: float = 6.0
@export var grid_row_spacing: float = 7.0
## Sideways offset of the two grid columns as a share of the road width.
@export_range(0.0, 0.5, 0.01) var grid_column_offset: float = 0.2

@export_group("Checkpoints")
## Evenly spaced gates around the lap; the first one is the start/finish line.
@export var checkpoint_count: int = 6
## Gate width as a multiple of the road width, so wide lines still count.
@export var checkpoint_width_scale: float = 2.2
@export var checkpoint_height: float = 6.0
@export var checkpoint_depth: float = 1.5
## Length of the chequered start line along the road (m).
@export var start_line_length: float = 2.4
@export var start_line_cells: Vector2 = Vector2(10.0, 2.0)
@export var start_line_lift: float = 0.02

var curve: Curve3D
var path: Path3D
var checkpoints: Array[Checkpoint] = []

## Centre line sampled every sample_spacing metres (global space), for fast local searches.
var _samples: PackedVector3Array = PackedVector3Array()
var _sample_step: float = 1.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = look_seed
	_build_curve()
	_build_ground()
	_build_walls()
	_build_road()
	_build_start_line()
	_build_checkpoints()
	for child: Node in get_children():
		var scenery: TrackScenery = child as TrackScenery
		if scenery != null:
			scenery.build(self)


func get_length() -> float:
	return curve.get_baked_length()


func get_position_at(offset: float) -> Vector3:
	return to_global(curve.sample_baked(fposmod(offset, get_length()), true))


func get_direction_at(offset: float) -> Vector3:
	var half_step: float = sample_spacing * 0.5
	var ahead: Vector3 = get_position_at(offset + half_step)
	var behind: Vector3 = get_position_at(offset - half_step)
	return (ahead - behind).normalized()


## Road surface at a point of the lap given as a fraction (0..1).
func get_road_surface_at(fraction: float) -> SurfaceData:
	var in_alt: bool = fraction >= alt_surface_range.x and fraction < alt_surface_range.y
	return alt_surface if alt_surface != null and in_alt else road_surface


## Unit vector pointing to the right of the driving direction.
func get_right_at(offset: float) -> Vector3:
	return get_direction_at(offset).cross(Vector3.UP).normalized()


## Point beside the road: side is -1 (left) or 1 (right), margin is metres past the road edge.
func get_roadside_position(offset: float, side: float, margin: float) -> Vector3:
	var distance: float = road_width * 0.5 + margin
	return get_position_at(offset) + get_right_at(offset) * side * distance


## Horizontal distance from a global position to the road centre line.
func get_distance_to_centerline(global_point: Vector3) -> float:
	var local_point: Vector3 = to_local(global_point)
	var closest: Vector3 = curve.get_closest_point(local_point)
	return Vector2(local_point.x - closest.x, local_point.z - closest.z).length()


## Lap offset (0..length) of the point on the centre line closest to a global position.
func get_offset_at(global_point: Vector3) -> float:
	return curve.get_closest_offset(to_local(global_point))


## Like get_offset_at(), but only searches within window metres of hint_offset.
## Keeps a car on its own stretch of road where the track crosses or runs
## close to itself. Falls back to a full search if the car is nowhere near.
func get_offset_near(global_point: Vector3, hint_offset: float, window: float = 40.0) -> float:
	var count: int = _samples.size()
	var hint_index: int = roundi(fposmod(hint_offset, get_length()) / _sample_step)
	var span: int = ceili(window / _sample_step)
	var best_index: int = posmod(hint_index, count)
	var best_distance: float = INF
	for i: int in range(-span, span + 1):
		var index: int = posmod(hint_index + i, count)
		var distance: float = _samples[index].distance_squared_to(global_point)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_distance > window * window:
		return get_offset_at(global_point)
	return float(best_index) * _sample_step


## Transform for the car in grid slot 0, 1, 2... behind the start line (-Z forward).
func get_grid_transform(slot: int) -> Transform3D:
	@warning_ignore("integer_division")
	var row: int = slot / 2
	var side: float = -1.0 if slot % 2 == 0 else 1.0
	var offset: float = -(grid_first_row_distance + float(row) * grid_row_spacing)
	var origin: Vector3 = get_position_at(offset) + Vector3.UP * start_height
	origin += get_right_at(offset) * side * road_width * grid_column_offset
	return Transform3D(Basis.looking_at(get_direction_at(offset), Vector3.UP), origin)


## Closed centre-line curve through the control points. Static so menus can
## draw a track outline without building the whole track.
static func make_curve(points: PackedVector3Array, handle_scale: float, bake_interval: float) -> Curve3D:
	var result: Curve3D = Curve3D.new()
	result.bake_interval = bake_interval
	var count: int = points.size()
	# The first point is repeated at the end to close the loop.
	for i: int in count + 1:
		var point: Vector3 = points[i % count]
		var previous: Vector3 = points[(i - 1 + count) % count]
		var next: Vector3 = points[(i + 1) % count]
		var handle: Vector3 = (next - previous) * handle_scale
		result.add_point(point, -handle, handle)
	return result


func _build_curve() -> void:
	curve = make_curve(control_points, tangent_scale, sample_spacing * 0.25)
	path = Path3D.new()
	path.name = "Path"
	path.curve = curve
	add_child(path)
	var count: int = maxi(1, floori(get_length() / sample_spacing))
	_sample_step = get_length() / float(count)
	for i: int in count:
		_samples.append(get_position_at(float(i) * _sample_step))


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


## Cross-section points (left to right) at a lap offset, in local space.
func _get_cross_section(offset: float, lateral_offsets: PackedFloat32Array) -> PackedVector3Array:
	var lift: float = road_lift
	if fposmod(offset, get_length()) > get_length() * 0.5:
		lift += second_half_extra_lift
	var center: Vector3 = to_local(get_position_at(offset)) + Vector3.UP * lift
	var right: Vector3 = global_basis.inverse() * get_right_at(offset)
	var points: PackedVector3Array = PackedVector3Array()
	for lateral: float in lateral_offsets:
		points.append(center + right * lateral)
	return points


func _build_ribbon(from_fraction: float, to_fraction: float, surface: SurfaceData) -> void:
	var length: float = get_length()
	var from_offset: float = from_fraction * length
	var to_offset: float = to_fraction * length
	var steps: int = maxi(1, ceili((to_offset - from_offset) / sample_spacing))
	var half_width: float = road_width * 0.5
	var inner: float = half_width - shoulder_width
	# Shoulder, two driving lanes, shoulder.
	var laterals: PackedFloat32Array = PackedFloat32Array([-half_width, -inner, 0.0, inner, half_width])
	var strip_count: int = laterals.size() - 1

	var tool: SurfaceTool = LowPoly.begin()
	var previous: PackedVector3Array = _get_cross_section(from_offset, laterals)
	for i: int in steps:
		var offset: float = lerpf(from_offset, to_offset, float(i + 1) / float(steps))
		var current: PackedVector3Array = _get_cross_section(offset, laterals)
		for strip: int in strip_count:
			var is_shoulder: bool = strip == 0 or strip == strip_count - 1
			var color: Color = surface.edge_color
			if not is_shoulder:
				color = surface.color_a.lerp(surface.color_b, _rng.randf())
			LowPoly.add_quad(
				tool, previous[strip], current[strip], current[strip + 1], previous[strip + 1],
				color, Vector3.UP
			)
		previous = current
	var mesh: ArrayMesh = tool.commit()

	var body: SurfaceBody = SurfaceBody.new()
	body.name = "Road_%s_%d" % [surface.display_name, get_child_count()]
	body.surface = surface
	add_child(body)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = LowPoly.vertex_color_material()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_instance)

	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape.backface_collision = true
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _build_start_line() -> void:
	var half_length: float = start_line_length * 0.5
	var half_width: float = road_width * 0.5 - shoulder_width
	var laterals: PackedFloat32Array = PackedFloat32Array([-half_width, half_width])
	var lift: Vector3 = Vector3.UP * start_line_lift
	var back: PackedVector3Array = _get_cross_section(-half_length, laterals)
	var front: PackedVector3Array = _get_cross_section(half_length, laterals)
	var corners: Array[Vector3] = [back[0] + lift, front[0] + lift, front[1] + lift, back[1] + lift]
	var uvs: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0)]

	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in [0, 1, 2, 0, 2, 3]:
		tool.set_normal(Vector3.UP)
		tool.set_uv(uvs[index])
		tool.add_vertex(corners[index])

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = CHECKER_SHADER
	material.set_shader_parameter("cells", start_line_cells)
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "StartLine"
	mesh_instance.mesh = tool.commit()
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


func _build_checkpoints() -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(road_width * checkpoint_width_scale, checkpoint_height, checkpoint_depth)
	for i: int in checkpoint_count:
		var offset: float = get_length() * float(i) / float(checkpoint_count)
		var checkpoint: Checkpoint = Checkpoint.new()
		checkpoint.name = "Checkpoint_%d" % i
		checkpoint.index = i
		add_child(checkpoint)
		var origin: Vector3 = get_position_at(offset) + Vector3.UP * checkpoint_height * 0.5
		checkpoint.global_transform = Transform3D(
			Basis.looking_at(get_direction_at(offset), Vector3.UP), origin
		)
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		checkpoint.add_child(collision)
		checkpoints.append(checkpoint)


func _build_ground() -> void:
	var body: SurfaceBody = SurfaceBody.new()
	body.name = "Ground"
	body.surface = ground_surface
	add_child(body)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = _build_terrain_mesh()
	mesh_instance.material_override = LowPoly.vertex_color_material()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_instance)

	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(ground_size.x, ground_thickness, ground_size.y)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = box
	collision.position = Vector3.DOWN * ground_thickness * 0.5
	body.add_child(collision)


## Flat triangle patchwork. Each triangle gets its own shade of the ground colours.
func _build_terrain_mesh() -> ArrayMesh:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = look_seed
	noise.frequency = terrain_noise_frequency
	var columns: int = ceili(ground_size.x / terrain_cell_size)
	var rows: int = ceili(ground_size.y / terrain_cell_size)
	var cell: Vector2 = Vector2(ground_size.x / float(columns), ground_size.y / float(rows))
	var origin: Vector3 = Vector3(-ground_size.x * 0.5, 0.0, -ground_size.y * 0.5)

	var tool: SurfaceTool = LowPoly.begin()
	for column: int in columns:
		for row: int in rows:
			var a: Vector3 = origin + Vector3(column * cell.x, 0.0, row * cell.y)
			var b: Vector3 = a + Vector3(cell.x, 0.0, 0.0)
			var c: Vector3 = a + Vector3(cell.x, 0.0, cell.y)
			var d: Vector3 = a + Vector3(0.0, 0.0, cell.y)
			# Alternate the diagonal so the triangles form diamonds instead of stripes.
			var triangles: Array = [[a, b, c], [a, c, d]]
			if (column + row) % 2 == 1:
				triangles = [[a, b, d], [b, c, d]]
			for triangle: Array in triangles:
				var p0: Vector3 = triangle[0]
				var p1: Vector3 = triangle[1]
				var p2: Vector3 = triangle[2]
				LowPoly.add_triangle(tool, p0, p1, p2, _get_terrain_color(noise, (p0 + p1 + p2) / 3.0), Vector3.UP)
	return tool.commit()


func _get_terrain_color(noise: FastNoiseLite, point: Vector3) -> Color:
	var shade: float = noise.get_noise_2d(point.x, point.z) * 0.5 + 0.5
	shade += _rng.randf_range(-terrain_color_jitter, terrain_color_jitter)
	return ground_surface.color_a.lerp(ground_surface.color_b, clampf(shade, 0.0, 1.0))


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
