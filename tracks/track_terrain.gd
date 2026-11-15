class_name TrackTerrain
extends RefCounted
## Height grid for a track's ground. Heights come from the track's own hills
## and hollows, then are pulled towards the road near it, which shapes the
## embankments and cuttings. Built once by Track; height_at() answers "how
## high is the ground here" for scenery, using the same triangles as the mesh.

var origin: Vector2 = Vector2.ZERO
var cell: Vector2 = Vector2.ONE
var columns: int = 1
var rows: int = 1
var heights: PackedFloat32Array = PackedFloat32Array()


## natural: Callable(x, z) -> float, the height without the road.
## road_points: road centre line samples (local). pulls[i] = 0 for samples
## that do not shape the ground (bridges).
## Within pull_inner of the road the ground sits sink below it; the pull fades
## out by pull_outer.
func build(
	size: Vector2, cell_size: float, natural: Callable, road_points: PackedVector3Array,
	pulls: PackedByteArray, pull_inner: float, pull_outer: float, sink: float
) -> void:
	columns = maxi(1, ceili(size.x / cell_size))
	rows = maxi(1, ceili(size.y / cell_size))
	cell = Vector2(size.x / float(columns), size.y / float(rows))
	origin = -size * 0.5
	var buckets: Dictionary = _make_buckets(road_points, pulls, pull_outer)
	heights.resize((columns + 1) * (rows + 1))
	for row: int in rows + 1:
		for column: int in columns + 1:
			var x: float = origin.x + float(column) * cell.x
			var z: float = origin.y + float(row) * cell.y
			var ground: float = natural.call(x, z)
			var pull: Vector2 = _road_pull(x, z, road_points, buckets, pull_inner, pull_outer)
			heights[row * (columns + 1) + column] = lerpf(ground, pull.y - sink, pull.x)


## Ground height under a local x, z, interpolated on the mesh's own triangles.
func height_at(x: float, z: float) -> float:
	var u: float = clampf((x - origin.x) / cell.x, 0.0, float(columns) - 0.0001)
	var v: float = clampf((z - origin.y) / cell.y, 0.0, float(rows) - 0.0001)
	var column: int = floori(u)
	var row: int = floori(v)
	u -= float(column)
	v -= float(row)
	var a: float = _vertex(column, row)
	var b: float = _vertex(column + 1, row)
	var c: float = _vertex(column + 1, row + 1)
	var d: float = _vertex(column, row + 1)
	if (column + row) % 2 == 0:
		# Diagonal a-c.
		if u >= v:
			return a + u * (b - a) + v * (c - b)
		return a + u * (c - d) + v * (d - a)
	# Diagonal b-d.
	if u + v <= 1.0:
		return a + u * (b - a) + v * (d - a)
	return c + (1.0 - u) * (d - c) + (1.0 - v) * (b - c)


func get_min_height() -> float:
	var lowest: float = INF
	for h: float in heights:
		lowest = minf(lowest, h)
	return lowest


## Flat-shaded triangle patchwork; color_for: Callable(centre: Vector3) -> Color.
func make_mesh(color_for: Callable) -> ArrayMesh:
	var tool: SurfaceTool = LowPoly.begin()
	for column: int in columns:
		for row: int in rows:
			var a: Vector3 = _point(column, row)
			var b: Vector3 = _point(column + 1, row)
			var c: Vector3 = _point(column + 1, row + 1)
			var d: Vector3 = _point(column, row + 1)
			# Alternate the diagonal so the triangles form diamonds instead of stripes.
			var triangles: Array = [[a, b, c], [a, c, d]]
			if (column + row) % 2 == 1:
				triangles = [[a, b, d], [b, c, d]]
			for triangle: Array in triangles:
				var p0: Vector3 = triangle[0]
				var p1: Vector3 = triangle[1]
				var p2: Vector3 = triangle[2]
				LowPoly.add_triangle(tool, p0, p1, p2, color_for.call((p0 + p1 + p2) / 3.0), Vector3.UP)
	return tool.commit()


func _vertex(column: int, row: int) -> float:
	return heights[row * (columns + 1) + column]


func _point(column: int, row: int) -> Vector3:
	return Vector3(origin.x + float(column) * cell.x, _vertex(column, row), origin.y + float(row) * cell.y)


## Road samples sorted into square buckets of size bucket for quick lookups.
func _make_buckets(road_points: PackedVector3Array, pulls: PackedByteArray, bucket: float) -> Dictionary:
	var buckets: Dictionary = {}
	for i: int in road_points.size():
		if pulls[i] == 0:
			continue
		var key: Vector2i = Vector2i(floori(road_points[i].x / bucket), floori(road_points[i].z / bucket))
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		var list: PackedInt32Array = buckets[key]
		list.append(i)
		buckets[key] = list
	buckets["size"] = bucket
	return buckets


## x = pull weight (0..1), y = road height to pull towards. The strongest pull
## wins; on a tie (two roads at once) the lower road, so the ground never
## covers a road underneath another.
func _road_pull(
	x: float, z: float, road_points: PackedVector3Array, buckets: Dictionary, inner: float, outer: float
) -> Vector2:
	var bucket: float = buckets["size"]
	var home: Vector2i = Vector2i(floori(x / bucket), floori(z / bucket))
	var best: Vector2 = Vector2(0.0, 0.0)
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			var key: Vector2i = home + Vector2i(dx, dz)
			if not buckets.has(key):
				continue
			for i: int in buckets[key]:
				var point: Vector3 = road_points[i]
				var distance: float = Vector2(point.x - x, point.z - z).length()
				if distance >= outer:
					continue
				var weight: float = 1.0 if distance <= inner else 1.0 - smoothstep(inner, outer, distance)
				var stronger: bool = weight > best.x + 0.0001
				var lower_tie: bool = absf(weight - best.x) <= 0.0001 and point.y < best.y
				if stronger or lower_tie:
					best = Vector2(weight, point.y)
	return best
