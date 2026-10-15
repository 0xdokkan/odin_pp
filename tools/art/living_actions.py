"""Choreography of the living cards (see living.py).

Times are milliseconds. Bones take (angle, dx, dy[, sx, sy]) as in
characters.py: angles in degrees, positive = clockwise on screen, so a
limb hanging from its pivot swings its end backwards (left) with a positive
angle and forwards (right) with a negative one, and a body leans forward with
a positive angle. `root` = (x, y, rot, sx, sy) moves the whole figure inside
its card: +x forward, -y up, `rot` turns it about its middle (positive = a
forward roll) and (sx, sy) squash it about its feet. Every print faces right
and is mirrored on the board to face left. Pencil marks (`fx`) are placed in
pixels from the resting feet.

The principles of hand animation drive every clip: anticipation before each
effort, squash and stretch, arcs, slow in and out, follow-through and
overlapping action (the soft parts swing on their own), and holds on the
strongest drawings. Clips are drawn on twos and switch to ones only for the
fastest instants.

Each character acts in its own way. The Viandante shoves his paper with a
shoulder or a kick; the ghoul bounds on all fours and claws; the archer darts
low with the crossbow levelled and is thrown back by its kick; the brute
stomps twice per cell; the bomber hops; the custodian levitates and punts the
card along with his crozier; the archmage drifts.

The Viandante's actions last one second, as the timed actions of the mechanics
lab do; the enemies act at most once per world beat. A reaction to a blow
(hurt, block, death) waits ~100 ms so it lands with the attacker's strike.
"""
from living import K, clip

HIDE = (0, 0, 0, 0.01)   # collapses a bone to nothing (a thrown bomb)
REACT = 100              # a reaction starts this long after its cue
STRIKE = REACT + 15      # ...and lands here


# --------------------------------------------------------------------------
# Shared reactions. Each character passes its own bones.

def hurt(body, head, flung=None, push=15, turn=11, settle=None, mark=(12, -44)):
    """Thrown back against the rear edge of the card, then recovering."""
    f = flung or {}
    s = settle or {}
    return clip([
        K(0), K(REACT, "hold"),
        K(STRIKE, "snap", root=(-push, -2, -turn, 0.86, 1.07), **{body: (-9, -2, 0), head: (-15, -2, -1)}, **f),
        K(200, "out", root=(-push - 1, -1, -turn + 1, 0.9, 1.04), **{body: (-7, -1, 0.5), head: (-11, -1, 0)}, **f),
        K(360, "io", root=(-push + 5, 0, -3, 1.04, 0.96), **{body: (2, 0, 0.5), head: (3, 0, 0)}, **s),
        K(520, "io", root=(-4, 0, 0), **{body: (-1, 0, 0)}),
        K(760, "io"),
    ], hit=STRIKE, ones=[(REACT, 220)], fx=[("impact", STRIKE + 3, mark[0], mark[1])])


def hurt_back(body, head, flung=None, push=13, turn=11, mark=(-12, -44)):
    """Struck from behind: pitched forward against the front edge."""
    f = flung or {}
    return clip([
        K(0), K(REACT, "hold"),
        K(STRIKE, "snap", root=(push, -2, turn, 0.86, 1.07), **{body: (11, 1, 0), head: (13, 1, 0)}, **f),
        K(200, "out", root=(push + 1, -1, turn - 1, 0.9, 1.04), **{body: (9, 1, 0), head: (10, 1, 0)}, **f),
        K(360, "io", root=(push - 5, 0, 3, 1.04, 0.96), **{body: (2, 0, 0.5), head: (2, 0, 0)}),
        K(520, "io", root=(4, 0, 0)),
        K(760, "io"),
    ], hit=STRIKE, ones=[(REACT, 220)], fx=[("impact", STRIKE + 3, mark[0], mark[1])])


def stunned(body, head, a=None, b=None, sway=7):
    """Staggering from one side of the card to the other."""
    return clip([
        K(0, root=(-sway, 0, -7), **{body: (-5, 0, 1), head: (-12, 0, 0)}, **(a or {})),
        K(420, "io", root=(0, 0, 0, 1.03, 0.97), **{body: (0, 0, 1.5), head: (0, 0, 1)}),
        K(840, "io", root=(sway + 2, 0, 8), **{body: (6, 0, 1), head: (13, 0, 0)}, **(b or {})),
        K(1260, "io", root=(0, 0, 0, 1.03, 0.97), **{body: (0, 0, 1.5), head: (0, 0, 1)}),
    ], loop=1680)


def block(guard, hold=None, body="torso", head="head"):
    """Braced behind a guard, shoved back a little by the blow."""
    h = hold or guard
    return clip([
        K(0), K(60, "io", root=(-1, 0, 0, 1.02, 0.98), **{body: (0, 0, 1)}, **guard),
        K(STRIKE, "snap", root=(-7, 0, 0, 1.07, 0.92), **{body: (1, 0, 2), head: (0, 0, 2)}, **guard),
        K(300, "out", root=(-8, 0, 0, 1.05, 0.94), **{body: (1, 0, 2), head: (0, 0, 2)}, **h),
        K(460, "io", root=(-4, 0, 0)),
        K(640, "io"),
    ], hit=STRIKE, ones=[(REACT, 200)], fx=[("impact", STRIKE + 3, 16, -40)])


def death_back(body, head, slump, lie=8, turn=-84):
    """Knocked back, the figure crumples and lies at the bottom of the card;
    the card itself then topples (runtime)."""
    a, b = slump
    return clip([
        K(0), K(REACT, "hold"),
        K(STRIKE, "snap", root=(-13, -2, -12, 0.88, 1.06), **{body: (-6, -2, 0), head: (-12, -2, -1)}),
        K(260, "out", root=(-14, -1, -14, 0.94, 1.02), **{body: (-6, -1, 0), head: (-10, -1, 0)}),
        K(520, "in", root=(-11, lie * 0.4, turn * 0.5, 1, 0.94), **{body: (4, 0, 5), head: (10, 0, 3)}, **a),
        K(690, "out", root=(-8, lie, turn, 1.04, 0.9), **{body: (6, 0, 8, 1.02, 0.88), head: (12, 1, 6)}, **b),
        K(790, "out", root=(-8, lie - 3, turn + 4, 1, 0.92), **{body: (6, 0, 8, 1.02, 0.88), head: (12, 1, 6)}, **b),
        K(920, "in", root=(-8, lie, turn, 1.03, 0.9), **{body: (6, 0, 8, 1.02, 0.88), head: (12, 1, 6)}, **b),
        K(1080, "io", root=(-8, lie, turn, 1, 0.92), **{body: (6, 0, 8, 1.02, 0.88), head: (12, 1, 6)}, **b),
    ], hit=STRIKE, ones=[(REACT, 200)], fx=[("impact", STRIKE + 3, 12, -44), ("dust", 690, -14, 0)])


def death_forward(body, head, slump, lie=6, turn=80):
    """Drops to its knees and falls on its face."""
    a, b = slump
    return clip([
        K(0), K(REACT, "hold"),
        K(STRIKE, "snap", root=(-7, -1, -8, 0.9, 1.05), **{body: (-6, -1, 0), head: (-10, -1, 0)}),
        K(300, "out", root=(0, 4, 0, 1.06, 0.84), **{body: (6, 0, 4), head: (8, 0, 2)}, **a),
        K(440, "hold", root=(0, 4, 0, 1.06, 0.84), **{body: (6, 0, 4), head: (8, 0, 2)}, **a),
        K(620, "in", root=(7, lie, turn, 1, 0.92), **{body: (8, 0, 6), head: (12, 0, 3)}, **b),
        K(710, "out", root=(8, lie - 3, turn - 5, 1, 0.92), **{body: (8, 0, 6), head: (12, 0, 3)}, **b),
        K(840, "in", root=(8, lie, turn, 1, 0.92), **{body: (8, 0, 6), head: (12, 0, 3)}, **b),
        K(1000, "io", root=(8, lie, turn, 1, 0.92), **{body: (8, 0, 6), head: (12, 0, 3)}, **b),
    ], hit=STRIKE, ones=[(REACT, 200)], fx=[("impact", STRIKE + 3, 12, -40), ("dust", 300, 0, 0), ("dust", 620, 20, 0)])


# --------------------------------------------------------------------------
# The Viandante.

def pilgrim():
    side = [
        K(0),
        # Weight back, then a deep coil: the anticipation of the shove.
        K(100, "io", root=(-3, 0, 0, 1.02, 0.98), torso=(-5, 0, 1), head=(-3, 0, 0)),
        K(190, "out", root=(-9, 1, 0, 1.07, 0.91), torso=(-14, 0, 2, 1.05, 0.93), head=(-7, 0, 1), arm_r=(14, 0, 0),
          lantern=(-4, 0, 0), leg_l=(6, -1, 0), leg_r=(-8, -2, -3)),
        K(240, "in", root=(-3, 0, 0, 0.95, 1.05), torso=(12, 0, 0, 0.96, 1.05), head=(5, 0, 0), arm_r=(16, 0, 0),
          leg_l=(-8, -2, 0), leg_r=(6, 2, -2)),
        # Shoulder first into the front edge of the card, squashed by the blow.
        K(275, "snap", root=(20, -1, 0, 0.86, 1.1), torso=(24, 1, 0, 0.9, 1.06), head=(12, 0, 0), arm_r=(20, 0, 1),
          leg_l=(-18, -4, -1), leg_r=(8, 3, -1)),
        K(330, "hold", root=(20, -1, 0, 0.88, 1.08), torso=(23, 1, 0, 0.92, 1.05), head=(11, 0, 0), arm_r=(19, 0, 1),
          leg_l=(-17, -4, -1), leg_r=(8, 3, -1)),
        # Still pushing while the card slides away.
        K(430, "out", root=(16, 0, 0, 0.95, 1.04), torso=(18, 0, 0), head=(8, 0, 0), arm_r=(14, 0, 0),
          leg_l=(-10, -2, 0), leg_r=(6, 2, -2)),
        # The card stops; he is carried on and catches himself.
        K(540, "out", root=(19, 0, 0), torso=(8, 0, 0.5), head=(3, 0, 0), leg_l=(2, 0, -1)),
        K(640, "io", root=(14, 0, 0, 1.05, 0.95), torso=(-5, 0, 1), head=(-4, 0, 0)),
        # Two small steps back to the middle of the card.
        K(760, "io", root=(7, 0, 0), torso=(-2, 0, 0), leg_r=(-8, -1, -3)),
        K(870, "io", root=(2, 0, 0), leg_l=(5, -1, -2)),
        K(1000, "io"),
    ]
    up = [
        K(0),
        K(110, "io", root=(-3, 0, 0, 1.03, 0.97), torso=(-4, 0, 1)),
        K(200, "out", root=(-7, 1, 0, 1.09, 0.88), torso=(-6, 0, 3, 1.04, 0.92), head=(-3, 0, 2), arm_r=(12, 0, 0),
          leg_l=(2, -1, 0), leg_r=(-2, 1, 0)),
        K(250, "in", root=(4, -8, 0, 0.93, 1.1), torso=(14, 0, -1), head=(6, 0, -1), leg_l=(-12, -2, -3), leg_r=(12, 2, -4)),
        # A leaping shoulder charge into the upper front corner.
        K(285, "snap", root=(19, -20, 4, 0.9, 0.96), torso=(26, 1, 0), head=(14, 0, 0), arm_r=(22, 0, -1),
          leg_l=(-22, -4, -4), leg_r=(16, 3, -5)),
        K(340, "hold", root=(19, -19, 4, 0.92, 0.97), torso=(25, 1, 0), head=(13, 0, 0), arm_r=(21, 0, -1),
          leg_l=(-21, -4, -4), leg_r=(15, 3, -5)),
        K(450, "in", root=(14, -6, 2, 0.97, 1.04), torso=(10, 0, 0), head=(4, 0, 0), leg_l=(-4, 0, -1), leg_r=(4, 0, -2)),
        K(500, "out", root=(12, 0, 0, 1.1, 0.88), torso=(4, 0, 2), head=(2, 0, 1)),
        K(620, "io", root=(9, 0, 0, 0.98, 1.02), torso=(-3, 0, 0)),
        K(760, "io", root=(5, 0, 0), leg_r=(-6, -1, -2)),
        K(880, "io", root=(1, 0, 0), leg_l=(4, -1, -1)),
        K(1000, "io"),
    ]
    down = [
        K(0),
        K(110, "io", root=(-3, 0, 0), torso=(-6, 0, 1)),
        # Leans back and chambers the knee...
        K(200, "out", root=(-6, 0, 0, 1.03, 0.96), torso=(-14, 0, 1), head=(-7, 0, 0), leg_r=(-28, 1, -6), arm_r=(-16, 0, 0)),
        # ...and kicks the low front of the card, the leg stretched long.
        K(270, "snap", root=(8, 1, 0, 1.04, 0.97), torso=(-20, -1, 0), head=(-9, 0, 0), leg_r=(-66, 5, -6, 1.08, 1.0),
          leg_l=(6, 0, 0), arm_r=(-32, 0, -1)),
        K(330, "hold", root=(8, 1, 0, 1.04, 0.97), torso=(-19, -1, 0), head=(-8, 0, 0), leg_r=(-64, 5, -6, 1.06, 1.0),
          leg_l=(6, 0, 0), arm_r=(-30, 0, -1)),
        K(420, "io", root=(9, 0, 0), torso=(-12, 0, 0), leg_r=(-40, 3, -4), arm_r=(-14, 0, 0)),
        K(500, "io", root=(10, 0, 0), torso=(-4, 0, 0), leg_r=(-10, 1, -2)),
        K(570, "out", root=(9, 0, 0, 1.06, 0.93), torso=(4, 0, 1), leg_r=(0, 0, 0)),
        K(700, "io", root=(5, 0, 0), torso=(-2, 0, 0)),
        K(840, "io", root=(1, 0, 0), leg_l=(4, -1, -1)),
        K(1000, "io"),
    ]
    channel = {"crystal": (0, 0, -2, 1.06)}
    return {
        # Breathes, shifts his weight and glances about.
        "idle": clip([
            K(0),
            K(600, "io", root=(1, 0, 0, 1, 0.985), torso=(0, 0, 0.8), head=(1, 0, 0.6), arm_r=(-3, 0, 0), lantern=(3, 0, 0)),
            K(1100, "io", root=(2, 0, 0), torso=(1, 0, 0.2), head=(4, 0, 0), lantern=(5, 0, 0), cape_l=(-2, 0, 0)),
            K(1500, "io", root=(1, 0, 0, 1.01, 0.98), torso=(0, 0, 1), head=(2, 0, 0.8), lantern=(2, 0, 0)),
            K(2000, "io", root=(-2, 0, 0), torso=(-1, 0, 0.3), head=(-4, 0, 0), lantern=(-4, 0, 0), cape_r=(2, 0, 0),
              leg_l=(0, 0, -1)),
            K(2350, "io", root=(-1, 0, 0, 1, 0.985), torso=(0, 0, 0.8), head=(-1, 0, 0.6)),
        ], loop=2600),
        "move_side": clip(side, travel=("shove", 275, 220), hit=275, ones=[(230, 340)],
                          fx=[("impact", 280, 40, -44), ("speed", 300, 470), ("dust", 640, 16, 0)]),
        "move_up": clip(up, travel=("shove", 285, 220), hit=285, horizontal=0.7, ones=[(240, 350)],
                        fx=[("dust", 205, -6, 0), ("impact", 290, 38, -72), ("dust", 500, 12, 0)]),
        "move_down": clip(down, travel=("shove", 275, 220), hit=275, horizontal=0.7, ones=[(230, 340)],
                          fx=[("impact", 280, 44, -10), ("dust", 570, 16, 0)]),
        # A leaping lantern smash, then a back flip to the middle.
        "attack": clip([
            K(0),
            K(60, "out", root=(-7, 0, 0, 1.05, 0.94), torso=(-12, 0, 2), head=(-5, 0, 0), arm_r=(-120, 0, -1),
              lantern=(-25, 0, 0)),
            K(120, "snap", root=(18, -9, 0, 0.88, 1.1), torso=(22, 1, 0, 0.92, 1.06), head=(10, 0, 0), arm_r=(-20, 1, 2),
              lantern=(45, 0, 0), leg_l=(-16, -3, -3), leg_r=(12, 2, -4)),
            K(170, "hold", root=(18, -8, 0, 0.9, 1.08), torso=(21, 1, 0, 0.93, 1.05), head=(9, 0, 0), arm_r=(-16, 1, 2),
              lantern=(50, 0, 0), leg_l=(-15, -3, -3), leg_r=(11, 2, -4)),
            K(270, "out", root=(15, -4, 0, 0.95, 1.03), torso=(14, 1, 0), arm_r=(-8, 1, 2), lantern=(62, 0, 0),
              leg_l=(-8, -1, -2), leg_r=(7, 1, -2)),
            K(340, "in", root=(12, 0, 0), torso=(8, 0, 0), arm_r=(5, 0, 1), lantern=(30, 0, 0), leg_l=(-4, 0, -1), leg_r=(4, 0, -1)),
            K(380, "out", root=(11, 0, 0, 1.09, 0.9), torso=(5, 0, 2), arm_r=(6, 0, 0), lantern=(10, 0, 0)),
            K(470, "out", root=(6, -13, -150), arm_r=(-20, 0, 0), leg_l=(-10, -2, -3), leg_r=(10, 2, -3)),
            K(550, "lin", root=(2, -10, -300), leg_l=(-6, -1, -2), leg_r=(6, 1, -2)),
            K(610, "out", root=(0, 0, -360, 1.1, 0.88)),
            K(720, "io", root=(0, 0, -360, 0.97, 1.03)),
            K(850, "io", root=(0, 0, -360)),
            K(1000, "io", root=(0, 0, -360)),
        ], hit=120, ones=[(40, 190), (440, 620)],
            fx=[("speed", 70, 125), ("impact", 125, 46, -36), ("dust", 380, 16, 0), ("dust", 610, 0, 0)]),
        # Crouches, rises on the painted cast pose and lands holding it.
        "cast": clip([
            K(0),
            K(110, "out", root=(0, 0, 0, 1.07, 0.91), torso=(0, 0, 2), head=(0, 0, 1), arm_r=(-14, 0, 0), lantern=(-8, 0, 0)),
            K(170, "in", root=(0, -7, 0, 0.95, 1.07), arm_r=(-30, 0, -1)),
            K(178, "hold", "cast", root=(0, -9, 0), crystal=(-4, 0, -1)),
            K(250, "out", "cast", root=(0, -13, 0), crystal=(-4, 0, -2, 1.1)),
            K(400, "io", "cast", root=(0, -14, 0), crystal=(4, 0, -4, 1.16)),
            K(520, "in", "cast", root=(0, -2, 0), crystal=(0, 0, -2, 1.06)),
            K(570, "out", "cast", root=(0, 0, 0, 1.06, 0.93), crystal=(0, 0, -2, 1.06)),
            K(720, "io", "cast", root=(0, 0, 0), **channel),
        ], hit=250, ones=[(160, 260)], fx=[("dust", 570, 0, 0)]),
        # While the card is cast: the crystal held high, pulsing.
        "channel": clip([
            K(0, "io", "cast", **channel),
            K(450, "io", "cast", root=(0, -1, 0, 1, 1.01), crystal=(0, 0, -3, 1.12)),
        ], loop=900),
        # The painted recoil, slammed against the rear edge.
        "hurt": clip([
            K(0), K(REACT, "hold"),
            K(STRIKE, "snap", "hit", root=(-16, -2, -12, 0.86, 1.07)),
            K(200, "out", "hit", root=(-17, -1, -11, 0.9, 1.04)),
            K(320, "io", "hit", root=(-14, 1, -5, 1, 0.98)),
            K(332, "hold", root=(-12, 0, -3), torso=(-8, 0, 1), head=(-6, 0, 0), lantern=(-10, 0, 0)),
            K(440, "out", root=(-9, 0, 0, 1.05, 0.94), torso=(-6, 0, 1)),
            K(560, "io", root=(-4, 0, 0), torso=(-2, 0, 0)),
            K(800, "io"),
        ], hit=STRIKE, ones=[(REACT, 220)], fx=[("impact", STRIKE + 3, 14, -46)]),
        "hurt_back": hurt_back("torso", "head", {"lantern": (24, 0, 0), "cape_l": (-10, 0, 0), "leg_l": (-10, -2, -2)}),
        # The cloak closes in front of him.
        "block": block({"cape_l": (14, 4, -1), "arm_l": (-22, 4, -4), "lantern": (-8, 0, 0)},
                       {"cape_l": (16, 4, -1), "arm_l": (-24, 4, -4)}),
        # The two-cell dash: a forward roll that carries the card along.
        "dodge": clip([
            K(0),
            K(80, "out", root=(-4, 0, 0, 1.07, 0.89), torso=(4, 0, 2)),
            K(130, "in", root=(4, -8, 90, 0.9, 0.9), leg_l=(-20, -2, -3), leg_r=(20, 2, -3), arm_r=(20, 0, 0)),
            K(200, "lin", root=(12, -11, 210, 0.85, 0.85), leg_l=(-20, -2, -3), leg_r=(20, 2, -3), arm_r=(20, 0, 0)),
            K(270, "lin", root=(16, -4, 320, 0.9, 0.9), leg_l=(-12, -1, -2), leg_r=(12, 1, -2), arm_r=(10, 0, 0)),
            K(310, "out", root=(14, 0, 360, 1.1, 0.88)),
            K(430, "io", root=(8, 0, 360), torso=(-4, 0, 0)),
            K(600, "io", root=(3, 0, 360)),
            K(1000, "io", root=(0, 0, 360)),
        ], travel=("dash", 80, 260), hit=80, horizontal=1.4, ones=[(120, 320)],
            fx=[("speed", 120, 300), ("dust", 310, 10, 0)]),
        "stunned": stunned("torso", "head", {"lantern": (10, 0, 0)}, {"lantern": (-10, 0, 0)}),
        # Stoops, picks it up and hops back with it.
        "interact": clip([
            K(0),
            K(160, "io", root=(3, 2, 0, 1.03, 0.96), torso=(14, 1, 3), head=(12, 1, 2), arm_l=(-24, 2, 3), lantern=(-10, 0, 0)),
            K(280, "out", root=(4, 3, 0), torso=(18, 1, 4), head=(14, 1, 2), arm_l=(-30, 3, 4)),
            K(380, "io", root=(2, -7, 0, 0.95, 1.06), torso=(-4, 0, 0), arm_l=(-60, 0, -4)),
            K(450, "out", root=(1, 0, 0, 1.07, 0.92)),
            K(640, "io"),
        ], hit=280, fx=[("dust", 450, 0, 0)]),
        "death": clip([
            K(0), K(REACT, "hold"),
            K(STRIKE, "snap", "hit", root=(-13, -2, -10, 0.88, 1.05)),
            K(260, "out", "hit", root=(-14, -1, -12)),
            K(272, "hold", root=(-12, 0, -16, 1, 0.96), torso=(-4, 0, 3), head=(-10, 0, 2), lantern=(-20, 0, 0)),
            K(500, "in", root=(-10, 3, -45, 1, 0.93), torso=(4, 0, 6), head=(10, 0, 4), lantern=(30, 0, 6)),
            K(680, "out", root=(-7, 8, -84, 1.04, 0.9), torso=(6, 0, 8, 1.02, 0.88), head=(12, 1, 6), lantern=(36, -1, 9)),
            K(780, "out", root=(-7, 5, -80, 1, 0.92), torso=(6, 0, 8, 1.02, 0.88), head=(12, 1, 6), lantern=(36, -1, 9)),
            K(900, "in", root=(-7, 8, -84, 1.03, 0.9), torso=(6, 0, 8, 1.02, 0.88), head=(12, 1, 6), lantern=(36, -1, 9)),
            K(1080, "io", root=(-7, 8, -84, 1, 0.92), torso=(6, 0, 8, 1.02, 0.88), head=(12, 1, 6), lantern=(36, -1, 9)),
        ], hit=STRIKE, ones=[(REACT, 220)], fx=[("impact", STRIKE + 3, 14, -46), ("dust", 680, -16, 0)]),
    }


# --------------------------------------------------------------------------
# Chaser: the flayed ghoul bounds on all fours and claws.

def _ghoul_run(lift):
    bound = {"torso": (18, 0, -1), "head": (14, 0, 0), "claw_l": (-16, 0, 0), "claw_r": (-16, 0, 0)}
    land = {"torso": (14, 0, 2), "head": (12, 0, 1)}
    return [
        K(0),
        # Gathers low before the first bound.
        K(90, "out", root=(-4, 0, 0, 1.06, 0.92), torso=(10, 0, 2), head=(8, 0, 2), arm_l=(-8, 2, 0), arm_r=(-12, 2, 0)),
        # Bound: the long arms reach far ahead while the legs kick back...
        K(170, "in", root=(8, -7 * lift, 6, 0.93, 1.08), arm_l=(-36, 3, -4), arm_r=(-40, 3, -4), leg_l=(16, 0, -3),
          leg_r=(20, 0, -3), **bound),
        # ...the claws strike the front edge and drag the card on.
        K(240, "out", root=(16, 0, 4, 1.07, 0.93), arm_l=(-14, 2, 0), arm_r=(-10, 2, 0), claw_l=(-4, 0, 0),
          claw_r=(-2, 0, 0), leg_l=(-12, 0, 0), leg_r=(-8, 0, 0), **land),
        K(320, "in", root=(12, -6 * lift, 6, 0.93, 1.08), arm_l=(-40, 3, -4), arm_r=(-36, 3, -4), leg_l=(20, 0, -3),
          leg_r=(16, 0, -3), **bound),
        K(390, "out", root=(17, 0, 4, 1.07, 0.93), arm_l=(-10, 2, 0), arm_r=(-14, 2, 0), leg_l=(-8, 0, 0),
          leg_r=(-12, 0, 0), **land),
        K(470, "in", root=(13, -6 * lift, 6, 0.93, 1.08), arm_l=(-38, 3, -4), arm_r=(-38, 3, -4), leg_l=(18, 0, -3),
          leg_r=(18, 0, -3), **bound),
        K(540, "out", root=(17, 0, 4, 1.07, 0.93), arm_l=(-12, 2, 0), arm_r=(-12, 2, 0), leg_l=(-10, 0, 0),
          leg_r=(-10, 0, 0), **land),
        # Skids as the card stops, then slinks back to the middle.
        K(660, "io", root=(11, 0, 2, 1.04, 0.97), torso=(8, 0, 1), head=(6, 0, 1), arm_l=(-4, 1, 0), arm_r=(-4, 1, 0)),
        K(900, "io"),
    ]


def ghoul():
    coil = {"torso": (-6, 0, -2), "head": (-8, 0, -1), "arm_l": (22, 0, -3), "arm_r": (-22, 0, -3),
            "claw_l": (10, 0, 0), "claw_r": (-10, 0, 0)}
    run_fx = [("dust", 240, 22, 0), ("dust", 390, 22, 0), ("dust", 540, 22, 0)]
    return {
        # Hunched breathing, a twitch of the head, flexing claws.
        "idle": clip([
            K(0),
            K(450, "io", root=(0, 0, 0, 1.02, 0.97), torso=(0, 0, 1.4), head=(0, 0, 1), claw_l=(3, 0, 0), claw_r=(-3, 0, 0)),
            K(800, "snap", root=(0, 0, 0, 1.01, 0.98), torso=(-2, 0, 0.6), head=(-10, 0, 0)),
            K(1000, "out", torso=(-1, 0, 0.8), head=(-7, 0, 0)),
            K(1400, "io", root=(2, 0, 0, 1.02, 0.97), torso=(2, 0, 1.4), head=(4, 0, 1), claw_l=(5, 0, 0), claw_r=(-5, 0, 0)),
            K(1800, "io", root=(1, 0, 0), torso=(1, 0, 0.4), head=(2, 0, 0)),
        ], loop=2200),
        "move_side": clip(_ghoul_run(1.0), travel=("run", 90, 520), hit=170, ones=[(160, 250)], fx=run_fx),
        "move_up": clip(_ghoul_run(1.7), travel=("run", 90, 520), hit=170, horizontal=0.7, ones=[(160, 250)], fx=run_fx),
        "move_down": clip(_ghoul_run(0.45), travel=("run", 90, 520), hit=170, horizontal=0.7, ones=[(160, 250)], fx=run_fx),
        # Coiled low, claws spread, quivering to pounce.
        "windup": clip([
            K(0, root=(-7, 0, 0, 1.07, 0.91), **coil),
            K(90, "lin", root=(-6, 0, 0, 1.08, 0.9), **dict(coil, claw_l=(13, 0, 0), claw_r=(-13, 0, 0))),
            K(180, "lin", root=(-8, 0, 0, 1.07, 0.91), **coil),
            K(270, "lin", root=(-6, 1, 0, 1.08, 0.9), **dict(coil, head=(-10, 0, -1))),
        ], loop=360),
        # Pounce across the card, two slashes at the front edge, land, slink back.
        "attack": clip([
            K(0, root=(-7, 0, 0, 1.07, 0.91), **coil),
            K(60, "in", root=(2, -9, 8, 0.9, 1.1), torso=(14, 0, -2), head=(12, 0, 0), arm_l=(30, 0, -5),
              arm_r=(-36, 0, -5), claw_l=(14, 0, 0), claw_r=(-16, 0, 0)),
            K(115, "snap", root=(20, -4, 10, 0.88, 1.06), torso=(20, 2, 2), head=(16, 2, 2), arm_l=(-24, 5, 3),
              arm_r=(-8, -3, 3), claw_l=(-18, 0, 0), claw_r=(14, 0, 0)),
            K(170, "out", root=(20, -2, 8, 0.9, 1.04), torso=(19, 2, 2), head=(15, 2, 2), arm_l=(-30, 5, 4),
              arm_r=(-14, -3, 3), claw_l=(-22, 0, 0), claw_r=(10, 0, 0)),
            K(240, "snap", root=(21, -1, 10, 0.88, 1.06), torso=(18, 2, 3), head=(14, 2, 2), arm_r=(16, -4, 4),
              claw_r=(20, 0, 0), arm_l=(-10, 2, 1)),
            K(330, "out", root=(17, 0, 6, 1.08, 0.91), torso=(12, 1, 2), head=(10, 1, 1)),
            K(520, "io", root=(6, 0, 2), torso=(4, 0, 1), head=(4, 0, 0)),
            K(900, "io"),
        ], hit=115, ones=[(40, 260)], fx=[("impact", 118, 46, -26), ("impact", 243, 46, -14), ("dust", 330, 18, 0)]),
        "hurt": hurt("torso", "head", {"arm_l": (16, 0, -2), "arm_r": (-16, 0, -2), "claw_l": (10, 0, 0),
                                        "claw_r": (-10, 0, 0)}, mark=(14, -36)),
        "hurt_back": hurt_back("torso", "head", {"arm_l": (-12, 0, 0), "arm_r": (12, 0, 0)}, mark=(-14, -36)),
        "block": block({"arm_l": (-8, 4, -2), "arm_r": (8, -4, -2), "claw_l": (-12, 0, 0), "claw_r": (12, 0, 0)}),
        "stunned": stunned("torso", "head", {"arm_l": (8, 0, 0), "arm_r": (8, 0, 0)},
                           {"arm_l": (-8, 0, 0), "arm_r": (-8, 0, 0)}),
        "death": death_forward("torso", "head", (
            {"arm_l": (-10, 0, 2), "arm_r": (10, 0, 2)},
            {"arm_l": (-30, 0, 6), "arm_r": (-20, 0, 6), "claw_l": (-14, 0, 0), "claw_r": (14, 0, 0)},
        ), lie=4, turn=70),
    }


# --------------------------------------------------------------------------
# Archer: darts low across the card with the crossbow levelled.

def _archer_dart(lift, low):
    return [
        K(0),
        K(130, "out", root=(-5, 0, 0, 1.06, 0.91), torso=(6, 0, 2), head=(4, 0, 1), bow=(-3, 0, 0), leg_l=(-4, -1, 0)),
        K(165, "snap", root=(18, -2 * lift + low, 0, 0.88, 1.06), torso=(14, 0, 1), head=(8, 0, 0), bow=(-5, 0, 0),
          leg_l=(-14, -3, -1), leg_r=(10, 3, -2), cape=(10, 0, 0)),
        K(280, "out", root=(17, -1 * lift + low, 0, 0.94, 1.03), torso=(12, 0, 1), leg_l=(-10, -2, -1), leg_r=(8, 2, -1)),
        # Skids to a halt already taking aim.
        K(420, "io", root=(13, low, 0, 1.05, 0.95), torso=(4, 0, 1), bow=(-4, 0, -1)),
        K(620, "io", root=(5, 0, 0), torso=(-2, 0, 0), bow=(-2, 0, 0)),
        K(860, "io"),
    ]


def archer():
    aim = {"torso": (-2, 0, 1), "head": (-3, 0, 0), "bow": (-4, 0, -1)}
    dart_fx = [("speed", 170, 330), ("dust", 420, 14, 0)]
    return {
        # Alert: the crossbow rises and falls, the hood turns to look about.
        "idle": clip([
            K(0),
            K(500, "io", root=(0, 0, 0, 1, 0.985), torso=(0, 0, 0.6), bow=(-2, 0, 0), head=(2, 0, 0)),
            K(1100, "io", root=(1, 0, 0), torso=(1, 0, 0.3), bow=(-4, 0, -0.5), head=(5, 0, 0)),
            K(1600, "io", root=(0, 0, 0, 1, 0.985), torso=(0, 0, 0.8), bow=(0, 0, 0), head=(0, 0, 0.5)),
            K(2100, "io", root=(-2, 0, 0), torso=(-1, 0, 0.3), bow=(2, 0, 0.5), head=(-4, 0, 0)),
        ], loop=2600),
        "move_side": clip(_archer_dart(1.0, 0), travel=("dash", 165, 240), hit=165, ones=[(140, 300)], fx=dart_fx),
        "move_up": clip(_archer_dart(4.0, 0), travel=("dash", 165, 240), hit=165, horizontal=0.7, ones=[(140, 300)], fx=dart_fx),
        "move_down": clip(_archer_dart(0.0, 2), travel=("dash", 165, 240), hit=165, horizontal=0.7, ones=[(140, 300)], fx=dart_fx),
        # Down on one knee, sighting along the crossbow, barely trembling.
        "windup": clip([
            K(0, root=(-3, 2, 0, 1.03, 0.95), **aim),
            K(200, "io", root=(-3, 2, 0, 1.03, 0.95), **dict(aim, bow=(-5, 0, -1.2), head=(-3.5, 0, 0))),
        ], loop=400),
        # The shot kicks him back into the rear edge; he cranks the string.
        "attack": clip([
            K(0, root=(-3, 2, 0, 1.03, 0.95), **aim),
            K(60, "snap", root=(-16, -1, -8, 0.88, 1.05), bow=(-16, -4, -1), torso=(-8, -1, 0), head=(-9, -1, 0),
              cape=(10, 0, 0), quiver=(8, 0, 0)),
            K(160, "hold", root=(-16, 0, -7, 0.9, 1.04), bow=(-15, -3, -1), torso=(-7, -1, 0), head=(-8, -1, 0)),
            K(300, "io", root=(-9, 0, -2), bow=(10, 0, 1), torso=(3, 0, 1), head=(4, 0, 1)),
            K(450, "io", root=(-6, 0, 0), bow=(14, 0, 2), torso=(4, 0, 1), head=(5, 0, 1)),
            K(600, "io", root=(-3, 0, 0), bow=(6, 0, 1)),
            K(860, "io"),
        ], hit=60, ones=[(40, 170)], fx=[("impact", 64, 44, -34)]),
        "hurt": hurt("torso", "head", {"bow": (8, 0, 1), "cape": (6, 0, 0)}),
        "hurt_back": hurt_back("torso", "head", {"bow": (-8, 0, 0), "cape": (-6, 0, 0)}),
        "block": block({"bow": (-18, -3, -5)}),
        "stunned": stunned("torso", "head", {"bow": (8, 0, 1)}, {"bow": (-4, 0, 0)}),
        "death": death_back("torso", "head", (
            {"bow": (16, 0, 4), "cape": (4, 0, 2)},
            {"bow": (30, -2, 10), "cape": (6, 0, 4), "quiver": (8, 0, 3)},
        ), lie=6),
    }


# --------------------------------------------------------------------------
# Brute: two heavy stomps per cell, an overhead chop.

def _brute_stomp(lean):
    return [
        K(0),
        K(160, "io", root=(0, -3, -3, 0.98, 1.02), torso=(-3 + lean, 0, -1), leg_r=(-12, 1, -6), loin=(4, 0, 0)),
        K(200, "snap", root=(5, 1, 2, 1.08, 0.9), torso=(4 + lean, 0, 2), leg_r=(0, 0, 0), loin=(-3, 0, 0), cleaver=(-6, 0, 0)),
        K(260, "hold", root=(5, 1, 2, 1.06, 0.92), torso=(4 + lean, 0, 2), loin=(-3, 0, 0), cleaver=(-6, 0, 0)),
        K(380, "io", root=(5, -3, 3, 0.98, 1.02), torso=(3 + lean, 0, -1), leg_l=(-10, -1, -6)),
        K(420, "snap", root=(9, 1, 2, 1.08, 0.9), torso=(5 + lean, 0, 2), leg_l=(0, 0, 0), cleaver=(-8, 0, 0)),
        K(480, "hold", root=(9, 1, 2, 1.06, 0.92), torso=(5 + lean, 0, 2), cleaver=(-8, 0, 0)),
        K(640, "out", root=(6, 0, 1, 1.02, 0.98), torso=(2 + lean, 0, 1)),
        K(1000, "io"),
    ]


def brute():
    raised = {"arm_l": (80, 0, -8), "cleaver": (40, 0, 0), "torso": (-10, 0, -2), "head": (-6, 0, 0)}
    stomp_fx = [("dust", 200, 18, 0), ("dust", 200, -18, 0), ("dust", 420, 20, 0), ("dust", 420, -16, 0)]
    return {
        # Heavy breathing: the chest heaves, the shoulders rise and fall.
        "idle": clip([
            K(0),
            K(700, "io", root=(0, 0, 0, 1.01, 0.98), torso=(0, 0, 2.4), head=(0, 0, 1.6), arm_l=(1.5, 0, 1),
              arm_r=(-1.5, 0, 1), cleaver=(-2, 0, 0)),
            K(1400, "io", root=(1, 0, 0), torso=(1, 0, 0.4), head=(2, 0, 0.3)),
            K(2100, "io", root=(0, 0, 0, 1.01, 0.98), torso=(0, 0, 2.4), head=(0, 0, 1.6), arm_l=(1.5, 0, 1),
              arm_r=(-1.5, 0, 1), cleaver=(-2, 0, 0)),
            K(2600, "io", root=(-1, 0, 0), torso=(-1, 0, 0.4), head=(-2, 0, 0.3)),
        ], loop=2800),
        "move_side": clip(_brute_stomp(0), travel=("stomp", 200, 440), hit=200, ones=[(180, 240), (400, 460)], fx=stomp_fx),
        "move_up": clip(_brute_stomp(2), travel=("stomp", 200, 440), hit=200, horizontal=0.7,
                        ones=[(180, 240), (400, 460)], fx=stomp_fx),
        "move_down": clip(_brute_stomp(-2), travel=("stomp", 200, 440), hit=200, horizontal=0.7,
                          ones=[(180, 240), (400, 460)], fx=stomp_fx),
        # The cleaver held high behind the head, trembling with strain.
        "windup": clip([
            K(0, root=(-3, 0, 0, 0.98, 1.02), **raised),
            K(240, "io", root=(-3, -1, 0, 0.98, 1.02), **dict(raised, arm_l=(84, 0, -9), torso=(-11, 0, -2.5))),
        ], loop=480),
        # Chop: the cleaver comes down on the low front of the card.
        "attack": clip([
            K(0, root=(-3, 0, 0, 0.98, 1.02), **raised),
            K(80, "in", root=(-4, -2, -4, 0.95, 1.05), arm_l=(95, 0, -8), cleaver=(50, 0, 0), torso=(-12, 0, -3), head=(-6, 0, 0)),
            K(140, "snap", root=(12, 1, 8, 1.1, 0.9), arm_l=(-30, 3, 5), cleaver=(-40, 0, 0), torso=(14, 2, 4),
              head=(8, 1, 2), arm_r=(8, 0, 2), loin=(-6, 0, 0)),
            K(260, "hold", root=(12, 1, 8, 1.07, 0.92), arm_l=(-34, 3, 6), cleaver=(-44, 0, 0), torso=(14, 2, 4), head=(8, 1, 2)),
            K(440, "io", root=(6, 0, 3), arm_l=(-10, 1, 2), cleaver=(-14, 0, 0), torso=(6, 0, 2)),
            K(1000, "io"),
        ], hit=140, ones=[(60, 200)], fx=[("impact", 143, 40, -6), ("dust", 143, 34, 0), ("dust", 143, 6, 0)]),
        # Barely moved: the head snaps back, then he shakes it off.
        "hurt": clip([
            K(0), K(REACT, "hold"),
            K(STRIKE, "snap", root=(-6, 0, -3, 0.95, 1.03), torso=(-4, 0, 0), head=(-14, -1, -1)),
            K(220, "out", root=(-7, 0, -3), torso=(-4, 0, 0), head=(-12, -1, -1)),
            K(320, "io", root=(-5, 0, 0), head=(8, 0, 0), torso=(2, 0, 0.5)),
            K(420, "io", root=(-3, 0, 0), head=(-6, 0, 0)),
            K(620, "io", head=(0, 0, 0)),
        ], hit=STRIKE, ones=[(REACT, 220)], fx=[("impact", STRIKE + 3, 16, -60)]),
        "hurt_back": hurt_back("torso", "head", {"arm_l": (-6, 0, 0), "arm_r": (6, 0, 0)}, push=7, turn=4, mark=(-16, -60)),
        "block": block({"arm_r": (26, -6, -5), "arm_l": (-16, 4, -3)}),
        "stunned": stunned("torso", "head", {"arm_l": (5, 0, 0), "arm_r": (-5, 0, 0)},
                           {"arm_l": (-5, 0, 0), "arm_r": (5, 0, 0)}, sway=4),
        "death": death_forward("torso", "head", (
            {"arm_l": (-6, 0, 3), "arm_r": (6, 0, 3), "cleaver": (-14, 0, 2)},
            {"arm_l": (-10, 0, 7), "arm_r": (10, 0, 7), "cleaver": (-30, 2, 4), "loin": (0, 0, 2)},
        ), lie=6, turn=76),
    }


# --------------------------------------------------------------------------
# Bomber: hops along, lobs the bomb and plucks another.

def _bomber_hops(lift):
    return [
        K(0),
        K(110, "out", root=(-2, 0, 0, 1.07, 0.89), torso=(2, 0, 2), bomb=(6, 0, 0)),
        K(180, "in", root=(5, -12 * lift, 4, 0.92, 1.09), torso=(6, 0, -1), leg_l=(-10, -1, -3), leg_r=(10, 1, -3),
          bomb=(-10, 0, 0), bombs_l=(8, 0, 0)),
        K(270, "out", root=(8, 0, 2, 1.09, 0.89), torso=(4, 0, 2), leg_l=(0, 0, 0), leg_r=(0, 0, 0), bomb=(8, 0, 0)),
        K(350, "in", root=(11, -10 * lift, 4, 0.93, 1.07), torso=(6, 0, -1), leg_l=(-10, -1, -3), leg_r=(10, 1, -3),
          bomb=(-10, 0, 0)),
        K(440, "out", root=(10, 0, 2, 1.09, 0.89), torso=(3, 0, 2), bomb=(6, 0, 0)),
        K(600, "io", root=(3, 0, 0)),
        K(860, "io"),
    ]


def bomber():
    wind = {"arm_r": (-44, 0, -2), "torso": (-4, 0, 0), "head": (-3, 0, 0)}
    hop_fx = [("dust", 270, 8, 0), ("dust", 440, 10, 0)]
    return {
        # Fidgets on his toes and tosses the bomb in his hand.
        "idle": clip([
            K(0),
            K(250, "out", root=(0, -2, 0), bomb=(0, 0, -6), head=(2, 0, 0)),
            K(500, "in", root=(0, 0, 0, 1.03, 0.96), bomb=(0, 0, 0), head=(0, 0, 0.5)),
            K(800, "io", root=(1, 0, 0), bombs_l=(-3, 0, 0), head=(3, 0, 0)),
            K(1100, "out", root=(1, -2, 0), bomb=(0, 0, -5), head=(1, 0, 0)),
            K(1350, "in", root=(0, 0, 0, 1.03, 0.96), bomb=(0, 0, 0)),
            K(1700, "io", root=(-1, 0, 0), bombs_l=(3, 0, 0), head=(-3, 0, 0)),
        ], loop=2000),
        "move_side": clip(_bomber_hops(1.0), travel=("hop", 120, 360), hit=180, fx=hop_fx),
        "move_up": clip(_bomber_hops(1.5), travel=("hop", 120, 360), hit=180, horizontal=0.7, fx=hop_fx),
        "move_down": clip(_bomber_hops(0.6), travel=("hop", 120, 360), hit=180, horizontal=0.7, fx=hop_fx),
        # The arm cocked back, bouncing, the fuse sputtering.
        "windup": clip([
            K(0, root=(0, 0, 0), **wind),
            K(170, "io", root=(0, -2, 0), **dict(wind, arm_r=(-48, 0, -2.5), bomb=(4, 0, 0))),
        ], loop=340),
        # Whips it forward and lets go; a new bomb pops into his hand.
        "attack": clip([
            K(0, **wind),
            K(70, "in", root=(-5, 0, 0, 1.05, 0.95), arm_r=(-70, 1, -3), torso=(-8, -1, 0), head=(-6, 0, 0), bombs_l=(4, 0, 0)),
            K(120, "snap", root=(10, -2, 0, 0.9, 1.06), arm_r=(40, -4, 2), bomb=HIDE, torso=(10, 2, 1), head=(8, 1, 1),
              bombs_l=(-4, 0, 0)),
            K(220, "out", root=(11, 0, 0), arm_r=(52, -5, 3), bomb=HIDE, torso=(8, 2, 1.5), head=(5, 1, 1)),
            K(360, "io", root=(5, 0, 0), arm_r=(10, 0, 0.5), bomb=HIDE, torso=(1, 0, 0.5)),
            K(460, "out", root=(1, -4, 0), arm_r=(-6, 0, 0), bomb=(0, 0, 0)),
            K(560, "in", root=(0, 0, 0, 1.04, 0.95)),
            K(800, "io"),
        ], hit=120, ones=[(50, 160)], fx=[("speed", 80, 160), ("dust", 560, 0, 0)]),
        "hurt": hurt("torso", "head", {"arm_r": (10, 0, 0), "bombs_l": (8, 0, 0)}),
        "hurt_back": hurt_back("torso", "head", {"arm_r": (-10, 0, 0), "bombs_l": (-8, 0, 0)}),
        "block": block({"arm_l": (-24, 4, -3), "bombs_l": (-10, 3, -2)}),
        "stunned": stunned("torso", "head", {"bomb": (8, 0, 0)}, {"bomb": (-8, 0, 0)}),
        "death": death_back("torso", "head", (
            {"arm_r": (16, 0, 3), "bombs_l": (-6, 0, 2)},
            {"arm_r": (30, 0, 8), "bombs_l": (-10, 0, 5), "bomb": (20, 0, 4)},
        ), lie=6),
    }


# --------------------------------------------------------------------------
# Custodian: levitates and punts the card along with his crozier.

def _bishop_glide(lift):
    return [
        K(0),
        # Rises a little and plants the crozier behind him...
        K(160, "io", root=(0, -4 * lift, 0), arm_r=(10, 0, 0), staff=(20, 0, 2), torso=(6, 0, 0), hem=(-4, 0, 0)),
        # ...pushes off like a ferryman...
        K(260, "io", root=(5, -5 * lift, 0), arm_r=(22, 2, 0), staff=(28, 0, 3), torso=(8, 0, 0), head=(4, 0, 0),
          hem=(-10, -1, 0)),
        # ...and glides, the hem trailing.
        K(520, "io", root=(10, -5 * lift, 0), arm_r=(4, 0, 0), staff=(6, 0, 0), torso=(3, 0, 0), hem=(-14, -1, 0)),
        K(680, "io", root=(6, -3 * lift, 0), staff=(-4, 0, 0), torso=(-2, 0, 0), hem=(6, 0, 0)),
        K(1000, "io"),
    ]


def bishop():
    lift = {"arm_r": (-10, 0, -4), "staff": (-6, 0, -2), "torso": (-2, 0, -0.5), "head": (-3, 0, 0)}
    return {
        # Hovers serenely; the hem sways, the crozier tips.
        "idle": clip([
            K(0),
            K(750, "io", root=(0, -2.5, 0), hem=(-3, 0, 0), staff=(1.5, 0, 0), head=(0, 0, 0.5)),
            K(1500, "io", root=(0, -1, 0), hem=(2, 0, 0), staff=(-1, 0, 0)),
            K(2250, "io", root=(0, -3, 0), hem=(-2, 0, 0), staff=(2, 0, 0), head=(2, 0, 0.8)),
        ], loop=3000),
        "move_side": clip(_bishop_glide(1.0), travel=("glide", 260, 420), hit=260),
        "move_up": clip(_bishop_glide(1.8), travel=("glide", 260, 420), hit=260, horizontal=0.7),
        "move_down": clip(_bishop_glide(0.5), travel=("glide", 260, 420), hit=260, horizontal=0.7),
        "windup": clip([
            K(0, root=(0, -5, 0), **lift),
            K(240, "io", root=(0, -7, 0), **dict(lift, staff=(-8, 0, -3))),
        ], loop=480),
        # Brings the crook down on the front of the card.
        "attack": clip([
            K(0, root=(0, -5, 0), **lift),
            K(70, "in", root=(-3, -6, 0), arm_r=(-16, 0, -6), staff=(-20, 0, -3), torso=(-4, 0, -1), head=(-5, 0, 0)),
            K(130, "snap", root=(10, -2, 4, 0.92, 1.05), arm_r=(14, -2, 2), staff=(40, 0, 2), torso=(8, 1, 1), head=(4, 0, 1)),
            K(250, "hold", root=(10, -1, 4), arm_r=(16, -2, 3), staff=(44, 0, 3), torso=(8, 1, 1.5)),
            K(440, "io", root=(4, -1, 0), arm_r=(3, 0, 0), staff=(6, 0, 0)),
            K(800, "io"),
        ], hit=130, ones=[(50, 190)], fx=[("impact", 133, 44, -30)]),
        # Protect: rises with the crozier high, then plants it.
        "cast": clip([
            K(0),
            K(120, "io", root=(0, -3, 0), **lift),
            K(280, "out", root=(0, -11, 0), arm_r=(-18, 0, -9), staff=(-4, 0, -6), arm_l=(14, 0, -4), torso=(-2, 0, -1.5),
              head=(-4, 0, -1)),
            K(420, "io", root=(0, -12, 0), arm_r=(-20, 0, -10), staff=(-6, 0, -7), arm_l=(16, 0, -5), torso=(-2, 0, -1.5)),
            K(500, "snap", root=(0, -2, 0, 1.04, 0.96), arm_r=(-6, 0, -3), staff=(0, 0, 2), arm_l=(18, 0, -6), torso=(0, 0, 1)),
            K(640, "io", root=(0, -1, 0), arm_l=(10, 0, -3)),
            K(900, "io"),
        ], hit=500, fx=[("impact", 503, 20, 0)]),
        "hurt": hurt("torso", "head", {"staff": (8, 0, 0), "arm_l": (10, 0, 0), "hem": (8, 0, 0)}),
        "hurt_back": hurt_back("torso", "head", {"staff": (-8, 0, 0), "hem": (-8, 0, 0)}),
        "block": block({"arm_r": (-12, -5, -3), "staff": (-14, -3, 0), "arm_l": (-10, 2, -2)}),
        "stunned": stunned("torso", "head", {"staff": (6, 0, 0)}, {"staff": (-6, 0, 0)}),
        "death": death_forward("torso", "head", (
            {"staff": (12, 0, 3), "arm_l": (8, 0, 2), "hem": (0, 0, 1)},
            {"staff": (26, 0, 8), "arm_l": (12, 0, 5), "hem": (0, 0, 2)},
        ), lie=6, turn=72),
    }


# --------------------------------------------------------------------------
# Demolitionist: the archmage drifts on the air, the halo turning.

def _archmage_drift(lift):
    return [
        K(0),
        K(180, "io", root=(-2, -4 * lift, 0), torso=(-2, 0, 0), halo=(-4, 0, 0), hem=(4, 0, 0)),
        K(420, "io", root=(10, -7 * lift, 4), torso=(4, 0, 0), halo=(6, 0, 0), hem=(-10, -1, 0), flame=(0, 0, 0, 1.1)),
        K(620, "io", root=(6, -4 * lift, 0), torso=(1, 0, 0), halo=(2, 0, 0), hem=(4, 0, 0)),
        K(1000, "io"),
    ]


def archmage():
    call = {"arm_r": (-10, 0, -4), "flame": (0, 0, -2, 1.1), "halo": (4, 0, 0), "torso": (-2, 0, 0)}
    return {
        "idle": clip([
            K(0),
            K(700, "io", root=(0, -3, 0), halo=(4, 0, 0), flame=(0, 0, -0.5, 1.06), hem=(-2, 0, 0)),
            K(1400, "io", root=(0, -1, 0), halo=(8, 0, 0), flame=(0, 0, -1, 1.1), skull=(0, 0, 0.8)),
            K(2100, "io", root=(0, -4, 0), halo=(4, 0, 0), flame=(0, 0, -0.5, 1.04), hem=(2, 0, 0)),
        ], loop=2800),
        "move_side": clip(_archmage_drift(1.0), travel=("float", 140, 500), hit=140),
        "move_up": clip(_archmage_drift(1.6), travel=("float", 140, 500), hit=140, horizontal=0.7),
        "move_down": clip(_archmage_drift(0.5), travel=("float", 140, 500), hit=140, horizontal=0.7),
        "windup": clip([
            K(0, root=(0, -4, 0), **call),
            K(180, "io", root=(0, -5, 0), **dict(call, flame=(0, 0, -3, 1.18), halo=(10, 0, 0))),
        ], loop=360),
        "attack": clip([
            K(0, root=(0, -3, 0)),
            K(70, "in", root=(-4, -4, 0), arm_l=(14, 0, -4), torso=(-4, 0, -1), skull=(-5, 0, 0)),
            K(130, "snap", root=(12, -2, 6, 0.92, 1.05), arm_l=(-18, 5, 2), torso=(6, 1, 1.5), skull=(5, 0, 1), halo=(-6, 0, 0)),
            K(250, "hold", root=(12, -2, 6), arm_l=(-20, 5, 2), torso=(6, 1, 1.5), skull=(5, 0, 1)),
            K(440, "io", root=(4, -2, 0), arm_l=(-4, 1, 0), torso=(1, 0, 0.5)),
            K(800, "io"),
        ], hit=130, ones=[(50, 190)], fx=[("impact", 133, 44, -40)]),
        # Bombard: the burning hand raised high, then flung forward.
        "cast": clip([
            K(0, root=(0, -3, 0), **call),
            K(180, "out", root=(-2, -10, -4), arm_r=(-22, 0, -8), flame=(0, 0, -4, 1.25), halo=(10, 0, 0),
              torso=(-3, 0, -1), skull=(-4, 0, -1), arm_l=(6, 0, -2)),
            K(250, "snap", root=(12, -4, 8, 0.92, 1.05), arm_r=(16, -3, 0), flame=(0, -2, 0, 0.8), halo=(-6, 0, 0),
              torso=(4, 1, 1), skull=(4, 0, 1)),
            K(400, "out", root=(9, -3, 4), arm_r=(10, -2, 0), flame=(0, 0, 0, 0.9), torso=(2, 0, 1)),
            K(700, "io", root=(0, -2, 0)),
        ], hit=250, ones=[(160, 280)], fx=[("speed", 190, 260)]),
        "hurt": hurt("torso", "skull", {"halo": (-8, 0, 0), "flame": (0, 0, 0, 0.9)}),
        "hurt_back": hurt_back("torso", "skull", {"halo": (8, 0, 0)}),
        "block": block({"arm_l": (-16, 5, -3), "arm_r": (12, -3, -2)}, head="skull"),
        "stunned": stunned("torso", "skull", {"halo": (10, 0, 0)}, {"halo": (-10, 0, 0)}),
        "death": death_back("torso", "skull", (
            {"halo": (-12, 0, 3), "arm_l": (10, 0, 3), "flame": (0, 0, 3, 0.7)},
            {"halo": (-24, 0, 8), "arm_l": (18, 0, 6), "arm_r": (8, 0, 4), "flame": HIDE, "hem": (0, 0, 2)},
        ), lie=8),
    }


# Soft parts of each figure (and `close`, the hollows filled in its card):
# {bone: (sign, gain deg per 1000 px/s^2, frequency Hz, damping)}; a positive
# sign suits parts hanging from their pivot, negative ones standing above it.
LIVING = {
    "pilgrim": {"actions": pilgrim,
                "soft": {"cape_l": (1, 0.35, 3.0, 0.35), "cape_r": (1, 0.3, 3.4, 0.35), "lantern": (1, 0.5, 2.8, 0.25)}},
    "ghoul": {"close": 12, "actions": ghoul,
              "soft": {"claw_l": (1, 0.3, 3.5, 0.4), "claw_r": (1, 0.3, 3.5, 0.4)}},
    "archer": {"actions": archer,
               "soft": {"cape": (1, 0.4, 3.0, 0.35), "quiver": (1, 0.2, 4.0, 0.4)}},
    "brute": {"close": 8, "actions": brute,
              "soft": {"loin": (1, 0.35, 2.6, 0.3), "cleaver": (1, 0.1, 2.2, 0.4)}},
    "bomber": {"actions": bomber,
               "soft": {"bombs_l": (1, 0.35, 3.2, 0.3), "bomb": (-1, 0.25, 3.5, 0.35)}},
    "bishop": {"actions": bishop,
               "soft": {"hem": (1, 0.3, 2.4, 0.35), "staff": (-1, 0.12, 2.0, 0.45)}},
    "archmage": {"actions": archmage,
                 "soft": {"hem": (1, 0.25, 2.2, 0.35), "halo": (-1, 0.2, 2.6, 0.35)}},
}
