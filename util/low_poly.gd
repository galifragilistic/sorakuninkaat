class_name LowPoly
extends RefCounted
## Helpers for building flat-shaded, vertex-coloured low-poly meshes in code.
## Every triangle gets its own face normal, so no smoothing is ever applied.


static func begin() -> SurfaceTool:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool


## Adds a triangle whose front face points towards outward_hint (winding is fixed up for you).
static func add_triangle(
	tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, outward_hint: Vector3
) -> void:
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	var second: Vector3 = b
	var third: Vector3 = c
	if normal.dot(outward_hint) < 0.0:
		normal = -normal
		second = c
		third = b
	for vertex: Vector3 in [a, second, third]:
		tool.set_color(color)
		tool.set_normal(normal)
		tool.add_vertex(vertex)


## Corners are given around the perimeter.
static func add_quad(
	tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	color: Color, outward_hint: Vector3
) -> void:
	add_triangle(tool, a, b, c, color, outward_hint)
	add_triangle(tool, a, c, d, color, outward_hint)


static func ring_point(center: Vector3, radius: float, index: int, sides: int, angle_offset: float) -> Vector3:
	var angle: float = angle_offset + TAU * float(index) / float(sides)
	return center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


static func add_cone(
	tool: SurfaceTool, base_center: Vector3, radius: float, height: float,
	sides: int, color: Color, angle_offset: float = 0.0
) -> void:
	var apex: Vector3 = base_center + Vector3.UP * height
	for i: int in sides:
		var a: Vector3 = ring_point(base_center, radius, i, sides, angle_offset)
		var b: Vector3 = ring_point(base_center, radius, i + 1, sides, angle_offset)
		add_triangle(tool, a, b, apex, color, (a + b) * 0.5 - base_center)


static func add_prism(
	tool: SurfaceTool, base_center: Vector3, radius: float, height: float,
	sides: int, color: Color, angle_offset: float = 0.0
) -> void:
	var top_center: Vector3 = base_center + Vector3.UP * height
	for i: int in sides:
		var a: Vector3 = ring_point(base_center, radius, i, sides, angle_offset)
		var b: Vector3 = ring_point(base_center, radius, i + 1, sides, angle_offset)
		var a_top: Vector3 = a + Vector3.UP * height
		var b_top: Vector3 = b + Vector3.UP * height
		add_quad(tool, a, b, b_top, a_top, color, (a + b) * 0.5 - base_center)
		add_triangle(tool, top_center, a_top, b_top, color, Vector3.UP)


static func add_box(tool: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h: Vector3 = size * 0.5
	for axis: int in 3:
		for direction: float in [-1.0, 1.0]:
			var normal: Vector3 = Vector3.ZERO
			normal[axis] = direction
			var u: Vector3 = Vector3.ZERO
			var v: Vector3 = Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var face_center: Vector3 = center + normal * h[axis]
			add_quad(
				tool,
				face_center - u - v, face_center + u - v, face_center + u + v, face_center - u + v,
				color, normal
			)


static func vertex_color_material(roughness: float = 1.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# Colours are authored in sRGB like every other colour in the project.
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	return material


static func emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## Soft round sprite texture (white centre fading to transparent).
static func radial_texture(size: int) -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size
	texture.height = size
	return texture


## Horizontal streak texture (transparent ends, bright middle).
static func streak_texture(width: int, height: int) -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = width
	texture.height = height
	return texture


## Unshaded additive billboard material for light glows and flares.
static func glow_material(texture: Texture2D, color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.albedo_color = color
	return material
