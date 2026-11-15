class_name TrackBridge
extends Node3D
## A stretch of road carried on a bridge: deck, railings, pillars down to the
## ground and supports at both ends. Track builds one per bridge range; the
## road surface itself is still Track's ribbon on top of the deck.

## Deck width past each road edge (m).
@export var deck_overhang: float = 1.0
@export var deck_thickness: float = 0.9
@export var railing_height: float = 1.0
@export var railing_width: float = 0.3
@export var pillar_spacing: float = 12.0
@export var pillar_size: float = 1.4
## Pillars are left out where they would stand this close to a road below (m).
@export var pillar_road_clearance: float = 1.5
## Pillars and end supports go this far into the ground.
@export var footing_depth: float = 0.6
@export var end_support_depth: float = 2.0
@export var deck_color: Color = Color(0.62, 0.6, 0.57)
@export var deck_dark_color: Color = Color(0.45, 0.44, 0.42)
@export var railing_color: Color = Color(0.86, 0.87, 0.9)
@export var railing_stripe_color: Color = Color("#ff7a1a")
@export var pillar_color: Color = Color(0.52, 0.5, 0.48)


func build(track: Track, start_offset: float, end_offset: float) -> void:
	var half: float = track.road_width * 0.5
	var deck_half: float = half + deck_overhang
	var steps: int = maxi(1, ceili((end_offset - start_offset) / track.sample_spacing))
	var laterals: PackedFloat32Array = PackedFloat32Array([
		-deck_half, -deck_half + railing_width, -half, half, deck_half - railing_width, deck_half,
	])
	var up: Vector3 = Vector3.UP
	var visual: SurfaceTool = LowPoly.begin()
	var solid: SurfaceTool = LowPoly.begin()

	var previous: PackedVector3Array = track.get_cross_section(start_offset, laterals)
	var previous_right: Vector3 = track.get_right_at(start_offset)
	for i: int in steps:
		var offset: float = lerpf(start_offset, end_offset, float(i + 1) / float(steps))
		var current: PackedVector3Array = track.get_cross_section(offset, laterals)
		var right: Vector3 = track.get_right_at(offset)
		var side_hint: Vector3 = (right + previous_right).normalized()
		var rail: Vector3 = up * railing_height
		var depth: Vector3 = up * -deck_thickness
		for side: int in [0, 1]:
			# 0 = left edge (points 0..2), 1 = right edge (points 5..3).
			var outer: int = 0 if side == 0 else 5
			var rail_inner: int = 1 if side == 0 else 4
			var road_edge: int = 2 if side == 0 else 3
			var outward: Vector3 = -side_hint if side == 0 else side_hint
			# Deck beside the road, under the railing.
			_quad(visual, solid, previous[rail_inner], current[rail_inner], current[road_edge], previous[road_edge], deck_color, up)
			# Railing: inner face, top, outer face down to the deck bottom.
			_quad(visual, solid, previous[rail_inner], current[rail_inner], current[rail_inner] + rail, previous[rail_inner] + rail, railing_color, -outward)
			_quad(visual, solid, previous[rail_inner] + rail, current[rail_inner] + rail, current[outer] + rail, previous[outer] + rail, railing_stripe_color, up)
			_quad(visual, solid, previous[outer] + rail, current[outer] + rail, current[outer] + depth, previous[outer] + depth, deck_color, outward)
		# Underside.
		LowPoly.add_quad(visual, previous[0] + depth, current[0] + depth, current[5] + depth, previous[5] + depth, deck_dark_color, -up)
		previous = current
		previous_right = right

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Deck"
	mesh_instance.mesh = visual.commit()
	mesh_instance.material_override = LowPoly.vertex_color_material()
	add_child(mesh_instance)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Railings"
	add_child(body)
	var shape: ConcavePolygonShape3D = solid.commit().create_trimesh_shape()
	shape.backface_collision = true
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	_build_pillars(track, start_offset, end_offset, half)
	_build_end_support(track, start_offset, deck_half)
	_build_end_support(track, end_offset, deck_half)


## Adds the same quad to the visible mesh and to the collision mesh.
func _quad(
	visual: SurfaceTool, solid: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	color: Color, outward: Vector3
) -> void:
	LowPoly.add_quad(visual, a, b, c, d, color, outward)
	LowPoly.add_quad(solid, a, b, c, d, color, outward)


func _build_pillars(track: Track, start_offset: float, end_offset: float, road_half: float) -> void:
	var length: float = end_offset - start_offset
	var count: int = floori(length / pillar_spacing)
	for i: int in count:
		var offset: float = start_offset + (float(i) + 0.5) * length / float(count)
		var top: Vector3 = to_local(track.get_position_at(offset)) + Vector3.UP * -deck_thickness
		var ground: float = track.get_ground_height(to_global(top)) - footing_depth
		if top.y - ground < 0.5:
			continue
		var clear_of_roads: float = track.get_distance_to_road_below(to_global(top))
		if clear_of_roads < road_half + pillar_size * 0.5 + pillar_road_clearance:
			continue
		_add_block(
			"Pillar_%d" % i, Vector3(top.x, (top.y + ground) * 0.5, top.z),
			Vector3(pillar_size, top.y - ground, pillar_size), track.get_direction_at(offset), pillar_color
		)


## A solid block under the deck end, down into the ground.
func _build_end_support(track: Track, offset: float, deck_half: float) -> void:
	var top: Vector3 = to_local(track.get_position_at(offset)) + Vector3.UP * -deck_thickness * 0.5
	var ground: float = track.get_ground_height(to_global(top)) - footing_depth
	if top.y - ground < 0.3:
		return
	_add_block(
		"EndSupport", Vector3(top.x, (top.y + ground) * 0.5, top.z),
		Vector3(deck_half * 2.0, top.y - ground, end_support_depth), track.get_direction_at(offset), deck_dark_color
	)


func _add_block(block_name: String, center: Vector3, size: Vector3, forward: Vector3, color: Color) -> void:
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
	var body: StaticBody3D = StaticBody3D.new()
	body.name = block_name
	add_child(body)
	body.transform = Transform3D(Basis.looking_at(flat, Vector3.UP), center)
	var tool: SurfaceTool = LowPoly.begin()
	LowPoly.add_box(tool, Vector3.ZERO, size, color)
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = tool.commit()
	mesh_instance.material_override = LowPoly.vertex_color_material()
	body.add_child(mesh_instance)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
