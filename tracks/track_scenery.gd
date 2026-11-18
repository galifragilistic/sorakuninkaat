class_name TrackScenery
extends Node3D
## Low-poly set dressing for a Track: trees, a lake, hay bales and track lights.
## Trees and objects are models made in Blender (PropModels); the rest is
## generated in code. Track calls build() once the road exists.

## Which trees grow by the track.
enum TreeStyle { FOREST, WINTER, DRY }

const TREE_MODELS: Dictionary = {
	TreeStyle.FOREST: [PropModels.SPRUCE, PropModels.PINE, PropModels.BIRCH, PropModels.SPRUCE],
	TreeStyle.WINTER: [PropModels.SPRUCE_SNOWY, PropModels.PINE_SNOWY, PropModels.SPRUCE_SNOWY],
	TreeStyle.DRY: [PropModels.PINE, PropModels.BIRCH, PropModels.PINE],
}
const ROCK_MODELS: Array[PackedScene] = [PropModels.ROCK_BOULDER, PropModels.ROCK_CLUSTER]

@export var scenery_seed: int = 11

@export_group("Trees")
@export var tree_count: int = 120
## Clear distance kept between the road edge and tree trunks (m).
@export var tree_road_margin: float = 3.5
@export var tree_spacing: float = 5.0
@export var tree_border_margin: float = 6.0
@export var tree_scale_range: Vector2 = Vector2(0.8, 1.3)
## Picks the tree models (TREE_MODELS): spruces, pines and birches, snowy ones
## in winter.
@export var tree_style: TreeStyle = TreeStyle.FOREST
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
## Water surface height above the lowest point of the lake's hollow (m). Give
## the lake a hollow with a negative terrain feature so the water has banks.
@export var lake_water_rise: float = 1.2

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
## Collision size of a bale (the model is PropModels.HAY_BALE).
@export var bale_size: Vector3 = Vector3(1.9, 1.1, 1.2)

@export_group("Jumps")
## Lap fractions (0..1) where a ramp starts.
@export var jumps: PackedFloat32Array = PackedFloat32Array()
@export var jump_length: float = 7.0
@export var jump_height: float = 1.0
## How much lighter the ramp is than the road, so it can be seen coming.
@export_range(0.0, 1.0, 0.01) var jump_lighten: float = 0.25
@export var jump_stripe_color: Color = Color(1.0, 0.48, 0.1)

@export_group("Placed objects")
## Objects placed in the track editor: (TrackDesign.Prop, x, z, yaw).
## Sizes come from TrackDesign.PROP_SIZES.
@export var props: PackedVector4Array = PackedVector4Array()
## Containers take these colours in turn.
@export var container_colors: Array[Color] = [
	Color(0.62, 0.62, 0.72), Color(0.78, 0.36, 0.24), Color(0.25, 0.45, 0.62), Color(0.36, 0.55, 0.32),
]
## Random trees keep this far from placed objects.
@export var prop_tree_clearance: float = 2.0

@export_group("Long containers")
## Shipping containers placed by hand in a track scene: x, z, yaw and how
## many are stacked on top of each other. They take container_colors in turn.
@export var long_containers: PackedVector4Array = PackedVector4Array()
## Size of one long container (the model is PropModels.CONTAINER_LONG).
@export var long_container_size: Vector3 = Vector3(12.0, 3.2, 4.2)

@export_group("Exclusion zones")
## No trees this close to the road on bridges and in tunnels (m beyond the road edge).
@export var structure_clearance: float = 13.0
## Extra circles kept free of trees: x, z = centre, y = radius.
@export var tree_exclusions: PackedVector3Array = PackedVector3Array()

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lit_nodes: Array[Node3D] = []
var _lake_shore_radius: float = 0.0


func build(track: Track) -> void:
	_rng.seed = scenery_seed
	if lake_enabled:
		_build_lake(track)
	_build_lamps(track)
	_build_bales(track)
	_build_jumps(track)
	_build_props(track)
	_build_long_containers(track)
	_build_trees(track)


## Switches lamp light sources, glows and flares on or off (env presets).
func set_lights_enabled(enabled: bool) -> void:
	for node: Node3D in _lit_nodes:
		node.visible = enabled


# --- Trees ---------------------------------------------------------------

func _build_trees(track: Track) -> void:
	var half: Vector2 = track.ground_size * 0.5 - Vector2.ONE * tree_border_margin
	var min_road_distance: float = track.road_width * 0.5 + tree_road_margin
	var positions: Array[Vector3] = []
	# Trees placed in the editor stand exactly where they were put.
	for prop: Vector4 in props:
		if roundi(prop.x) == TrackDesign.Prop.TREE:
			var placed: Vector3 = Vector3(prop.y, 0.0, prop.z)
			placed.y = track.get_ground_height(to_global(placed))
			positions.append(placed)
	var target: int = positions.size() + tree_count
	var attempts: int = tree_count * 30
	while positions.size() < target and attempts > 0:
		attempts -= 1
		var point: Vector3 = Vector3(_rng.randf_range(-half.x, half.x), 0.0, _rng.randf_range(-half.y, half.y))
		if track.get_distance_to_centerline(to_global(point)) < min_road_distance:
			continue
		if _is_excluded(point):
			continue
		if track.is_near_structure(to_global(point), structure_clearance):
			continue
		point.y = track.get_ground_height(to_global(point))
		var crowded: bool = false
		for other: Vector3 in positions:
			if other.distance_to(point) < tree_spacing:
				crowded = true
				break
		if not crowded:
			positions.append(point)

	# One MultiMesh per tree model.
	var models: Array = TREE_MODELS[tree_style]
	var model_of: PackedInt32Array = PackedInt32Array()
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(models.size())
	for i: int in positions.size():
		var model: int = _rng.randi_range(0, models.size() - 1)
		model_of.append(model)
		counts[model] += 1
	var multimeshes: Array[MultiMesh] = []
	for model: int in models.size():
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = PropModels.get_mesh(models[model])
		multimesh.instance_count = counts[model]
		multimeshes.append(multimesh)
	var filled: PackedInt32Array = PackedInt32Array()
	filled.resize(models.size())

	var trunk_shape: CylinderShape3D = CylinderShape3D.new()
	trunk_shape.radius = tree_collision_radius
	trunk_shape.height = tree_collision_height
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TreeTrunks"
	add_child(body)

	for i: int in positions.size():
		var tree_scale: float = _rng.randf_range(tree_scale_range.x, tree_scale_range.y)
		var basis: Basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * tree_scale)
		var multimesh: MultiMesh = multimeshes[model_of[i]]
		var slot: int = filled[model_of[i]]
		filled[model_of[i]] += 1
		multimesh.set_instance_transform(slot, Transform3D(basis, positions[i]))
		var tint: float = 1.0 - _rng.randf_range(0.0, tree_tint_variation)
		multimesh.set_instance_color(slot, Color(tint, tint, tint))

		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = trunk_shape
		collision.position = positions[i] + Vector3.UP * tree_collision_height * 0.5
		body.add_child(collision)

	var material: StandardMaterial3D = LowPoly.vertex_color_material()
	for model: int in models.size():
		if counts[model] == 0:
			continue
		var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
		instance.name = "Trees_%d" % model
		instance.multimesh = multimeshes[model]
		instance.material_override = material
		add_child(instance)


func _is_excluded(point: Vector3) -> bool:
	if lake_enabled and _flat_distance(point, lake_center) < _lake_shore_radius + tree_road_margin:
		return true
	for zone: Vector3 in tree_exclusions:
		if _flat_distance(point, Vector3(zone.x, 0.0, zone.z)) < zone.y:
			return true
	for prop: Vector4 in props:
		var size: Vector3 = TrackDesign.PROP_SIZES[roundi(prop.x)]
		var reach: float = Vector2(size.x, size.z).length() * 0.5 + prop_tree_clearance
		if _flat_distance(point, Vector3(prop.y, 0.0, prop.z)) < reach:
			return true
	return false


## True if something placed at global_point would stand on a road (closer to
## any road centre line than half the road width plus clearance).
func _blocks_road(track: Track, global_point: Vector3, clearance: float) -> bool:
	return track.get_distance_to_ground_road(global_point) < track.road_width * 0.5 + clearance * 0.5


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Lake ----------------------------------------------------------------

func _build_lake(track: Track) -> void:
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

	# The water lies flat in the lake's hollow; the beach climbs the banks.
	var water_level: float = track.get_ground_height(to_global(lake_center)) + lake_water_rise
	for i: int in lake_sides:
		var bank: Vector3 = lake_center + beach[i]
		beach[i].y = maxf(track.get_ground_height(to_global(bank)) - water_level, 0.0)
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
	body.position = Vector3(lake_center.x, water_level, lake_center.z)
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
		var lamp_offset: float = lamp.x * track.get_length()
		var lamp_base: Vector3 = track.get_roadside_position(lamp_offset, lamp.y, lamp_margin)
		if not track.is_on_bridge(lamp_offset):
			# On a tight bend or where the track passes close by, the roadside
			# can be on another stretch of road.
			if _blocks_road(track, lamp_base, lamp_margin):
				continue
			lamp_base.y = track.get_ground_height(lamp_base)
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "Lamp_%d" % get_child_count()
		add_child(body)
		body.global_position = lamp_base

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
	var mesh: Mesh = PropModels.get_mesh(PropModels.HAY_BALE)
	var material: StandardMaterial3D = LowPoly.vertex_color_material()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = bale_size

	for row: Vector2 in bale_rows:
		for i: int in bales_per_row:
			var offset: float = row.x * track.get_length() + float(i) * bale_spacing
			var origin: Vector3 = track.get_roadside_position(offset, row.y, bale_margin + bale_size.z * 0.5)
			if _blocks_road(track, origin, bale_margin):
				continue
			var body: StaticBody3D = StaticBody3D.new()
			body.name = "Bale_%d" % get_child_count()
			add_child(body)
			origin.y = track.get_ground_height(origin)
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


# --- Placed objects ------------------------------------------------------

## Builds the hay bales, containers, houses, rocks and tyre stacks placed in
## the track editor. Trees are part of _build_trees().
func _build_props(track: Track) -> void:
	if props.is_empty():
		return
	var material: StandardMaterial3D = LowPoly.vertex_color_material()
	var container_index: int = 0
	var rock_index: int = 0
	for prop: Vector4 in props:
		var kind: int = roundi(prop.x)
		if kind == TrackDesign.Prop.TREE:
			continue
		var size: Vector3 = TrackDesign.PROP_SIZES[kind]
		var model: PackedScene
		var paint_material: Material = null
		match kind:
			TrackDesign.Prop.BALE:
				model = PropModels.HAY_BALE
			TrackDesign.Prop.CONTAINER:
				model = PropModels.CONTAINER
				paint_material = _paint_material(container_index)
				container_index += 1
			TrackDesign.Prop.HOUSE:
				model = PropModels.HOUSE
			TrackDesign.Prop.ROCK:
				model = ROCK_MODELS[rock_index % ROCK_MODELS.size()]
				rock_index += 1
			_:
				model = PropModels.TYRE_STACK

		var body: StaticBody3D = StaticBody3D.new()
		body.name = "Prop_%d" % get_child_count()
		add_child(body)
		var base: Vector3 = Vector3(prop.y, 0.0, prop.z)
		base.y = track.get_ground_height(to_global(base))
		body.position = base
		body.rotation.y = prop.w

		body.add_child(_model_node(model, material, paint_material))
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.position = Vector3.UP * size.y * 0.5
		if kind == TrackDesign.Prop.ROCK or kind == TrackDesign.Prop.TIRES:
			var cylinder: CylinderShape3D = CylinderShape3D.new()
			cylinder.radius = size.x * 0.5
			cylinder.height = size.y
			collision.shape = cylinder
		else:
			var box: BoxShape3D = BoxShape3D.new()
			box.size = size
			collision.shape = box
		body.add_child(collision)


## Hand-placed stacks of long shipping containers, standing on the ground.
func _build_long_containers(track: Track) -> void:
	var material: StandardMaterial3D = LowPoly.vertex_color_material()
	var color_index: int = 0
	for stack: Vector4 in long_containers:
		var levels: int = maxi(1, roundi(stack.w))
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "Container_%d" % get_child_count()
		add_child(body)
		var base: Vector3 = Vector3(stack.x, 0.0, stack.y)
		base.y = track.get_ground_height(to_global(base))
		body.position = base
		body.rotation.y = stack.z
		for level: int in levels:
			var node: MeshInstance3D = _model_node(PropModels.CONTAINER_LONG, material, _paint_material(color_index))
			color_index += 1
			node.position = Vector3.UP * long_container_size.y * float(level)
			body.add_child(node)
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(long_container_size.x, long_container_size.y * float(levels), long_container_size.z)
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = box
		collision.position = Vector3.UP * box.size.y * 0.5
		body.add_child(collision)


func _model_node(model: PackedScene, material: Material, paint_material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = PropModels.get_mesh(model)
	PropModels.apply_materials(node, material, paint_material)
	return node


## Containers take container_colors in turn.
func _paint_material(index: int) -> StandardMaterial3D:
	var paint: StandardMaterial3D = LowPoly.vertex_color_material()
	paint.albedo_color = container_colors[index % container_colors.size()]
	return paint
