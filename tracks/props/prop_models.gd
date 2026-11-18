class_name PropModels
extends RefCounted
## The low-poly track props made in Blender (tools/blender/build_props.py,
## exported to this folder). Each model is one vertex-coloured mesh standing
## on the ground at its origin.

const SPRUCE: PackedScene = preload("res://tracks/props/spruce.glb")
const PINE: PackedScene = preload("res://tracks/props/pine.glb")
const BIRCH: PackedScene = preload("res://tracks/props/birch.glb")
const SPRUCE_SNOWY: PackedScene = preload("res://tracks/props/spruce_snowy.glb")
const PINE_SNOWY: PackedScene = preload("res://tracks/props/pine_snowy.glb")
const HAY_BALE: PackedScene = preload("res://tracks/props/hay_bale.glb")
const CONTAINER: PackedScene = preload("res://tracks/props/container.glb")
const CONTAINER_LONG: PackedScene = preload("res://tracks/props/container_long.glb")
const HOUSE: PackedScene = preload("res://tracks/props/house.glb")
const ROCK_BOULDER: PackedScene = preload("res://tracks/props/rock_boulder.glb")
const ROCK_CLUSTER: PackedScene = preload("res://tracks/props/rock_cluster.glb")
const TYRE_STACK: PackedScene = preload("res://tracks/props/tyre_stack.glb")

## Material name of the container surface the game paints.
const PAINT_SURFACE: String = "Paint"

static var _meshes: Dictionary = {}


## The mesh of a model scene (loaded once, then shared).
static func get_mesh(scene: PackedScene) -> Mesh:
	if not _meshes.has(scene):
		var root: Node = scene.instantiate()
		var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
		var mesh: Mesh = null
		if root is MeshInstance3D:
			mesh = (root as MeshInstance3D).mesh
		elif not found.is_empty():
			mesh = (found[0] as MeshInstance3D).mesh
		root.free()
		_meshes[scene] = mesh
	return _meshes[scene]


## Gives mesh_node the shared vertex colour material, with surfaces named
## "Paint" tinted by paint.
static func apply_materials(mesh_node: MeshInstance3D, base: Material, paint_material: Material = null) -> void:
	var mesh: Mesh = mesh_node.mesh
	if paint_material == null:
		mesh_node.material_override = base
		return
	for i: int in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(i)
		var is_paint: bool = material != null and material.resource_name == PAINT_SURFACE
		mesh_node.set_surface_override_material(i, paint_material if is_paint else base)
