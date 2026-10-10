"""Model the Viandante (the player) for the character sheet.

    blender -b --factory-startup --python tools/art/build_pilgrim.py -- [--preview DIR] [--blend FILE]

A low-poly sculpt of the board sprite: ivory hooded cloak open at the front,
charcoal tunic with the crimson cross, belt and boots, a raised iron lantern
with cold cyan glass, and a shadowed face with two glowing eyes. Modelled in
Blender (Z up, facing -Y), with subdivision on cloth, then exported in the
board's ODM format (see build_walls.py) as game space (Y up, facing +Z).
"""
import math
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "pilgrim.odm")

IVORY = (222, 208, 178)
IVORY_SHADE = (176, 160, 132)
CHARCOAL = (34, 36, 44)
CHARCOAL_LIGHT = (54, 57, 68)
CRIMSON = (178, 28, 34)
LEATHER = (92, 58, 36)
LEATHER_DARK = (58, 37, 25)
IRON = (26, 29, 36)
IRON_EDGE = (70, 76, 90)
BRASS = (150, 118, 64)
GLASS = (90, 200, 240)
VOID = (9, 12, 20)
EYE = (150, 236, 255)

parts = []  # (object, colour, smooth)


def new_object(name, bm, colour, smooth=False, subsurf=0):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    if subsurf:
        mod = obj.modifiers.new("sub", 'SUBSURF')
        mod.levels = subsurf
        mod.render_levels = subsurf
    parts.append((obj, colour, smooth))
    return obj


def transformed(bm, matrix):
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return bm


def box(name, centre, size, colour, bevel=0.0, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect='EDGES', profile=0.5)
    if rot:
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    return new_object(name, bm, colour)


def sphere(name, centre, radius, colour, scale=(1, 1, 1), segments=12, rings=8, smooth=True):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    return new_object(name, bm, colour, smooth)


def frustum(name, bottom, top, r_bottom, r_top, colour, segments=16, smooth=True, cap=True, arc=None,
            subsurf=0, flare=None, folds=None):
    """A tapered tube from `bottom` to `top`; `arc` (start, end degrees) leaves it open."""
    bm = bmesh.new()
    rings = 6
    a0, a1 = (0.0, 360.0) if arc is None else arc
    closed = arc is None
    count = segments if closed else segments + 1
    grid = []
    for ri in range(rings + 1):
        t = ri / rings
        r = r_bottom + (r_top - r_bottom) * t
        if flare:
            r += flare * (1 - t) ** 3
        c = Vector(bottom).lerp(Vector(top), t)
        row = []
        for si in range(count):
            a = math.radians(a0 + (a1 - a0) * si / (segments if closed else segments))
            rr = r
            if folds:
                # Cloth folds deepen toward the hem.
                rr *= 1 + folds[1] * math.sin(folds[0] * a) * (1 - t) ** 0.7
            row.append(bm.verts.new((c.x + rr * math.cos(a), c.y + rr * math.sin(a), c.z)))
        grid.append(row)
    for ri in range(rings):
        for si in range(count if closed else count - 1):
            sj = (si + 1) % count
            bm.faces.new((grid[ri][si], grid[ri][sj], grid[ri + 1][sj], grid[ri + 1][si]))
    if cap and closed:
        bm.faces.new(list(reversed(grid[0])))
        bm.faces.new(grid[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if not closed:
        # Cloth has two sides: give it a little thickness.
        bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=0.018)
    return new_object(name, bm, colour, smooth, subsurf)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Boots.
    for sx in (-1, 1):
        box("boot", (sx * 0.13, -0.05, 0.06), (0.15, 0.24, 0.12), LEATHER_DARK, bevel=0.03)
        box("cuff", (sx * 0.13, 0.0, 0.14), (0.14, 0.15, 0.05), LEATHER, bevel=0.015)
    # Robe: a flared charcoal skirt from the waist to the hem.
    frustum("robe", (0, 0, 0.12), (0, 0, 0.82), 0.33, 0.22, CHARCOAL, 18, flare=0.06)
    box("robe_panel", (0, -0.25, 0.47), (0.14, 0.02, 0.66), CHARCOAL_LIGHT, bevel=0.006,
        rot=Matrix.Rotation(math.radians(-8), 3, 'X'))
    # Tunic and the crimson cross.
    frustum("torso", (0, 0, 0.8), (0, 0, 1.32), 0.23, 0.25, CHARCOAL, 16)
    box("cross_v", (0, -0.245, 1.12), (0.035, 0.02, 0.2), CRIMSON)
    box("cross_h", (0, -0.245, 1.15), (0.14, 0.02, 0.035), CRIMSON)
    # Belt with a brass buckle.
    frustum("belt", (0, 0, 0.8), (0, 0, 0.88), 0.245, 0.24, LEATHER, 16)
    box("buckle", (0, -0.245, 0.84), (0.07, 0.025, 0.06), BRASS, bevel=0.008)
    box("pouch", (0.17, -0.18, 0.76), (0.09, 0.07, 0.1), LEATHER_DARK, bevel=0.02)
    # The ivory cloak: open at the front, falling from the shoulders.
    frustum("cloak", (0, 0.03, 0.08), (0, 0.0, 1.36), 0.47, 0.28, IVORY, 24, arc=(-45, 225), subsurf=1,
            folds=(9, 0.07))
    frustum("mantle", (0, 0.0, 1.1), (0, 0.0, 1.42), 0.38, 0.25, IVORY_SHADE, 24, arc=(-70, 250), subsurf=1,
            folds=(7, 0.05))
    # Hood: a pointed cowl with the face sunk in shadow.
    hood = bmesh.new()
    bmesh.ops.create_uvsphere(hood, u_segments=18, v_segments=12, radius=0.21)
    for v in hood.verts:
        z = v.co.z
        if z > 0:
            # A pointed cowl, its tip leaning back.
            k = (z / 0.21) ** 1.4
            v.co.x *= 1 - 0.6 * k
            v.co.y *= 1 - 0.6 * k
            v.co.z = z * 1.6
            v.co.y += 0.06 * k
        else:
            # The hem of the hood drapes onto the shoulders.
            k = -z / 0.21
            v.co.x *= 1 + 0.55 * k
            v.co.y *= 1 + 0.35 * k
            v.co.z = z * 0.9
    # Open the cowl at the front, then give the cloth its thickness.
    opening = [f for f in hood.faces
               if (lambda c: c.y < -0.06 and abs(c.x) < 0.125 and -0.13 < c.z < 0.17)(f.calc_center_median())]
    bmesh.ops.delete(hood, geom=opening, context='FACES')
    bmesh.ops.solidify(hood, geom=list(hood.faces), thickness=-0.022)
    bmesh.ops.translate(hood, vec=(0, 0.02, 1.52), verts=hood.verts)
    new_object("hood", hood, IVORY, True, 1)
    sphere("face", (0, -0.02, 1.52), 0.15, VOID, scale=(0.95, 0.9, 1.1))
    for sx in (-1, 1):
        sphere("eye", (sx * 0.048, -0.15, 1.53), 0.02, EYE, scale=(1.3, 0.6, 0.75), segments=8, rings=6)
    # Left arm hangs, the gloved hand gathering the cloak.
    frustum("sleeve_l", (-0.27, -0.16, 0.9), (-0.26, -0.04, 1.3), 0.075, 0.088, CHARCOAL, 10)
    sphere("glove_l", (-0.26, -0.2, 0.85), 0.066, LEATHER, scale=(1, 1, 1.1))
    # Right arm raised forward with the lantern.
    shoulder = Vector((0.27, -0.05, 1.3))
    elbow = Vector((0.42, -0.2, 1.1))
    hand = Vector((0.46, -0.34, 1.22))
    frustum("upper_r", shoulder, elbow, 0.085, 0.075, CHARCOAL, 10)
    frustum("fore_r", elbow, hand, 0.075, 0.06, CHARCOAL, 10)
    sphere("glove_r", hand, 0.062, LEATHER)
    lantern = hand + Vector((0, -0.02, -0.24))
    frustum("ring", hand + Vector((0, -0.02, -0.06)), hand + Vector((0, -0.02, -0.03)), 0.03, 0.03, IRON_EDGE, 8)
    frustum("lantern_cap", lantern + Vector((0, 0, 0.11)), lantern + Vector((0, 0, 0.19)), 0.085, 0.02, IRON, 6, smooth=False)
    frustum("lantern_top", lantern + Vector((0, 0, 0.09)), lantern + Vector((0, 0, 0.115)), 0.09, 0.09, IRON_EDGE, 6, smooth=False)
    frustum("lantern_glass", lantern + Vector((0, 0, -0.08)), lantern + Vector((0, 0, 0.09)), 0.06, 0.06, GLASS, 6, smooth=False)
    frustum("lantern_base", lantern + Vector((0, 0, -0.12)), lantern + Vector((0, 0, -0.08)), 0.08, 0.09, IRON_EDGE, 6, smooth=False)
    for i in range(6):
        a = math.radians(30 + 60 * i)
        c = lantern + Vector((math.cos(a) * 0.075, math.sin(a) * 0.075, 0))
        box("bar", c, (0.014, 0.014, 0.2), IRON)
    sphere("flame", lantern, 0.03, (230, 250, 255), segments=8, rings=6)


def to_game(co):
    return (co.x, co.z, -co.y)


def export(path):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    vertices = []
    for obj, colour, smooth in parts:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        mesh.calc_normals_split()
        for tri in mesh.loop_triangles:
            for li in tri.loops:
                loop = mesh.loops[li]
                co = mesh.vertices[loop.vertex_index].co
                n = loop.normal if smooth else tri.normal
                vertices.append((to_game(co), to_game(n), colour))
        evaluated.to_mesh_clear()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"ODM1")
        f.write(struct.pack("<I", 1))
        f.write(b"pilgrim".ljust(24, b"\0"))
        f.write(struct.pack("<II", 0, len(vertices)))
        f.write(struct.pack("<I", len(vertices)))
        for (x, y, z), (nx, ny, nz), (r, g, b) in vertices:
            f.write(struct.pack("<fffbbbbBBBB", x, y, z, int(round(nx * 127)), int(round(ny * 127)),
                                int(round(nz * 127)), 0, r, g, b, 255))
    print("PILGRIM", len(vertices) // 3, "triangles")
    print("WROTE", path)


def preview(folder):
    for obj, colour, _ in parts:
        mat = bpy.data.materials.new(obj.name)
        mat.diffuse_color = (colour[0] / 255, colour[1] / 255, colour[2] / 255, 1)
        obj.data.materials.append(mat)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.show_cavity = True
    scene.render.resolution_x, scene.render.resolution_y = 800, 1000
    scene.world = bpy.data.worlds.new("w")
    cam = bpy.data.cameras.new("cam")
    cam.lens = 70
    cam_obj = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (1.6, -3.6, 1.55)
    cam_obj.rotation_euler = (Vector((0, 0, 0.95)) - cam_obj.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam_obj
    os.makedirs(folder, exist_ok=True)
    scene.render.filepath = os.path.join(folder, "pilgrim_preview.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build()
    if "--no-write" not in argv:
        export(OUT)
    if "--blend" in argv:
        bpy.ops.wm.save_as_mainfile(filepath=argv[argv.index("--blend") + 1])
    if "--preview" in argv:
        preview(argv[argv.index("--preview") + 1])


main()
