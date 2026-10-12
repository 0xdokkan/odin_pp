"""Living cards: a hand-animated drawing on a still paper card.

Runs inside Blender's Python (numpy); see build_living.py.

The classic flipbook prints a handful of key drawings and the paper follows
each pose. A living card keeps the paper still, at the classic card's size and
shape, and prints the figure a little smaller on it, animated the way a
drawing on paper is: each action is a timeline of key poses (ms) eased
between keys and drawn on twos (12 drawings a second), on ones only where
the motion is fastest. Every drawing is rendered by the pixel rig, so it is
real pixel art in the figure's own palette, never a resampled image, and:

- the body stretches along its motion and squashes as it stops;
- the ink line boils a little from drawing to drawing, as hand-inked lines do;
- small pencil marks follow the action: dust where a foot lands, a few speed
  strokes behind a dash, a short burst at an impact, and the faint trace of
  the previous drawing where the figure moves very fast.

Where the figure reaches the edge of the card it is cut by it, like a drawing
running off the sheet. The card itself never changes: it only slides on the
board, as a whole, when the figure shoves it.
"""
import math
import os
import struct
import zlib

import numpy as np

import pixel_rig as pr

TWOS = 12          # drawings per second for most of the motion
ONES = 24          # ...and where it is fastest
# Figure size against the classic card: the paper keeps its size and the
# print shrinks, so the figure has room to move inside it.
LIVING_SCALE = 0.89
COLUMNS = 16
MAX_FRAMES = 48
RENDER_MARGIN = 60
# Paper constants of the card shader (build_sprites.py): the card is cut
# PAPER px out from the field's zero set, with an ink line and a cut edge.
CARD_PAPER = 5.5
CARD_INK = 1.5
CARD_EDGE = 1.1
PAPER_SCALE = 20
# Field texels around the print cell: room for the ink line and the cut edge.
CARD_MARGIN = 6
# Stretch along the motion: per px/s of the figure inside its card, capped.
STRETCH_PER_SPEED = 1.0 / 2600.0
STRETCH_MAX = 0.16
# Boiling line: share of the silhouette's border that gains an ink pixel.
BOIL = 0.035
# Pencil marks.
PENCIL = np.array([96, 92, 88], np.float32) / 255
PENCIL_LIGHT = np.array([168, 160, 146], np.float32) / 255
TRACE_SPEED = 260.0       # px/s of the figure above which its last drawing leaves a trace

ACTIONS = ["idle", "move_side", "move_up", "move_down", "attack", "windup", "cast", "channel", "hurt",
           "hurt_back", "block", "dodge", "stunned", "interact", "death"]
TRAVELS = ["none", "shove", "run", "stomp", "hop", "glide", "dash", "float"]


# --------------------------------------------------------------------------
# Timeline.

def ease(name, u):
    u = min(max(u, 0.0), 1.0)
    if name == "lin":
        return u
    if name == "in":
        return u * u
    if name == "out":
        return 1 - (1 - u) * (1 - u)
    if name == "io":
        return u * u * (3 - 2 * u)
    if name == "snap":
        return 1 - (1 - u) ** 4
    if name == "back":
        c = 1.7
        v = u - 1
        return 1 + v * v * ((c + 1) * v + c)
    if name == "hold":
        return 0.0 if u < 1 else 1.0
    raise ValueError(name)


def K(t, ease_name="io", rig="base", **pose):
    """A key pose at `t` ms. `ease_name` shapes the segment that ends here.
    Bones take (angle, dx, dy[, sx, sy]); `root` takes (x, y, rot, sx, sy):
    the feet move by (x, y), the figure turns by `rot` around its middle and
    scales by (sx, sy) about its feet."""
    return {"t": float(t), "ease": ease_name, "rig": rig, "pose": pose}


def clip(keys, loop=None, hit=None, travel=None, horizontal=1.0, ones=None, fx=None):
    """A choreography. `loop` is the cycle length (ms) of a looping state;
    `hit` the impact moment (ms); `travel` (kind, start ms, duration ms) slides
    the card on the board; `horizontal` is the share of that travel that runs
    across the screen (for the soft parts' inertia); `ones` lists the (from,
    to) ms spans drawn on ones; `fx` the pencil marks:
        ("dust", t, x, y)       a puff where a foot lands (x, y from the feet)
        ("impact", t, x, y)     a short burst of strokes
        ("speed", t0, t1)       strokes trailing a fast motion
    """
    keys = sorted(keys, key=lambda k: k["t"])
    return {"keys": keys, "loop": loop, "hit": hit, "travel": travel, "horizontal": horizontal,
            "ones": ones or [], "fx": fx or []}


def _five(v):
    if v is None:
        return (0.0, 0.0, 0.0, 1.0, 1.0)
    a, dx, dy = float(v[0]), float(v[1]), float(v[2])
    sx = float(v[3]) if len(v) > 3 else 1.0
    sy = float(v[4]) if len(v) > 4 else sx
    return (a, dx, dy, sx, sy)


def _root(v):
    if v is None:
        return (0.0, 0.0, 0.0, 1.0, 1.0)
    out = [0.0, 0.0, 0.0, 1.0, 1.0]
    for i, x in enumerate(v):
        out[i] = float(x)
    if len(v) == 4:
        out[4] = out[3]
    return tuple(out)


def _mix(a, b, e):
    return tuple(x + (y - x) * e for x, y in zip(a, b))


def segment(c, t):
    keys = c["keys"]
    if c["loop"]:
        t = t % c["loop"]
        ext = keys + [dict(keys[0], t=keys[0]["t"] + c["loop"])]
    else:
        ext = keys
        t = min(max(t, keys[0]["t"]), keys[-1]["t"])
    for i in range(len(ext) - 1):
        k0, k1 = ext[i], ext[i + 1]
        if k0["t"] <= t < k1["t"] or i == len(ext) - 2:
            span = max(k1["t"] - k0["t"], 1e-6)
            u = (t - k0["t"]) / span
            e = ease(k1["ease"], u)
            if k0["rig"] != k1["rig"]:
                # A rig change is a cut on the later key.
                e = 0.0 if u < 1 else 1.0
            return k0, k1, e
    return keys[-1], keys[-1], 1.0


def pose_at(c, t):
    k0, k1, e = segment(c, t)
    rig = k1["rig"] if e >= 1 else k0["rig"]
    pose = {}
    if k0["rig"] != k1["rig"]:
        src = k1 if e >= 1 else k0
        for name, v in src["pose"].items():
            pose[name] = _root(v) if name == "root" else _five(v)
        return rig, pose
    for name in set(k0["pose"]) | set(k1["pose"]):
        if name == "root":
            pose[name] = _mix(_root(k0["pose"].get(name)), _root(k1["pose"].get(name)), e)
        else:
            pose[name] = _mix(_five(k0["pose"].get(name)), _five(k1["pose"].get(name)), e)
    return rig, pose


def duration(c):
    return c["loop"] if c["loop"] else c["keys"][-1]["t"]


def drawing_times(c):
    """When each drawing starts: on twos, on ones inside the `ones` spans."""
    total = duration(c)
    times, t = [], 0.0
    while t < total - 1e-6:
        times.append(t)
        fast = any(a <= t < b for a, b in c["ones"])
        t += 1000.0 / (ONES if fast else TWOS)
    if not c["loop"]:
        times.append(total)
    return times


def root_xy(c, t):
    r = pose_at(c, t)[1].get("root", (0.0, 0.0, 0.0, 1.0, 1.0))
    return r[0], r[1]


# --------------------------------------------------------------------------
# Board travel: the same curves as the runtime (src/render/living_card.odin).

def travel_progress(kind, u):
    u = min(max(u, 0.0), 1.0)
    if kind == "shove":
        c = 1.2
        v = u - 1
        return 1 + v * v * ((c + 1) * v + c)
    if kind in ("run", "glide", "float"):
        return 0.5 - 0.5 * math.cos(math.pi * u)
    if kind == "stomp":
        a = min(max(u * 2, 0), 1)
        b = min(max(u * 2 - 1, 0), 1)
        return 0.5 * (1 - (1 - a) ** 3) + 0.5 * (1 - (1 - b) ** 3)
    if kind == "hop":
        return u * u * (3 - 2 * u)
    if kind == "dash":
        c = 0.9
        v = u - 1
        return 1 + v * v * ((c + 1) * v + c)
    return 0.0


def travel_offset(c, t, cell_px):
    if not c["travel"]:
        return 0.0
    kind, start, dur = c["travel"]
    return travel_progress(kind, (t - start) / max(dur, 1)) * cell_px * c["horizontal"]


# --------------------------------------------------------------------------
# Soft parts: capes, lanterns, claws lag behind the body and swing back.

def soft_angles(c, soft, cell_px):
    """Extra angle (degrees) per soft bone at every ms of the clip. `soft`:
    {bone: (sign, gain deg per 1000 px/s^2, frequency Hz, damping)}."""
    if not soft:
        return None
    total = duration(c)
    cycles = 3 if c["loop"] else 1
    n = int(total * cycles) + 2
    xs = np.array([root_xy(c, t)[0] + travel_offset(c, t, cell_px) for t in range(-1, n + 1)], np.float64)
    accel = (xs[2:] - 2 * xs[1:-1] + xs[:-2]) * 1e6
    out = {}
    for bone, (sign, gain, freq, damp) in soft.items():
        w = 2 * math.pi * freq
        theta, vel = 0.0, 0.0
        trace = np.zeros(n)
        for i in range(n):
            target = sign * gain * accel[i] / 1000.0
            acc = w * w * (target - theta) - 2 * damp * w * vel
            vel += acc * 0.001
            theta += vel * 0.001
            trace[i] = theta
        if c["loop"]:
            trace = trace[int(total) * (cycles - 1):int(total) * (cycles - 1) + int(total) + 1]
        out[bone] = np.clip(trace, -40, 40)
    return out


def stretch(c, t):
    """Squash and stretch along the figure's motion inside the card."""
    x0, y0 = root_xy(c, t - 20)
    x1, y1 = root_xy(c, t + 20)
    vx, vy = (x1 - x0) * 25.0, (y1 - y0) * 25.0      # px/s
    speed = math.hypot(vx, vy)
    a = min(STRETCH_MAX, speed * STRETCH_PER_SPEED)
    if a < 0.01:
        return 1.0, 1.0, speed
    if abs(vx) >= abs(vy):
        return 1 + a, 1 / (1 + a), speed
    return 1 / (1 + a), 1 + a, speed


# --------------------------------------------------------------------------
# Rendering one pose.

def root_matrix(rot, sx, sy):
    a = math.radians(rot)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c * sx, -s * sy], [s * sx, c * sy]]), np.array([[c, -s], [s, c]])


def rig_pose(rig, feet, rest_h, pose):
    """The rig pose for a sampled pose: the `root` channel becomes the root
    bone's transform (scale about the feet, turn about the middle)."""
    out = {name: v for name, v in pose.items() if name != "root"}
    x, y, rot, sx, sy = pose.get("root", (0.0, 0.0, 0.0, 1.0, 1.0))
    if (x, y, rot, sx, sy) != (0.0, 0.0, 0.0, 1.0, 1.0):
        rs, r = root_matrix(rot, sx, sy)
        f = np.array(feet, np.float64)
        cen = f - np.array([0.0, rest_h / 2.0])
        p = rig.bones[rig.root].pivot
        d = (-rs @ f + r @ f - r @ cen + cen + np.array([x, y])) - (-rs @ p + p)
        out[rig.root] = (rot, float(d[0]), float(d[1]), sx, sy)
    return out


def boil(idx, seed, amount=BOIL):
    """A hand-inked line never sits still: a few border pixels gain ink."""
    rng = np.random.default_rng(seed)
    solid = idx >= 0
    grown = solid.copy()
    grown[1:] |= solid[:-1]
    grown[:-1] |= solid[1:]
    grown[:, 1:] |= solid[:, :-1]
    grown[:, :-1] |= solid[:, 1:]
    border = np.argwhere(grown & ~solid)
    if not len(border):
        return idx
    pick = border[rng.random(len(border)) < amount]
    out = idx.copy()
    out[pick[:, 0], pick[:, 1]] = 0
    return out


def silhouette_edge(idx):
    solid = idx >= 0
    inner = np.roll(solid, 1, 0) & np.roll(solid, -1, 0) & np.roll(solid, 1, 1) & np.roll(solid, -1, 1)
    return solid & ~inner


# --------------------------------------------------------------------------
# Pencil marks, drawn in canvas pixels around the feet.

def _plot(layer, x, y, colour):
    h, w = layer.shape[:2]
    x, y = int(round(x)), int(round(y))
    if 0 <= x < w and 0 <= y < h:
        layer[y, x, :3] = colour
        layer[y, x, 3] = 1


def _ring(layer, cx, cy, r, colour, gaps=0):
    n = max(8, int(r * 7))
    for i in range(n):
        if gaps and i % gaps == 0:
            continue
        a = 2 * math.pi * i / n
        _plot(layer, cx + math.cos(a) * r * 1.3, cy + math.sin(a) * r * 0.75, colour)


def _stroke(layer, x0, y0, x1, y1, colour):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n):
        u = i / max(n - 1, 1)
        _plot(layer, x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, colour)


def draw_marks(layer, c, t, feet, figure_box):
    """Pencil marks of the clip at time t (ms)."""
    fx, fy = feet
    x0, y0, x1, y1 = figure_box
    for mark in c["fx"]:
        kind = mark[0]
        if kind == "dust":
            _, at, dx, dy = mark
            age = t - at
            if 0 <= age < 260:
                k = age / 260.0
                colour = PENCIL if k < 0.6 else PENCIL_LIGHT
                for side in (-1, 1):
                    _ring(layer, fx + dx + side * (3 + 5 * k), fy + dy - 1 - 2 * k, 1.5 + 2.2 * k, colour,
                          gaps=3 if k > 0.5 else 0)
        elif kind == "impact":
            _, at, dx, dy = mark
            age = t - at
            if 0 <= age < 130:
                k = age / 130.0
                colour = PENCIL if k < 0.5 else PENCIL_LIGHT
                cx, cy = fx + dx, fy + dy
                for a in (-50, -15, 20, 55):
                    r = math.radians(a)
                    inner, outer = 3 + 4 * k, 6 + 5 * k
                    _stroke(layer, cx + math.cos(r) * inner, cy + math.sin(r) * inner,
                            cx + math.cos(r) * outer, cy + math.sin(r) * outer, colour)
        elif kind == "speed":
            _, a, b = mark
            if a <= t < b:
                k = (t - a) / max(b - a, 1)
                colour = PENCIL_LIGHT
                height = y1 - y0
                for i, f in enumerate((0.3, 0.55, 0.78)):
                    y = y0 + height * f
                    length = 6 + 4 * (1 - k) - i
                    _stroke(layer, x0 - 3 - length, y, x0 - 3, y, colour)


def compose(figure, layer):
    """Marks lie under the figure: they show only where the figure is not."""
    out = figure.copy()
    show = (layer[..., 3] > 0) & (figure[..., 3] <= 0)
    out[show] = layer[show]
    return out


# --------------------------------------------------------------------------
# Paper.

def distance_to(mask):
    """Exact distance (px) from every texel to the nearest texel of `mask`."""
    h, w = mask.shape
    if not mask.any():
        return np.full((h, w), 1e3, np.float32)
    inner = np.roll(mask, 1, 0) & np.roll(mask, -1, 0) & np.roll(mask, 1, 1) & np.roll(mask, -1, 1)
    edge = mask & ~inner
    ey, ex = np.nonzero(edge)
    yy, xx = np.mgrid[0:h, 0:w]
    best = np.full((h, w), 1e9, np.float32)
    for start in range(0, len(ex), 192):
        bx = ex[start:start + 192][None, None, :]
        by = ey[start:start + 192][None, None, :]
        dx = np.maximum(np.abs(xx[..., None] - bx) - 0.5, 0)
        dy = np.maximum(np.abs(yy[..., None] - by) - 0.5, 0)
        best = np.minimum(best, np.sqrt(dx * dx + dy * dy).min(-1))
    best[mask] = 0
    return best


def card_distance(rest, feet, grow, closing):
    """The still card: the resting silhouette and its mirror image (so the card
    suits both facings), grown about the feet by `grow` to the classic card's
    size around a figure printed 1/grow smaller, hollows closed. Returns the
    distance (px) from every texel to that grown silhouette."""
    h, w = rest.shape
    fx, fy = feet
    xs = np.arange(w)
    mirror = np.clip(np.round(2 * fx - xs - 1).astype(int), 0, w - 1)
    both = rest | rest[:, mirror]
    yy, xx = np.mgrid[0:h, 0:w]
    sx = np.floor(fx + (xx + 0.5 - fx) / grow).astype(int)
    sy = np.floor(fy + (yy + 0.5 - fy) / grow).astype(int)
    ok = (sx >= 0) & (sy >= 0) & (sx < w) & (sy < h)
    grown = np.zeros_like(both)
    grown[ok] = both[sy[ok], sx[ok]]
    grown = pr._close(grown, closing)
    return distance_to(grown)


def field_texels(field):
    v = np.clip(np.round(field * PAPER_SCALE), 0, 255) / 255.0
    out = np.ones(field.shape + (4,), np.float32)
    out[..., 0] = v
    out[..., 1] = v
    out[..., 2] = v
    return out


# --------------------------------------------------------------------------
# Building one character.

def build(name, spec, living, px, figure_cell, feet_anchor, block, colours, pad):
    """Draw every living clip of a character and pack its atlas."""
    rigs = {}
    for key, fig in spec["figures"].items():
        bones = spec["rigs"].get(key)
        if bones is None:
            continue
        pal, idx = pr.repixelate(figure_cell(px, fig), block, colours)
        idx = pr.pad(idx, pad)
        rig = pr.Rig(pal, idx, bones, spec["roots"][key])
        ys = np.nonzero(idx >= 0)[0]
        rigs[key] = (rig, feet_anchor(idx), float(ys.max() - ys.min() + 3))
    _, _, rest_h = rigs["base"]
    base_h = max(r.idx.shape[0] for r, _, _ in rigs.values())
    base_w = max(r.idx.shape[1] for r, _, _ in rigs.values())
    size = (base_h + 2 * RENDER_MARGIN, base_w + 2 * RENDER_MARGIN)
    feet = (size[1] / 2.0, float(base_h + RENDER_MARGIN))
    world_per_px = spec["height"] * LIVING_SCALE / rest_h
    cell_px = 1.0 / world_per_px
    scraps = []

    def render(rig_key, pose):
        rig, (ax, ay), rh = rigs[rig_key]
        origin = (feet[0] - ax, feet[1] - ay)
        idx = rig.render(rig_pose(rig, (ax, ay), rh, pose), size, origin)
        # Before the ink line, which would join a scrap lying a pixel away.
        return pr.outline(pr.mend(pr.clean_frame(idx), log=scraps))

    rest = render("base", {}) >= 0
    grow = 1.0 / LIVING_SCALE
    d = card_distance(rest, feet, grow, living.get("close", 6))
    paper_px = CARD_PAPER * grow
    # The print shows only on the paper, a hair inside its ink line.
    inside = d <= paper_px - 0.6
    paper = d <= paper_px
    field_all = np.maximum(d - (paper_px - CARD_PAPER), 0)
    # The shader draws the ink line and the cut edge in field pixels; these
    # are smaller than the classic card's, so the ramp past the paper is
    # stretched to keep the classic line on the board (and the runtime scales
    # the edge offset the same way, LIVING_PRINT_SCALE).
    beyond = field_all > CARD_PAPER
    field_all[beyond] = CARD_PAPER + (field_all[beyond] - CARD_PAPER) * LIVING_SCALE
    clips = living["actions"]()
    soft = living.get("soft", {})
    rendered = []
    serial = 0
    for action in ACTIONS:
        c = clips.get(action)
        if c is None:
            continue
        total = duration(c)
        times = drawing_times(c)
        swings = soft_angles(c, soft, cell_px)
        drawings = []
        previous = None
        for t in times:
            rig_key, pose = pose_at(c, t)
            if swings and rig_key == "base":
                ms = int(round(t)) % max(int(c["loop"]), 1) if c["loop"] else int(round(t))
                for bone, trace in swings.items():
                    extra = float(trace[min(ms, len(trace) - 1)])
                    a, dx, dy, sx, sy = pose.get(bone, (0.0, 0.0, 0.0, 1.0, 1.0))
                    pose[bone] = (a + extra, dx, dy, sx, sy)
            ex, ey, speed = stretch(c, t)
            r = list(pose.get("root", (0.0, 0.0, 0.0, 1.0, 1.0)))
            r[3] *= ex
            r[4] *= ey
            pose["root"] = tuple(r)
            idx = render(rig_key, pose)
            idx = boil(idx, zlib.crc32(("%s:%s:%d" % (name, action, serial)).encode()))
            serial += 1
            # What the paper shows: the edge may cut a scrap off a limb that
            # reaches out of the card, and that goes too.
            shown = idx.copy()
            shown[~inside] = -1
            figure = pr.to_rgba(rigs[rig_key][0].palette, pr.mend(shown, log=scraps))
            layer = np.zeros(figure.shape, np.float32)
            ys, xs = np.nonzero(idx >= 0)
            box = (xs.min(), ys.min(), xs.max(), ys.max()) if len(xs) else (feet[0], feet[1], feet[0], feet[1])
            draw_marks(layer, c, t, feet, box)
            # The faint trace of the last drawing where the figure flies.
            if previous is not None and speed > TRACE_SPEED:
                ghost = silhouette_edge(previous) & (idx < 0)
                layer[ghost, :3] = PENCIL_LIGHT
                layer[ghost, 3] = 1
            frame = compose(figure, layer)
            frame[~inside] = 0
            drawings.append((t, frame))
            previous = idx
        # One drawing per change: identical neighbours merge into a longer hold.
        merged = []
        for i, (t, frame) in enumerate(drawings):
            end = times[i + 1] if i + 1 < len(times) else (total if c["loop"] else total + 1000.0 / TWOS * 2)
            if merged and np.array_equal(merged[-1][1], frame):
                merged[-1][2] = end
            else:
                merged.append([t, frame, end])
        if len(merged) > MAX_FRAMES:
            raise ValueError("%s %s: %d drawings (max %d)" % (name, action, len(merged), MAX_FRAMES))
        hit = -1
        if c["hit"] is not None:
            for i, (t, _, end) in enumerate(merged):
                if t <= c["hit"] < end:
                    hit = i
                    break
            else:
                hit = len(merged) - 1
        rendered.append((action, c, hit, merged))
        print("  %-10s %2d drawings  %4d ms%s%s" % (action, len(merged), total, "  loop" if c["loop"] else "",
                                                 "  scraps %s" % scraps if scraps else ""))
        del scraps[:]
    # The print cell is the paper; the field atlas adds room for ink and edge.
    ys, xs = np.nonzero(paper)
    y0, y1 = ys.min() - 1, ys.max() + 2
    x0, x1 = xs.min() - 1, xs.max() + 2
    cell_h, cell_w = y1 - y0, x1 - x0
    m = CARD_MARGIN
    if y0 - m < 0 or x0 - m < 0 or y1 + m > size[0] or x1 + m > size[1]:
        raise ValueError("%s: raise RENDER_MARGIN, the card leaves the canvas" % name)
    field = field_all[y0 - m:y1 + m, x0 - m:x1 + m]
    total_frames = sum(len(r[3]) for r in rendered)
    rows = (total_frames + COLUMNS - 1) // COLUMNS
    atlas = np.zeros((rows * cell_h, COLUMNS * cell_w, 4), np.float32)
    table = []
    index = 0
    previews = {}
    for action, c, hit, merged in rendered:
        first = index
        durations = []
        shots = []
        for t, frame, end in merged:
            col, row = index % COLUMNS, index // COLUMNS
            crop = frame[y0:y1, x0:x1]
            atlas[row * cell_h:(row + 1) * cell_h, col * cell_w:(col + 1) * cell_w] = crop
            durations.append(end - t)
            shots.append((crop, end - t))
            index += 1
        table.append({"action": action, "first": first, "count": len(merged), "hit": hit,
                      "loop": bool(c["loop"]), "travel": c["travel"], "durations": _round_durations(durations)})
        previews[action] = (shots, c)
    return {
        "name": name,
        "cell": (cell_w, cell_h),
        "feet": (feet[0] - x0, feet[1] - y0),
        "rest_height": rest_h,
        "world_height": spec["height"] * LIVING_SCALE,
        "ground": float(paper_px - CARD_PAPER),
        "card_margin": m,
        "paper_cell": (cell_w + 2 * m, cell_h + 2 * m),
        "actions": table,
        "atlas": atlas,
        "field": field,
        "previews": previews,
        "cell_px": cell_px,
    }


def _round_durations(durations):
    out, carry = [], 0.0
    for d in durations:
        v = d + carry
        r = max(1, int(round(v)))
        carry = v - r
        out.append(min(r, 65535))
    return out


# --------------------------------------------------------------------------
# Output.

def odin_name(name):
    return "_".join(part.capitalize() for part in name.split("_"))


def write_odin(built, path):
    out = []
    out.append("// Generated by tools/art/build_living.py. Do not edit by hand: change the")
    out.append("// choreography in tools/art/living_actions.py and rebuild (see tools/art/README.md).")
    out.append("package gfx")
    out.append("")
    out.append("// Living cards (PROVA MECCANICHE): the board characters drawn smaller on a")
    out.append("// still card and hand-animated on it. Each clip is a run of drawings in its")
    out.append("// atlas (row-major, LIVING_COLUMNS per row); the card has one field.")
    out.append("Living_Action :: enum u8 {%s}" % ", ".join(odin_name(a) for a in ACTIONS))
    out.append("// How a move clip slides the card across the board (living_card.odin).")
    out.append("Living_Travel :: enum u8 {%s}" % ", ".join(odin_name(t) for t in TRAVELS))
    out.append("LIVING_MAX_FRAMES :: %d" % MAX_FRAMES)
    out.append("LIVING_COLUMNS :: %d" % COLUMNS)
    out.append("// The drawings' size against the classic print: the card shader's edge")
    out.append("// offset is scaled by it so lines keep their classic thickness.")
    out.append("LIVING_PRINT_SCALE :: f32(%.3f)" % LIVING_SCALE)
    out.append("")
    out.append("// Durations are milliseconds per drawing; `hit` is the drawing on the")
    out.append("// action's impact (-1: none); a move clip starts sliding the card at")
    out.append("// `travel_start` ms, for `travel_ms`.")
    out.append("Living_Clip :: struct {first, count, hit: i32, loop: bool, travel: Living_Travel, travel_start, travel_ms: u16, durations: [LIVING_MAX_FRAMES]u16}")
    out.append("")
    out.append("// `cell` is one drawing in pixels, `feet` the resting ground contact in it,")
    out.append("// `ground` the paper under the feet beyond the shader's own; the field adds")
    out.append("// `card_margin` pixels on every side of the cell.")
    out.append("Living_Sheet :: struct {")
    out.append("\tcell: [2]i32,")
    out.append("\tfeet: [2]f32,")
    out.append("\trest_height, world_height, ground: f32,")
    out.append("\tcard_margin: i32,")
    out.append("\tpaper_cell: [2]i32,")
    out.append("\tclips: [Living_Action]Living_Clip,")
    out.append("}")
    out.append("")
    out.append("@(rodata)")
    out.append("LIVING_SHEETS := [Flipbook_Character]Living_Sheet{")
    for b in built:
        clips = {a["action"]: a for a in b["actions"]}
        out.append("\t.%s = {cell = {%d, %d}, feet = {%.1f, %.1f}, rest_height = %.1f, world_height = %.3f, ground = %.2f, card_margin = %d, paper_cell = {%d, %d}, clips = {"
                   % (odin_name(b["name"]), b["cell"][0], b["cell"][1], b["feet"][0], b["feet"][1], b["rest_height"],
                      b["world_height"], b["ground"], b["card_margin"], b["paper_cell"][0], b["paper_cell"][1]))
        for action in ACTIONS:
            entry = clips.get(action)
            if entry is None:
                out.append("\t\t.%s = {hit = -1}," % odin_name(action))
                continue
            durations = entry["durations"] + [0] * (MAX_FRAMES - len(entry["durations"]))
            travel = entry["travel"]
            kind, start, dur = travel if travel else ("none", 0, 0)
            out.append("\t\t.%s = {first = %d, count = %d, hit = %d, loop = %s, travel = .%s, travel_start = %d, travel_ms = %d, durations = {%s}},"
                       % (odin_name(action), entry["first"], entry["count"], entry["hit"],
                          "true" if entry["loop"] else "false", odin_name(kind), int(start), int(dur),
                          ", ".join(str(d) for d in durations)))
        out.append("\t}},")
    out.append("}")
    out.append("")
    for kind, suffix in (("FRAMES", ""), ("PAPER", "-paper")):
        out.append("LIVING_%s_PNG := [Flipbook_Character][]u8{" % kind)
        for b in built:
            out.append('\t.%s = #load("../../../assets/gothic/flipbook/living/%s%s.png"),' % (odin_name(b["name"]), b["name"], suffix))
        out.append("}")
        out.append("")
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(out))


def _upsample(field, factor):
    h, w = field.shape
    ys = (np.arange(h * factor) + 0.5) / factor - 0.5
    xs = (np.arange(w * factor) + 0.5) / factor - 0.5
    y0 = np.clip(np.floor(ys).astype(int), 0, h - 1)
    x0 = np.clip(np.floor(xs).astype(int), 0, w - 1)
    y1 = np.clip(y0 + 1, 0, h - 1)
    x1 = np.clip(x0 + 1, 0, w - 1)
    fy = np.clip(ys - np.floor(ys), 0, 1)[:, None]
    fx = np.clip(xs - np.floor(xs), 0, 1)[None, :]
    a = field[y0][:, x0] * (1 - fx) + field[y0][:, x1] * fx
    b = field[y1][:, x0] * (1 - fx) + field[y1][:, x1] * fx
    return a * (1 - fy) + b * fy


PAPER_RGB = np.array([228, 221, 201], np.float32) / 255
PAPER_EDGE_RGB = np.array([164, 152, 131], np.float32) / 255
INK_RGB = np.array(pr.INK, np.float32) / 255


def card_image(frame, field, factor):
    """What the card shader draws: paper, cut edge and ink, then the print."""
    f = _upsample(np.round(field * PAPER_SCALE) / PAPER_SCALE, factor)
    shift = max(1, int(round(CARD_EDGE / LIVING_SCALE * factor)))
    shifted = np.full_like(f, 1e3)
    shifted[shift:, shift:] = f[:-shift, :-shift]
    paper = f <= CARD_PAPER
    body = paper | (shifted <= CARD_PAPER)
    ink = np.minimum(f, shifted) <= CARD_PAPER + CARD_INK
    out = np.zeros(f.shape + (4,), np.float32)
    out[ink, :3] = INK_RGB
    out[ink, 3] = 1
    out[body & ~paper, :3] = PAPER_EDGE_RGB
    out[paper, :3] = PAPER_RGB
    m = CARD_MARGIN * factor
    big = np.repeat(np.repeat(frame, factor, 0), factor, 1)
    region = out[m:m + big.shape[0], m:m + big.shape[1]]
    a = big[..., 3:4]
    region[..., :3] = big[..., :3] * a + region[..., :3] * (1 - a)
    region[..., 3] = np.maximum(region[..., 3], big[..., 3])
    return out


def write_apng(frames, path):
    """frames: [(rgba float HxWx4, duration ms)] -> an animated PNG that loops."""
    h, w = frames[0][0].shape[:2]

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    def pixels(rgba):
        raw = np.clip(np.round(rgba * 255), 0, 255).astype(np.uint8)
        rows = np.concatenate([np.zeros((h, 1), np.uint8), raw.reshape(h, w * 4)], 1)
        return zlib.compress(rows.tobytes(), 9)

    out = [b"\x89PNG\r\n\x1a\n", chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)),
           chunk(b"acTL", struct.pack(">II", len(frames), 0))]
    seq = 0
    for i, (rgba, ms) in enumerate(frames):
        out.append(chunk(b"fcTL", struct.pack(">IIIIIHHBB", seq, w, h, 0, 0, max(1, int(round(ms))), 1000, 0, 0)))
        seq += 1
        data = pixels(rgba)
        if i == 0:
            out.append(chunk(b"IDAT", data))
        else:
            out.append(chunk(b"fdAT", struct.pack(">I", seq) + data))
            seq += 1
    out.append(chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"".join(out))


def preview(info, folder, factor=3):
    """One looping APNG per action: the card acting in place and, for a move,
    sliding as a whole along a strip of floor."""
    cw, ch = info["cell"]
    m = info["card_margin"]
    for action, (shots, c) in info["previews"].items():
        travel = c["travel"]
        span = int(info["cell_px"] * c["horizontal"]) if travel else 0
        width = (cw + 2 * m + span) * factor
        height = (ch + 2 * m + 8) * factor
        frames = []
        t = 0.0
        floor = int((m + info["feet"][1] + info["ground"] + CARD_PAPER) * factor)
        for frame, ms in shots:
            card = card_image(frame, info["field"], factor)
            # The drawing holds while the card may keep sliding: show the
            # slide in 40 ms steps, as the board draws it every frame.
            steps = max(1, int(math.ceil(ms / 40.0))) if travel else 1
            for k in range(steps):
                canvas = np.zeros((height, width, 4), np.float32)
                canvas[..., :3] = np.array([0.20, 0.22, 0.27], np.float32)
                canvas[..., 3] = 1
                canvas[floor:, :, :3] = np.array([0.15, 0.16, 0.20], np.float32)
                x = int(round(travel_offset(c, t + ms * k / steps, info["cell_px"]) * factor)) if travel else 0
                x = min(max(x, 0), width - card.shape[1])
                region = canvas[0:card.shape[0], x:x + card.shape[1]]
                a = card[..., 3:4]
                region[..., :3] = card[..., :3] * a + region[..., :3] * (1 - a)
                frames.append((canvas, ms / steps))
            t += ms
        if not c["loop"]:
            frames.append((frames[-1][0], 600))
        write_apng(frames, os.path.join(folder, "%s_%s.png" % (info["name"], action)))
