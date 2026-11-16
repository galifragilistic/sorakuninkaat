"""Builds the game's car models in Blender and exports them as .glb files.

Run (Blender 4.2 or newer):
    blender --background --factory-startup --python tools/blender/build_cars.py -- <project dir> [preview.png]

Every car is made from numbers in CARS below, so a model can be changed and
rebuilt at any time. Blender axes: X right, Y forward (the car's nose), Z up.
The glTF exporter turns that into Godot's X right, -Z forward, Y up.

Each .glb holds:
  Body        painted shell and cabin with inset windows ("Paint", "Glass", ...)
  Details     lamps, grille, bumpers, mirrors, spoilers and other parts
  Wheel       one wheel at the origin, axle along Z (the game mounts four)
  Pattern_*   decals for the paint patterns, laid onto the body (material "Decal")
  Headlamp_L / Headlamp_R   empties where the headlight beams start

The game recolours every surface whose material is "Paint" or "Decal" and
makes "HeadLight" and "TailLight" glow.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# --- Fixed by the car physics (cars/car.gd) -------------------------------------

AXLE_Y = 1.2          # front axle at +AXLE_Y, rear at -AXLE_Y
WHEEL_X = 0.8         # half the track width
WHEEL_Z = 0.27        # wheel centre height at rest
TYRE_RADIUS = 0.33
GROUND_Z = WHEEL_Z - TYRE_RADIUS

DECAL_OFFSET = 0.012
STRIPE_WIDTH = 0.16
STRIPE_GAP = 0.10
CHECKER_SIZE = 0.12
DECAL_STEP = 0.08

# --- Materials: (name, colour, roughness, metallic, emission) ----------------------

MATERIALS = [
    ("Paint", (0.9, 0.9, 0.9), 0.45, 0.0),
    ("Glass", (0.07, 0.09, 0.14), 0.15, 0.0),
    ("Trim", (0.06, 0.065, 0.08), 0.75, 0.0),
    ("Chrome", (0.78, 0.8, 0.84), 0.25, 0.6),
    ("HeadLight", (1.0, 0.95, 0.78), 0.3, 0.0),
    ("TailLight", (0.85, 0.08, 0.06), 0.3, 0.0),
    ("Rubber", (0.045, 0.045, 0.05), 0.9, 0.0),
    ("Rim", (0.7, 0.72, 0.75), 0.35, 0.3),
    ("Grille", (0.02, 0.022, 0.03), 0.8, 0.0),
    ("Plate", (0.92, 0.92, 0.88), 0.6, 0.0),
    ("Indicator", (1.0, 0.55, 0.1), 0.3, 0.0),
    ("Decal", (0.95, 0.95, 0.92), 0.5, 0.0),
    ("Arch", (0.03, 0.03, 0.035), 0.9, 0.0),
]
MAT = {name: index for index, (name, *_rest) in enumerate(MATERIALS)}


def make_materials():
    result = []
    for name, colour, roughness, metallic in MATERIALS:
        material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (*colour, 1.0)
        shader.inputs["Roughness"].default_value = roughness
        shader.inputs["Metallic"].default_value = metallic
        # The preview render (Workbench) shows the viewport colour.
        material.diffuse_color = (*colour, 1.0)
        material.roughness = roughness
        result.append(material)
    return result


def rim_material(name, colour, metallic=0.3):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*colour, 1.0)
    shader.inputs["Roughness"].default_value = 0.35
    shader.inputs["Metallic"].default_value = metallic
    material.diffuse_color = (*colour, 1.0)
    return material


# --- bmesh helpers --------------------------------------------------------------------

def faces_of(verts):
    return {face for vert in verts for face in vert.link_faces}


def set_material(faces, name):
    for face in faces:
        face.material_index = MAT[name]


def add_box(bm, centre, size, material, rotation=None):
    matrix = Matrix.Translation(Vector(centre))
    if rotation is not None:
        matrix = matrix @ rotation.to_4x4()
    matrix = matrix @ Matrix.Diagonal((*size, 1.0))
    verts = bmesh.ops.create_cube(bm, size=1.0, matrix=matrix)["verts"]
    set_material(faces_of(verts), material)
    return verts


AXES = {
    "X": Matrix.Rotation(math.radians(90), 4, "Y"),
    "Y": Matrix.Rotation(math.radians(-90), 4, "X"),
    "Z": Matrix.Identity(4),
}


def add_cylinder(bm, centre, axis, radius, depth, segments, material, radius_top=None):
    matrix = Matrix.Translation(Vector(centre)) @ AXES[axis]
    verts = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
        radius2=radius if radius_top is None else radius_top, depth=depth, matrix=matrix,
    )["verts"]
    set_material(faces_of(verts), material)
    return verts


def add_tube(bm, start, end, radius, material, segments=8):
    start, end = Vector(start), Vector(end)
    direction = end - start
    rotation = Vector((0, 0, 1)).rotation_difference(direction.normalized()).to_matrix().to_4x4()
    matrix = Matrix.Translation((start + end) / 2) @ rotation
    verts = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius,
        depth=direction.length, matrix=matrix,
    )["verts"]
    set_material(faces_of(verts), material)
    return verts


def new_object(name, bm, collection, materials):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    for material in materials:
        mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return obj


def apply_modifiers(obj):
    """Bakes the object's modifiers into its mesh."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated)
    old = obj.data
    obj.modifiers.clear()
    obj.data = mesh
    bpy.data.meshes.remove(old)


# --- Body --------------------------------------------------------------------------

def body_top(spec, y):
    """Height of the body's top surface at y (linear between sections)."""
    sections = spec["body"]
    for a, b in zip(sections, sections[1:]):
        if a[0] >= y >= b[0]:
            t = (a[0] - y) / (a[0] - b[0]) if a[0] != b[0] else 0.0
            return a[3] + (b[3] - a[3]) * t
    return sections[0][3] if y > sections[0][0] else sections[-1][3]


def body_ring(bm, section):
    y, half, bottom, top, shoulder, sill = section
    points = [
        (-half + sill, bottom), (-half, bottom + sill), (-half, top - shoulder), (-half + shoulder, top),
        (half - shoulder, top), (half, top - shoulder), (half, bottom + sill), (half - sill, bottom),
    ]
    return [bm.verts.new((x, y, z)) for x, z in points]


def build_body(spec, collection, materials):
    bm = bmesh.new()
    rings = [body_ring(bm, section) for section in spec["body"]]
    for front, back in zip(rings, rings[1:]):
        count = len(front)
        for i in range(count):
            j = (i + 1) % count
            bm.faces.new((front[i], front[j], back[j], back[i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    set_material(bm.faces, "Paint")
    _build_cabin(bm, spec)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    body = new_object("Body", bm, collection, materials)

    # Wheel arches: cylinders cut out of the shell; the cut faces turn dark.
    arch_radius, arch_lift = spec.get("arch", (0.42, 0.03))
    cutter_bm = bmesh.new()
    # Only the flanks are cut, so a low bonnet between the wheels stays whole.
    inner = spec.get("arch_inner", 0.5)
    for y in (AXLE_Y, -AXLE_Y):
        for side in (-1, 1):
            add_cylinder(cutter_bm, (side * (inner + 0.75), y, WHEEL_Z + arch_lift), "X", arch_radius, 1.5, 20, "Arch")
    cutter = new_object("ArchCutter", cutter_bm, collection, materials)
    modifier = body.modifiers.new("Arches", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "EXACT"
    modifier.object = cutter
    modifier.material_mode = "TRANSFER"
    modifier.use_self = True
    modifier.use_hole_tolerant = True
    apply_modifiers(body)
    bpy.data.objects.remove(cutter)
    # Softer edges: one small bevel on the sharp creases.
    bevel = body.modifiers.new("Bevel", "BEVEL")
    bevel.width = 0.018
    bevel.segments = 1
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(40)
    apply_modifiers(body)
    return body


def _cabin_width(spec, z):
    cabin = spec["cabin"]
    base_z = min(point[1] for point in cabin["profile"])
    roof_z = max(point[1] for point in cabin["profile"])
    t = (z - base_z) / max(roof_z - base_z, 0.01)
    return cabin["width"][0] + (cabin["width"][1] - cabin["width"][0]) * t


def cabin_profile(spec):
    """The cabin's side profile with its two base points sunk into the body top."""
    profile = list(spec["cabin"]["profile"])
    for index in (0, len(profile) - 1):
        y = profile[index][0]
        profile[index] = (y, body_top(spec, y) - 0.01)
    return profile


def _build_cabin(bm, spec):
    cabin = spec["cabin"]
    profile = cabin_profile(spec)
    left = [bm.verts.new((-_cabin_width(spec, z), y, z)) for y, z in profile]
    right = [bm.verts.new((_cabin_width(spec, z), y, z)) for y, z in profile]
    count = len(profile)
    tops = []
    for i in range(count - 1):
        tops.append(bm.faces.new((left[i], left[i + 1], right[i + 1], right[i])))
    bm.faces.new((left[-1], left[0], right[0], right[-1]))
    side_left = bm.faces.new(list(reversed(left)))
    side_right = bm.faces.new(right)
    cabin_faces = tops + [side_left, side_right]
    set_material(cabin_faces, "Paint")
    bmesh.ops.recalc_face_normals(bm, faces=cabin_faces)

    glass = [tops[index] for index in cabin["glass"]] + [side_left, side_right]
    pillar = cabin.get("pillar", 0.08)
    bmesh.ops.inset_individual(bm, faces=glass, thickness=pillar, depth=-0.012, use_even_offset=True)
    set_material(glass, "Glass")
    # Window line under the side glass: the inset leaves the bottom frame thick enough.
    for y in cabin.get("pillars", []):
        z_low = body_top(spec, y)
        z_high = max(point[1] for point in profile)
        for side in (-1, 1):
            x = side * (_cabin_width(spec, (z_low + z_high) / 2) + 0.004)
            add_box(bm, (x, y, (z_low + z_high) / 2), (0.03, pillar * 1.4, z_high - z_low), "Paint")


# --- Details --------------------------------------------------------------------

def front_y(spec):
    return spec["body"][0][0]


def rear_y(spec):
    return spec["body"][-1][0]


def section_at(spec, y):
    sections = spec["body"]
    for a, b in zip(sections, sections[1:]):
        if a[0] >= y >= b[0]:
            t = (a[0] - y) / (a[0] - b[0]) if a[0] != b[0] else 0.0
            return [a[k] + (b[k] - a[k]) * t for k in range(6)]
    return list(sections[0] if y > sections[0][0] else sections[-1])


def build_details(spec, collection, materials):
    bm = bmesh.new()
    lamps = []
    for feature in spec["features"]:
        kind, params = feature[0], feature[1] if len(feature) > 1 else {}
        result = FEATURES[kind](bm, spec, **params)
        if kind in ("round_headlights", "rect_headlights", "slim_headlights", "grille_headlights"):
            lamps.extend(result)
    _mirrors(bm, spec)
    _plates(bm, spec)
    return new_object("Details", bm, collection, materials), lamps


def _mirrors(bm, spec):
    profile = cabin_profile(spec)
    y = profile[0][0] - 0.08
    z = profile[0][1] + 0.1
    x = _cabin_width(spec, z) + 0.12
    for side in (-1, 1):
        add_box(bm, (side * x, y, z), (0.16, 0.06, 0.1), "Paint")
        add_box(bm, (side * (x - 0.07), y, z - 0.02), (0.08, 0.04, 0.03), "Trim")


def _plates(bm, spec):
    for y, z in ((front_y(spec) + 0.01, spec.get("plate_z", (0.3, 0.42))[0]),
                 (rear_y(spec) - 0.01, spec.get("plate_z", (0.3, 0.42))[1])):
        add_box(bm, (0, y, z), (0.42, 0.02, 0.11), "Plate")


def round_headlights(bm, spec, x, z, radius=0.11, inset=0.0, pairs=1, spacing=0.26):
    y = front_y(spec) - inset
    lamps = []
    for side in (-1, 1):
        for k in range(pairs):
            lx = side * (x - k * spacing)
            add_cylinder(bm, (lx, y + 0.01, z), "Y", radius + 0.025, 0.05, 14, "Chrome")
            add_cylinder(bm, (lx, y + 0.03, z), "Y", radius, 0.03, 14, "HeadLight")
            lamps.append((lx, y + 0.1, z))
    return lamps


def rect_headlights(bm, spec, x, z, size=(0.3, 0.12), inset=0.0):
    y = front_y(spec) - inset
    lamps = []
    for side in (-1, 1):
        add_box(bm, (side * x, y + 0.005, z), (size[0] + 0.04, 0.04, size[1] + 0.04), "Trim")
        add_box(bm, (side * x, y + 0.025, z), (size[0], 0.03, size[1]), "HeadLight")
        add_box(bm, (side * (x + size[0] / 2 + 0.05), y + 0.01, z - 0.02), (0.07, 0.03, 0.05), "Indicator")
        lamps.append((side * x, y + 0.1, z))
    return lamps


def slim_headlights(bm, spec, x, z, length=0.42, y_back=0.2):
    """Narrow lamps lying on a sloping nose."""
    y = front_y(spec)
    lamps = []
    for side in (-1, 1):
        start = Vector((side * (x - length / 2), y - 0.02, z))
        end = Vector((side * (x + length / 2), y - y_back, z + 0.06))
        centre = (start + end) / 2
        add_box(bm, centre, (length, 0.12, 0.04), "HeadLight")
        add_box(bm, centre - Vector((0, 0, 0.02)), (length + 0.04, 0.16, 0.03), "Trim")
        lamps.append((side * x, y + 0.08, z))
    return lamps


def grille_headlights(bm, spec, x, z, radius=0.1, width=1.3, height=0.32):
    """A boxy grille panel with round lamps set into it (off-roaders)."""
    y = front_y(spec)
    add_box(bm, (0, y + 0.01, z), (width, 0.04, height), "Grille")
    for k in range(5):
        add_box(bm, (0, y + 0.035, z - height / 2 + height * (k + 0.5) / 5), (width * 0.45, 0.02, 0.025), "Trim")
    return round_headlights(bm, spec, x, z, radius=radius, inset=-0.02)


def grille(bm, spec, z, width=0.6, height=0.14, slats=3, material="Grille", slat_material="Trim"):
    y = front_y(spec)
    add_box(bm, (0, y + 0.01, z), (width, 0.04, height), material)
    for k in range(slats):
        sz = z - height / 2 + height * (k + 0.5) / slats
        add_box(bm, (0, y + 0.032, sz), (width * 0.94, 0.012, height / (slats * 2.5)), slat_material)


def chrome_grille(bm, spec, z, width=0.7, height=0.3):
    y = front_y(spec)
    add_box(bm, (0, y + 0.01, z), (width + 0.06, 0.05, height + 0.06), "Chrome")
    add_box(bm, (0, y + 0.03, z), (width, 0.03, height), "Grille")
    for k in range(9):
        x = -width / 2 + width * (k + 0.5) / 9
        add_box(bm, (x, y + 0.045, z), (0.02, 0.02, height), "Chrome")


def bumpers(bm, spec, z_front, z_rear, height=0.14, depth=0.12, material="Trim", wrap=0.25):
    for y, z, sign in ((front_y(spec), z_front, 1), (rear_y(spec), z_rear, -1)):
        half = section_at(spec, y - sign * 0.1)[1]
        add_box(bm, (0, y + sign * depth * 0.3, z), (half * 2 + 0.04, depth, height), material)
        # Corners wrap round the sides a little.
        for side in (-1, 1):
            add_box(bm, (side * (half + 0.01), y - sign * wrap / 2, z), (0.05, wrap, height), material)


def chrome_bumpers(bm, spec, z_front, z_rear):
    for y, z, sign in ((front_y(spec), z_front, 1), (rear_y(spec), z_rear, -1)):
        half = section_at(spec, y - sign * 0.1)[1]
        add_tube(bm, (-half - 0.02, y + sign * 0.06, z), (half + 0.02, y + sign * 0.06, z), 0.05, "Chrome", 10)
        for side in (-1, 1):
            add_box(bm, (side * 0.3, y + sign * 0.03, z), (0.06, 0.06, 0.14), "Chrome")


def tail_lights(bm, spec, x, z, size=(0.3, 0.12), round_lamps=False):
    y = rear_y(spec)
    for side in (-1, 1):
        if round_lamps:
            add_cylinder(bm, (side * x, y - 0.01, z), "Y", size[1] * 0.6 + 0.02, 0.04, 12, "Chrome")
            add_cylinder(bm, (side * x, y - 0.03, z), "Y", size[1] * 0.6, 0.03, 12, "TailLight")
        else:
            add_box(bm, (side * x, y - 0.005, z), (size[0] + 0.03, 0.03, size[1] + 0.03), "Trim")
            add_box(bm, (side * x, y - 0.02, z), (size[0], 0.03, size[1]), "TailLight")


def exhaust(bm, spec, x, z, count=1, radius=0.045):
    y = rear_y(spec) - 0.04
    for k in range(count):
        px = x + k * 0.13
        add_cylinder(bm, (px, y, z), "Y", radius, 0.18, 10, "Chrome")
        add_cylinder(bm, (px, y - 0.06, z), "Y", radius * 0.7, 0.08, 10, "Grille")


def wing(bm, spec, y, z, span=1.5, chord=0.36, height=0.22, material="Paint"):
    top = body_top(spec, y)
    for side in (-1, 1):
        add_box(bm, (side * span * 0.32, y, top + height / 2), (0.05, chord * 0.5, height), "Trim")
    plate_z = top + height + 0.025
    tilt = Matrix.Rotation(math.radians(-8), 3, "X")
    add_box(bm, (0, y, plate_z), (span, chord, 0.04), material, tilt)
    for side in (-1, 1):
        add_box(bm, (side * span / 2, y, plate_z + 0.04), (0.03, chord + 0.04, 0.14), "Trim")


def roof_spoiler(bm, spec, depth=0.3):
    profile = cabin_profile(spec)
    roof = [point for point in profile if point[1] > profile[0][1] + 0.1]
    y, z = roof[-1]
    half = _cabin_width(spec, z)
    tilt = Matrix.Rotation(math.radians(-10), 3, "X")
    add_box(bm, (0, y - depth / 2 + 0.05, z + 0.03), (half * 2 + 0.02, depth, 0.05), "Paint", tilt)


def lip_spoiler(bm, spec):
    y = rear_y(spec) + 0.08
    add_box(bm, (0, y, body_top(spec, y) + 0.04), (section_at(spec, y)[1] * 1.8, 0.14, 0.05), "Trim")


def hood_scoop(bm, spec, y, width=0.5, length=0.45):
    z = body_top(spec, y)
    add_box(bm, (0, y, z + 0.04), (width, length, 0.1), "Trim")
    add_box(bm, (0, y + length / 2, z + 0.05), (width * 0.85, 0.02, 0.06), "Grille")


def roof_vent(bm, spec):
    profile = cabin_profile(spec)
    roof_z = max(point[1] for point in profile)
    roof_points = [point[0] for point in profile if point[1] > roof_z - 0.05]
    y = sum(roof_points) / len(roof_points)
    add_box(bm, (0, y, roof_z + 0.03), (0.3, 0.3, 0.06), "Trim")
    add_box(bm, (0, y + 0.15, roof_z + 0.03), (0.26, 0.02, 0.04), "Grille")


def rally_lights(bm, spec, z, count=4, radius=0.08, spacing=0.26):
    y = front_y(spec) + 0.1
    add_box(bm, (0, y - 0.02, z), (spacing * count, 0.05, 0.04), "Trim")
    for k in range(count):
        x = -spacing * (count - 1) / 2 + spacing * k
        add_cylinder(bm, (x, y + 0.02, z), "Y", radius + 0.02, 0.08, 12, "Trim")
        add_cylinder(bm, (x, y + 0.065, z), "Y", radius, 0.02, 12, "HeadLight")


def fog_lights(bm, spec, x, z, radius=0.05):
    y = front_y(spec) + 0.04
    for side in (-1, 1):
        add_cylinder(bm, (side * x, y, z), "Y", radius, 0.03, 10, "HeadLight")


def mud_flaps(bm, spec, material="Trim"):
    for y in (AXLE_Y, -AXLE_Y):
        for side in (-1, 1):
            add_box(bm, (side * WHEEL_X, y - 0.47, GROUND_Z + 0.2), (0.26, 0.015, 0.26), material)


def flares(bm, spec, width=0.14, thickness=0.06):
    """Plastic arches standing out over the wheels."""
    arch_radius, arch_lift = spec.get("arch", (0.42, 0.03))
    for y in (AXLE_Y, -AXLE_Y):
        for side in (-1, 1):
            for step in range(7):
                angle = math.radians(15 + step * 150 / 6)
                cy = y + math.cos(angle) * (arch_radius + thickness / 2)
                cz = WHEEL_Z + arch_lift + math.sin(angle) * (arch_radius + thickness / 2)
                half = section_at(spec, cy)[1]
                rotation = Matrix.Rotation(angle + math.pi / 2, 3, "X")
                add_box(bm, (side * (half + width / 2 - 0.03), cy, cz), (width, 0.17, thickness), "Trim", rotation)


def side_steps(bm, spec, z=None, material="Trim"):
    z = spec["body"][1][2] + 0.02 if z is None else z
    length = 2 * AXLE_Y - 2 * 0.5
    for side in (-1, 1):
        half = section_at(spec, 0)[1]
        add_box(bm, (side * (half + 0.05), 0, z), (0.12, length, 0.05), material)


def bull_bar(bm, spec, height=0.62, width=1.2):
    y = front_y(spec) + 0.14
    z0 = GROUND_Z + 0.25
    for side in (-1, 1):
        add_tube(bm, (side * width * 0.32, y, z0), (side * width * 0.32, y - 0.04, z0 + height), 0.035, "Trim")
    add_tube(bm, (-width / 2, y, z0 + 0.1), (width / 2, y, z0 + 0.1), 0.04, "Trim")
    add_tube(bm, (-width * 0.32, y - 0.04, z0 + height), (width * 0.32, y - 0.04, z0 + height), 0.03, "Trim")


def roof_rack(bm, spec, bars=4):
    profile = cabin_profile(spec)
    roof_z = max(point[1] for point in profile)
    roof_points = [point[0] for point in profile if point[1] > roof_z - 0.05]
    y0, y1 = min(roof_points) + 0.05, max(roof_points) - 0.05
    half = _cabin_width(spec, roof_z) - 0.06
    for side in (-1, 1):
        add_box(bm, (side * half, (y0 + y1) / 2, roof_z + 0.09), (0.04, y1 - y0, 0.04), "Trim")
        for y in (y0, y1):
            add_box(bm, (side * half, y, roof_z + 0.045), (0.04, 0.04, 0.09), "Trim")
    for k in range(bars):
        y = y0 + (y1 - y0) * (k + 0.5) / bars
        add_box(bm, (0, y, roof_z + 0.09), (half * 2, 0.035, 0.025), "Trim")


def snorkel(bm, spec):
    profile = cabin_profile(spec)
    base_y, base_z = profile[0]
    half = section_at(spec, base_y)[1]
    x = half + 0.04
    add_tube(bm, (x, base_y + 0.25, base_z - 0.25), (x, base_y + 0.05, base_z + 0.05), 0.045, "Trim")
    add_tube(bm, (x, base_y + 0.05, base_z + 0.05), (x - 0.04, base_y - 0.15, base_z + 0.6), 0.045, "Trim")
    add_box(bm, (x - 0.04, base_y - 0.12, base_z + 0.65), (0.1, 0.14, 0.1), "Trim")


def spare_wheel(bm, spec, z):
    y = rear_y(spec) - 0.12
    add_cylinder(bm, (0, y, z), "Y", 0.33, 0.24, 18, "Rubber")
    add_cylinder(bm, (0, y - 0.125, z), "Y", 0.18, 0.02, 12, "Rim")
    add_cylinder(bm, (0, y - 0.14, z), "Y", 0.05, 0.02, 8, "Chrome")


def louvres(bm, spec, y, count=5):
    z = body_top(spec, y)
    for k in range(count):
        add_box(bm, (0, y - k * 0.07, z + 0.01), (0.5, 0.035, 0.02), "Grille")


def side_intakes(bm, spec, y):
    for side in (-1, 1):
        half = section_at(spec, y)[1]
        add_box(bm, (side * (half + 0.005), y, 0.42), (0.03, 0.4, 0.14), "Grille")


def diffuser(bm, spec, z):
    y = rear_y(spec) - 0.02
    half = section_at(spec, y)[1]
    add_box(bm, (0, y, z), (half * 1.6, 0.08, 0.1), "Trim")
    for k in range(4):
        add_box(bm, (-0.3 + k * 0.2, y - 0.05, z), (0.02, 0.06, 0.1), "Grille")


def splitter(bm, spec, z):
    y = front_y(spec) + 0.04
    half = section_at(spec, y - 0.1)[1]
    add_box(bm, (0, y, z), (half * 2, 0.16, 0.03), "Trim")


def running_boards(bm, spec, z):
    for side in (-1, 1):
        half = section_at(spec, 0)[1]
        add_box(bm, (side * (half + 0.02), 0, z), (0.1, 2 * AXLE_Y - 0.9, 0.04), "Trim")


def hood_ornament(bm, spec):
    y = front_y(spec) - 0.12
    z = body_top(spec, y)
    add_box(bm, (0, y, z + 0.04), (0.03, 0.1, 0.08), "Chrome")


def side_trim(bm, spec, z):
    """A chrome strip along the flanks."""
    y0, y1 = rear_y(spec) + 0.15, front_y(spec) - 0.15
    for side in (-1, 1):
        for a, b in ((y1, AXLE_Y + 0.5), (AXLE_Y - 0.5, -AXLE_Y + 0.5), (-AXLE_Y - 0.5, y0)):
            ya, yb = max(a, b), min(a, b)
            half = section_at(spec, (ya + yb) / 2)[1]
            add_box(bm, (side * (half + 0.006), (ya + yb) / 2, z), (0.015, ya - yb, 0.025), "Chrome")


def door_lines(bm, spec, ys, z_low, z_high):
    for y in ys:
        for side in (-1, 1):
            half = section_at(spec, y)[1]
            add_box(bm, (side * (half + 0.003), y, (z_low + z_high) / 2), (0.008, 0.012, z_high - z_low), "Grille")


FEATURES = {
    name: function for name, function in globals().items()
    if callable(function) and name in (
        "round_headlights", "rect_headlights", "slim_headlights", "grille_headlights", "grille",
        "chrome_grille", "bumpers", "chrome_bumpers", "tail_lights", "exhaust", "wing", "roof_spoiler",
        "lip_spoiler", "hood_scoop", "roof_vent", "rally_lights", "fog_lights", "mud_flaps", "flares",
        "side_steps", "bull_bar", "roof_rack", "snorkel", "spare_wheel", "louvres", "side_intakes",
        "diffuser", "splitter", "running_boards", "hood_ornament", "side_trim", "door_lines",
    )
}


# --- Wheel -------------------------------------------------------------------------

def build_wheel(spec, collection, materials):
    style = spec["wheel"]
    width = style.get("width", 0.26)
    ratio = style.get("rim_ratio", 0.62)
    spokes = style.get("spokes", 5)
    bm = bmesh.new()
    # Tyre: a cylinder with chamfered shoulders. Axle along Z (the game turns it).
    add_cylinder(bm, (0, 0, 0), "Z", TYRE_RADIUS, width - 0.06, 20, "Rubber")
    for side in (-1, 1):
        add_cylinder(
            bm, (0, 0, side * (width / 2 - 0.015)), "Z",
            TYRE_RADIUS - 0.03 if side < 0 else TYRE_RADIUS, 0.03, 20, "Rubber",
            radius_top=TYRE_RADIUS if side < 0 else TYRE_RADIUS - 0.03,
        )
        if style.get("whitewall"):
            add_cylinder(bm, (0, 0, side * (width / 2 + 0.002)), "Z", TYRE_RADIUS * 0.9, 0.004, 20, "Plate")
        rim_r = TYRE_RADIUS * ratio
        face = side * (width / 2 + 0.006)
        add_cylinder(bm, (0, 0, face), "Z", rim_r, 0.012, 18, "Rim")
        add_cylinder(bm, (0, 0, face + side * 0.008), "Z", rim_r * 0.8, 0.006, 18, "Grille")
        for k in range(spokes):
            angle = 2 * math.pi * k / spokes
            centre = (math.cos(angle) * rim_r * 0.42, math.sin(angle) * rim_r * 0.42, face + side * 0.012)
            add_box(bm, centre, (rim_r * 0.75, rim_r * 0.2, 0.012), "Rim", Matrix.Rotation(angle, 3, "Z"))
        add_cylinder(bm, (0, 0, face + side * 0.018), "Z", rim_r * 0.24, 0.016, 10, "Chrome")
    obj = new_object("Wheel", bm, collection, materials)
    rim = rim_material("Rim_" + spec["id"], style.get("rim_colour", (0.7, 0.72, 0.75)), style.get("rim_metal", 0.3))
    obj.data.materials[MAT["Rim"]] = rim
    return obj


# --- Pattern decals ----------------------------------------------------------------

def _grid(bm, corners_for, rows, columns):
    """A grid of quads; corners_for(u, v) gives a vertex position for u, v in 0..1."""
    verts = [[bm.verts.new(corners_for(c / columns, r / rows)) for c in range(columns + 1)] for r in range(rows + 1)]
    for r in range(rows):
        for c in range(columns):
            bm.faces.new((verts[r][c], verts[r][c + 1], verts[r + 1][c + 1], verts[r + 1][c]))


def _top_strip(bm, x0, x1, y0, y1):
    columns = max(1, int(abs(y1 - y0) / DECAL_STEP))
    _grid(bm, lambda u, v: (x0 + (x1 - x0) * v, y0 + (y1 - y0) * u, 5.0), 1, columns)


def _side_strip(bm, side, y0, y1, z0, z1):
    columns = max(1, int(abs(y1 - y0) / DECAL_STEP))
    _grid(bm, lambda u, v: (side * 3.0, y0 + (y1 - y0) * u, z0 + (z1 - z0) * v), 1, columns)


def _checker(bm, side, y0, y1, z_mid):
    columns = int(abs(y1 - y0) / CHECKER_SIZE)
    step = CHECKER_SIZE if y1 > y0 else -CHECKER_SIZE
    for c in range(columns):
        for row in range(2):
            if (c + row) % 2:
                continue
            ya = y0 + c * step
            za = z_mid - CHECKER_SIZE + row * CHECKER_SIZE
            _grid(bm, lambda u, v, ya=ya, za=za: (side * 3.0, ya + step * u, za + CHECKER_SIZE * v), 1, 1)


def build_patterns(spec, body, collection, decal_material):
    profile = cabin_profile(spec)
    roof_z = max(point[1] for point in profile)
    roof_points = [point[0] for point in profile if point[1] > roof_z - 0.06]
    roof_front, roof_rear = max(roof_points), min(roof_points)
    base_front, base_rear = profile[0][0], profile[-1][0]
    # Decals start a little in from the ends, where the body curls down steeply.
    nose, tail = front_y(spec) - 0.14, rear_y(spec) + 0.1
    band = spec.get("band", (0.42, 0.56))
    two_tone = spec.get("two_tone", (spec["body"][1][2] + 0.03, 0.42))
    roof_half = _cabin_width(spec, roof_z) - 0.05
    patterns = {}

    bm = bmesh.new()
    for side in (-1, 1):
        x0, x1 = side * STRIPE_GAP / 2, side * (STRIPE_GAP / 2 + STRIPE_WIDTH)
        # Keep clear of the windows: the projection would climb onto the glass.
        for y0, y1 in ((nose, base_front + 0.12), (roof_front - 0.06, roof_rear + 0.06), (base_rear - 0.12, tail)):
            if y0 - y1 > 0.05:
                _top_strip(bm, x0, x1, y0, y1)
    patterns["STRIPE"] = ("Z", bm)

    bm = bmesh.new()
    for side in (-1, 1):
        _side_strip(bm, side, nose, tail, *band)
    patterns["SIDE_BAND"] = ("X", bm)

    bm = bmesh.new()
    for side in (-1, 1):
        _side_strip(bm, side, nose, tail, *two_tone)
    patterns["TWO_TONE"] = ("X", bm)
    roof_bm = bmesh.new()
    _top_strip(roof_bm, -roof_half, roof_half, roof_front - 0.06, roof_rear + 0.06)
    patterns["TWO_TONE_ROOF"] = ("Z", roof_bm)

    bm = bmesh.new()
    for side in (-1, 1):
        _checker(bm, side, nose - 0.15, tail + 0.15, (band[0] + band[1]) / 2)
    patterns["CHECKER"] = ("X", bm)

    objects = {}
    for name, (axis, pattern_bm) in patterns.items():
        obj = new_object("Pattern_" + name, pattern_bm, collection, [decal_material])
        modifier = obj.modifiers.new("Wrap", "SHRINKWRAP")
        modifier.wrap_method = "PROJECT"
        modifier.target = body
        modifier.offset = DECAL_OFFSET
        modifier.use_negative_direction = True
        modifier.use_positive_direction = True
        modifier.use_project_x = axis == "X"
        modifier.use_project_z = axis == "Z"
        apply_modifiers(obj)
        # Drop everything that found no body to land on (over the wheel arches).
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        missed = [v for v in bm.verts if abs(v.co.x) > 2.0 or v.co.z > 4.0]
        bmesh.ops.delete(bm, geom=missed, context="VERTS")
        bm.normal_update()
        # Every decal faces outwards: up for the top ones, away from the car for the sides.
        for face in bm.faces:
            outward = Vector((0, 0, 1)) if axis == "Z" else Vector((1 if face.calc_center_median().x > 0 else -1, 0, 0))
            if face.normal.dot(outward) < 0:
                face.normal_flip()
        bm.to_mesh(obj.data)
        bm.free()
        objects[name] = obj
    # The two-tone roof belongs to the two-tone pattern.
    roof = objects.pop("TWO_TONE_ROOF")
    _join(objects["TWO_TONE"], roof)
    return list(objects.values())


def _join(target, other):
    bm = bmesh.new()
    bm.from_mesh(target.data)
    bm.from_mesh(other.data)
    bm.to_mesh(target.data)
    bm.free()
    bpy.data.objects.remove(other)


# --- Cars ----------------------------------------------------------------------------

CARS = [
    {
        "id": "kuplakone",
        "body": [
            (2.02, 0.62, 0.26, 0.56, 0.10, 0.06),
            (1.88, 0.80, 0.18, 0.72, 0.16, 0.06),
            (1.40, 0.86, 0.15, 0.80, 0.18, 0.06),
            (0.80, 0.86, 0.15, 0.84, 0.16, 0.06),
            (-0.70, 0.86, 0.15, 0.84, 0.16, 0.06),
            (-1.45, 0.86, 0.16, 0.78, 0.18, 0.06),
            (-1.88, 0.78, 0.19, 0.68, 0.16, 0.06),
            (-2.00, 0.62, 0.26, 0.56, 0.10, 0.06),
        ],
        "arch": (0.43, 0.04),
        "cabin": {
            "profile": [(0.78, 0), (0.38, 1.20), (0.05, 1.37), (-0.55, 1.40), (-1.05, 1.25), (-1.52, 0)],
            "width": (0.78, 0.58), "glass": [0, 4], "pillar": 0.07, "pillars": [-0.3],
        },
        "band": (0.42, 0.54), "two_tone": (0.17, 0.4), "plate_z": (0.34, 0.36),
        "wheel": {"width": 0.24, "rim_ratio": 0.66, "spokes": 4, "rim_colour": (0.93, 0.91, 0.85)},
        "features": [
            ("round_headlights", {"x": 0.58, "z": 0.62, "radius": 0.12, "inset": 0.12}),
            ("chrome_bumpers", {"z_front": 0.3, "z_rear": 0.3}),
            ("tail_lights", {"x": 0.62, "z": 0.58, "size": (0.14, 0.16), "round_lamps": True}),
            ("louvres", {"y": -1.62, "count": 5}),
            ("running_boards", {"z": 0.17}),
            ("exhaust", {"x": -0.35, "z": 0.24, "count": 2}),
            ("door_lines", {"ys": [0.72, -0.35], "z_low": 0.22, "z_high": 0.8}),
        ],
    },
    {
        "id": "pikku_turbo",
        "body": [
            (1.86, 0.76, 0.22, 0.62, 0.06, 0.05),
            (1.72, 0.85, 0.16, 0.73, 0.07, 0.05),
            (0.90, 0.87, 0.14, 0.81, 0.07, 0.05),
            (-1.30, 0.87, 0.14, 0.83, 0.07, 0.05),
            (-1.62, 0.84, 0.18, 0.81, 0.06, 0.05),
        ],
        "arch": (0.42, 0.03),
        "cabin": {
            "profile": [(0.86, 0), (0.22, 1.32), (-1.22, 1.34), (-1.58, 0)],
            "width": (0.8, 0.69), "glass": [0, 2], "pillar": 0.08, "pillars": [-0.42],
        },
        "band": (0.45, 0.58), "two_tone": (0.17, 0.42), "plate_z": (0.3, 0.42),
        "wheel": {"width": 0.25, "rim_ratio": 0.64, "spokes": 8, "rim_colour": (0.2, 0.21, 0.24)},
        "features": [
            ("rect_headlights", {"x": 0.56, "z": 0.6, "size": (0.28, 0.12)}),
            ("grille", {"z": 0.5, "width": 0.62, "height": 0.12, "slats": 2}),
            ("bumpers", {"z_front": 0.28, "z_rear": 0.3, "height": 0.18}),
            ("fog_lights", {"x": 0.55, "z": 0.3}),
            ("tail_lights", {"x": 0.62, "z": 0.62, "size": (0.22, 0.2)}),
            ("roof_spoiler", {"depth": 0.3}),
            ("flares", {"width": 0.08, "thickness": 0.05}),
            ("exhaust", {"x": 0.5, "z": 0.22, "count": 2}),
            ("door_lines", {"ys": [0.8, -0.42], "z_low": 0.24, "z_high": 0.8}),
        ],
    },
    {
        "id": "sora_gt",
        "body": [
            (2.10, 0.76, 0.22, 0.56, 0.06, 0.05),
            (1.95, 0.88, 0.15, 0.68, 0.08, 0.05),
            (1.00, 0.90, 0.13, 0.80, 0.08, 0.05),
            (-1.10, 0.90, 0.13, 0.84, 0.08, 0.05),
            (-1.85, 0.88, 0.15, 0.84, 0.08, 0.05),
            (-2.05, 0.80, 0.20, 0.80, 0.06, 0.05),
        ],
        "arch": (0.42, 0.03),
        "cabin": {
            "profile": [(0.95, 0), (0.30, 1.27), (-0.68, 1.29), (-1.45, 0)],
            "width": (0.8, 0.63), "glass": [0, 2], "pillar": 0.08, "pillars": [-0.18],
        },
        "band": (0.42, 0.56), "two_tone": (0.16, 0.4), "plate_z": (0.3, 0.44),
        "wheel": {"width": 0.26, "rim_ratio": 0.66, "spokes": 6, "rim_colour": (0.86, 0.68, 0.22), "rim_metal": 0.5},
        "features": [
            ("rect_headlights", {"x": 0.58, "z": 0.53, "size": (0.3, 0.1)}),
            ("grille", {"z": 0.45, "width": 0.6, "height": 0.1, "slats": 2}),
            ("bumpers", {"z_front": 0.27, "z_rear": 0.3, "height": 0.16}),
            ("rally_lights", {"z": 0.5, "count": 4}),
            ("splitter", {"z": 0.17}),
            ("hood_scoop", {"y": 1.35}),
            ("roof_vent", {}),
            ("wing", {"y": -1.82, "z": 0.84, "span": 1.6, "height": 0.24}),
            ("tail_lights", {"x": 0.6, "z": 0.66, "size": (0.3, 0.1)}),
            ("mud_flaps", {}),
            ("exhaust", {"x": -0.55, "z": 0.22}),
            ("door_lines", {"ys": [0.88, -0.18], "z_low": 0.2, "z_high": 0.8}),
        ],
    },
    {
        "id": "hirvi_4x4",
        "body": [
            (2.05, 0.82, 0.38, 0.96, 0.05, 0.04),
            (1.92, 0.88, 0.32, 1.02, 0.05, 0.04),
            (-1.92, 0.90, 0.32, 1.04, 0.05, 0.04),
            (-2.05, 0.86, 0.36, 1.00, 0.05, 0.04),
        ],
        "arch": (0.46, 0.06),
        "cabin": {
            "profile": [(0.82, 0), (0.48, 1.68), (-1.92, 1.70), (-2.0, 0)],
            "width": (0.86, 0.8), "glass": [0, 2], "pillar": 0.09, "pillars": [-0.42, -1.25],
        },
        "band": (0.6, 0.76), "two_tone": (0.34, 0.58), "plate_z": (0.42, 0.5),
        "wheel": {"width": 0.34, "rim_ratio": 0.52, "spokes": 6, "rim_colour": (0.32, 0.34, 0.36)},
        "features": [
            ("grille_headlights", {"x": 0.55, "z": 0.74, "radius": 0.11, "width": 1.4, "height": 0.34}),
            ("bumpers", {"z_front": 0.42, "z_rear": 0.44, "height": 0.2, "depth": 0.16}),
            ("bull_bar", {"height": 0.6, "width": 1.3}),
            ("flares", {"width": 0.16, "thickness": 0.07}),
            ("roof_rack", {"bars": 5}),
            ("snorkel", {}),
            ("spare_wheel", {"z": 0.72}),
            ("side_steps", {"z": 0.3}),
            ("tail_lights", {"x": 0.7, "z": 0.72, "size": (0.12, 0.3)}),
            ("mud_flaps", {}),
            ("door_lines", {"ys": [0.78, -0.42, -1.25], "z_low": 0.36, "z_high": 1.0}),
        ],
    },
    {
        "id": "lumikko",
        "body": [
            (2.15, 0.72, 0.19, 0.40, 0.05, 0.05),
            (2.00, 0.88, 0.14, 0.56, 0.10, 0.05),
            (1.00, 0.92, 0.12, 0.71, 0.12, 0.05),
            (-1.20, 0.94, 0.12, 0.74, 0.12, 0.05),
            (-1.95, 0.92, 0.14, 0.76, 0.10, 0.05),
            (-2.12, 0.86, 0.20, 0.74, 0.06, 0.05),
        ],
        "arch": (0.39, 0.01),
        "cabin": {
            "profile": [(0.72, 0), (-0.08, 1.12), (-0.78, 1.13), (-1.58, 0)],
            "width": (0.78, 0.56), "glass": [0, 2], "pillar": 0.07, "pillars": [],
        },
        "band": (0.36, 0.48), "two_tone": (0.15, 0.34), "plate_z": (0.26, 0.4),
        "wheel": {"width": 0.27, "rim_ratio": 0.7, "spokes": 5, "rim_colour": (0.94, 0.94, 0.95)},
        "features": [
            ("slim_headlights", {"x": 0.55, "z": 0.44, "length": 0.4, "y_back": 0.22}),
            ("grille", {"z": 0.26, "width": 0.9, "height": 0.1, "slats": 1}),
            ("splitter", {"z": 0.16}),
            ("side_intakes", {"y": -0.7}),
            ("wing", {"y": -1.86, "z": 0.76, "span": 1.7, "height": 0.3, "chord": 0.4}),
            ("tail_lights", {"x": 0.55, "z": 0.62, "size": (0.42, 0.07)}),
            ("diffuser", {"z": 0.22}),
            ("exhaust", {"x": -0.07, "z": 0.24, "count": 2}),
            ("door_lines", {"ys": [0.6], "z_low": 0.2, "z_high": 0.66}),
        ],
    },
    {
        "id": "vanha_valtias",
        "body": [
            (2.30, 0.80, 0.24, 0.66, 0.05, 0.05),
            (2.15, 0.86, 0.18, 0.78, 0.07, 0.05),
            (0.75, 0.88, 0.16, 0.84, 0.07, 0.05),
            (-1.30, 0.88, 0.16, 0.86, 0.07, 0.05),
            (-2.10, 0.86, 0.18, 0.84, 0.07, 0.05),
            (-2.26, 0.80, 0.24, 0.80, 0.05, 0.05),
        ],
        "arch": (0.42, 0.04),
        "cabin": {
            "profile": [(0.62, 0), (0.12, 1.32), (-0.95, 1.34), (-1.52, 0)],
            "width": (0.82, 0.68), "glass": [0, 2], "pillar": 0.08, "pillars": [-0.42],
        },
        "band": (0.46, 0.6), "two_tone": (0.19, 0.44), "plate_z": (0.32, 0.4),
        "wheel": {"width": 0.25, "rim_ratio": 0.6, "spokes": 8, "rim_colour": (0.82, 0.84, 0.88),
                  "rim_metal": 0.6, "whitewall": True},
        "features": [
            ("round_headlights", {"x": 0.66, "z": 0.62, "radius": 0.09, "pairs": 2, "spacing": 0.24}),
            ("chrome_grille", {"z": 0.5, "width": 0.62, "height": 0.28}),
            ("chrome_bumpers", {"z_front": 0.3, "z_rear": 0.32}),
            ("hood_ornament", {}),
            ("side_trim", {"z": 0.6}),
            ("tail_lights", {"x": 0.66, "z": 0.62, "size": (0.14, 0.14), "round_lamps": True}),
            ("exhaust", {"x": 0.5, "z": 0.24}),
            ("door_lines", {"ys": [0.6, -0.42], "z_low": 0.22, "z_high": 0.84}),
        ],
    },
]


def build_car(spec, materials):
    collection = bpy.data.collections.new(spec["id"])
    bpy.context.scene.collection.children.link(collection)
    body = build_body(spec, collection, materials)
    details, lamps = build_details(spec, collection, materials)
    wheel = build_wheel(spec, collection, materials)
    patterns = build_patterns(spec, body, collection, materials[MAT["Decal"]])
    for index, lamp in enumerate(sorted(lamps, key=lambda p: p[0])[:1] + sorted(lamps, key=lambda p: -p[0])[:1]):
        empty = bpy.data.objects.new("Headlamp_" + ("L" if index == 0 else "R"), None)
        empty.location = lamp
        collection.objects.link(empty)
    return collection


def export_car(collection, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_materials="EXPORT",
    )
    # Free the plain names (Body, Wheel, Pattern_...) for the next car.
    for obj in collection.objects:
        obj.name = collection.name + "__" + obj.name


def render_preview(collections, path):
    """All cars in a row, seen from the game's camera angle and from behind."""
    scene = bpy.context.scene
    spacing = 3.4
    for index, collection in enumerate(collections):
        for obj in collection.objects:
            obj.location.x += index * spacing
            if "Pattern_" in obj.name and "Pattern_STRIPE" not in obj.name:
                obj.hide_render = True
        # Show the four wheels the game would mount.
        wheel = next(obj for obj in collection.objects if obj.name.endswith("Wheel"))
        for x in (-WHEEL_X, WHEEL_X):
            for y in (AXLE_Y, -AXLE_Y):
                copy = wheel.copy()
                copy.location = (x + index * spacing, y, WHEEL_Z)
                copy.rotation_euler = (0, math.radians(90), 0)
                collection.objects.link(copy)
        wheel.hide_render = True
    centre = Vector(((len(collections) - 1) * spacing / 2, 0, 0.6))
    # Blue paint in the preview so the white decals show.
    bpy.data.materials["Paint"].diffuse_color = (0.15, 0.38, 0.85, 1.0)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 900
    scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.12, 0.13, 0.18)
    camera_data = bpy.data.cameras.new("Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = len(collections) * spacing + 1.0
    camera = bpy.data.objects.new("Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    root, ext = os.path.splitext(path)
    for suffix, yaw in (("", 225.0), ("_rear", 45.0)):
        direction = Matrix.Rotation(math.radians(yaw), 3, "Z") @ Vector((0, 1, 0))
        offset = Vector((direction.x, direction.y, 0)).normalized() * 30 + Vector((0, 0, 21))
        camera.location = centre + offset
        camera.rotation_euler = (centre - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = root + suffix + ext
        bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    project = args[0] if args else os.getcwd()
    preview = args[1] if len(args) > 1 else ""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials = make_materials()
    out_dir = os.path.join(project, "cars", "models")
    os.makedirs(out_dir, exist_ok=True)
    collections = []
    for spec in CARS:
        collection = build_car(spec, materials)
        export_car(collection, os.path.join(out_dir, spec["id"] + ".glb"))
        collections.append(collection)
        print("BUILT", spec["id"])
    if preview:
        render_preview(collections, preview)


main()
