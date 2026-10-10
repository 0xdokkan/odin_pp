"""Rigs and flipbook key poses for every board character.

Coordinates are logical pixels of the 3 px-block conversion of
assets/gothic/figures-v2.png, padded by 2 (see build_sprites.py --sheets).
Angles are degrees, positive = clockwise on screen; offsets are pixels with
+y pointing down. Every frame is a deliberate key drawing: the flipbook never
tweens between them.

Action modes
  loop  plays at the frame durations (ms) for as long as the state lasts
  once  is stretched over the presentation cue that triggered it; `hit`
        names the frame that lands on the cue's impact moment
"""
from pixel_rig import Bone

# --------------------------------------------------------------------------
# Viandante (player).

PILGRIM_BONES = [
    Bone("hips", None, (40, 66)),
    Bone("torso", "hips", (40, 64), 0.0, [(12, 26), (68, 26), (68, 68), (12, 68)]),
    Bone("head", "torso", (40, 29), 0.6, [(20, 0), (58, 0), (58, 14), (56, 30), (24, 30), (19, 14)]),
    Bone("cape_l", "torso", (28, 30), 0.4,
         [(0, 40), (20, 25), (33, 28), (31, 34), (22, 44), (17, 58), (16, 76), (0, 78)]),
    Bone("arm_l", "torso", (28, 42), 1.0, [(16, 44), (29, 42), (30, 60), (16, 60)], back=True),
    Bone("arm_r", "torso", (53, 31), 1.0, [(51, 26), (71, 26), (71, 45), (51, 45)], back=True),
    Bone("lantern", "arm_r", (61, 44), 2.0, [(53, 44), (71, 44), (71, 59), (53, 59)]),
    Bone("cape_r", "torso", (54, 52), 0.3, [(52, 59), (69, 59), (69, 76), (52, 76)]),
    Bone("leg_l", "hips", (23, 70), -1.0, [(10, 69), (33, 69), (33, 82), (10, 82)], joint="torso"),
    Bone("leg_r", "hips", (52, 70), -1.0, [(42, 69), (64, 69), (64, 82), (42, 82)], joint="torso"),
]

# The painted cast pose (crystal raised) and hit pose get light rigs of their
# own so their key drawings can breathe for a frame or two.
PILGRIM_CAST_BONES = [
    Bone("hips", None, (37, 70)),
    Bone("torso", "hips", (37, 68), 0.0, [(0, 6), (80, 6), (80, 71), (0, 71)]),
    Bone("head", "torso", (38, 34), 0.6, [(26, 6), (50, 6), (52, 34), (24, 34)]),
    Bone("arm", "torso", (52, 38), 1.0, [(48, 20), (64, 20), (64, 42), (48, 42)], back=True),
    Bone("crystal", "arm", (60, 29), 2.0, [(52, 0), (78, 0), (78, 29), (52, 29)]),
    Bone("legs", "hips", (37, 72), -1.0, [(4, 71), (68, 71), (68, 84), (4, 84)]),
]

PILGRIM_HIT_BONES = [
    Bone("hips", None, (33, 60)),
    Bone("torso", "hips", (33, 58), 0.0, [(0, 0), (78, 0), (78, 61), (0, 61)]),
    Bone("head", "torso", (27, 26), 0.6, [(8, 0), (36, 0), (38, 27), (6, 27)]),
    Bone("cloak", "torso", (40, 24), 0.4, [(40, 16), (78, 16), (78, 58), (40, 58)]),
    Bone("legs", "hips", (33, 62), -1.0, [(0, 61), (78, 61), (78, 76), (0, 76)]),
]


def _pilgrim_actions():
    rest = {}
    return {
        # Slow breath: the hood settles a pixel, the lantern sways.
        "idle": ("loop", [
            (rest, 260),
            ({"torso": (0, 0, 0.6), "head": (0, 0, 0.4), "lantern": (3, 0, 0)}, 220),
            ({"torso": (0, 0, 1.1), "head": (0, 0, 0.9), "lantern": (5, 0, 0), "cape_l": (-1.5, 0, 0)}, 300),
            ({"torso": (0, 0, 0.5), "head": (0, 0, 0.4), "lantern": (2, 0, 0)}, 220),
        ]),
        # Six-drawing stride: contact, down, passing on each foot. The body
        # dips on the contact drawings and rises on the passing ones, while
        # lantern and cloak swing against the stride.
        "walk": ("loop", [
            ({"torso": (-2, 0, 1), "leg_l": (-4, -1, 1), "leg_r": (3, 1, -2), "lantern": (-8, 0, 0),
              "cape_l": (3, 0, 0), "cape_r": (-3, 0, 0), "arm_l": (4, 0, 0)}, 90),
            ({"torso": (-1, 0, 1.5), "leg_l": (-2, 0, 0.5), "leg_r": (2, 0, -3), "lantern": (-4, 0, 0),
              "cape_l": (1.5, 0, 0), "arm_l": (2, 0, 0)}, 80),
            ({"torso": (0, 0, -1), "head": (0, 0, -0.5), "leg_r": (0, 0, -1), "lantern": (3, 0, 0),
              "cape_l": (-2, 0, 0), "cape_r": (2, 0, 0)}, 90),
            ({"torso": (2, 0, 1), "leg_r": (4, 1, 1), "leg_l": (-3, -1, -2), "lantern": (8, 0, 0),
              "cape_l": (-3, 0, 0), "cape_r": (3, 0, 0), "arm_l": (-4, 0, 0)}, 90),
            ({"torso": (1, 0, 1.5), "leg_r": (2, 0, 0.5), "leg_l": (-2, 0, -3), "lantern": (4, 0, 0),
              "cape_r": (1.5, 0, 0), "arm_l": (-2, 0, 0)}, 80),
            ({"torso": (0, 0, -1), "head": (0, 0, -0.5), "leg_l": (0, 0, -1), "lantern": (-3, 0, 0),
              "cape_l": (2, 0, 0), "cape_r": (-2, 0, 0)}, 90),
        ]),
        # Lantern swing: wind back, hold, strike across, follow through.
        "attack": ("once", [
            ({"torso": (-3, 0, 1), "arm_r": (-28, 0, 0), "lantern": (-20, 0, 0), "head": (-2, 0, 0)}, 2),
            ({"torso": (-5, -1, 1.5), "arm_r": (-46, 0, -1), "lantern": (-30, 0, 0), "head": (-3, 0, 0),
              "cape_l": (3, 0, 0)}, 3),
            ({"torso": (6, 1, 0), "arm_r": (38, 0, 1), "lantern": (34, 0, 0), "head": (3, 0, 0),
              "cape_l": (-4, 0, 0), "cape_r": (5, 0, 0), "leg_r": (2, 1, 0)}, 2),
            ({"torso": (4, 1, 0.5), "arm_r": (52, 0, 2), "lantern": (40, 0, 0), "head": (2, 0, 0),
              "cape_r": (6, 0, 0)}, 3),
            ({"torso": (1, 0, 0.5), "arm_r": (14, 0, 0), "lantern": (10, 0, 0)}, 2),
        ], 2),
        # Anticipation on the base drawing, then the painted cast pose.
        "cast": ("once", [
            ({"torso": (0, 0, 1.5), "arm_r": (-12, 0, 0), "lantern": (-6, 0, 0), "head": (0, 0, 1)}, 2),
            ({"torso": (-1, 0, 2.5), "arm_r": (-24, 0, -1), "lantern": (-10, 0, 0), "head": (0, 0, 2),
              "cape_l": (2, 0, 0), "cape_r": (-2, 0, 0)}, 2),
            ("cast", {"crystal": (-4, 0, -1)}, 2),
            ("cast", {"crystal": (0, 0, -3, 1.08), "torso": (0, 0, -1)}, 3),
            ("cast", {"crystal": (2, 0, -2, 1.04), "torso": (0, 0, -0.5)}, 3),
            ({"torso": (0, 0, 0.5), "arm_r": (-6, 0, 0)}, 2),
        ], 3),
        # The painted recoil, then a stagger back onto the base drawing.
        "hurt": ("once", [
            ("hit", {"torso": (-3, -2, 0), "head": (-5, -1, 0)}, 2),
            ("hit", {}, 3),
            ("hit", {"torso": (2, 1, 0.5), "head": (2, 0, 0)}, 2),
            ({"torso": (-2, 0, 1), "head": (-2, 0, 0), "lantern": (-6, 0, 0)}, 2),
        ], 0),
        # The cloak closes in front of the body.
        "block": ("once", [
            ({"cape_l": (8, 2, 0), "arm_l": (-10, 2, -2), "torso": (0, 0, 1)}, 2),
            ({"cape_l": (14, 4, -1), "arm_l": (-22, 4, -4), "torso": (1, 0, 1.5), "head": (0, 0, 1.5),
              "lantern": (-6, 0, 0)}, 4),
            ({"cape_l": (6, 1, 0), "arm_l": (-8, 1, -1), "torso": (0, 0, 0.5)}, 2),
        ], 1),
        # A low sidestep: crouch, lunge sideways, land.
        "dodge": ("once", [
            ({"torso": (0, 0, 2.5), "head": (0, 0, 1.5), "leg_l": (0, -1, 0), "leg_r": (0, 1, 0)}, 2),
            ({"torso": (-14, -3, 1), "head": (-6, 0, 0), "leg_l": (-10, -3, -1), "leg_r": (12, 2, -3),
              "cape_l": (10, 0, 0), "cape_r": (10, 0, 0), "lantern": (16, 0, 0)}, 3),
            ({"torso": (-4, -1, 2), "leg_l": (-3, -1, 0), "leg_r": (3, 0, 0), "cape_l": (4, 0, 0),
              "lantern": (8, 0, 0)}, 2),
            ({"torso": (0, 0, 0.5), "lantern": (-3, 0, 0)}, 2),
        ], 1),
        # Dazed sway.
        "stunned": ("loop", [
            ({"torso": (-3, 0, 1), "head": (-7, 0, 0), "lantern": (6, 0, 0)}, 160),
            ({"torso": (0, 0, 1.5), "head": (0, 0, 1), "lantern": (0, 0, 0)}, 140),
            ({"torso": (3, 0, 1), "head": (7, 0, 0), "lantern": (-6, 0, 0)}, 160),
            ({"torso": (0, 0, 1.5), "head": (0, 0, 1), "lantern": (0, 0, 0)}, 140),
        ]),
        # Stoops to pick something up.
        "interact": ("once", [
            ({"torso": (4, 0, 2), "head": (6, 0, 1)}, 2),
            ({"torso": (8, 1, 4), "head": (10, 1, 2), "arm_l": (-18, 2, 2), "lantern": (-8, 0, 0)}, 3),
            ({"torso": (3, 0, 1.5), "head": (3, 0, 0.5), "arm_l": (-6, 0, 0)}, 2),
        ], 1),
        # Knees give way and the figure slumps; the card itself then falls.
        "death": ("once", [
            ("hit", {}, 2),
            ({"torso": (-2, 0, 2), "head": (-6, 0, 1), "lantern": (-12, 0, 0), "cape_l": (3, 0, 0)}, 2),
            ({"torso": (2, 0, 5, 1.0, 0.94), "head": (8, 0, 3), "lantern": (18, 0, 4), "arm_l": (8, 0, 1),
              "cape_l": (-3, 0, 2), "cape_r": (4, 0, 1)}, 3),
            ({"torso": (3, 0, 9, 1.02, 0.86), "head": (12, 1, 6), "lantern": (30, -1, 9), "arm_l": (12, 0, 3),
              "cape_l": (-4, 1, 5), "cape_r": (6, 0, 3)}, 4),
        ], 0),
    }


# --------------------------------------------------------------------------
# Shared enemy beats. Each enemy passes the names of its own bones; the
# timing and spacing stay consistent across the bestiary.

HIDE = (0, 0, 0, 0.01)  # collapses a bone to nothing (a thrown bomb)


def _walk(lead_a, lead_b, body="torso", bob=1.0, sway=2.0, lift=3.0, extra_a=None, extra_b=None):
    """Six-drawing stride. lead_a/lead_b: bones that step (legs, hem, claws)."""
    ea = extra_a or {}
    eb = extra_b or {}
    return ("loop", [
        ({body: (-sway, 0, bob), lead_a: (-3, -1, 1), lead_b: (2, 1, -lift * 0.6), **ea}, 95),
        ({body: (-sway * 0.5, 0, bob * 1.5), lead_a: (-1, 0, 0.5), lead_b: (1, 0, -lift)}, 85),
        ({body: (0, 0, -bob), lead_b: (0, 0, -lift * 0.3)}, 95),
        ({body: (sway, 0, bob), lead_b: (3, 1, 1), lead_a: (-2, -1, -lift * 0.6), **eb}, 95),
        ({body: (sway * 0.5, 0, bob * 1.5), lead_b: (1, 0, 0.5), lead_a: (-1, 0, -lift)}, 85),
        ({body: (0, 0, -bob), lead_a: (0, 0, -lift * 0.3)}, 95),
    ])


def _hurt(head="head", body="torso", extra=None):
    e = extra or {}
    return ("once", [
        ({body: (-7, -3, 0), head: (-12, -2, -1), **e}, 2),
        ({body: (-5, -2, 0.5), head: (-8, -1, 0)}, 3),
        ({body: (2, 0, 0.5), head: (3, 0, 0)}, 2),
        ({body: (0, 0, 0.3)}, 1),
    ], 0)


def _stunned(head="head", body="torso", extra=None):
    e = extra or {}
    return ("loop", [
        ({body: (-3, 0, 1), head: (-8, 0, 0), **e}, 170),
        ({body: (0, 0, 1.5), head: (0, 0, 1)}, 150),
        ({body: (3, 0, 1), head: (8, 0, 0)}, 170),
        ({body: (0, 0, 1.5), head: (0, 0, 1)}, 150),
    ])


def _idle(body="torso", head="head", extra=None, depth=1.0):
    e = extra or {}
    return ("loop", [
        ({}, 280),
        ({body: (0, 0, 0.6 * depth), head: (0, 0, 0.4 * depth)}, 230),
        ({body: (0, 0, 1.2 * depth), head: (0, 0, 1.0 * depth), **e}, 320),
        ({body: (0, 0, 0.6 * depth), head: (0, 0, 0.4 * depth)}, 230),
    ])


def _death(slump, body="torso", head="head"):
    """slump: extra bones per frame for the last two drawings."""
    a, b = slump
    return ("once", [
        ({body: (-6, -2, 0), head: (-12, -2, -1)}, 2),
        ({body: (2, 0, 4, 1.0, 0.95), head: (8, 0, 2), **a}, 3),
        ({body: (4, 0, 9, 1.03, 0.86), head: (14, 1, 6), **b}, 4),
    ], 0)


# --------------------------------------------------------------------------
# Chaser: the flayed ghoul.

GHOUL_BONES = [
    Bone("hips", None, (44, 44)),
    Bone("torso", "hips", (44, 42), 0.0, [(18, 0), (68, 0), (68, 44), (18, 44)]),
    Bone("leg_l", "hips", (38, 42), -0.5, [(27, 40), (46, 40), (46, 73), (25, 73)], joint="torso"),
    Bone("leg_r", "hips", (50, 42), -0.5, [(46, 40), (58, 40), (60, 48), (60, 75), (46, 75)], joint="torso"),
    Bone("arm_l", "torso", (27, 20), 1.0, [(4, 40), (16, 22), (28, 8), (31, 24), (27, 40), (26, 75), (0, 75)]),
    Bone("claw_l", "arm_l", (16, 50), 1.1, [(0, 48), (27, 48), (27, 75), (0, 75)]),
    Bone("arm_r", "torso", (58, 18), 1.0, [(52, 8), (68, 10), (79, 28), (84, 75), (59, 75), (59, 36), (54, 30)]),
    Bone("claw_r", "arm_r", (68, 56), 1.1, [(58, 56), (84, 56), (84, 77), (58, 77)]),
    Bone("head", "torso", (34, 32), 0.8, [(24, 6), (43, 6), (44, 37), (25, 37)]),
]


def _ghoul_actions():
    rear = {"torso": (-5, 0, -2), "head": (-8, 0, -1), "arm_l": (20, 0, -2), "arm_r": (-20, 0, -2),
            "claw_l": (8, 0, 0), "claw_r": (-8, 0, 0)}
    return {
        "idle": _idle(extra={"claw_l": (3, 0, 0), "claw_r": (-3, 0, 0)}, depth=1.4),
        "walk": _walk("leg_l", "leg_r", bob=1.5, sway=3,
                      extra_a={"arm_l": (-6, 1, -2), "arm_r": (4, 0, 1)},
                      extra_b={"arm_r": (6, -1, -2), "arm_l": (-4, 0, 1)}),
        "windup": ("loop", [
            (rear, 120),
            ({**rear, "torso": (-6, 0, -2.5), "claw_l": (12, 0, 0), "claw_r": (-12, 0, 0)}, 110),
        ]),
        "attack": ("once", [
            (rear, 2),
            ({**rear, "torso": (-8, -1, -3), "arm_l": (28, 0, -3), "arm_r": (-28, 0, -3)}, 2),
            ({"torso": (8, 3, 3), "head": (10, 2, 2), "arm_l": (-6, 5, 3), "arm_r": (8, -3, 3),
              "claw_l": (-10, 0, 0), "claw_r": (10, 0, 0), "leg_l": (0, 1, 0)}, 2),
            ({"torso": (7, 3, 3.5), "head": (8, 2, 2), "arm_l": (-10, 5, 4), "arm_r": (12, -4, 4),
              "claw_l": (-16, 0, 0), "claw_r": (16, 0, 0)}, 3),
            ({"torso": (2, 1, 1), "head": (2, 0, 0), "arm_l": (-6, 1, 0), "arm_r": (6, 0, 0)}, 2),
        ], 2),
        "hurt": _hurt(extra={"arm_l": (10, 0, 0), "arm_r": (-10, 0, 0)}),
        "block": ("once", [
            ({"arm_l": (-5, 3, -1), "arm_r": (5, -3, -1), "head": (0, 0, 2), "torso": (0, 0, 1)}, 2),
            ({"arm_l": (-8, 4, -2), "arm_r": (8, -4, -2), "claw_l": (-12, 0, 0), "claw_r": (12, 0, 0), "head": (4, 0, 3), "torso": (0, 0, 2)}, 4),
            ({"arm_l": (-6, 2, 0), "arm_r": (6, -2, 0), "torso": (0, 0, 0.5)}, 2),
        ], 1),
        "stunned": _stunned(extra={"arm_l": (6, 0, 0), "arm_r": (-6, 0, 0)}),
        "death": _death((
            {"arm_l": (-8, 0, 2), "arm_r": (8, 0, 2)},
            {"arm_l": (-14, 0, 6), "arm_r": (14, 0, 6), "claw_l": (-10, 0, 0), "claw_r": (10, 0, 0)},
        )),
    }


# --------------------------------------------------------------------------
# Archer: hooded crossbowman.

ARCHER_BONES = [
    Bone("hips", None, (38, 64)),
    Bone("torso", "hips", (38, 62), 0.0, [(2, 0), (76, 0), (76, 66), (2, 66)]),
    Bone("cape", "torso", (26, 28), -0.3, [(0, 26), (30, 26), (32, 46), (28, 72), (0, 72)]),
    Bone("quiver", "torso", (24, 24), -0.5, [(4, 2), (30, 2), (30, 24), (4, 24)]),
    Bone("head", "torso", (41, 31), 0.6, [(29, 0), (56, 0), (57, 32), (29, 32)]),
    Bone("bow", "torso", (30, 40), 1.5, [(20, 31), (76, 31), (76, 66), (36, 66), (20, 44)], back=True),
    Bone("leg_l", "hips", (22, 64), -1.0, [(8, 63), (34, 63), (34, 79), (8, 79)], joint="torso"),
    Bone("leg_r", "hips", (55, 66), -1.0, [(43, 65), (69, 65), (69, 79), (43, 79)], joint="torso"),
]


def _archer_actions():
    aim = {"bow": (-6, 0, -1), "torso": (-2, 0, 0), "head": (-2, 0, 0)}
    return {
        "idle": _idle(extra={"bow": (1.5, 0, 0), "cape": (-1.5, 0, 0)}),
        "walk": _walk("leg_l", "leg_r", extra_a={"bow": (-2, 0, 0), "cape": (3, 0, 0)},
                      extra_b={"bow": (2, 0, 0), "cape": (-3, 0, 0)}),
        "windup": ("loop", [
            (aim, 140),
            ({**aim, "bow": (-7, 0, -1.5)}, 120),
        ]),
        "attack": ("once", [
            (aim, 2),
            ({**aim, "bow": (-8, 0, -1.5), "torso": (-3, 0, 0)}, 3),
            ({"bow": (-14, -4, -1), "torso": (-6, -1, 0), "head": (-7, -1, 0), "cape": (5, 0, 0)}, 2),
            ({"bow": (-4, -1, 0), "torso": (-2, 0, 0), "head": (-2, 0, 0), "cape": (2, 0, 0)}, 2),
            ({"bow": (9, 0, 2), "torso": (2, 0, 1), "head": (3, 0, 1)}, 2),
            ({"bow": (2, 0, 0.5)}, 1),
        ], 2),
        "hurt": _hurt(extra={"bow": (6, 0, 1), "cape": (5, 0, 0)}),
        "block": ("once", [
            ({"bow": (-12, -2, -3), "head": (0, 0, 1), "torso": (-2, 0, 1)}, 2),
            ({"bow": (-18, -3, -5), "head": (2, 0, 2), "torso": (-3, 0, 1.5)}, 4),
            ({"bow": (-5, -1, -1), "torso": (0, 0, 0.5)}, 2),
        ], 1),
        "stunned": _stunned(extra={"bow": (6, 0, 1)}),
        "death": _death((
            {"bow": (14, 0, 4), "cape": (4, 0, 2)},
            {"bow": (28, -2, 10), "cape": (6, 0, 4), "quiver": (8, 0, 3)},
        )),
    }


# --------------------------------------------------------------------------
# Brute: armoured skull knight with a cleaver.

BRUTE_BONES = [
    Bone("hips", None, (46, 72)),
    Bone("torso", "hips", (46, 70), 0.0, [(0, 2), (88, 2), (88, 72), (0, 72)]),
    Bone("head", "torso", (46, 29), 0.6, [(36, 0), (57, 0), (57, 30), (36, 30)]),
    Bone("loin", "hips", (50, 60), 0.5, [(40, 58), (60, 58), (60, 96), (40, 96)], joint="torso"),
    Bone("leg_l", "hips", (26, 74), -1.0, [(6, 70), (24, 70), (24, 97), (6, 97)], joint="torso"),
    Bone("leg_r", "hips", (64, 74), -1.0, [(58, 72), (82, 72), (82, 97), (58, 97)], joint="torso"),
    Bone("arm_l", "torso", (24, 36), 1.0, [(0, 38), (30, 38), (30, 70), (0, 70)], back=8),
    Bone("arm_r", "torso", (68, 36), 1.0, [(60, 38), (88, 38), (88, 76), (60, 76)], back=True),
    Bone("cleaver", "arm_l", (22, 68), 2.0, [(18, 66), (52, 66), (52, 95), (18, 95)], back=14),
]


def _brute_actions():
    raise_ = {"arm_l": (24, 0, -3), "cleaver": (22, 0, 0), "torso": (-4, 0, -1), "head": (-3, 0, 0)}
    return {
        "idle": _idle(extra={"arm_l": (1.5, 0, 0.5), "arm_r": (-1.5, 0, 0.5)}, depth=1.3),
        "walk": _walk("leg_l", "leg_r", bob=2.0, sway=2.5, lift=3.5,
                      extra_a={"loin": (3, 0, 0), "arm_r": (-3, 0, 0)},
                      extra_b={"loin": (-3, 0, 0), "arm_l": (3, 0, 0)}),
        "windup": ("loop", [
            (raise_, 150),
            ({**raise_, "arm_l": (27, 0, -3.5), "torso": (-5, 0, -1.5)}, 130),
        ]),
        "attack": ("once", [
            (raise_, 2),
            ({**raise_, "arm_l": (34, 0, -5), "cleaver": (30, 0, 0), "torso": (-7, -1, -2), "head": (-5, 0, 0)}, 3),
            ({"arm_l": (-14, 3, 4), "cleaver": (-22, 0, 0), "torso": (8, 2, 3), "head": (6, 1, 2),
              "arm_r": (6, 0, 2), "loin": (-5, 0, 0)}, 2),
            ({"arm_l": (-16, 3, 5), "cleaver": (-26, 0, 0), "torso": (9, 2, 4), "head": (7, 1, 3),
              "arm_r": (6, 0, 2)}, 3),
            ({"arm_l": (-4, 1, 1), "cleaver": (-6, 0, 0), "torso": (2, 0, 1)}, 2),
        ], 2),
        "hurt": _hurt(extra={"arm_l": (6, 0, 0), "arm_r": (-6, 0, 0)}),
        "block": ("once", [
            ({"arm_r": (16, -4, -3), "arm_l": (-10, 3, -2), "head": (0, 0, 2), "torso": (0, 0, 1)}, 2),
            ({"arm_r": (26, -6, -5), "arm_l": (-16, 4, -3), "head": (0, 0, 4), "torso": (0, 0, 2)}, 4),
            ({"arm_r": (8, -2, -1), "arm_l": (-5, 1, -1), "torso": (0, 0, 0.5)}, 2),
        ], 1),
        "stunned": _stunned(extra={"arm_l": (5, 0, 0), "arm_r": (-5, 0, 0)}),
        "death": _death((
            {"arm_l": (-6, 0, 3), "arm_r": (6, 0, 3), "cleaver": (-14, 0, 2)},
            {"arm_l": (-10, 0, 7), "arm_r": (10, 0, 7), "cleaver": (-30, 2, 4), "loin": (0, 0, 2)},
        )),
    }


# --------------------------------------------------------------------------
# Bomber: hooded skull with a lit bomb.

BOMBER_BONES = [
    Bone("hips", None, (38, 62)),
    Bone("torso", "hips", (38, 60), 0.0, [(0, 0), (75, 0), (75, 62), (0, 62)]),
    Bone("head", "torso", (41, 31), 0.6, [(28, 0), (54, 0), (54, 32), (28, 32)]),
    Bone("bombs_l", "torso", (22, 30), 0.5, [(0, 28), (26, 28), (26, 60), (0, 60)]),
    Bone("arm_l", "torso", (24, 24), 1.0, [(18, 20), (31, 20), (31, 44), (18, 44)]),
    Bone("bomb", "arm_r", (60, 44), 1.5, [(54, 6), (75, 6), (75, 50), (42, 50), (42, 33), (54, 33)], back=8),
    Bone("arm_r", "torso", (50, 32), 2.0, [(54, 36), (71, 36), (71, 54), (54, 54)], back=6),
    Bone("leg_l", "hips", (22, 62), -1.0, [(6, 61), (32, 61), (32, 78), (6, 78)], joint="torso"),
    Bone("leg_r", "hips", (44, 58), 0.2, [(33, 50), (57, 50), (57, 78), (33, 78)], joint="torso"),
]


def _bomber_actions():
    wind = {"arm_r": (-40, 0, -2), "torso": (-4, 0, 0), "head": (-3, 0, 0)}
    return {
        "idle": _idle(extra={"bomb": (2, 0, 0), "bombs_l": (-1.5, 0, 0)}),
        "walk": _walk("leg_l", "leg_r", lift=2.5, extra_a={"bombs_l": (3, 0, 0), "arm_r": (-4, 0, 0)},
                      extra_b={"bombs_l": (-3, 0, 0), "arm_r": (4, 0, 0)}),
        "windup": ("loop", [
            (wind, 120),
            ({**wind, "arm_r": (-44, 0, -2.5), "bomb": (4, 0, 0)}, 110),
        ]),
        "attack": ("once", [
            (wind, 2),
            ({"arm_r": (-62, 1, -3), "torso": (-8, -1, 0), "head": (-6, 0, 0), "bombs_l": (4, 0, 0)}, 3),
            ({"arm_r": (30, -4, 2), "bomb": HIDE, "torso": (8, 2, 1), "head": (6, 1, 1), "bombs_l": (-4, 0, 0)}, 2),
            ({"arm_r": (40, -5, 3), "bomb": HIDE, "torso": (7, 2, 1.5), "head": (5, 1, 1)}, 3),
            ({"arm_r": (8, 0, 0.5), "torso": (1, 0, 0.5)}, 2),
        ], 2),
        "hurt": _hurt(extra={"arm_r": (8, 0, 0), "bombs_l": (6, 0, 0)}),
        "block": ("once", [
            ({"arm_l": (-14, 3, -2), "bombs_l": (-6, 2, -1), "head": (0, 0, 2), "torso": (0, 0, 1)}, 2),
            ({"arm_l": (-24, 4, -3), "bombs_l": (-10, 3, -2), "head": (4, 0, 3), "torso": (0, 0, 1.5)}, 4),
            ({"arm_l": (-6, 1, 0), "bombs_l": (-3, 1, 0), "torso": (0, 0, 0.5)}, 2),
        ], 1),
        "stunned": _stunned(extra={"bomb": (6, 0, 0)}),
        "death": _death((
            {"arm_r": (16, 0, 3), "bombs_l": (-6, 0, 2)},
            {"arm_r": (30, 0, 8), "bombs_l": (-10, 0, 5), "bomb": (20, 0, 4)},
        )),
    }


# --------------------------------------------------------------------------
# Custodian: the bishop who shields his allies.

BISHOP_BONES = [
    Bone("hips", None, (32, 74)),
    Bone("torso", "hips", (32, 72), 0.0, [(0, 24), (68, 24), (68, 78), (0, 78)]),
    Bone("head", "torso", (31, 30), 0.6, [(17, 0), (43, 0), (43, 33), (17, 33)]),
    Bone("hem", "hips", (32, 78), -0.5, [(0, 78), (68, 78), (68, 95), (0, 95)], joint="torso", reach=40),
    Bone("arm_l", "torso", (22, 40), 1.0, [(1, 36), (24, 36), (24, 78), (1, 78)], back=True),
    Bone("arm_r", "torso", (46, 38), 1.0, [(44, 34), (64, 34), (64, 72), (44, 72)], back=True),
    Bone("staff", "arm_r", (53, 46), 2.0,
         [(39, 3), (68, 3), (68, 31), (58, 31), (58, 95), (47, 95), (47, 31), (39, 31)]),
]


def _bishop_actions():
    lift = {"arm_r": (-10, 0, -4), "staff": (-6, 0, -2), "torso": (-2, 0, -0.5), "head": (-3, 0, 0)}
    return {
        "idle": _idle(extra={"staff": (1.5, 0, 0)}, depth=0.9),
        # A gliding walk: the hem swings while the robe barely bobs.
        "walk": ("loop", [
            ({"torso": (-1.5, 0, 0.5), "hem": (-4, -1, 0), "staff": (-3, 0, 0), "arm_l": (3, 0, 0)}, 110),
            ({"torso": (0, 0, -0.5), "hem": (0, 0, -0.5), "staff": (0, 0, -0.5)}, 100),
            ({"torso": (1.5, 0, 0.5), "hem": (4, 1, 0), "staff": (3, 0, 0), "arm_l": (-3, 0, 0)}, 110),
            ({"torso": (0, 0, -0.5), "hem": (0, 0, -0.5), "staff": (0, 0, -0.5)}, 100),
        ]),
        "windup": ("loop", [
            (lift, 150),
            ({**lift, "staff": (-7, 0, -3)}, 130),
        ]),
        "attack": ("once", [
            (lift, 2),
            ({"arm_r": (-16, 0, -6), "staff": (-12, 0, -3), "torso": (-4, 0, -1), "head": (-5, 0, 0)}, 3),
            ({"arm_r": (14, -2, 2), "staff": (18, 0, 2), "torso": (5, 1, 1), "head": (4, 0, 1)}, 2),
            ({"arm_r": (16, -2, 3), "staff": (22, 0, 3), "torso": (6, 1, 1.5), "head": (5, 0, 1)}, 3),
            ({"arm_r": (3, 0, 0), "staff": (4, 0, 0)}, 2),
        ], 2),
        # Protect: the crozier is raised and planted, a ward goes up.
        "cast": ("once", [
            (lift, 2),
            ({"arm_r": (-18, 0, -9), "staff": (-4, 0, -6), "arm_l": (14, 0, -4), "torso": (-2, 0, -1.5),
              "head": (-4, 0, -1)}, 3),
            ({"arm_r": (-6, 0, -3), "staff": (0, 0, 1), "arm_l": (18, 0, -6), "torso": (0, 0, 1), "head": (0, 0, 1)}, 3),
            ({"arm_r": (-4, 0, -2), "staff": (0, 0, 1), "arm_l": (10, 0, -3), "torso": (0, 0, 0.5)}, 3),
        ], 2),
        "hurt": _hurt(extra={"staff": (6, 0, 0), "arm_l": (8, 0, 0)}),
        "block": ("once", [
            ({"arm_r": (-8, -3, -2), "staff": (-10, -2, 0), "head": (0, 0, 1)}, 2),
            ({"arm_r": (-12, -5, -3), "staff": (-14, -3, 0), "head": (0, 0, 2), "arm_l": (-10, 2, -2)}, 4),
            ({"arm_r": (-4, -1, -1), "staff": (-4, -1, 0)}, 2),
        ], 1),
        "stunned": _stunned(extra={"staff": (5, 0, 0)}),
        "death": _death((
            {"staff": (12, 0, 3), "arm_l": (8, 0, 2), "hem": (0, 0, 1)},
            {"staff": (26, 0, 8), "arm_l": (12, 0, 5), "hem": (0, 0, 2)},
        )),
    }


# --------------------------------------------------------------------------
# Demolitionist: the crowned archmage who calls down fire.

ARCHMAGE_BONES = [
    Bone("hips", None, (42, 80)),
    Bone("torso", "hips", (42, 78), 0.0, [(16, 28), (66, 28), (66, 82), (16, 82)]),
    Bone("halo", "torso", (42, 24), -0.4, [(19, 0), (67, 0), (67, 36), (19, 36)]),
    Bone("skull", "torso", (42, 34), 0.6, [(34, 18), (50, 18), (50, 35), (34, 35)]),
    Bone("hem", "hips", (42, 82), -0.5, [(0, 82), (84, 82), (84, 95), (0, 95)], joint="torso", reach=44),
    Bone("arm_l", "torso", (22, 42), 1.0, [(0, 6), (23, 6), (23, 95), (13, 95), (9, 82), (0, 82)], back=True),
    Bone("arm_r", "torso", (60, 44), 1.0, [(57, 40), (84, 40), (84, 82), (57, 82)], back=True),
    Bone("flame", "arm_r", (70, 42), 2.0, [(59, 19), (84, 19), (84, 42), (59, 42)]),
]


def _archmage_actions():
    call = {"arm_r": (-10, 0, -4), "flame": (0, 0, -2, 1.1), "halo": (4, 0, 0), "torso": (-2, 0, 0)}
    return {
        "idle": ("loop", [
            ({}, 260),
            ({"halo": (3, 0, 0), "flame": (0, 0, -0.5, 1.04), "torso": (0, 0, 0.5)}, 240),
            ({"halo": (6, 0, 0), "flame": (0, 0, -1, 1.08), "torso": (0, 0, 1), "skull": (0, 0, 0.8)}, 300),
            ({"halo": (3, 0, 0), "flame": (0, 0, -0.5, 1.04), "torso": (0, 0, 0.5)}, 240),
        ]),
        "walk": ("loop", [
            ({"torso": (-1.5, 0, 0.5), "hem": (-4, -1, 0), "arm_l": (3, 0, 0), "halo": (-2, 0, 0)}, 110),
            ({"torso": (0, 0, -0.5), "hem": (0, 0, -0.5), "flame": (0, 0, 0, 1.05)}, 100),
            ({"torso": (1.5, 0, 0.5), "hem": (4, 1, 0), "arm_l": (-3, 0, 0), "halo": (2, 0, 0)}, 110),
            ({"torso": (0, 0, -0.5), "hem": (0, 0, -0.5), "flame": (0, 0, 0, 1.05)}, 100),
        ]),
        "windup": ("loop", [
            (call, 120),
            ({**call, "flame": (0, 0, -3, 1.16), "halo": (8, 0, 0)}, 110),
        ]),
        "attack": ("once", [
            ({"arm_l": (8, 0, -2), "torso": (-2, 0, 0), "skull": (-3, 0, 0)}, 2),
            ({"arm_l": (14, 0, -4), "torso": (-4, 0, -1), "skull": (-5, 0, 0)}, 3),
            ({"arm_l": (-14, 4, 1), "torso": (5, 1, 1), "skull": (4, 0, 1), "halo": (-6, 0, 0)}, 2),
            ({"arm_l": (-18, 5, 2), "torso": (6, 1, 1.5), "skull": (5, 0, 1)}, 3),
            ({"arm_l": (-4, 1, 0), "torso": (1, 0, 0.5)}, 2),
        ], 2),
        # Bombard: the burning hand is raised high, then thrown forward.
        "cast": ("once", [
            (call, 2),
            ({"arm_r": (-22, 0, -8), "flame": (0, 0, -4, 1.2), "halo": (10, 0, 0), "torso": (-3, 0, -1),
              "skull": (-4, 0, -1), "arm_l": (6, 0, -2)}, 3),
            ({"arm_r": (16, -3, 0), "flame": (0, -2, 0, 0.8), "halo": (-6, 0, 0), "torso": (4, 1, 1),
              "skull": (4, 0, 1)}, 2),
            ({"arm_r": (10, -2, 0), "flame": (0, 0, 0, 0.9), "torso": (2, 0, 1)}, 3),
        ], 2),
        "hurt": _hurt(head="skull", extra={"halo": (-6, 0, 0), "flame": (0, 0, 0, 0.9)}),
        "block": ("once", [
            ({"arm_l": (-10, 3, -2), "arm_r": (8, -2, -1), "skull": (0, 0, 1)}, 2),
            ({"arm_l": (-16, 5, -3), "arm_r": (12, -3, -2), "skull": (0, 0, 2), "halo": (-4, 0, 1)}, 4),
            ({"arm_l": (-5, 1, -1), "arm_r": (4, -1, 0)}, 2),
        ], 1),
        "stunned": _stunned(head="skull", extra={"halo": (10, 0, 0)}),
        "death": _death((
            {"halo": (-12, 0, 3), "arm_l": (10, 0, 3), "flame": (0, 0, 3, 0.7)},
            {"halo": (-24, 0, 8), "arm_l": (18, 0, 6), "arm_r": (8, 0, 4), "flame": HIDE, "hem": (0, 0, 2)},
        ), head="skull"),
    }


CHARACTERS = {
    "pilgrim": {
        "figures": {"base": 0, "cast": 12, "hit": 13},
        "rigs": {"base": PILGRIM_BONES, "cast": PILGRIM_CAST_BONES, "hit": PILGRIM_HIT_BONES},
        "roots": {"base": "hips", "cast": "hips", "hit": "hips"}, "height": 1.35,
        "actions": _pilgrim_actions,
    },
    "ghoul": {"figures": {"base": 1}, "rigs": {"base": GHOUL_BONES}, "roots": {"base": "hips"}, "height": 1.19,
              "actions": _ghoul_actions},
    "archer": {"figures": {"base": 2}, "rigs": {"base": ARCHER_BONES}, "roots": {"base": "hips"}, "height": 1.35,
               "actions": _archer_actions},
    "brute": {"figures": {"base": 3}, "rigs": {"base": BRUTE_BONES}, "roots": {"base": "hips"}, "height": 1.56,
              "actions": _brute_actions},
    "bomber": {"figures": {"base": 4}, "rigs": {"base": BOMBER_BONES}, "roots": {"base": "hips"}, "height": 1.35,
               "actions": _bomber_actions},
    "bishop": {"figures": {"base": 5}, "rigs": {"base": BISHOP_BONES}, "roots": {"base": "hips"}, "height": 1.35,
               "actions": _bishop_actions},
    "archmage": {"figures": {"base": 6}, "rigs": {"base": ARCHMAGE_BONES}, "roots": {"base": "hips"}, "height": 1.65,
                 "actions": _archmage_actions},
}
