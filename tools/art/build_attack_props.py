"""Draw the paper props of the board's blows.

    python tools/art/build_attack_props.py

(Any Python 3 will do, Blender's included: the script uses only the standard
library.)

The weapons the living cards swing, the bolts, bomb and embers they throw and
the paper bits of an impact (src/render/attack_fx.odin); the flames of the
ground's fires, the flask a pool is thrown in, its drops and the cinders a
fire throws (src/render/ground_fx.odin); the Canna da Pesca's rod, its
bobber, the water's drops, the bite's "!" and what it catches: a fish, an
apple, bread, cheese, meat or a card (src/render/fishing.odin); the stone dust
of the Lazzo's smash into a wall (src/render/lasso.odin). Each prop is pixel
art written here as rows of palette letters, in the figures' own colours;
the script adds its ink outline (every empty texel touching the body, 8-way)
and closes hollows of a texel or two. Its paper is an exact distance field
from the print, cut by the living cards' own shader (gfx
FLIPBOOK_PAPER_FRAGMENT) on their whiter sheet. A prop's paper is narrower
than a card's: its field is stored stretched, so the shader's 5.5 px of paper
are `paper` texels around the print.

Writes, packed on shelves in one layout:

    assets/gothic/attack-props.png        the prints (RGBA, never filtered)
    assets/gothic/attack-props-paper.png  their fields (one channel)
    src/engine/gfx/attack_props_data.odin the table (generated, LF)

The same script gives the same bytes.

Options:
    --check        exit 1 if any output is not what this script would write
    --preview DIR  also write DIR/attack-props-preview.png (each prop on its
                   paper, x4) and DIR/attack-props-flight.png (props turned as
                   they fly and swing, their cut edge kept down and to the
                   right on screen, as the runtime keeps it), emulating the
                   shader
    --no-write     leave the outputs as they are
"""
import argparse
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PRINTS = os.path.join(ROOT, "assets", "gothic", "attack-props.png")
FIELDS = os.path.join(ROOT, "assets", "gothic", "attack-props-paper.png")
TABLE = os.path.join(ROOT, "src", "engine", "gfx", "attack_props_data.odin")

SIGNATURE = b"\x89PNG\r\n\x1a\n"
# The card shader's constants (src/engine/gfx/flipbook_data.odin).
PAPER_SCALE = 20.0
PAPER_PX = 5.5
INK_PX = 5.5 + 1.5
EDGE_PX = 1.1
# Texels of field around each print: paper, ink, the cut edge and smoothing.
MARGIN = 7
ATLAS_WIDTH = 192

PALETTE = {
    "K": (13, 20, 30),      # ink, the figures' outline
    "I": (29, 30, 34), "i": (44, 47, 53), "j": (66, 65, 68),        # iron
    "S": (122, 118, 116), "s": (176, 189, 204), "z": (82, 78, 80),  # steel
    "W": (111, 79, 54), "w": (147, 112, 79), "v": (82, 53, 35),     # wood
    "L": (87, 57, 42), "l": (132, 72, 46),                          # leather
    "R": (176, 20, 31), "r": (215, 41, 42), "d": (114, 10, 22),     # crimson
    "B": (48, 199, 237), "b": (8, 112, 166), "G": (221, 241, 255),  # glass, glow
    "Y": (211, 175, 116), "y": (175, 129, 80), "e": (236, 212, 157),  # gold
    "N": (216, 188, 161), "n": (244, 224, 198),                     # bone
    "q": (149, 13, 25), "Q": (98, 5, 15), "p": (226, 55, 50),        # ghoul flesh
    "X": (55, 53, 60), "x": (94, 78, 76),                           # bomb
    "O": (244, 147, 5), "U": (255, 236, 170),                       # fuse, spark
    "o": (201, 10, 18), "P": (241, 12, 13),                         # orb
    "F": (190, 82, 35), "f": (255, 214, 120), "g": (244, 157, 104), # fire
    "T": (40, 71, 108),                                             # storm blue
    "H": (250, 250, 246),                                           # white print, tinted at run time
    "a": (28, 74, 52), "c": (52, 128, 72), "h": (150, 222, 132),    # venom
    "k": (196, 226, 214), "m": (150, 104, 64),                      # glass, cork
    "A": (36, 84, 150), "C": (70, 140, 208), "E": (186, 226, 248),  # water, foam
    "M": (126, 156, 184), "J": (74, 100, 134),                      # a fish
    "u": (242, 198, 74), "t": (196, 146, 44),                       # cheese
    "V": (204, 198, 188), "D": (158, 152, 144), "Z": (112, 106, 100),  # stone dust
}

# name, rows (None: an analytic shape), grip, tip (texels of the rows, x to the
# right, y down), whether it gets an ink outline, whether it prints anything,
# its paper's width in texels (0: no paper).
PROPS = [
    # The archer's crossbow bolt, its head to the right.
    ("Bolt", [
        "RRr.......................",
        "RRRr.................zs...",
        "dRRwwwwwwwwwwwwwwwwwwSSSss",
        "RRRr.................zs...",
        "RRr.......................",
    ], (0.5, 2.5), (25.5, 2.5), True, True, 2.4),
    # The Viandante's iron cage lantern, hung from its ring.
    ("Lantern", [
        "....jjj....",
        "...j...j...",
        "...j...j...",
        "....jjj....",
        "..iiiiiii..",
        ".ijjjjjjji.",
        ".iBBGBBBbi.",
        ".iBGGBBBbi.",
        ".iBBGBBBbi.",
        ".iiiiiiiii.",
        ".iBBBBBBbi.",
        ".ibBBBBbbi.",
        ".ijjjjjjji.",
        "..iiiiiii..",
        "...iiiii...",
    ], (5.5, 0.5), (5.5, 14.5), True, True, 3.2),
    # M8, Mannaia di ferro: held at the foot of its handle, the blade above.
    ("Iron_Cleaver", [
        "..sssssssss.",
        ".sSSSSSSSSSz",
        ".sSSjjSSSSSz",
        ".sSSjjSSSSSz",
        ".sSSSSSSSSSz",
        ".sSSSSSSSSSz",
        ".sSSSSSSSSSz",
        ".sSSSSSSSSzz",
        ".zzzzzzzzzz.",
        ".LL.........",
        ".lL.........",
        ".LL.........",
        ".lL.........",
        ".LL.........",
        ".lL.........",
        ".LL.........",
        ".jj.........",
    ], (1.5, 16.5), (6.5, 0.5), True, True, 3.2),
    # M8, Picca della tempesta: the storm crackling at its point.
    ("Storm_Pike", [
        "..G.G..",
        "...s...",
        "..sSs..",
        ".GsSsG.",
        "..sSs..",
        "..sSz..",
        "..zSz..",
        "...z...",
        "..TBT..",
    ] + ["...w...", "...W..."] * 9 + ["...j..."], (3.5, 26.5), (3.5, 0.5), True, True, 2.4),
    # The ghoul's own red hand, three long talons fanning out of its palm,
    # their hooked tips darker (raking to the right).
    ("Claw", [
        "...........pppqdddd...",
        ".........ppqqq........",
        ".......ppqqq..........",
        "......ppqq............",
        "..ppppqqq.............",
        ".Qpppqqq..............",
        "QQqqqqpppppppppppd....",
        "QQqqqqqqqqqqqqqqqdddd.",
        "QQqqqqqqq............d",
        ".QQQQppp..............",
        "..QQQqqqpp............",
        "......qqqqp...........",
        ".........qqqp.........",
        "...........qqqd.......",
        "..............dd......",
        "................d.....",
    ], (0.5, 7.5), (21.5, 8.5), True, True, 3.0),
    # The brute's cleaver: a slab of steel, blood on its edge.
    ("Cleaver", [
        "..ssssssssssss.",
        ".sSSSSSSSSSSSSz",
        ".sSSSSSSSSSSSrz",
        ".sSSjjSSSSSSSRz",
        ".sSSjjSSSSSSrRz",
        ".sSSSSSSSSSSSRz",
        ".sSSSSSSSSSSSrz",
        ".sSSSSSSSSSSSSz",
        ".sSSSSSSSSSSSSz",
        ".zSSSSSSSSSSSzz",
        ".zzzzzzzzzzzzz.",
    ] + ["..LL...........", "..lL..........."] * 4 + ["..jj..........."], (2.5, 19.5), (8.5, 0.5), True, True, 3.4),
    # The custodian's crozier: a gold crook around its blue cross.
    ("Crozier", [
        "..yYYy...",
        ".Y....Y..",
        "Y..BB..Y.",
        "Y.BGGB.Y.",
        "Y..BB..y.",
        ".y....Y..",
        "..yY.Y...",
        "....YY...",
    ] + ["....Ye...", "....yY..."] * 11 + ["....yy..."], (4.5, 30.5), (4.5, 0.5), True, True, 2.4),
    # The archmage's staff: gnarled wood, a red orb in its claw.
    ("Staff", [
        "...vv.vv..",
        "..v.oo.v..",
        "..voPPov..",
        "..voPoov..",
        "...voov...",
    ] + ["....vW....", "....Wv....", "....vW....", "...vW.....", "...Wv.....", "...vW.....",
         "....Wv....", "....vW...."] * 3 + ["....vv...."], (4.5, 29.5), (4.5, 0.5), True, True, 2.4),
    # The bomber's bomb, its fuse alight.
    ("Bomb", [
        "......U.U",
        ".......O.",
        "......O..",
        ".....yy..",
        "...XXXX..",
        "..XxxXXX.",
        ".XxXXXXXX",
        ".XxXXXXXX",
        ".XXXXXXXX",
        ".XXXXXXXX",
        "..XXXXXX.",
        "...XXXX..",
    ], (4.5, 8.0), (8.5, 0.5), True, True, 3.0),
    # The archmage's ember, flung at a barrel: two drawings that flicker.
    ("Ember_A", [
        "....gg.......",
        "..gFFFgg.....",
        ".gFFffFFgg...",
        "gFffUUffFFggg",
        ".gFFffFFgg...",
        "..gFFFgg.....",
        "....gg.......",
    ], (0.5, 3.5), (12.5, 3.5), True, True, 2.8),
    ("Ember_B", [
        "...ggg.......",
        ".ggFFFgg.....",
        "gFFfffFFgg...",
        ".gFfUUUfFFgg.",
        "gFFfffFFgg...",
        ".ggFFFgg.....",
        "...ggg.......",
    ], (0.5, 3.5), (12.5, 3.5), True, True, 2.8),
    # The swing's smear: paper only, a crescent thin at its tail and wide at
    # the weapon, bent along the swing's path at run time.
    ("Swoosh", None, (0.5, 5.0), (47.5, 5.0), False, False, 2.0),
    # An impact: a jagged star printed white (tinted by its blow) on paper.
    ("Impact", [
        "......H......",
        "......H......",
        ".H...HHH...H.",
        "..H.HHHHH.H..",
        "...HHHHHHH...",
        "..HHHHHHHHH..",
        "HHHHHHHHHHHHH",
        "..HHHHHHHHH..",
        "...HHHHHHH...",
        "..H.HHHHH.H..",
        ".H...HHH...H.",
        "......H......",
        "......H......",
    ], (6.5, 6.5), (6.5, 0.5), True, True, 2.6),
    # The ghoul's rake on a struck card: three tears, print only.
    ("Scratch", [
        "d.....d.....d.",
        ".r.....r.....r",
        "..r.....r.....",
        "...d.....d....",
        "....r.....r...",
        ".....r.....r..",
        "......d.....d.",
    ], (0.5, 0.5), (12.5, 6.5), False, True, 0.0),
    # Paper bits thrown off a blow: paper only.
    ("Shard_A", ["XX.", "XXX", "X.."], (1.5, 1.5), (2.5, 0.5), False, False, 1.6),
    ("Shard_B", [".X.", "XXX", ".XX"], (1.5, 1.5), (2.5, 0.5), False, False, 1.6),
    ("Shard_C", ["XXX", ".XX", "..X"], (1.5, 1.5), (2.5, 0.5), False, False, 1.6),
    # INCENDIO: a fire's centre flames (two drawings that flicker), standing on
    # their base, a tongue licking up beside the tip...
    ("Flame_A", [
        "......F......",
        ".....FF......",
        ".....FgF.....",
        "....FggF..F..",
        "....FggF..FF.",
        "...FggggF.FgF",
        "...FgffgFFggF",
        "..FggffggFggF",
        "..FgfffggggF.",
        ".FggffUfgggF.",
        ".FgfffUUfggF.",
        "FggffUUUffggF",
        "FgfffUUUUfggF",
        "FgffUUUUUffgF",
        "FgffUUUUUUfgF",
        "FgfUUUUUUUfgF",
        ".FgfUUUUUfgF.",
        ".FggfUUUffgF.",
        "..FggfffggF..",
        "...FFFFFFF...",
    ], (6.5, 19.5), (6.5, 0.5), True, True, 2.6),
    ("Flame_B", [
        "......F......",
        "......FF.....",
        ".....FgF.....",
        "..F..FggF....",
        ".FF..FggF....",
        "FgF.FggggF...",
        "FggFFgffgF...",
        "FggFggffggF..",
        ".FggggfffgF..",
        ".FgggfUffggF.",
        ".FggfUUfffgF.",
        "FggffUUUffggF",
        "FggfUUUUfffgF",
        "FgffUUUUUffgF",
        "FgfUUUUUUffgF",
        "FgfUUUUUUUfgF",
        ".FgfUUUUUfgF.",
        ".FgffUUUfggF.",
        "..FggfffggF..",
        "...FFFFFFF...",
    ], (6.5, 19.5), (6.5, 0.5), True, True, 2.6),
    # ...and the smaller flames along its arms.
    ("Flame_C", [
        "....F....",
        "...FF....",
        "...FgF...",
        "..FggF.F.",
        "..FgfgFFF",
        ".FgffgFgF",
        ".FgfUfggF",
        "FgfUUfgF.",
        "FgfUUUfgF",
        "FgUUUUfgF",
        ".FgUUUfF.",
        "..FgffF..",
        "...FFF...",
    ], (4.5, 12.5), (4.5, 0.5), True, True, 2.2),
    ("Flame_D", [
        "....F....",
        "....FF...",
        "...FgF...",
        ".F.FggF..",
        "FFFgfgF..",
        "FgFgffgF.",
        "FggfUfgF.",
        ".FgfUUfgF",
        "FgfUUUfgF",
        "FgfUUUUgF",
        ".FfUUUgF.",
        "..FffgF..",
        "...FFF...",
    ], (4.5, 12.5), (4.5, 0.5), True, True, 2.2),
    # POZZA DI VELENO: the flask it is thrown in, corked, and the drops of its
    # splash.
    ("Flask", [
        "...mmm...",
        "...mmm...",
        "....k....",
        "...kak...",
        "...kak...",
        "..kaaak..",
        ".kacccak.",
        "kacchccak",
        "kachhccak",
        "kacccccak",
        "kaccccaak",
        ".kaaaaak.",
        "..kkkkk..",
    ], (4.5, 12.5), (4.5, 0.5), True, True, 2.6),
    ("Drop_A", [".h.", "hhc", "hcc", "cca", ".a."], (1.5, 4.5), (1.5, 0.5), True, True, 1.2),
    ("Drop_B", ["..h.", ".hcc", "hcca", ".aa."], (1.5, 3.5), (2.5, 0.5), True, True, 1.2),
    # A cinder a fire throws: a spark in its glow.
    ("Cinder", [".g.", "gUg", ".F."], (1.5, 2.5), (1.5, 0.5), True, True, 1.6),
    # CANNA DA PESCA: the rod, held at its cork grip under the reel, its line
    # guides on one side, the tip leading.
    ("Rod", [
        ".w..",
        ".w..",
        ".w..",
        ".ws.",
        ".w..",
        ".w..",
        ".w..",
        ".w..",
        ".ws.",
        ".w..",
        ".w..",
        ".w..",
        ".w..",
        ".W..",
        ".Ws.",
        ".W..",
        ".W..",
        ".W..",
        ".W..",
        ".W..",
        ".Ws.",
        ".W..",
        ".W..",
        ".W..",
        ".W..",
        ".W..",
        ".W..",
        ".Ws.",
        ".W..",
        ".W..",
        "sSs.",
        "SsSj",
        "sSs.",
        ".L..",
        ".l..",
        ".L..",
        ".l..",
        ".L..",
        ".v..",
    ], (1.5, 34.5), (1.5, 0.5), True, True, 1.6),
    # Its bobber, red over white, its quill up.
    ("Bobber", [".v.", ".v.", "rRr", "RrR", "nNn", "NnN", ".N."], (1.5, 6.5), (1.5, 0.5), True, True, 1.8),
    # The drops of the water it lands in and a catch comes out of.
    ("Wet_A", [".E.", "ECC", "ECC", "CCA", ".A."], (1.5, 4.5), (1.5, 0.5), True, True, 1.2),
    ("Wet_B", ["..E.", ".ECC", "ECCA", ".AA."], (1.5, 3.5), (2.5, 0.5), True, True, 1.2),
    # The bite's "!".
    ("Bang", ["rr", "rR", "rR", "rR", "RR", "..", "rR"], (1.0, 6.5), (1.0, 0.5), True, True, 2.6),
    # What it catches: the foods (a fish, an apple, a loaf, a wedge of cheese,
    # a leg of meat) held at their bottom, and a card, its gold-edged back.
    ("Fish", [
        "....JJJJ....",
        "..JJMMMMJJ.J",
        ".JKMMMMMMMJJ",
        "JMMMMMMMMMJJ",
        ".JMEEEEEEMJJ",
        "..JJEEEEJJ.J",
        "....JJJJ....",
    ], (6.0, 6.5), (6.0, 0.5), True, True, 1.6),
    ("Apple", [
        "....vh..",
        "...vhhc.",
        ".rrvrr..",
        "rrRRRRr.",
        "rRRRRRRd",
        "rRRRRRRd",
        ".RRRRRd.",
        "..dddd..",
    ], (4.0, 7.5), (4.0, 0.5), True, True, 1.6),
    ("Bread", [
        "..yyyyyy..",
        ".yYeYeYey.",
        "yYYYYYYYYy",
        "yYYYYYYYYy",
        "WyyyyyyyyW",
        ".WWWWWWWW.",
    ], (5.0, 5.5), (5.0, 0.5), True, True, 1.6),
    ("Cheese", [
        "......uu.",
        "....uuuut",
        "..uuutuut",
        "uuuuuuuut",
        "uutuuuutt",
        "tttttttt.",
    ], (4.5, 5.5), (4.5, 0.5), True, True, 1.6),
    ("Meat", [
        "..qqqq....",
        ".qppppq...",
        "qpprppq...",
        "qppppppq..",
        ".qppppqnn.",
        "..qqqqnNnn",
        "......nNNn",
        ".......nn.",
    ], (5.0, 7.5), (5.0, 0.5), True, True, 1.6),
    ("Card_Back", [
        "YYYYYYYY",
        "YTTTTTTY",
        "YTTeeTTY",
        "YTeTTeTY",
        "YTTeeTTY",
        "YTTTTTTY",
        "YTTeeTTY",
        "YTeTTeTY",
        "YTTeeTTY",
        "YTTTTTTY",
        "YYYYYYYY",
    ], (4.0, 10.5), (4.0, 0.5), True, True, 2.2),
    # LAZZO: the stone dust a swung foe knocks off a wall it smashes into, two
    # puffs, pale where the light takes them, held at their foot
    # (src/render/lasso.odin).
    ("Dust_A", [
        "..VVV.VV.",
        ".VVVVVVDV",
        "VVVDDDDDD",
        "VDDDDDDZD",
        ".DDZDDZZ.",
        "..ZZZZZ..",
    ], (4.0, 5.5), (4.0, 0.5), True, True, 1.4),
    ("Dust_B", [
        ".VV.V.",
        "VVVVDV",
        "VDDDDD",
        ".DZZZ.",
    ], (2.5, 3.5), (2.5, 0.5), True, True, 1.4),
]


def swoosh_field(w, h, margin):
    """Distance (texels) to a crescent: a centre line bending up to its head,
    0.4 texels thick at the tail and 3 at the head."""
    samples = []
    for i in range(97):
        u = i / 96
        x = margin + 0.5 + u * (w - 1)
        y = margin + h * 0.5 + 2.2 - 3.4 * math.sin(u * math.pi * 0.5)
        samples.append((x, y, 0.4 + 2.6 * u ** 1.6))

    def field(px, py):
        best = 1e9
        for x, y, r in samples:
            best = min(best, math.hypot(px - x, py - y) - r)
        return max(0.0, best)
    return field


def with_outline(rows, ink):
    """One texel of room around the rows and, with `ink`, the body's ink line:
    every empty texel touching the body (8-way)."""
    h, w = len(rows), max(len(r) for r in rows)
    out = [["." for _ in range(w + 2)] for _ in range(h + 2)]
    for y in range(h):
        for x in range(len(rows[y])):
            out[y + 1][x + 1] = rows[y][x]
    if not ink:
        return out
    inked = [row[:] for row in out]
    for y in range(h + 2):
        for x in range(w + 2):
            if out[y][x] != ".":
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h + 2 and 0 <= xx < w + 2 and out[yy][xx] not in (".", "K"):
                        inked[y][x] = "K"
    return inked


def closed(mask, w, h):
    """Hollows of a texel or two are filled: the paper never shows a pinhole."""
    def get(m, x, y):
        return 0 <= y < h and 0 <= x < w and m[y][x]
    grown = [[any(get(mask, x + dx, y + dy) for dy in (-1, 0, 1) for dx in (-1, 0, 1)) for x in range(w)] for y in range(h)]
    return [[mask[y][x] or all(get(grown, x + dx, y + dy) or not (0 <= y + dy < h and 0 <= x + dx < w)
                               for dy in (-1, 0, 1) for dx in (-1, 0, 1)) for x in range(w)] for y in range(h)]


def distance_field(mask, w, h):
    """Exact distance (texels) from every texel to the nearest texel of
    `mask`, measured to its square's edge as tools/art/living.py does."""
    edge = []
    for y in range(h):
        for x in range(w):
            if mask[y][x] and any(not (0 <= y + dy < h and 0 <= x + dx < w) or not mask[y + dy][x + dx]
                                  for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                edge.append((x, y))
    field = [[0.0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if mask[y][x] or not edge:
                continue
            best = min(max(abs(x - ex) - 0.5, 0) ** 2 + max(abs(y - ey) - 0.5, 0) ** 2 for ex, ey in edge)
            field[y][x] = math.sqrt(best)
    return field


def png_bytes(width, height, pixels, channels=4):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            p = pixels[y][x]
            raw.extend(bytes(p[:channels]) if channels > 1 else bytes((p,)))
    colour = {4: 6, 3: 2, 1: 0}[channels]

    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff)

    data = SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0))
    return data + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def build():
    """The packed atlases and the table: each prop's print and field share
    one cell, its print MARGIN texels in from the cell's edge."""
    cells = []
    for name, rows, grip, tip, ink, prints, paper in PROPS:
        pad = 0 if rows is None else 1
        if rows is None:
            w, h = 48, 10
            grid = [["." for _ in range(w)] for _ in range(h)]
        else:
            grid = with_outline(rows, ink)
            h, w = len(grid), len(grid[0])
        cells.append((name, grid, w, h, rows is None, prints, paper, (grip[0] + pad, grip[1] + pad), (tip[0] + pad, tip[1] + pad)))
    x = y = shelf = 0
    placed = []
    for cell in cells:
        w, h = cell[2], cell[3]
        cw, ch = w + 2 * MARGIN, h + 2 * MARGIN
        if x + cw > ATLAS_WIDTH:
            x, y, shelf = 0, y + shelf, 0
        placed.append((cell, x, y))
        x += cw
        shelf = max(shelf, ch)
    width, height = ATLAS_WIDTH, y + shelf
    prints_px = [[(0, 0, 0, 0) for _ in range(width)] for _ in range(height)]
    fields = [[255 for _ in range(width)] for _ in range(height)]
    table = []
    for (name, grid, w, h, analytic, prints, paper, grip, tip), cx, cy in placed:
        cw, ch = w + 2 * MARGIN, h + 2 * MARGIN
        stretch = PAPER_PX / paper if paper > 0 else 0
        field = None
        if analytic:
            shape = swoosh_field(w, h, MARGIN)
            field = [[shape(xx + 0.5, yy + 0.5) for xx in range(cw)] for yy in range(ch)]
        elif paper > 0:
            big = [[False] * cw for _ in range(ch)]
            for yy in range(h):
                for xx in range(w):
                    big[yy + MARGIN][xx + MARGIN] = grid[yy][xx] != "."
            field = distance_field(closed(big, cw, ch), cw, ch)
        for yy in range(ch):
            for xx in range(cw):
                # A print with no paper keeps 255: the shader cuts nothing there.
                value = 255 if field is None else int(round(field[yy][xx] * PAPER_SCALE * stretch))
                fields[cy + yy][cx + xx] = max(0, min(255, value))
        if prints:
            for yy in range(h):
                for xx in range(w):
                    letter = grid[yy][xx]
                    if letter != ".":
                        r, g, b = PALETTE[letter]
                        prints_px[cy + MARGIN + yy][cx + MARGIN + xx] = (r, g, b, 255)
        table.append((name, cx + MARGIN, cy + MARGIN, w, h, grip, tip, paper))
    return width, height, prints_px, fields, table


def table_source(table):
    lines = ["// Generated by tools/art/build_attack_props.py. Do not edit by hand:",
             "// change the props there and rebuild (see tools/art/README.md).",
             "package gfx", "",
             "// The paper props of the board's blows (render/attack_fx.odin).",
             "Attack_Prop :: enum u8 {%s}" % ", ".join(e[0] for e in table),
             "// `rect` is the print, in texels of both atlases; its field reaches",
             "// ATTACK_PROP_MARGIN texels further on every side. `grip` is the texel",
             "// held (a bolt's tail), `tip` the one that leads. `paper` is the paper's",
             "// width around the print in texels (0: a print with no paper).",
             "Attack_Prop_Sheet :: struct {rect: [4]i32, grip, tip: [2]f32, paper: f32}",
             "ATTACK_PROP_MARGIN :: %d" % MARGIN,
             "@(rodata)",
             "ATTACK_PROPS := [Attack_Prop]Attack_Prop_Sheet{"]
    for name, x, y, w, h, grip, tip, paper in table:
        lines.append("\t.%s = {rect = {%d, %d, %d, %d}, grip = {%.1f, %.1f}, tip = {%.1f, %.1f}, paper = %.1f}," %
                     (name, x, y, w, h, grip[0], grip[1], tip[0], tip[1], paper))
    lines += ["}", "",
              'ATTACK_PROPS_PNG := #load("../../../assets/gothic/attack-props.png")',
              'ATTACK_PROPS_PAPER_PNG := #load("../../../assets/gothic/attack-props-paper.png")', ""]
    return "\n".join(lines).encode("ascii")


# --------------------------------------------------------------------------
# Previews: the card shader in Python.

SHEET = (241, 239, 230)
EDGE_COLOUR = (164, 152, 131)
INK_COLOUR = (13, 20, 30)


def sample_field(fields, fx0, fy0, fw, fh, u, v):
    """Bilinear, clamped to the prop's own field cell (as the shader clamps uv)."""
    x, y = u - 0.5, v - 0.5
    ix, iy = int(math.floor(x)), int(math.floor(y))
    ax, ay = x - ix, y - iy

    def f(xx, yy):
        xx, yy = min(max(xx, 0), fw - 1), min(max(yy, 0), fh - 1)
        return fields[fy0 + yy][fx0 + xx]
    return (f(ix, iy) * (1 - ax) + f(ix + 1, iy) * ax) * (1 - ay) + (f(ix, iy + 1) * (1 - ax) + f(ix + 1, iy + 1) * ax) * ay


def shade(fields, prints, entry, u, v, edge, tint=None):
    """One screen pixel of a prop at texel (u, v) of its field cell; `edge` is
    the cut edge's direction in texels (down-right on screen)."""
    name, x, y, w, h, grip, tip, paper = entry
    fx0, fy0, fw, fh = x - MARGIN, y - MARGIN, w + 2 * MARGIN, h + 2 * MARGIN
    if not (0 <= u < fw and 0 <= v < fh):
        return None
    col = None
    if paper > 0:
        d = sample_field(fields, fx0, fy0, fw, fh, u, v) / PAPER_SCALE
        de = sample_field(fields, fx0, fy0, fw, fh, u - edge[0] * EDGE_PX, v - edge[1] * EDGE_PX) / PAPER_SCALE
        if min(d, de) < INK_PX:
            col = SHEET if d < PAPER_PX else (EDGE_COLOUR if de < PAPER_PX else INK_COLOUR)
    p = prints[fy0 + int(v)][fx0 + int(u)]
    if p[3] > 0:
        col = p[:3]
        if tint is not None and p[:3] == PALETTE["H"]:
            col = tint
    return col


def preview_sheet(fields, prints, table):
    scale, pad = 4, 8
    ground = (34, 38, 48)
    tiles = []
    for entry in table:
        name, x, y, w, h, grip, tip, paper = entry
        fw, fh = w + 2 * MARGIN, h + 2 * MARGIN
        tile = [[ground] * (fw * scale) for _ in range(fh * scale)]
        for sy in range(fh * scale):
            for sx in range(fw * scale):
                c = shade(fields, prints, entry, (sx + 0.5) / scale, (sy + 0.5) / scale, (1, 1))
                if c is not None:
                    tile[sy][sx] = c
        tiles.append(tile)
    rows, current, row_w = [], [], 0
    for tile in tiles:
        if row_w + len(tile[0]) + pad > 1500 and current:
            rows.append(current)
            current, row_w = [], 0
        current.append(tile)
        row_w += len(tile[0]) + pad
    rows.append(current)
    cw = max(sum(len(t[0]) + pad for t in r) for r in rows) + pad
    chh = sum(max(len(t) for t in r) + pad for r in rows) + pad
    canvas = [[ground + (255,)] * cw for _ in range(chh)]
    cy = pad
    for r in rows:
        cx = pad
        for tile in r:
            for yy, line in enumerate(tile):
                for xx, c in enumerate(line):
                    canvas[cy + yy][cx + xx] = c + (255,)
            cx += len(tile[0]) + pad
        cy += max(len(t) for t in r) + pad
    return png_bytes(cw, chh, canvas)


def place(canvas, fields, prints, entry, at, angle, scale, tint=None):
    """Draws a prop on `canvas` with its grip at screen point `at` and its
    grip-to-tip axis turned to `angle` radians on screen (0: to the right),
    the cut edge kept down-right on screen."""
    name, x, y, w, h, grip, tip, paper = entry
    axis = (tip[0] - grip[0], tip[1] - grip[1])
    rot = angle - math.atan2(axis[1], axis[0])
    c, s = math.cos(rot), math.sin(rot)
    pivot = (grip[0] + MARGIN, grip[1] + MARGIN)
    fw, fh = w + 2 * MARGIN, h + 2 * MARGIN
    reach = int(math.hypot(fw, fh) * scale) + 2
    # The screen's down-right in the prop's texel axes (the inverse turn).
    edge = (c + s, -s + c)
    for sy in range(int(at[1]) - reach, int(at[1]) + reach):
        for sx in range(int(at[0]) - reach, int(at[0]) + reach):
            if not (0 <= sy < len(canvas) and 0 <= sx < len(canvas[0])):
                continue
            dx, dy = (sx + 0.5 - at[0]) / scale, (sy + 0.5 - at[1]) / scale
            col = shade(fields, prints, entry, pivot[0] + c * dx + s * dy, pivot[1] - s * dx + c * dy, edge, tint)
            if col is not None:
                canvas[sy][sx] = col + (255,)


def place_arc(canvas, fields, prints, entry, center, radius, a0, a1, scale):
    """A paper strip bent along an arc of the screen: its length runs from a0
    to a1, its width across the arc, the cut edge down-right on screen."""
    name, x, y, w, h, grip, tip, paper = entry
    fw, fh = w + 2 * MARGIN, h + 2 * MARGIN
    half = fh * scale * 0.5
    for sy in range(int(center[1] - radius - half) - 2, int(center[1] + radius + half) + 2):
        for sx in range(int(center[0] - radius - half) - 2, int(center[0] + radius + half) + 2):
            if not (0 <= sy < len(canvas) and 0 <= sx < len(canvas[0])):
                continue
            dx, dy = sx + 0.5 - center[0], sy + 0.5 - center[1]
            a = math.atan2(dy, dx)
            t = (a - a0) / (a1 - a0)
            if not (0 <= t <= 1):
                continue
            u = t * fw
            v = fh * 0.5 - (math.hypot(dx, dy) - radius) / scale
            # The strip's texel axes on screen: x along the arc, y inward.
            tx, ty = -math.sin(a), math.cos(a)
            ix, iy = -math.cos(a), -math.sin(a)
            col = shade(fields, prints, entry, u, v, (tx + ty, ix + iy))
            if col is not None:
                canvas[sy][sx] = col + (255,)


def preview_flight(fields, prints, table):
    by_name = {e[0]: e for e in table}
    scale = 3
    w, h = 900, 420
    ground = (52, 48, 46)
    canvas = [[ground + (255,)] * w for _ in range(h)]
    # Bolts along a slight arc, turned with their flight.
    for i in range(7):
        u = i / 6
        x = 40 + u * 360
        y = 200 - math.sin(u * math.pi) * 60
        slope = -math.cos(u * math.pi) * 60 * math.pi / 360
        place(canvas, fields, prints, by_name["Bolt"], (x, y), math.atan(slope), scale)
    # A lantern swing: the smear along the arc behind it, the lantern at its head.
    cx, cy, r = 640, 250, 150
    a0, a1 = math.radians(-160), math.radians(-40)
    place_arc(canvas, fields, prints, by_name["Swoosh"], (cx, cy), r, a0, a1, scale)
    place(canvas, fields, prints, by_name["Lantern"], (cx + math.cos(a1) * (r - 40), cy + math.sin(a1) * (r - 40)), a1, scale)
    place(canvas, fields, prints, by_name["Impact"], (cx + 120, cy - 40), 0, scale, tint=(196, 44, 44))
    place(canvas, fields, prints, by_name["Shard_A"], (cx + 160, cy - 80), 0.4, scale)
    place(canvas, fields, prints, by_name["Shard_B"], (cx + 170, cy - 20), 1.2, scale)
    place(canvas, fields, prints, by_name["Cleaver"], (480, 330), math.radians(-60), scale)
    place(canvas, fields, prints, by_name["Crozier"], (780, 380), math.radians(-110), scale)
    place(canvas, fields, prints, by_name["Ember_A"], (120, 330), math.radians(15), scale)
    place(canvas, fields, prints, by_name["Scratch"], (260, 330), 0.3, scale)
    return png_bytes(w, h, canvas)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--preview")
    parser.add_argument("--no-write", action="store_true")
    args = parser.parse_args()
    width, height, prints, fields, table = build()
    outputs = [
        (PRINTS, png_bytes(width, height, prints)),
        (FIELDS, png_bytes(width, height, fields, channels=1)),
        (TABLE, table_source(table)),
    ]
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        with open(os.path.join(args.preview, "attack-props-preview.png"), "wb") as f:
            f.write(preview_sheet(fields, prints, table))
        with open(os.path.join(args.preview, "attack-props-flight.png"), "wb") as f:
            f.write(preview_flight(fields, prints, table))
    stale = []
    for path, data in outputs:
        current = open(path, "rb").read() if os.path.exists(path) else None
        if current != data:
            stale.append(path)
    if args.check:
        for path in stale:
            print("out of date:", os.path.relpath(path, ROOT))
        print("up to date" if not stale else "%d file(s) out of date" % len(stale))
        sys.exit(1 if stale else 0)
    if not args.no_write:
        for path, data in outputs:
            if path in stale:
                with open(path, "wb") as f:
                    f.write(data)
    print("atlas %dx%d, %d props" % (width, height, len(table)))


if __name__ == "__main__":
    main()
