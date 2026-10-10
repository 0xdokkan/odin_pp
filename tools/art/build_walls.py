"""Model the gothic wall kit in Blender and export it for the board renderer.

    blender -b --factory-startup --python tools/art/build_walls.py -- [--preview DIR] [--blend FILE]

Every piece is modelled with bmesh in game space (y up, one unit per cell,
origin at the bottom centre of the cell) and faces +Z (grid +y); the
renderer turns it toward each side. Colours are vertex colours from the board
palette, so the existing resin shader lights the kit exactly like the old
procedural blocks.

Output: assets/models/gothic-walls.odm, a flat triangle list per piece:
    "ODM1", u32 piece_count,
    piece_count x (char name[24], u32 first_vertex, u32 vertex_count),
    u32 vertex_count, vertex_count x (f32 x, y, z, i8 nx, ny, nz, pad, u8 r, g, b, a)
"""
import math
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "gothic-walls.odm")

H = 1.58          # DIORAMA_WALL_HEIGHT
CORE = 0.40       # core half-width; faces and links fill 0.40..0.50
FACE = 0.50

STONE_DARK = (21, 30, 43)
STONE = (30, 41, 57)
STONE_MID = (41, 55, 74)
STONE_LIGHT = (58, 75, 98)
CAP = (65, 83, 107)
CAP_EDGE = (80, 101, 128)
VOID = (7, 11, 19)
BONE = (128, 128, 118)
BONE_DIM = (92, 96, 96)
GLASS = (34, 104, 146)
GLASS_HOT = (96, 190, 228)
IRON = (17, 20, 27)
IRON_EDGE = (46, 52, 64)
FLAME = (150, 226, 248)


class Piece:
    def __init__(self, name):
        self.name = name
        self.parts = []   # (bmesh, colour, smooth)

    # Axis-aligned box, optionally with bevelled edges that catch the light.
    # Faces that can never be seen (against the floor, the wall behind, the
    # cap above) are dropped: every vertex is submitted each frame.
    def box(self, mn, mx, colour, bevel=0.0, skip=("bottom", "back")):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        size = Vector(mx) - Vector(mn)
        centre = (Vector(mx) + Vector(mn)) * 0.5
        for v in bm.verts:
            v.co = Vector((v.co.x * size.x, v.co.y * size.y, v.co.z * size.z)) + centre
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45),
                            segments=1, affect='EDGES', profile=0.5)
        hidden = []
        for f in bm.faces:
            c = f.calc_center_median()
            if "bottom" in skip and f.normal.y < -0.99 and c.y < mn[1] + 1e-4:
                hidden.append(f)
            if "back" in skip and f.normal.z < -0.99 and c.z < mn[2] + 1e-4:
                hidden.append(f)
            if "top" in skip and f.normal.y > 0.99 and c.y > mx[1] - 1e-4:
                hidden.append(f)
        if hidden:
            bmesh.ops.delete(bm, geom=hidden, context='FACES_ONLY')
        self.parts.append((bm, colour, False))

    # A 2D outline in the face plane (x, y) extruded between depths z0..z1.
    def prism(self, outline, z0, z1, colour):
        bm = bmesh.new()
        verts = [bm.verts.new((x, y, z0)) for x, y in outline]
        face = bm.faces.new(verts)
        bmesh.ops.recalc_face_normals(bm, faces=[face])
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
        for v in moved:
            v.co.z = z1
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        # The back cap lies against the recessed field.
        back = [f for f in bm.faces if f.normal.z < -0.99]
        bmesh.ops.delete(bm, geom=back, context='FACES_ONLY')
        self.parts.append((bm, colour, False))

    # Vertical shaft.
    def column(self, x, z, y0, y1, radius, colour, segments=8):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                              radius1=radius, radius2=radius, depth=y1 - y0)
        for v in bm.verts:
            v.co = Vector((v.co.x + x, v.co.z + (y0 + y1) * 0.5, v.co.y + z))
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        self.parts.append((bm, colour, True))

    # Disc or ring in the face plane (axis along z).
    def ring(self, cx, cy, r_in, r_out, z0, z1, colour, segments=16):
        outline_out = [(cx + r_out * math.cos(2 * math.pi * i / segments),
                        cy + r_out * math.sin(2 * math.pi * i / segments)) for i in range(segments)]
        if r_in <= 0:
            self.prism(outline_out, z0, z1, colour)
            return
        # Build the annulus as quads between two circles, then extrude.
        bm = bmesh.new()
        outer = [bm.verts.new((x, y, z0)) for x, y in outline_out]
        inner = [bm.verts.new((cx + r_in * math.cos(2 * math.pi * i / segments),
                               cy + r_in * math.sin(2 * math.pi * i / segments), z0)) for i in range(segments)]
        faces = []
        for i in range(segments):
            j = (i + 1) % segments
            faces.append(bm.faces.new((outer[i], outer[j], inner[j], inner[i])))
        bmesh.ops.recalc_face_normals(bm, faces=faces)
        ext = bmesh.ops.extrude_face_region(bm, geom=faces)
        for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
            v.co.z = z1
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        back = [f for f in bm.faces if f.normal.z < -0.99]
        bmesh.ops.delete(bm, geom=back, context='FACES_ONLY')
        self.parts.append((bm, colour, False))

    def triangles(self):
        out = []
        for bm, colour, smooth in self.parts:
            bm.normal_update()
            tri = bm.copy()
            bmesh.ops.triangulate(tri, faces=list(tri.faces))
            tri.normal_update()
            for face in tri.faces:
                for loop in face.loops:
                    n = loop.vert.normal if smooth and abs(face.normal.y) < 0.9 else face.normal
                    out.append((tuple(loop.vert.co), tuple(n), colour))
            tri.free()
        return out


def pointed_arch(cx, spring, half, segments=6):
    """Equilateral pointed arch from the left to the right springing point."""
    r = 2 * half
    pts = []
    for i in range(segments + 1):
        a = math.radians(180 - 60 * i / segments)
        pts.append((cx + half + r * math.cos(a), spring + r * math.sin(a)))
    for i in range(1, segments + 1):
        a = math.radians(60 - 60 * i / segments)
        pts.append((cx - half + r * math.cos(a), spring + r * math.sin(a)))
    return pts


def arch_band(cx, bottom, spring, half_in, width, segments=6):
    """An inverted U: two jambs and a pointed arch, `width` thick."""
    outer = pointed_arch(cx, spring, half_in + width, segments)
    inner = pointed_arch(cx, spring, half_in, segments)
    pts = [(cx - half_in - width, bottom)] + outer + [(cx + half_in + width, bottom), (cx + half_in, bottom)]
    pts += list(reversed(inner)) + [(cx - half_in, bottom)]
    return pts


def arch_opening(cx, bottom, spring, half, segments=6):
    return [(cx - half, bottom)] + pointed_arch(cx, spring, half, segments) + [(cx + half, bottom)]


# --------------------------------------------------------------------------
# Structural pieces.

def core():
    p = Piece("core")
    p.box((-CORE, 0, -CORE), (CORE, H, CORE), STONE_DARK, skip=("bottom", "top"))
    return p


def link():
    # Toward a wall neighbour: plain stone so long walls read as one mass.
    p = Piece("link")
    p.box((-CORE, 0, CORE), (CORE, H, FACE), STONE_DARK, skip=("bottom", "top", "back"))
    return p


def post():
    p = Piece("post")
    p.box((CORE, 0, CORE), (FACE, H, FACE), STONE_DARK, skip=("bottom", "top", "back"))
    return p


def pilaster():
    # A convex corner: a clustered shaft on a stepped base, with a capital.
    p = Piece("pilaster")
    c = (CORE + FACE) * 0.5
    p.box((CORE - 0.01, 0, CORE - 0.01), (FACE, 0.2, FACE), STONE_MID, bevel=0.012)
    p.column(c, c, 0.2, H - 0.2, 0.046, STONE_LIGHT)
    p.column(c - 0.02, c + 0.028, 0.2, H - 0.2, 0.016, STONE_MID, segments=6)
    p.column(c + 0.028, c - 0.02, 0.2, H - 0.2, 0.016, STONE_MID, segments=6)
    p.box((CORE - 0.01, H - 0.2, CORE - 0.01), (FACE, H - 0.13, FACE), STONE_MID, bevel=0.01)
    p.box((CORE, H - 0.13, CORE), (FACE, H, FACE), STONE, bevel=0.008)
    return p


def face_frame(p):
    """Plinth, recessed field and cornice shared by every decorated face."""
    p.box((-CORE, 0, CORE), (CORE, 0.17, FACE), STONE_MID, bevel=0.014)
    p.box((-CORE, 0.17, CORE), (CORE, H - 0.16, CORE + 0.025), STONE)
    p.box((-CORE, H - 0.16, CORE), (CORE, H - 0.1, FACE - 0.012), STONE_MID)
    p.box((-CORE, H - 0.1, CORE), (CORE, H, FACE), STONE_LIGHT, bevel=0.012, skip=("bottom", "back", "top"))


def face_lancet():
    # Twin lancets under a pointed arch, a roundel in the head, hood mould.
    p = Piece("face_lancet")
    face_frame(p)
    for s in (-1, 1):
        p.box((s * CORE if s < 0 else CORE - 0.065, 0.17, CORE), (s * (CORE - 0.065) if s < 0 else CORE, H - 0.16, FACE),
              STONE_MID, bevel=0.01)
    spring, half = 0.86, 0.23
    p.prism(arch_opening(0, 0.17, spring, half), CORE + 0.026, CORE + 0.03, VOID)
    p.prism(arch_band(0, 0.17, spring, half, 0.045), CORE + 0.025, FACE - 0.006, STONE_LIGHT)
    p.prism(arch_band(0, spring - 0.02, spring + 0.0, half + 0.045, 0.022, 5), CORE + 0.025, FACE, CAP_EDGE)
    p.box((-0.014, 0.17, CORE + 0.025), (0.014, 0.98, FACE - 0.02), BONE_DIM)
    for cx in (-0.115, 0.115):
        p.prism(arch_band(cx, 0.86, 0.9, 0.088, 0.02, 4), CORE + 0.025, FACE - 0.02, BONE_DIM)
    p.ring(0, 1.16, 0.05, 0.075, CORE + 0.025, FACE - 0.016, BONE, 12)
    p.ring(0, 1.16, 0, 0.05, CORE + 0.026, CORE + 0.034, GLASS, 12)
    return p


def face_buttress():
    # A stepped buttress between two arrow-slit lancets.
    p = Piece("face_buttress")
    face_frame(p)
    p.box((-0.12, 0.17, CORE + 0.02), (0.12, 0.92, FACE), STONE_MID, bevel=0.014)
    p.box((-0.095, 0.92, CORE + 0.02), (0.095, 1.24, FACE - 0.02), STONE_MID, bevel=0.012)
    p.prism([(-0.095, 1.24), (0.095, 1.24), (0.0, 1.36)], CORE + 0.02, FACE - 0.02, STONE_LIGHT)
    p.box((-0.13, 0.9, CORE + 0.02), (0.13, 0.94, FACE), STONE_LIGHT, bevel=0.008)
    for cx in (-0.27, 0.27):
        p.prism(arch_opening(cx, 0.46, 1.02, 0.035, 3), CORE + 0.026, CORE + 0.03, VOID)
        p.prism(arch_band(cx, 0.44, 1.02, 0.035, 0.02, 3), CORE + 0.025, FACE - 0.02, STONE_LIGHT)
    return p


def face_rose():
    # A rose window of cold glass with eight spokes over a small arcade.
    p = Piece("face_rose")
    face_frame(p)
    cy, r = 1.0, 0.24
    p.ring(0, cy, 0, r, CORE + 0.026, CORE + 0.03, GLASS, 16)
    p.ring(0, cy, r, r + 0.045, CORE + 0.025, FACE - 0.006, STONE_LIGHT, 16)
    for i in range(8):
        a = math.pi * 2 * i / 8
        d = (math.cos(a), math.sin(a))
        t = (-d[1], d[0])
        w = 0.011
        a0, a1 = 0.05, r
        quad = [(d[0] * a0 + t[0] * w, cy + d[1] * a0 + t[1] * w), (d[0] * a1 + t[0] * w, cy + d[1] * a1 + t[1] * w),
                (d[0] * a1 - t[0] * w, cy + d[1] * a1 - t[1] * w), (d[0] * a0 - t[0] * w, cy + d[1] * a0 - t[1] * w)]
        p.prism(quad, CORE + 0.025, FACE - 0.02, BONE)
    p.ring(0, cy, 0, 0.055, CORE + 0.025, FACE - 0.015, BONE, 10)
    p.ring(0, cy, 0, 0.026, CORE + 0.025, FACE - 0.01, GLASS_HOT, 8)
    for cx in (-0.17, 0.17):
        p.prism(arch_opening(cx, 0.24, 0.5, 0.07, 3), CORE + 0.026, CORE + 0.03, VOID)
        p.prism(arch_band(cx, 0.17, 0.5, 0.07, 0.022, 3), CORE + 0.025, FACE - 0.02, STONE_MID)
    return p


def face_ashlar():
    # Coursed ashlar: offset blocks with fine joints and slight relief.
    p = Piece("face_ashlar")
    p.box((-CORE, 0, CORE), (CORE, 0.17, FACE), STONE_MID, bevel=0.014)
    p.box((-CORE, 0.17, CORE), (CORE, H - 0.1, CORE + 0.02), VOID)
    rows = 7
    height = (H - 0.27) / rows
    seed = 0
    for row in range(rows):
        y0 = 0.17 + row * height
        offset = 0.0 if row % 2 == 0 else 0.13
        x = -CORE - offset
        while x < CORE - 0.01:
            w = 0.26
            a, b = max(x, -CORE), min(x + w, CORE)
            if b - a > 0.04:
                seed = (seed * 1103515245 + 12345) & 0x7fffffff
                depth = FACE - 0.004 - (seed % 3) * 0.006
                tone = STONE if seed % 5 else STONE_MID
                p.box((a + 0.006, y0 + 0.006, CORE + 0.02), (b - 0.006, y0 + height - 0.006, depth), tone)
            x += w
    p.box((-CORE, H - 0.1, CORE), (CORE, H, FACE), STONE_LIGHT, bevel=0.012)
    return p


def merlons():
    # Crenellated parapet along an exposed edge, three merlons per cell.
    p = Piece("merlons")
    top = H + 0.06
    for cx in (-1 / 3, 0, 1 / 3):
        p.box((cx - 0.095, top, CORE - 0.04), (cx + 0.095, top + 0.13, FACE), CAP, skip=("bottom",))
        p.box((cx - 0.105, top + 0.13, CORE - 0.05), (cx + 0.105, top + 0.155, FACE), CAP_EDGE, bevel=0.008, skip=("bottom",))
    return p


def cap():
    # The top of a wall, and the cut face when a near wall is retracted.
    p = Piece("cap")
    p.box((-0.5, 0, -0.5), (0.5, 0.06, 0.5), CAP, bevel=0.012)
    p.box((-0.36, 0.06, -0.36), (0.36, 0.068, 0.36), CAP_EDGE)
    return p


def cut_cap():
    # The section of a retracted near wall: darker stone, a sunken panel and
    # a carved cross, so the cut reads as masonry rather than a lit tile.
    p = Piece("cut_cap")
    p.box((-0.5, 0, -0.5), (0.5, 0.045, 0.5), STONE_MID, bevel=0.01)
    p.box((-0.34, 0.045, -0.34), (0.34, 0.05, 0.34), VOID)
    p.box((-0.3, 0.05, -0.025), (0.3, 0.062, 0.025), STONE_LIGHT)
    p.box((-0.025, 0.05, -0.3), (0.025, 0.062, 0.3), STONE_LIGHT)
    p.box((-0.06, 0.05, -0.06), (0.06, 0.068, 0.06), CAP_EDGE, bevel=0.006)
    return p


def sconce():
    # An iron lantern sconce; the origin is the flame (the board's lamp light).
    p = Piece("sconce")
    back = 0.5 - 0.47  # from the flame to the wall face
    p.prism([(-0.06, -0.16), (0.06, -0.16), (0.075, 0.06), (0.0, 0.17), (-0.075, 0.06)], -back - 0.004, -back + 0.018, IRON)
    p.box((-0.015, -0.13, -back), (0.015, -0.1, 0.03), IRON_EDGE)
    p.box((-0.07, -0.12, -0.04), (0.07, -0.08, 0.1), IRON, bevel=0.008)
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box((sx * 0.055 - 0.008, -0.08, sz * 0.055 - 0.008 + 0.03), (sx * 0.055 + 0.008, 0.1, sz * 0.055 + 0.008 + 0.03), IRON_EDGE)
    p.ring(0, 0.0, 0, 0.035, 0.0, 0.06, FLAME, 8)
    p.box((-0.075, 0.1, -0.045), (0.075, 0.13, 0.105), IRON, bevel=0.008)
    p.prism([(-0.05, 0.13), (0.05, 0.13), (0.0, 0.2)], -0.01, 0.07, IRON_EDGE)
    return p


PIECES = [core, link, post, pilaster, face_lancet, face_buttress, face_rose, face_ashlar, merlons, cap, cut_cap, sconce]


def export(pieces, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    table = []
    vertices = []
    for piece in pieces:
        tris = piece.triangles()
        table.append((piece.name, len(vertices), len(tris)))
        vertices.extend(tris)
    with open(path, "wb") as f:
        f.write(b"ODM1")
        f.write(struct.pack("<I", len(table)))
        for name, first, count in table:
            f.write(name.encode("ascii").ljust(24, b"\0"))
            f.write(struct.pack("<II", first, count))
        f.write(struct.pack("<I", len(vertices)))
        for (x, y, z), (nx, ny, nz), (r, g, b) in vertices:
            f.write(struct.pack("<fffbbbbBBBB", x, y, z,
                                int(round(nx * 127)), int(round(ny * 127)), int(round(nz * 127)), 0, r, g, b, 255))
    for name, first, count in table:
        print("PIECE", name, count // 3, "triangles")
    print("WROTE", path, len(vertices), "vertices")


# --------------------------------------------------------------------------
# Preview: assemble a little room corner in a Blender scene and render it.

def to_blender(co):
    return (co[0], -co[2], co[1])


def add_object(name, tris, transform):
    mesh = bpy.data.meshes.new(name)
    verts = []
    faces = []
    colours = []
    for i in range(0, len(tris), 3):
        face = []
        for (co, n, colour) in tris[i:i + 3]:
            verts.append(to_blender(transform(co)))
            colours.append(colour)
            face.append(len(verts) - 1)
        faces.append(face)
    mesh.from_pydata(verts, [], faces)
    attr = mesh.color_attributes.new("col", 'BYTE_COLOR', 'POINT')
    for i, c in enumerate(colours):
        attr.data[i].color = (c[0] / 255 * 2.2, c[1] / 255 * 2.2, c[2] / 255 * 2.2, 1)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def rotation(side):
    def f(co):
        x, y, z = co
        if side == 0:
            return (x, y, z)
        if side == 1:
            return (z, y, -x)
        if side == 2:
            return (-x, y, -z)
        return (-z, y, x)
    return f


def preview(pieces, folder):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    by_name = {p.name: p.triangles() for p in pieces}
    # An L-shaped wall run: three cells along x, one turning along z.
    walls = [(0, 0), (1, 0), (2, 0), (2, 1)]
    faces = ["face_lancet", "face_rose", "face_buttress", "face_ashlar"]
    for i, (cx, cz) in enumerate(walls):
        def at(f, cx=cx, cz=cz):
            return lambda co: (lambda r: (r[0] + cx, r[1], r[2] + cz))(f(co))
        add_object("core", by_name["core"], at(rotation(0)))
        add_object("cap", by_name["cap"], at(lambda co: (co[0], co[1] + H, co[2])))
        for side, (dx, dz) in enumerate(((0, 1), (1, 0), (0, -1), (-1, 0))):
            neighbour = (cx + dx, cz + dz)
            if neighbour in walls:
                add_object("link", by_name["link"], at(rotation(side)))
            elif side in (0, 3) or (cx, cz) == (2, 1) and side == 1:
                add_object(faces[i], by_name[faces[i]], at(rotation(side)))
                add_object("merlons", by_name["merlons"], at(rotation(side)))
            else:
                add_object("link", by_name["link"], at(rotation(side)))
        for corner in range(4):
            add_object("post", by_name["post"], at(rotation(corner)))
    add_object("pilaster", by_name["pilaster"], lambda co: (lambda r: (r[0], r[1], r[2]))(rotation(3)(co)))
    add_object("sconce", by_name["sconce"], lambda co: (co[0] + 1, co[1] + H * 0.58, co[2] + 0.47))
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'VERTEX'
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = True
    scene.render.resolution_x, scene.render.resolution_y = 1280, 800
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("w")
    cam = bpy.data.cameras.new("cam")
    cam.lens = 50
    cam_obj = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (4.6, -5.4, 3.4)
    direction = Vector((1.2, 0.0, 0.7)) - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam_obj
    os.makedirs(folder, exist_ok=True)
    scene.render.filepath = os.path.join(folder, "walls_preview.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scene.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    pieces = [build() for build in PIECES]
    if "--no-write" not in argv:
        export(pieces, OUT)
    if "--preview" in argv:
        preview(pieces, argv[argv.index("--preview") + 1])


main()
