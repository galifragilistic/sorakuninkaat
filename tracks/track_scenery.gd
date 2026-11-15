class_name TrackScenery
extends Node3D
## Low-poly set dressing for a Track: trees, a lake, hay bales and track lights.
## Everything is generated in code; Track calls build() once the road exists.

@export var scenery_seed: int = 11

@export_group("Trees")
@export var tree_count: int = 120
## Clear distance kept between the road edge and tree trunks (m).
@export var tree_road_margin: float = 3.5
@export var tree_spacing: float = 5.0
@export var tree_border_margin: float = 6.0
@export var tree_scale_range: Vector2 = Vector2(0.85, 1.5)
@export var tree_sides: int = 6
@export var tree_trunk_radius: float = 0.24
@export var tree_trunk_height: float = 1.0
## Per tier: x = base height, y = radius, z = cone height.
@export var tree_tiers: PackedVector3Array = PackedVector3Array([
	Vector3(0.7, 1.5, 2.6), Vector3(2.0, 1.1, 2.7),
])
@export var tree_color: Color = Color(0.3, 0.52, 0.22)
@export var tree_top_color: Color = Color(0.4, 0.62, 0.26)
@export var tree_trunk_color: Color = Color(0.42, 0.27, 0.17)
## Random darkening per tree (0..1).
@export_range(0.0, 0.5, 0.01) var tree_tint_variation: float = 0.18
@export var tree_collision_radius: float = 0.4
@export var tree_collision_height: float = 3.0

@export_group("Lake")
@export var lake_enabled: bool = true
@export var lake_center: Vector3 = Vector3.ZERO
@export var lake_radius: float = 13.0
@export var lake_sides: int = 7
## Radius variation of the shoreline corners (0..1).
@export_range(0.0, 0.5, 0.01) var lake_irregularity: float = 0.2
@export var lake_shore_width: float = 2.4
@export var lake_surface: SurfaceData
@export var lake_highlight_color: Color = Color(0.72, 0.87, 0.9)
@export var lake_layer_lift: float = 0.02

@export_group("Track lights")
## x = lap fraction (0..1), y = side (-1 left, 1 right).
@export var lamps: PackedVector2Array = PackedVector2Array()
@export var lamp_margin: float = 2.5
@export var lamp_height: float = 7.0
@export var lamp_pole_width: float = 0.2
@export var lamp_pole_color: Color = Color(0.11, 0.12, 0.19)
@export var lamp_color: Color = Color(1.0, 0.86, 0.6)
@export var lamp_energy: float = 9.0
@export var lamp_range: float = 16.0
@export var lamp_head_size: Vector3 = Vector3(0.6, 0.3, 0.6)
@export var lamp_emission_energy: float = 6.0
@export var lamp_flare_size: Vector2 = Vector2(9.0, 0.16)
@export var lamp_halo_size: float = 2.6
@export_range(0.0, 1.0, 0.01) var lamp_flare_alpha: float = 0.55

@export_group("Hay bales")
## Start of each bale row: x = lap fraction (0..1), y = side (-1 left, 1 right).
@export var bale_rows: PackedVector2Array = PackedVector2Array()
@export var bales_per_row: int = 4
@export var bale_spacing: float = 4.5
@export var bale_margin: float = 1.2
@export var bale_size: Vector3 = Vector3(1.9, 1.1, 1.2)
@export var bale_color: Color = Color(0.86, 0.66, 0.27)

@export_group("Jumps")
## Lap fractions (0..1) where a ramp starts.
@export var jumps: PackedFloat32Array = PackedFloat32Array()
@export var jump_length: float = 7.0
@export var jump_height: float = 1.0
## How much lighter the ramp is than the road, so it can be seen coming.
@export_range(0.0, 1.0, 0.01) var jump_lighten: float = 0.25
@export var jump_stripe_color: Color = Color(1.0, 0.48, 0.1)

@export_group("Exclusion zones")
## Extra circles kept free of trees: x, z = centre, y = radius.
@export var tree_exclusions: PackedVector3Array = PackedVector3Array()

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lit_nodes: Array[Node3D] = []
var _lake_shore_radius: float = 0.0


func build(track: Track) -> void:
	_rng.seed = scenery_seed
	if lake_enabled:
		_build_lake()
	_build_lamps(track)
	_build_bales(track)
	_build_jumps(track)
	_build_trees(track)


## Switches lamp light sources, glows and flares on or off (env presets).
func set_lights_enabled(enabled: bool) -> void:
	for node: Node3D in _lit_nodes:
		node.visible = enabled


# --- Trees ---------------------------------------------------------------

func _build_tree_mesh() -> ArrayMesh:
	var tool: SurfaceTool = LowPoly.begin()
	LowPoly.add_prism(tool, Vector3.ZERO, tree_trunk_radius, tree_trunk_height, tree_sides, tree_trunk_color)
	var tier_count: int = tree_tiers.size()
	for i: int in tier_count:
		var tier: Vector3 = tree_tiers[i]
		var blend: float = float(i) / float(maxi(1, tier_count - 1))
		var color: Color = tree_color.lerp(tree_top_color, blend)
		# Twist each tier so the facets do not line up.
		var twist: float = PI / float(tree_sides) * float(i)
		LowPoly.add_cone(tool, Vector3.UP * tier.x, tier.y, tier.z, tree_sides, color, twist)
	return tool.commit()


func _build_trees(track: Track) -> void:
	var half: Vector2 = track.ground_size * 0.5 - Vector2.ONE * tree_border_margin
	var min_road_distance: float = track.road_width * 0.5 + tree_road_margin
	var positions: Array[Vector3] = []
	var attempts: int = tree_count * 30
	while positions.size() < tree_count and attempts > 0:
		attempts -= 1
		var point: Vector3 = Vector3(_rng.randf_range(-half.x, half.x), 0.0, _rng.randf_range(-half.y, half.y))
		if track.get_distance_to_centerline(to_global(point)) < min_road_distance:
			continue
		if _is_excluded(point):
			continue
		var crowded: bool = false
		for other: Vector3 in positions:
			if other.distance_to(point) < tree_spacing:
				crowded = true
				break
		if not crowded:
			positions.append(point)

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _build_tree_mesh()
	multimesh.instance_count = positions.size()

	var trunk_shape: CylinderShape3D = CylinderShape3D.new()
	trunk_shape.radius = tree_collision_radius
	trunk_shape.height = tree_collision_height
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TreeTrunks"
	add_child(body)

	for i: int in positions.size():
		var tree_scale: float = _rng.randf_range(tree_scale_range.x, tree_scale_range.y)
		var basis: Basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * tree_scale)
		multimesh.set_instance_transform(i, Transform3D(basis, positions[i]))
		var tint: float = 1.0 - _rng.randf_range(0.0, tree_tint_variation)
		multimesh.set_instance_color(i, Color(tint, tint, tint))

		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = trunk_shape
		collision.position = positions[i] + Vector3.UP * tree_collision_height * 0.5
		body.add_child(collision)

	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = "Trees"
	instance.multimesh = multimesh
	instance.material_override = LowPoly.vertex_color_material()
	add_child(instance)


func _is_excluded(point: Vector3) -> bool:
	if lake_enabled and _flat_distance(point, lake_center) < _lake_shore_radius + tree_road_margin:
		return true
	for zone: Vector3 in tree_exclusions:
		if _flat_distance(point, Vector3(zone.x, 0.0, zone.z)) < zone.y:
			return true
	return false


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Lake ----------------------------------------------------------------

func _build_lake() -> void:
	var shore: PackedVector3Array = PackedVector3Array()
	var beach: PackedVector3Array = PackedVector3Array()
	var inner: PackedVector3Array = PackedVector3Array()
	var max_radius: float = 0.0
	for i: int in lake_sides:
		var radius: float = lake_radius * (1.0 + _rng.randf_range(-lake_irregularity, lake_irregularity))
		max_radius = maxf(max_radius, radius)
		shore.append(LowPoly.ring_point(Vector3.ZERO, radius, i, lake_sides, 0.0))
		beach.append(LowPoly.ring_point(Vector3.ZERO, radius + lake_shore_width, i, lake_sides, 0.0))
		inner.append(LowPoly.ring_point(Vector3.ZERO, radius * 0.55, i, lake_sides, 0.3))
	_lake_shore_radius = max_radius + lake_shore_width

	var beach_y: Vector3 = Vector3.UP * lake_layer_lift
	var water_y: Vector3 = Vector3.UP * lake_layer_lift * 2.0
	var inner_y: Vector3 = Vector3.UP * lake_layer_lift * 3.0
	var highlight_y: Vector3 = Vector3.UP * lake_layer_lift * 4.0
	var inner_shift: Vector3 = Vector3(lake_radius * 0.12, 0.0, -lake_radius * 0.08)

	var tool: SurfaceTool = LowPoly.begin()
	for i: int in lake_sides:
		var next: int = (i + 1) % lake_sides
		LowPoly.add_quad(
			tool, beach[i] + beach_y, beach[next] + beach_y, shore[next] + beach_y, shore[i] + beach_y,
			lake_surface.edge_color, Vector3.UP
		)
		var deep: Color = lake_surface.color_a.darkened(_rng.randf_range(0.0, 0.12))
		LowPoly.add_triangle(tool, water_y, shore[i] + water_y, shore[next] + water_y, deep, Vector3.UP)
		var shallow: Color = lake_surface.color_b.darkened(_rng.randf_range(0.0, 0.1))
		LowPoly.add_triangle(
			tool, inner_shift + inner_y, inner[i] + inner_shift + inner_y,
			inner[next] + inner_shift + inner_y, shallow, Vector3.UP
		)
	# A single bright facet reads as a reflection of the sky.
	var glint: float = lake_radius * 0.16
	var glint_center: Vector3 = inner_shift + highlight_y + Vector3(glint * 0.6, 0.0, -glint * 0.4)
	LowPoly.add_quad(
		tool,
		glint_center + Vector3(-glint, 0.0, -glint * 0.3), glint_center + Vector3(glint * 0.5, 0.0, -glint * 0.5),
		glint_center + Vector3(glint, 0.0, glint * 0.4), glint_center + Vector3(-glint * 0.3, 0.0, glint * 0.3),
		lake_highlight_color, Vector3.UP
	)

	var body: SurfaceBody = SurfaceBody.new()
	body.name = "Lake"
	body.surface = lake_surface
	body.position = lake_center
	add_child(body)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = tool.commit()
	mesh_instance.material_override = LowPoly.vertex_color_material(0.35)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh_instance)

	# Thin disc so wheel rays report water instead of the ground below.
	var disc: CylinderShape3D = CylinderShape3D.new()
	disc.radius = lake_radius * (1.0 - lake_irregularity)
	disc.height = lake_layer_lift * 2.0
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = disc
	body.add_child(collision)


# --- Track lights --------------------------------------------------------

func _build_lamps(track: Track) -> void:
	if lamps.is_empty():
		return
	var pole_tool: SurfaceTool = LowPoly.begin()
	LowPoly.add_box(
		pole_tool, Vector3.UP * lamp_height * 0.5,
		Vector3(lamp_pole_width, lamp_height, lamp_pole_width), lamp_pole_color
	)
	var pole_mesh: ArrayMesh = pole_tool.commit()
	var pole_material: StandardMaterial3D = LowPoly.vertex_color_material()

	var head_mesh: BoxMesh = BoxMesh.new()
	head_mesh.size = lamp_head_size
	var head_material: StandardMaterial3D = LowPoly.emissive_material(lamp_color, lamp_emission_energy)
	var off_material: StandardMaterial3D = StandardMaterial3D.new()
	off_material.albedo_color = lamp_pole_color

	var flare_color: Color = Color(lamp_color, lamp_flare_alpha)
	var flare_mesh: QuadMesh = QuadMesh.new()
	flare_mesh.size = lamp_flare_size
	var flare_material: StandardMaterial3D = LowPoly.glow_material(LowPoly.streak_texture(64, 4), flare_color)
	var halo_mesh: QuadMesh = QuadMesh.new()
	halo_mesh.size = Vector2.ONE * lamp_halo_size
	var halo_material: StandardMaterial3D = LowPoly.glow_material(LowPoly.radial_texture(64), flare_color)

	var pole_shape: BoxShape3D = BoxShape3D.new()
	pole_shape.size = Vector3(lamp_pole_width * 2.0, lamp_height, lamp_pole_width * 2.0)

	for lamp: Vector2 in lamps:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "Lamp_%d" % get_child_count()
		add_child(body)
		body.global_position = track.get_roadside_position(lamp.x * track.get_length(), lamp.y, lamp_margin)

		var pole: MeshInstance3D = MeshInstance3D.new()
		pole.mesh = pole_mesh
		pole.material_override = pole_material
		# A thin pole only produces a flickering sliver of shadow.
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(pole)

		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = pole_shape
		collision.position = Vector3.UP * lamp_height * 0.5
		body.add_child(collision)

		var head_position: Vector3 = Vector3.UP * lamp_height
		var dark_head: MeshInstance3D = MeshInstance3D.new()
		dark_head.mesh = head_mesh
		dark_head.material_override = off_material
		dark_head.position = head_position
		dark_head.scale = Vector3.ONE * 0.98
		body.add_child(dark_head)

		# Everything that only exists while the lamp is on.
		var lit: Node3D = Node3D.new()
		lit.name = "Lit"
		lit.position = head_position
		body.add_child(lit)
		_lit_nodes.append(lit)

		var head: MeshInstance3D = MeshInstance3D.new()
		head.mesh = head_mesh
		head.material_override = head_material
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lit.add_child(head)

		var light: OmniLight3D = OmniLight3D.new()
		light.light_color = lamp_color
		light.light_energy = lamp_energy
		light.omni_range = lamp_range
		light.position = Vector3.DOWN * lamp_head_size.y
		lit.add_child(light)

		for glow: Array in [[flare_mesh, flare_material], [halo_mesh, halo_material]]:
			var sprite: MeshInstance3D = MeshInstance3D.new()
			sprite.mesh = glow[0]
			sprite.material_override = glow[1]
			sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lit.add_child(sprite)


# --- Jumps ---------------------------------------------------------------

## A wedge across the whole road: a slope up in the driving direction and a drop at the end.
func _build_jumps(track: Track) -> void:
	var half_width: float = track.road_width * 0.5
	for fraction: float in jumps:
		var surface: SurfaceData = track.get_road_surface_at(fraction)
		var start: float = fraction * track.get_length()
		var end: float = start + jump_length
		var lift: Vector3 = Vector3.UP * track.road_lift
		var start_center: Vector3 = to_local(track.get_position_at(start)) + lift
		var end_center: Vector3 = to_local(track.get_position_at(end)) + lift
		var start_right: Vector3 = global_basis.inverse() * track.get_right_at(start) * half_width
		var end_right: Vector3 = global_basis.inverse() * track.get_right_at(end) * half_width
		var forward: Vector3 = global_basis.inverse() * track.get_direction_at(end)
		var top: Vector3 = Vector3.UP * jump_height

		var a_left: Vector3 = start_center - start_right
		var a_right: Vector3 = start_center + start_right
		var b_left: Vector3 = end_center - end_right
		var b_right: Vector3 = end_center + end_right
		var slope_color: Color = surface.color_a.lightened(jump_lighten)

		var tool: SurfaceTool = LowPoly.begin()
		LowPoly.add_quad(tool, a_left, a_right, b_right + top, b_left + top, slope_color, Vector3.UP)
		LowPoly.add_quad(tool, b_left + top, b_right + top, b_right, b_left, jump_stripe_color, forward)
		LowPoly.add_triangle(tool, a_left, b_left + top, b_left, surface.edge_color, -start_right)
		LowPoly.add_triangle(tool, a_right, b_right + top, b_right, surface.edge_color, start_right)
		var mesh: ArrayMesh = tool.commit()

		var body: SurfaceBody = SurfaceBody.new()
		body.name = "Jump_%d" % get_child_count()
		body.surface = surface
		add_child(body)
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.material_override = LowPoly.vertex_color_material()
		body.add_child(mesh_instance)
		var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
		shape.backface_collision = true
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)


# --- Hay bales -----------------------------------------------------------

func _build_bales(track: Track) -> void:
	if bale_rows.is_empty():
		return
	var tool: SurfaceTool = LowPoly.begin()
	LowPoly.add_box(tool, Vector3.UP * bale_size.y * 0.5, bale_size, bale_color)
	var mesh: ArrayMesh = tool.commit()
	var material: StandardMaterial3D = LowPoly.vertex_color_material()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = bale_size

	for row: Vector2 in bale_rows:
		for i: int in bales_per_row:
			var offset: float = row.x * track.get_length() + float(i) * bale_spacing
			var body: StaticBody3D = StaticBody3D.new()
			body.name = "Bale_%d" % get_child_count()
			add_child(body)
			var origin: Vector3 = track.get_roadside_position(offset, row.y, bale_margin + bale_size.z * 0.5)
			# Long side along the road.
			var facing: Basis = Basis.looking_at(track.get_right_at(offset), Vector3.UP)
			body.global_transform = Transform3D(facing, origin)

			var mesh_instance: MeshInstance3D = MeshInstance3D.new()
			mesh_instance.mesh = mesh
			mesh_instance.material_override = material
			body.add_child(mesh_instance)

			var collision: CollisionShape3D = CollisionShape3D.new()
			collision.shape = shape
			collision.position = Vector3.UP * bale_size.y * 0.5
			body.add_child(collision)
