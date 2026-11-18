"""Builds the low-poly track props (trees, bales, containers, a house, rocks,
tyre stacks) in Blender and exports them as .glb files to tracks/props/.

Run (Blender 4.2 or newer):
    blender --background --factory-startup --python tools/blender/build_props.py -- <project dir> [preview.png]

Every model is made from the numbers below, so it can be changed and rebuilt
at any time. Blender axes: X right, Y back (the glTF exporter turns -Y into
Godot's +Z, the front), Z up. Models stand on the ground at the origin;
buildings and rocks reach FOUNDATION below it so slopes show no gap.

Colours are per-face vertex colours (a flat, N64-style look) in a float
colour attribute holding sRGB values, which the game reads with
vertex_color_is_srgb. Each mesh has one material, "Prop", except the
containers: their "Paint" surface holds light grey shading that the game
multiplies with the container colour, and "Trim" keeps its own colours.

Sizes follow TrackDesign.PROP_SIZES (tracks/track_design.gd), width x height x depth:
    tree 3 x 6 x 3, bale 1.9 x 1.1 x 1.2, container 6.1 x 2.6 x 2.4,
    house 8 x 5 x 6, rock 3.2 x 1.8 x 3.2, tyres 1.0 x 1.05 x 1.0.
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

FOUNDATION = 0.8
# Random brightness change per face, so flat faces read as facets.
FACE_JITTER = 0.05

# --- Colours (sRGB) ------------------------------------------------------------------

SPRUCE_DARK = (0.18, 0.36, 0.2)
SPRUCE_LIGHT = (0.27, 0.48, 0.25)
SPRUCE_UNDER = (0.12, 0.25, 0.15)
PINE_GREEN = (0.24, 0.42, 0.2)
PINE_TOP = (0.36, 0.55, 0.26)
LEAF_GREEN = (0.36, 0.58, 0.22)
LEAF_TOP = (0.5, 0.7, 0.28)
SNOW = (0.9, 0.94, 0.98)
SNOW_SHADE = (0.76, 0.82, 0.9)
BARK = (0.38, 0.27, 0.19)
PINE_BARK = (0.62, 0.36, 0.2)
BIRCH_BARK = (0.9, 0.89, 0.84)
BIRCH_MARK = (0.12, 0.12, 0.12)

STRAW = (0.86, 0.66, 0.27)
STRAW_END = (0.78, 0.58, 0.22)
TWINE = (0.75, 0.3, 0.16)

PAINT_LIGHT = (1.0, 1.0, 1.0)
PAINT_GROOVE = (0.8, 0.8, 0.8)
PAINT_POST = (0.68, 0.68, 0.68)
TRIM_DARK = (0.16, 0.17, 0.2)
TRIM_STEEL = (0.55, 0.56, 0.6)

WALL_RED = (0.6, 0.17, 0.13)
TRIM_WHITE = (0.93, 0.92, 0.88)
GLASS = (0.2, 0.27, 0.4)
DOOR = (0.32, 0.22, 0.15)
PLINTH = (0.46, 0.46, 0.47)
ROOF = (0.24, 0.25, 0.29)
CHIMNEY = (0.5, 0.25, 0.2)

ROCK_GREY = (0.5, 0.5, 0.52)
ROCK_TOP = (0.62, 0.62, 0.63)
ROCK_DARK = (0.4, 0.4, 0.43)

RUBBER = (0.09, 0.09, 0.1)
RUBBER_PAINT = (0.92, 0.92, 0.9)
HOLE = (0.03, 0.03, 0.035)


# --- Mesh building ----------------------------------------------------------------------

class Builder:
    """A bmesh with per-face colours and material slots."""

    def __init__(self, seed, materials=("Prop",)):
        self.bm = bmesh.new()
        self.colour_layer = self.bm.loops.layers.float_color.new("Col")
        self.materials = list(materials)
        self.rng = random.Random(seed)

    def paint(self, faces, colour, material=0, jitter=FACE_JITTER):
        for face in faces:
            shade = 1.0 + self.rng.uniform(-jitter, jitter)
            rgba = (*(min(1.0, c * shade) for c in colour), 1.0)
            face.material_index = material
            face.smooth = False
            for loop in face.loops:
                loop[self.colour_layer] = rgba

    def face(self, points, colour, material=0, jitter=FACE_JITTER):
        verts = [self.bm.verts.new(p) for p in points]
        face = self.bm.faces.new(verts)
        self.paint([face], colour, material, jitter)
        return face

    def box(self, centre, size, colour, material=0, skip=(), rotation=None):
        """skip: sides to leave out, any of "top", "bottom", "+x", "-x", "+y", "-y"."""
        matrix = Matrix.Translation(Vector(centre))
        if rotation is not None:
            matrix = matrix @ rotation.to_4x4()
        matrix = matrix @ Matrix.Diagonal((*size, 1.0))
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=matrix)["verts"]
        faces = list({f for v in verts for f in v.link_faces})
        normal_matrix = rotation if rotation is not None else Matrix.Identity(3)
        names = {"top": (0, 0, 1), "bottom": (0, 0, -1), "+x": (1, 0, 0), "-x": (-1, 0, 0),
                 "+y": (0, 1, 0), "-y": (0, -1, 0)}
        drop = []
        for face in faces:
            normal = face.normal_update() or face.normal
            for name in skip:
                if (normal - normal_matrix @ Vector(names[name])).length < 0.01:
                    drop.append(face)
        if drop:
            bmesh.ops.delete(self.bm, geom=drop, context="FACES_ONLY")
            faces = [f for f in faces if f not in drop]
        self.paint(faces, colour, material)
        return faces

    def ring(self, centre, radius, sides, twist=0.0, jitter=0.0, squash=(1.0, 1.0)):
        cx, cy, cz = centre
        points = []
        for i in range(sides):
            angle = twist + math.tau * i / sides
            r = radius * (1.0 + self.rng.uniform(-jitter, jitter))
            points.append(self.bm.verts.new((cx + math.cos(angle) * r * squash[0],
                                             cy + math.sin(angle) * r * squash[1], cz)))
        return points

    def bridge(self, lower, upper, colours, material=0):
        """Quads between two rings of equal size; colours: one or one per side."""
        faces = []
        sides = len(lower)
        for i in range(sides):
            j = (i + 1) % sides
            face = self.bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
            colour = colours[i % len(colours)] if isinstance(colours[0], tuple) else colours
            self.paint([face], colour, material)
            faces.append(face)
        return faces

    def fan(self, ring, apex, colour, material=0):
        tip = self.bm.verts.new(apex)
        faces = []
        for i in range(len(ring)):
            face = self.bm.faces.new((ring[i], ring[(i + 1) % len(ring)], tip))
            faces.append(face)
        self.paint(faces, colour, material)
        return faces

    def cap(self, ring, colour, material=0, downward=False):
        face = self.bm.faces.new(list(reversed(ring)) if downward else ring)
        self.paint([face], colour, material)
        return face

    def blob(self, centre, size, colour_for, subdivisions=1, jitter=0.12):
        """A lumpy ball: icosphere with moved vertices. colour_for(normal) -> colour."""
        matrix = Matrix.Translation(Vector(centre)) @ Matrix.Diagonal((*size, 1.0))
        verts = bmesh.ops.create_icosphere(self.bm, subdivisions=subdivisions, radius=0.5,
                                           matrix=Matrix.Identity(4))["verts"]
        for vert in verts:
            vert.co *= 1.0 + self.rng.uniform(-jitter, jitter)
            vert.co = matrix @ vert.co
        faces = list({f for v in verts for f in v.link_faces})
        for face in faces:
            face.normal_update()
            self.paint([face], colour_for(face.normal))
        return faces

    def finish(self, name, collection, materials):
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for material_name in self.materials:
            mesh.materials.append(materials[material_name])
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        mesh.color_attributes.render_color_index = 0
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        return obj


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def snow_or(colour, normal, threshold=0.45):
    return SNOW if normal.z > threshold else colour


# --- Trees --------------------------------------------------------------------------------

# Spruce tiers: base height, radius, cone height. The cone's lower band and tip
# get their own colours (snow on the tips in winter).
SPRUCE_TIERS = [(0.8, 1.6, 2.4), (2.0, 1.25, 2.3), (3.2, 0.85, 2.3)]
SPRUCE_SIDES = 7
SPRUCE_BAND = 0.45


def build_spruce(b, snowy):
    trunk_low = b.ring((0, 0, 0), 0.24, 6)
    trunk_high = b.ring((0, 0, 1.2), 0.18, 6)
    b.bridge(trunk_low, trunk_high, BARK)
    for index, (base, radius, height) in enumerate(SPRUCE_TIERS):
        twist = math.pi / SPRUCE_SIDES * index
        rim = b.ring((0, 0, base), radius, SPRUCE_SIDES, twist, jitter=0.12)
        band_radius = radius * (1.0 - SPRUCE_BAND)
        band = b.ring((0, 0, base + height * SPRUCE_BAND), band_radius, SPRUCE_SIDES, twist, jitter=0.06)
        tint = index / (len(SPRUCE_TIERS) - 1)
        lower = mix(SPRUCE_DARK, SPRUCE_LIGHT, tint * 0.6)
        # In winter, snow lies on most sides of each layer of branches.
        b.bridge(rim, band, [SNOW, lower, lower, SNOW_SHADE, lower, SNOW, lower] if snowy else lower)
        b.fan(band, (0, 0, base + height), SNOW if snowy else mix(lower, SPRUCE_LIGHT, 0.5))
        b.cap(rim, SPRUCE_UNDER, downward=True)


def build_pine(b, snowy):
    sides = 5
    low = b.ring((0, 0, 0), 0.22, sides)
    high = b.ring((0.12, 0.05, 3.6), 0.13, sides)
    b.bridge(low, high, [BARK, PINE_BARK, PINE_BARK, BARK, PINE_BARK])

    def colour(normal):
        if snowy and normal.z > 0.6:
            return SNOW
        return PINE_TOP if normal.z > 0.5 else PINE_GREEN if normal.z > -0.3 else mix(PINE_GREEN, SPRUCE_UNDER, 0.6)

    b.blob((0.15, 0.05, 4.2), (3.0, 2.6, 1.0), colour)
    b.blob((-0.3, 0.35, 4.95), (2.0, 1.8, 0.8), colour)
    b.blob((0.75, -0.55, 3.55), (1.7, 1.4, 0.65), colour)


def build_birch(b, snowy):
    sides = 5
    heights = [0.0, 1.1, 2.1, 3.0]
    radii = [0.2, 0.17, 0.14, 0.11]
    rings = [b.ring((0.04 * i, 0, z), r, sides) for i, (z, r) in enumerate(zip(heights, radii))]
    for lower, upper in zip(rings, rings[1:]):
        marks = [BIRCH_MARK if b.rng.random() < 0.3 else BIRCH_BARK for _ in range(sides)]
        b.bridge(lower, upper, marks)

    def colour(normal):
        if snowy and normal.z > 0.4:
            return SNOW
        return LEAF_TOP if normal.z > 0.45 else LEAF_GREEN if normal.z > -0.35 else mix(LEAF_GREEN, SPRUCE_UNDER, 0.5)

    b.blob((0.1, 0.0, 4.0), (2.6, 2.4, 2.4), colour, jitter=0.14)
    b.blob((0.7, 0.5, 4.9), (1.6, 1.5, 1.5), colour)
    b.blob((-0.8, -0.3, 3.5), (1.5, 1.4, 1.3), colour)


TREES = [
    ("spruce", build_spruce, False),
    ("pine", build_pine, False),
    ("birch", build_birch, False),
    ("spruce_snowy", build_spruce, True),
    ("pine_snowy", build_pine, True),
]


# --- Hay bale -----------------------------------------------------------------------------

BALE_SIZE = (1.9, 1.2, 1.1)
BALE_BEVEL = 0.09


def build_bale(b):
    sx, sy, sz = BALE_SIZE
    verts = bmesh.ops.create_cube(b.bm, size=1.0, matrix=Matrix.Translation((0, 0, sz / 2))
                                  @ Matrix.Diagonal((sx, sy, sz, 1.0)))["verts"]
    edges = list({e for v in verts for e in v.link_edges})
    bmesh.ops.bevel(b.bm, geom=verts + edges, offset=BALE_BEVEL, segments=1, affect="EDGES",
                    profile=0.5)
    faces = list(b.bm.faces)
    for face in faces:
        face.normal_update()
        b.paint([face], STRAW_END if abs(face.normal.x) > 0.9 else STRAW)
    # Two strings around the bale.
    for x in (-sx * 0.27, sx * 0.27):
        b.box((x, 0, sz / 2), (0.05, sy + 0.02, sz + 0.02), TWINE, skip=("+x", "-x"))


# --- Container ----------------------------------------------------------------------------

def build_container(b, length, height, width, grooves):
    """Paint (material 0) carries light shading, Trim (material 1) its own colours."""
    hl, hw = length / 2, width / 2
    bottom = -FOUNDATION
    # Ends and top.
    b.face(((hl, -hw, bottom), (hl, hw, bottom), (hl, hw, height), (hl, -hw, height)), PAINT_LIGHT)
    b.face(((-hl, hw, bottom), (-hl, -hw, bottom), (-hl, -hw, height), (-hl, hw, height)), PAINT_GROOVE)
    b.face(((-hl, -hw, height), (hl, -hw, height), (hl, hw, height), (-hl, hw, height)), PAINT_LIGHT, jitter=0.0)
    # Corrugated long sides: strips in two shades.
    for side in (-1, 1):
        y = side * hw
        for i in range(grooves):
            x0 = -hl + length * i / grooves
            x1 = -hl + length * (i + 1) / grooves
            quad = [(x0, y, bottom), (x1, y, bottom), (x1, y, height), (x0, y, height)]
            if side > 0:
                quad.reverse()
            b.face(quad, PAINT_LIGHT if i % 2 == 0 else PAINT_GROOVE, jitter=0.0)
    # Corner posts and top rails.
    post = 0.14
    for x in (-hl, hl):
        for y in (-hw, hw):
            inner = ("-x" if x > 0 else "+x", "-y" if y > 0 else "+y")
            b.box((x, y, (height + bottom) / 2), (post, post, height - bottom), PAINT_POST,
                  skip=("bottom", "top") + inner)
    for y in (-hw, hw):
        b.box((0, y, height - 0.07), (length, 0.1, 0.14), PAINT_POST,
              skip=("bottom", "+x", "-x", "-y" if y > 0 else "+y"))
    # Door end: the doors' meeting line and four locking bars.
    door_x = hl + 0.03
    b.box((door_x, 0, height / 2), (0.04, 0.06, height - 0.1), TRIM_DARK, 1, skip=("-x", "top", "bottom"))
    for y in (-hw * 0.62, -hw * 0.18, hw * 0.18, hw * 0.62):
        b.box((door_x, y, height / 2), (0.08, 0.05, height - 0.2), TRIM_STEEL, 1, skip=("-x", "top", "bottom"))


CONTAINERS = [
    # name, length, height, width, grooves
    ("container", 6.1, 2.6, 2.4, 8),
    ("container_long", 12.0, 3.2, 4.2, 12),
]


# --- House ----------------------------------------------------------------------------------

HOUSE_SIZE = (8.0, 6.0, 5.0)
HOUSE_WALL_SHARE = 0.55
HOUSE_OVERHANG = 0.4
ROOF_THICKNESS = 0.18


def build_house(b):
    sx, sy, sz = HOUSE_SIZE
    hx, hy = sx / 2, sy / 2
    wall = sz * HOUSE_WALL_SHARE
    plinth = 0.35
    b.box((0, 0, (wall + plinth) / 2), (sx, sy, wall - plinth), WALL_RED, skip=("top", "bottom"))
    b.box((0, 0, (plinth - FOUNDATION) / 2), (sx + 0.12, sy + 0.12, plinth + FOUNDATION), PLINTH,
          skip=("bottom",))
    for x in (-hx, hx):
        for y in (-hy, hy):
            b.box((x, y, (wall + plinth) / 2), (0.24, 0.24, wall - plinth), TRIM_WHITE, skip=("top", "bottom"))
    # Windows on both long sides, the door in the front (-Y, Godot's +Z).
    for side in (-1, 1):
        y = side * (hy + 0.02)
        for x in (-hx * 0.6, hx * 0.6):
            _wall_panel(b, (x, y, wall * 0.58), (1.15, 1.2), side, TRIM_WHITE)
            _wall_panel(b, (x, y + side * 0.02, wall * 0.58), (0.8, 0.9), side, GLASS)
    _wall_panel(b, (0, -(hy + 0.02), plinth + 0.95), (1.2, 1.9), -1, TRIM_WHITE)
    _wall_panel(b, (0, -(hy + 0.04), plinth + 0.9), (0.9, 1.8), -1, DOOR)
    # Gables with a small window, roof slabs and a chimney.
    ridge = sz
    for side in (-1, 1):
        x = side * hx
        tri = [(x, -hy, wall), (x, hy, wall), (x, 0, ridge)]
        b.face(tri if side > 0 else list(reversed(tri)), WALL_RED)
        _gable_panel(b, (x + side * 0.02, 0, wall + (ridge - wall) * 0.38), (0.75, 0.75), side, TRIM_WHITE)
        _gable_panel(b, (x + side * 0.04, 0, wall + (ridge - wall) * 0.38), (0.5, 0.5), side, GLASS)
    slope = math.atan2(ridge - wall, hy)
    run = math.hypot(hy + HOUSE_OVERHANG, (ridge - wall) * (hy + HOUSE_OVERHANG) / hy)
    for side in (-1, 1):
        rotation = Matrix.Rotation(-side * slope, 3, "X")
        centre = Vector((0, 0, ridge)) + rotation @ Vector((0, side * run / 2, ROOF_THICKNESS / 2))
        b.box(centre, (sx + HOUSE_OVERHANG * 2, run, ROOF_THICKNESS), ROOF, rotation=rotation)
    chimney_x, chimney_y = hx * 0.45, hy * 0.35
    chimney_base = ridge - (ridge - wall) * chimney_y / hy
    b.box((chimney_x, chimney_y, (chimney_base + ridge + 0.7) / 2), (0.6, 0.6, ridge + 0.7 - chimney_base),
          CHIMNEY, skip=("bottom",))


def _wall_panel(b, centre, size, side, colour):
    x, y, z = centre
    w, h = size[0] / 2, size[1] / 2
    quad = [(x - w, y, z - h), (x + w, y, z - h), (x + w, y, z + h), (x - w, y, z + h)]
    b.face(quad if side < 0 else list(reversed(quad)), colour)


def _gable_panel(b, centre, size, side, colour):
    x, y, z = centre
    w, h = size[0] / 2, size[1] / 2
    quad = [(x, y - w, z - h), (x, y + w, z - h), (x, y + w, z + h), (x, y - w, z + h)]
    b.face(quad if side > 0 else list(reversed(quad)), colour)


# --- Rocks ----------------------------------------------------------------------------------

ROCK_SIZE = (3.2, 3.2, 1.8)


def rock_colour(normal):
    return ROCK_TOP if normal.z > 0.55 else ROCK_GREY if normal.z > -0.2 else ROCK_DARK


def build_rock_boulder(b):
    sx, sy, sz = ROCK_SIZE
    height = sz + FOUNDATION
    b.blob((0, 0, sz - height / 2), (sx, sy * 0.85, height), rock_colour, subdivisions=2, jitter=0.1)


def build_rock_cluster(b):
    sx, sy, sz = ROCK_SIZE
    height = sz + FOUNDATION
    b.blob((-0.3, 0.2, sz - height / 2), (2.3, 2.1, height), rock_colour, jitter=0.16)
    small = 0.9 + FOUNDATION
    b.blob((0.95, -0.6, 0.9 - small / 2), (1.3, 1.2, small), rock_colour, jitter=0.18)
    tiny = 0.5 + FOUNDATION
    b.blob((-0.6, -1.05, 0.5 - tiny / 2), (0.9, 0.8, tiny), rock_colour, jitter=0.2)


# --- Tyre stack -----------------------------------------------------------------------------

TYRE_COUNT = 3
TYRE_HEIGHT = 0.35
TYRE_RADIUS = 0.5
TYRE_WAIST = 0.44
TYRE_HOLE = 0.24
TYRE_SIDES = 8


def build_tyres(b):
    rings = [b.ring((0, 0, 0), TYRE_WAIST, TYRE_SIDES)]
    for i in range(TYRE_COUNT):
        colour = RUBBER_PAINT if i % 2 == 1 else RUBBER
        z = i * TYRE_HEIGHT
        middle = b.ring((0, 0, z + TYRE_HEIGHT / 2), TYRE_RADIUS, TYRE_SIDES)
        top = b.ring((0, 0, z + TYRE_HEIGHT), TYRE_WAIST, TYRE_SIDES)
        b.bridge(rings[-1], middle, colour)
        b.bridge(middle, top, colour)
        rings.append(top)
    top_z = TYRE_COUNT * TYRE_HEIGHT
    hole = b.ring((0, 0, top_z), TYRE_HOLE, TYRE_SIDES)
    b.bridge(rings[-1], hole, RUBBER)
    b.cap(hole, HOLE)


# --- Build, export, preview -----------------------------------------------------------------

def make_materials():
    result = {}
    for name in ("Prop", "Paint", "Trim"):
        material = bpy.data.materials.new(name)
        if material.node_tree is None:
            material.use_nodes = True
        nodes = material.node_tree.nodes
        shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        shader.inputs["Roughness"].default_value = 0.9
        attribute = nodes.new("ShaderNodeVertexColor")
        attribute.layer_name = "Col"
        # The colours are sRGB numbers; gamma makes Blender's preview match the game.
        gamma = nodes.new("ShaderNodeGamma")
        gamma.inputs["Gamma"].default_value = 2.2
        material.node_tree.links.new(attribute.outputs["Color"], gamma.inputs["Color"])
        material.node_tree.links.new(gamma.outputs["Color"], shader.inputs["Base Color"])
        result[name] = material
    return result


def build_all(materials):
    collection = bpy.data.collections.new("Props")
    bpy.context.scene.collection.children.link(collection)
    objects = []
    seed = 7

    def make(name, builder, *args, mats=("Prop",)):
        nonlocal seed
        seed += 1
        b = Builder(seed, mats)
        builder(b, *args)
        obj = b.finish(name, collection, materials)
        objects.append(obj)

    for name, builder, snowy in TREES:
        make(name, builder, snowy)
    make("hay_bale", build_bale)
    for name, length, height, width, grooves in CONTAINERS:
        make(name, build_container, length, height, width, grooves, mats=("Paint", "Trim"))
    make("house", build_house)
    make("rock_boulder", build_rock_boulder)
    make("rock_cluster", build_rock_cluster)
    make("tyre_stack", build_tyres)
    for obj in objects:
        for polygon in obj.data.polygons:
            polygon.use_smooth = False
    return objects


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_materials="EXPORT", export_vertex_color="ACTIVE", export_all_vertex_colors=False,
        export_normals=True, export_texcoords=False,
    )


def render_preview(objects, path):
    """All props in a row, seen from the game's camera angle."""
    scene = bpy.context.scene
    x = 0.0
    for obj in objects:
        width = obj.dimensions.x
        obj.location.x = x + width / 2
        x += width + 1.5
    centre = Vector((x / 2, 0, 2.0))
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_shadows = True
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 700
    scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.12, 0.13, 0.18)
    camera_data = bpy.data.cameras.new("Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = x + 2.0
    camera = bpy.data.objects.new("Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.location = centre + Vector((0, -40, 24))
    camera.rotation_euler = (centre - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    project = args[0] if args else os.getcwd()
    preview = args[1] if len(args) > 1 else ""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials = make_materials()
    out_dir = os.path.join(project, "tracks", "props")
    os.makedirs(out_dir, exist_ok=True)
    objects = build_all(materials)
    for obj in objects:
        export(obj, os.path.join(out_dir, obj.name + ".glb"))
        print("BUILT %s: %d triangles" % (obj.name, len(obj.data.polygons)))
    if preview:
        render_preview(objects, preview)


if __name__ == "__main__":
    main()
