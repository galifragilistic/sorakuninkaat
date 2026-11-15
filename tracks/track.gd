class_name Track
extends Node3D
## Builds a closed circuit from control points: low-poly road ribbon(s) with
## per-surface colliders, a hilly patchwork terrain shaped around the road,
## bridges, tunnels and boundary walls. The control points' y values are the
## road heights. A TrackScenery child, if present, is built afterwards.

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
## Road in several surfaces: section i starts at road_section_starts[i]
## (share of the lap, the first one 0) and runs to the next start. When set,
## road_surface and alt_surface are not used for the road.
@export var road_sections: Array[SurfaceData] = []
@export var road_section_starts: PackedFloat32Array = PackedFloat32Array()

@export_group("Terrain")
@export var ground_size: Vector2 = Vector2(280.0, 220.0)
## Edge length of the terrain triangles (m).
@export var terrain_cell_size: float = 5.0
## Hills and hollows: x, z = centre, z of the vector = radius, w = height
## (negative for a hollow).
@export var terrain_features: PackedVector4Array = PackedVector4Array()
## Like terrain_features (x, z, radius, height), but overlapping ones take
## the highest rise and the deepest dip instead of adding up. Tracks made in
## the editor use these to lift the land under raised road and sink it under
## lowered road.
@export var road_hills: PackedVector4Array = PackedVector4Array()
## Gentle random rolling on top of the features (m).
@export var terrain_noise_height: float = 1.2
@export var terrain_height_frequency: float = 0.012
## Hills and rolling fade out over this distance from the outer walls (m).
@export var terrain_edge_falloff: float = 25.0
## The ground is flattened to road height this far beyond the road edges (m)...
@export var road_flat_margin: float = 3.0
## ...and blends back to its own shape over this distance (m).
@export var road_blend_width: float = 12.0
## The ground sits this far below the road surface next to it.
@export var road_sink: float = 0.2
## Side skirts hide the gap between the road edge and lower ground (m).
@export var road_skirt_depth: float = 2.0
## Lower = larger light and dark areas.
@export var terrain_noise_frequency: float = 0.018
## Random per-triangle tint on top of the noise (0..1).
@export_range(0.0, 1.0, 0.01) var terrain_color_jitter: float = 0.22
@export var look_seed: int = 7

@export_group("Bridges and tunnels")
## Each entry: x = control point index, y and z = start and end in metres
## relative to that point along the road (y negative = before the point).
@export var bridges: PackedVector3Array = PackedVector3Array()
@export var tunnels: PackedVector3Array = PackedVector3Array()

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

@export_group("Checkpoint gates")
## Glow colour of the gates and the dashed line across the road.
@export var checkpoint_marker_color: Color = Color("#3fd8ff")
@export var checkpoint_post_color: Color = Color(0.12, 0.13, 0.19)
@export var checkpoint_post_height: float = 2.6
@export var checkpoint_post_width: float = 0.28
## Distance of the posts from the road edge (m).
@export var checkpoint_post_margin: float = 0.7
@export var checkpoint_light_size: Vector3 = Vector3(0.5, 0.36, 0.5)
@export var checkpoint_light_energy: float = 3.0
@export var checkpoint_dash_length: float = 0.9
@export var checkpoint_dash_gap: float = 0.6
@export var checkpoint_dash_depth: float = 0.4
@export var checkpoint_dash_energy: float = 0.6
## Above the road, below nothing else.
@export var checkpoint_dash_lift: float = 0.025

var curve: Curve3D
var path: Path3D
var checkpoints: Array[Checkpoint] = []

## Centre line sampled every sample_spacing metres (global space), for fast local searches.
var _samples: PackedVector3Array = PackedVector3Array()
var _sample_step: float = 1.0

## True for samples on a bridge: those do not shape the ground.
var _sample_on_bridge: PackedByteArray = PackedByteArray()
var _point_offsets: PackedFloat32Array = PackedFloat32Array()
var _bridge_ranges: Array[Vector2] = []
var _tunnel_ranges: Array[Vector2] = []
var _terrain: TrackTerrain

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = look_seed
	_build_curve()
	_resolve_structures()
	_build_ground()
	_build_walls()
	_build_road()
	_build_start_line()
	_build_checkpoints()
	_build_structures()
	_place_props_on_ground()
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
	if not road_sections.is_empty():
		var surface: SurfaceData = road_sections[0]
		for i: int in road_sections.size():
			if road_section_starts[i] <= fraction:
				surface = road_sections[i]
		return surface
	var in_alt: bool = fraction >= alt_surface_range.x and fraction < alt_surface_range.y
	return alt_surface if alt_surface != null and in_alt else road_surface


## Ground height under a global point (the terrain, not the road).
func get_ground_height(global_point: Vector3) -> float:
	var local_point: Vector3 = to_local(global_point)
	return _terrain.height_at(local_point.x, local_point.z)


func is_on_bridge(offset: float) -> bool:
	return _in_ranges(fposmod(offset, get_length()), _bridge_ranges)


func is_in_tunnel(offset: float) -> bool:
	return _in_ranges(fposmod(offset, get_length()), _tunnel_ranges)


## Horizontal distance from a point to the nearest road that passes at least
## a few metres below it (not counting bridges). INF when there is none.
func get_distance_to_road_below(global_point: Vector3) -> float:
	var nearest: float = INF
	for i: int in _samples.size():
		var sample: Vector3 = _samples[i]
		if _sample_on_bridge[i] == 1 or sample.y > global_point.y - 2.0:
			continue
		nearest = minf(nearest, Vector2(sample.x - global_point.x, sample.z - global_point.z).length())
	return nearest


## Horizontal distance to the nearest road that lies on the ground (bridges
## are left out, since things may stand under them).
func get_distance_to_ground_road(global_point: Vector3) -> float:
	var nearest: float = INF
	for i: int in _samples.size():
		if _sample_on_bridge[i] == 1:
			continue
		var sample: Vector3 = _samples[i]
		nearest = minf(nearest, Vector2(sample.x - global_point.x, sample.z - global_point.z).length())
	return nearest


## True if a point is within margin metres of the road on a bridge or in a tunnel.
func is_near_structure(global_point: Vector3, margin: float) -> bool:
	for i: int in _samples.size():
		var offset: float = float(i) * _sample_step
		if not (is_on_bridge(offset) or is_in_tunnel(offset)):
			continue
		var sample: Vector3 = _samples[i]
		if Vector2(sample.x - global_point.x, sample.z - global_point.z).length() < road_width * 0.5 + margin:
			return true
	return false


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
	_point_offsets = _measure_point_offsets()


## Lap offset of every control point: the length of the curve up to it.
func _measure_point_offsets() -> PackedFloat32Array:
	var offsets: PackedFloat32Array = PackedFloat32Array([0.0])
	for i: int in range(1, control_points.size()):
		var partial: Curve3D = Curve3D.new()
		partial.bake_interval = curve.bake_interval
		for p: int in i + 1:
			partial.add_point(curve.get_point_position(p), curve.get_point_in(p), curve.get_point_out(p))
		offsets.append(partial.get_baked_length())
	return offsets


## Turns the bridge and tunnel entries into lap offset ranges and marks the
## road samples on bridges.
func _resolve_structures() -> void:
	for entry: Vector3 in bridges:
		_bridge_ranges.append(_entry_range(entry))
	for entry: Vector3 in tunnels:
		_tunnel_ranges.append(_entry_range(entry))
	_sample_on_bridge.resize(_samples.size())
	for i: int in _samples.size():
		_sample_on_bridge[i] = 1 if _in_ranges(float(i) * _sample_step, _bridge_ranges) else 0


func _entry_range(entry: Vector3) -> Vector2:
	var base: float = _point_offsets[clampi(int(entry.x), 0, _point_offsets.size() - 1)]
	return Vector2(base + entry.y, base + entry.z)


func _in_ranges(offset: float, ranges: Array[Vector2]) -> bool:
	for range_offsets: Vector2 in ranges:
		if offset >= range_offsets.x and offset <= range_offsets.y:
			return true
	return false


func _build_structures() -> void:
	for i: int in _bridge_ranges.size():
		var bridge: TrackBridge = TrackBridge.new()
		bridge.name = "Bridge_%d" % i
		add_child(bridge)
		bridge.build(self, _bridge_ranges[i].x, _bridge_ranges[i].y)
	for i: int in _tunnel_ranges.size():
		var tunnel: TrackTunnel = TrackTunnel.new()
		tunnel.name = "Tunnel_%d" % i
		# The top of the mound looks like the ground around it (grass, sand, snow).
		tunnel.grass_top_color = ground_surface.color_a
		add_child(tunnel)
		tunnel.build(self, _tunnel_ranges[i].x, _tunnel_ranges[i].y)


## Blocks placed in the scene (containers, buildings) stand on the ground.
func _place_props_on_ground() -> void:
	for child: Node in get_children():
		var block: CSGBox3D = child as CSGBox3D
		if block != null:
			block.position.y = get_ground_height(block.global_position) + block.size.y * 0.5


## Height of the ground before the road shapes it: rolling plus features,
## fading out towards the outer walls.
func _natural_height(x: float, z: float, noise: FastNoiseLite) -> float:
	var height: float = noise.get_noise_2d(x, z) * terrain_noise_height
	for feature: Vector4 in terrain_features:
		var distance: float = Vector2(x - feature.x, z - feature.y).length()
		if distance < feature.z:
			height += feature.w * smoothstep(feature.z, 0.0, distance)
	# Overlapping road hills do not stack: the highest hill and the deepest
	# hollow win, so a raised stretch of road becomes one even ridge.
	var rise: float = 0.0
	var dip: float = 0.0
	for hill: Vector4 in road_hills:
		var distance: float = Vector2(x - hill.x, z - hill.y).length()
		if distance < hill.z:
			var shaped: float = hill.w * smoothstep(hill.z, 0.0, distance)
			rise = maxf(rise, shaped)
			dip = minf(dip, shaped)
	height += rise + dip
	var half: Vector2 = ground_size * 0.5
	var to_edge: float = minf(half.x - absf(x), half.y - absf(z))
	return height * smoothstep(0.0, terrain_edge_falloff, to_edge)


func _build_road() -> void:
	if not road_sections.is_empty():
		for i: int in road_sections.size():
			var end: float = road_section_starts[i + 1] if i + 1 < road_sections.size() else 1.0
			_build_ribbon(road_section_starts[i], end, road_sections[i])
		return
	var has_alt: bool = alt_surface != null and alt_surface_range.y > alt_surface_range.x
	if not has_alt:
		_build_ribbon(0.0, 1.0, road_surface)
		return
	if alt_surface_range.x > 0.0:
		_build_ribbon(0.0, alt_surface_range.x, road_surface)
	_build_ribbon(alt_surface_range.x, alt_surface_range.y, alt_surface)
	if alt_surface_range.y < 1.0:
		_build_ribbon(alt_surface_range.y, 1.0, road_surface)


## Cross-section points (left to right) on the road surface at a lap offset, in local space.
func get_cross_section(offset: float, lateral_offsets: PackedFloat32Array) -> PackedVector3Array:
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
	var skirt_tool: SurfaceTool = LowPoly.begin()
	var skirt_color: Color = surface.edge_color.darkened(0.25)
	var skirt: Vector3 = Vector3.DOWN * road_skirt_depth
	var previous: PackedVector3Array = get_cross_section(from_offset, laterals)
	for i: int in steps:
		var offset: float = lerpf(from_offset, to_offset, float(i + 1) / float(steps))
		var current: PackedVector3Array = get_cross_section(offset, laterals)
		# Skirts down the road edges, except on bridges where the deck takes over.
		if not is_on_bridge(offset - sample_spacing * 0.5):
			var right: Vector3 = global_basis.inverse() * get_right_at(offset)
			var last: int = laterals.size() - 1
			LowPoly.add_quad(skirt_tool, previous[0], current[0], current[0] + skirt, previous[0] + skirt, skirt_color, -right)
			LowPoly.add_quad(skirt_tool, previous[last], current[last], current[last] + skirt, previous[last] + skirt, skirt_color, right)
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
	# Visual only: driving back up onto the road should not catch on the skirt.
	var skirt_instance: MeshInstance3D = MeshInstance3D.new()
	skirt_instance.mesh = skirt_tool.commit()
	skirt_instance.material_override = LowPoly.vertex_color_material()
	body.add_child(skirt_instance)

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
	var back: PackedVector3Array = get_cross_section(-half_length, laterals)
	var front: PackedVector3Array = get_cross_section(half_length, laterals)
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
		# The start line already has its chequered stripe.
		if i > 0:
			_build_checkpoint_gate(offset, i)


## Lap offset of checkpoint i (0 = the start line).
func get_checkpoint_offset(index: int) -> float:
	return get_length() * float(index) / float(checkpoint_count)


## A gate the driver can see: two posts with glowing lamps beside the road
## and a glowing dashed line across it. Visual only; nothing to crash into.
func _build_checkpoint_gate(offset: float, index: int) -> void:
	var gate: Node3D = Node3D.new()
	gate.name = "CheckpointGate_%d" % index
	add_child(gate)

	var posts: SurfaceTool = LowPoly.begin()
	var post_size: Vector3 = Vector3(checkpoint_post_width, checkpoint_post_height, checkpoint_post_width)
	var lights: SurfaceTool = LowPoly.begin()
	for side: float in [-1.0, 1.0]:
		var base: Vector3 = to_local(get_roadside_position(offset, side, checkpoint_post_margin))
		# On a bridge the posts stand on the deck, elsewhere on the ground.
		if not is_on_bridge(offset):
			base.y = get_ground_height(to_global(base))
		LowPoly.add_box(posts, base + Vector3.UP * checkpoint_post_height * 0.5, post_size, checkpoint_post_color)
		var lamp: Vector3 = base + Vector3.UP * (checkpoint_post_height + checkpoint_light_size.y * 0.5)
		LowPoly.add_box(lights, lamp, checkpoint_light_size, checkpoint_marker_color)
	_add_gate_mesh(gate, posts.commit(), LowPoly.vertex_color_material())
	_add_gate_mesh(gate, lights.commit(), LowPoly.emissive_material(checkpoint_marker_color, checkpoint_light_energy))

	# Dashes across the driving lanes.
	var half_width: float = road_width * 0.5 - shoulder_width
	var laterals: PackedFloat32Array = PackedFloat32Array()
	var position_on_line: float = -half_width
	while position_on_line + checkpoint_dash_length <= half_width + 0.01:
		laterals.append(position_on_line)
		laterals.append(position_on_line + checkpoint_dash_length)
		position_on_line += checkpoint_dash_length + checkpoint_dash_gap
	var half_depth: float = checkpoint_dash_depth * 0.5
	var back: PackedVector3Array = get_cross_section(offset - half_depth, laterals)
	var front: PackedVector3Array = get_cross_section(offset + half_depth, laterals)
	var lift: Vector3 = Vector3.UP * checkpoint_dash_lift
	var dashes: SurfaceTool = LowPoly.begin()
	for i: int in range(0, laterals.size(), 2):
		LowPoly.add_quad(
			dashes, back[i] + lift, front[i] + lift, front[i + 1] + lift, back[i + 1] + lift,
			checkpoint_marker_color, Vector3.UP
		)
	_add_gate_mesh(gate, dashes.commit(), LowPoly.emissive_material(checkpoint_marker_color, checkpoint_dash_energy))


func _add_gate_mesh(gate: Node3D, mesh: ArrayMesh, material: Material) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	gate.add_child(mesh_instance)


func _build_ground() -> void:
	var body: SurfaceBody = SurfaceBody.new()
	body.name = "Ground"
	body.surface = ground_surface
	add_child(body)

	var height_noise: FastNoiseLite = FastNoiseLite.new()
	height_noise.seed = look_seed + 101
	height_noise.frequency = terrain_height_frequency
	var road_points: PackedVector3Array = PackedVector3Array()
	var pulls: PackedByteArray = PackedByteArray()
	for i: int in _samples.size():
		road_points.append(to_local(_samples[i]))
		pulls.append(0 if _sample_on_bridge[i] == 1 else 1)
	var pull_inner: float = road_width * 0.5 + road_flat_margin
	_terrain = TrackTerrain.new()
	_terrain.build(
		ground_size, terrain_cell_size, _natural_height.bind(height_noise), road_points, pulls,
		pull_inner, pull_inner + road_blend_width, road_sink
	)

	var color_noise: FastNoiseLite = FastNoiseLite.new()
	color_noise.seed = look_seed
	color_noise.frequency = terrain_noise_frequency
	var mesh: ArrayMesh = _terrain.make_mesh(_get_terrain_color.bind(color_noise))
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = LowPoly.vertex_color_material()
	# Hills now throw shadows on the road and on each other.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh_instance)

	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


## Each triangle gets its own shade of the ground colours.
func _get_terrain_color(point: Vector3, noise: FastNoiseLite) -> Color:
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
