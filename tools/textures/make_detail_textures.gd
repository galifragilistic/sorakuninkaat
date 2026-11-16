extends SceneTree
## Writes the ground and road detail textures (tracks/textures/*.png): small,
## greyscale images that tile without seams. The ground shader lays them over
## the vertex colours.
## Run: godot --headless --path <project> --script tools/textures/make_detail_textures.gd
##
## Every noise here wraps around the image edges by construction (periodic
## lattices and wrapped cell distances), so there is no blending at the seams.

const SIZE: int = 128
const OUT_DIR: String = "res://tracks/textures"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save("grass", _layer(func(u: float, v: float) -> float:
		return _fbm(u, v, [16, 32, 64], [0.5, 0.35, 0.25], 11)))
	_save("sand", _layer(func(u: float, v: float) -> float:
		return _fbm(u, v, [6, 12], [0.7, 0.3], 21) + _fbm(u, v, [64], [0.18], 22)))
	_save("snow", _layer(func(u: float, v: float) -> float:
		return _fbm(u, v, [3, 6, 12], [0.6, 0.3, 0.1], 31)))
	_save("gravel", _layer(func(u: float, v: float) -> float:
		var cell: Vector3 = _worley(u, v, 14, 41)
		# A shade per stone, dark gaps between the stones, and a little grain.
		var gap: float = smoothstep(0.0, 0.025, cell.y - cell.x)
		return (0.35 + 0.65 * cell.z) * (0.45 + 0.55 * gap) + _fbm(u, v, [64], [0.12], 42)))
	_save("asphalt", _layer(func(u: float, v: float) -> float:
		return _fbm(u, v, [64, 128], [0.6, 0.4], 51) + _fbm(u, v, [6], [0.35], 52)))
	_save("concrete", _layer(func(u: float, v: float) -> float:
		return _fbm(u, v, [8, 16, 32], [0.5, 0.3, 0.2], 61)))
	_save("ice", _layer(func(u: float, v: float) -> float:
		var cell: Vector3 = _worley(u, v, 5, 71)
		# Bright ice with thin dark cracks along the cell borders.
		var crack: float = smoothstep(0.0, 0.012, cell.y - cell.x)
		return 0.55 + 0.25 * crack + _fbm(u, v, [4, 8], [0.25, 0.1], 72) - (1.0 - crack) * 0.4))
	_save("rock", _layer(func(u: float, v: float) -> float:
		var cell: Vector3 = _worley(u, v, 6, 81)
		return cell.x * 1.4 + 0.3 * cell.z + _fbm(u, v, [16, 32], [0.3, 0.2], 82)))
	quit()


## Samples value(u, v) over the image (u, v in 0..1) and stretches it to 0..1.
func _layer(value: Callable) -> Image:
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(SIZE * SIZE)
	var low: float = INF
	var high: float = -INF
	for y: int in SIZE:
		for x: int in SIZE:
			var sample: float = value.call(float(x) / float(SIZE), float(y) / float(SIZE))
			values[y * SIZE + x] = sample
			low = minf(low, sample)
			high = maxf(high, sample)
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	for y: int in SIZE:
		for x: int in SIZE:
			var shade: float = (values[y * SIZE + x] - low) / maxf(high - low, 0.0001)
			image.set_pixel(x, y, Color(shade, shade, shade))
	return image


func _save(texture_name: String, image: Image) -> void:
	image.save_png(ProjectSettings.globalize_path("%s/%s_detail.png" % [OUT_DIR, texture_name]))
	print("wrote ", texture_name)


## Value noise on a period x period lattice that wraps at the image edges.
func _value(u: float, v: float, period: int, noise_seed: int) -> float:
	var x: float = u * float(period)
	var y: float = v * float(period)
	var x0: int = floori(x)
	var y0: int = floori(y)
	var fx: float = smoothstep(0.0, 1.0, x - float(x0))
	var fy: float = smoothstep(0.0, 1.0, y - float(y0))
	var a: float = _hash(x0, y0, period, noise_seed)
	var b: float = _hash(x0 + 1, y0, period, noise_seed)
	var c: float = _hash(x0, y0 + 1, period, noise_seed)
	var d: float = _hash(x0 + 1, y0 + 1, period, noise_seed)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func _fbm(u: float, v: float, periods: Array, weights: Array, noise_seed: int) -> float:
	var total: float = 0.0
	for i: int in periods.size():
		total += _value(u, v, periods[i], noise_seed + i) * float(weights[i])
	return total


## Cell noise with one random point per cell of a cells x cells grid, wrapped.
## Returns (distance to nearest point, to second nearest, random value of the
## nearest cell), distances in image widths.
func _worley(u: float, v: float, cells: int, noise_seed: int) -> Vector3:
	var x: float = u * float(cells)
	var y: float = v * float(cells)
	var cx: int = floori(x)
	var cy: int = floori(y)
	var first: float = INF
	var second: float = INF
	var shade: float = 0.0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var gx: int = cx + dx
			var gy: int = cy + dy
			var point: Vector2 = Vector2(
				float(gx) + _hash(gx, gy, cells, noise_seed),
				float(gy) + _hash(gx, gy, cells, noise_seed + 1)
			)
			var distance: float = point.distance_to(Vector2(x, y)) / float(cells)
			if distance < first:
				second = first
				first = distance
				shade = _hash(gx, gy, cells, noise_seed + 2)
			elif distance < second:
				second = distance
	return Vector3(first, second, shade)


## Repeatable 0..1 value for a lattice point, wrapping with the period.
func _hash(x: int, y: int, period: int, noise_seed: int) -> float:
	var wx: int = posmod(x, period)
	var wy: int = posmod(y, period)
	var h: int = (wx * 374761393 + wy * 668265263 + noise_seed * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0
