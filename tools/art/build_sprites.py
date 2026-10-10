"""Build the flipbook atlases and paper cards for the board characters.

    blender -b --factory-startup --python tools/art/build_sprites.py -- [options]

Options
  --only NAME[,NAME]  build only these characters
  --sheets DIR        write coordinate-grid sheets of the base drawings
  --preview DIR       write contact sheets of every action, printed on the card
  --no-write          do not touch assets/ or src/ (useful with --preview)

Outputs
  assets/gothic/flipbook/<name>.png       frames, one row per action
  assets/gothic/flipbook/<name>-card.png  the rigid paper card (4x resolution)
  src/render/flipbook_data.odin           frame tables (generated)
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import characters  # noqa: E402
import pixel_rig as pr  # noqa: E402
import sheets  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "assets", "gothic", "figures-v2.png")
OUT_DIR = os.path.join(ROOT, "assets", "gothic", "flipbook")
ODIN_OUT = os.path.join(ROOT, "src", "engine", "gfx", "flipbook_data.odin")
COLS = [0, 320, 640, 940, 1254]
ROWS = [0, 350, 675, 923, 1254]
BLOCK = 3
COLOURS = 16
PAD = 2

CARD_SCALE = 4         # card texels per logical pixel
CARD_PAPER = 5.5       # paper thickness around the print, logical pixels
CARD_INK = 1.5         # ink line around the paper
CARD_EDGE = 1.1        # visible cut edge (card thickness), bottom-right
PAPER = np.array([228, 221, 201], np.float32) / 255
PAPER_EDGE = np.array([164, 152, 131], np.float32) / 255
INK = np.array(pr.INK, np.float32) / 255

ACTION_ORDER = ["idle", "walk", "attack", "windup", "cast", "hurt", "block", "dodge",
                "stunned", "interact", "death"]


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"only": None, "sheets": None, "preview": None, "write": True}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            opts["only"] = argv[i + 1].split(",")
            i += 1
        elif a == "--sheets":
            opts["sheets"] = argv[i + 1]
            i += 1
        elif a == "--preview":
            opts["preview"] = argv[i + 1]
            i += 1
        elif a == "--no-write":
            opts["write"] = False
        i += 1
    return opts


def figure_cell(px, index):
    r, c = divmod(index, 4)
    return px[ROWS[r]:ROWS[r + 1], COLS[c]:COLS[c + 1]]


def feet_anchor(idx):
    ys, xs = np.nonzero(idx >= 0)
    bottom = ys.max()
    near = ys >= bottom - 8
    return float(xs[near].mean()), float(bottom + 1)


PAPER_SCALE = 20       # field units per logical pixel (8-bit: up to 12.75 px)


def paper_field(alpha, margin):
    """Exact distance (logical px) from every texel of the paper cell to the
    figure's silhouette; 0 inside. One field per drawing: the card follows the
    pose, and the renderer morphs between consecutive drawings."""
    mask = np.pad(alpha > 0, margin)
    h, w = mask.shape
    solid = mask
    edge = solid & ~(np.roll(solid, 1, 0) & np.roll(solid, -1, 0) & np.roll(solid, 1, 1) & np.roll(solid, -1, 1))
    ey, ex = np.nonzero(edge)
    yy, xx = np.mgrid[0:h, 0:w]
    best = np.full((h, w), 1e9, np.float32)
    for start in range(0, len(ex), 256):
        bx = ex[start:start + 256][None, None, :]
        by = ey[start:start + 256][None, None, :]
        dx = np.maximum(np.abs(xx[..., None] - bx) - 0.5, 0)
        dy = np.maximum(np.abs(yy[..., None] - by) - 0.5, 0)
        best = np.minimum(best, np.sqrt(dx * dx + dy * dy).min(-1))
    best[solid] = 0
    best = pr.gaussian(best, 0.6)
    best[solid] = 0
    return best


def field_texels(field):
    v = np.clip(np.round(field * PAPER_SCALE), 0, 255) / 255.0
    out = np.ones(field.shape + (4,), np.float32)
    out[..., 0] = v
    out[..., 1] = v
    out[..., 2] = v
    return out


def _upsample(field, factor):
    # Bilinear, as the GPU samples the field.
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


def paper_preview(field, factor):
    """What the card shader draws for one field (for the contact sheets)."""
    f = _upsample(np.round(field * PAPER_SCALE) / PAPER_SCALE, factor)
    shift = int(round(CARD_EDGE * factor))
    shifted = np.full_like(f, 1e3)
    shifted[shift:, shift:] = f[:-shift, :-shift]
    paper = f <= CARD_PAPER
    body = paper | (shifted <= CARD_PAPER)
    ink = np.minimum(f, shifted) <= CARD_PAPER + CARD_INK
    out = np.zeros(f.shape + (4,), np.float32)
    out[ink, :3] = INK
    out[ink, 3] = 1
    out[body & ~paper, :3] = PAPER_EDGE
    out[paper, :3] = PAPER
    return out

def build_character(name, spec, px, opts):
    rigs = {}
    for key, fig in spec["figures"].items():
        pal, idx = pr.repixelate(figure_cell(px, fig), BLOCK, COLOURS)
        idx = pr.pad(idx, PAD)
        if opts["sheets"]:
            sheets.grid_sheet(pr.to_rgba(pal, pr.outline(idx)),
                              os.path.join(opts["sheets"], f"{name}_{key}_grid.png"), 9)
        bones = spec["rigs"].get(key)
        if bones is None:
            continue
        rigs[key] = (pr.Rig(pal, idx, bones, spec["roots"][key]), feet_anchor(idx))
    if not rigs:
        return None
    actions = spec["actions"]()
    margin = 44
    base_h = max(r.idx.shape[0] for r, _ in rigs.values())
    base_w = max(r.idx.shape[1] for r, _ in rigs.values())
    size = (base_h + 2 * margin, base_w + 2 * margin)
    feet = (size[1] / 2.0, float(base_h + margin))
    rendered = []
    for action in ACTION_ORDER:
        if action not in actions:
            continue
        entry = actions[action]
        mode, frames = entry[0], entry[1]
        hit = entry[2] if len(entry) > 2 else -1
        row = []
        for f in frames:
            if isinstance(f[0], str):
                key, pose, dur = f
            else:
                key = "base"
                pose, dur = f
            rig, (ax, ay) = rigs[key]
            origin = (feet[0] - ax, feet[1] - ay)
            out = pr.outline(pr.clean_frame(rig.render(pose, size, origin)))
            row.append((pr.to_rgba(rig.palette, out), dur))
        rendered.append((action, mode, hit, row))
    union = np.zeros(size, bool)
    for _, _, _, row in rendered:
        for rgba, _ in row:
            union |= rgba[..., 3] > 0
    ys, xs = np.nonzero(union)
    y0, y1 = ys.min() - 1, ys.max() + 2
    x0, x1 = xs.min() - 1, xs.max() + 2
    union = union[y0:y1, x0:x1]
    cell_h, cell_w = union.shape
    card_margin = int(math.ceil(CARD_PAPER + CARD_INK + CARD_EDGE + 1))
    paper_h, paper_w = cell_h + 2 * card_margin, cell_w + 2 * card_margin
    cols = max(len(row) for _, _, _, row in rendered)
    atlas = np.zeros((cell_h * len(rendered), cell_w * cols, 4), np.float32)
    paper = np.zeros((paper_h * len(rendered), paper_w * cols, 4), np.float32)
    paper[..., 3] = 1
    fields = {}
    table = []
    for ri, (action, mode, hit, row) in enumerate(rendered):
        durations = []
        for ci, (rgba, dur) in enumerate(row):
            frame = rgba[y0:y1, x0:x1]
            atlas[ri * cell_h:(ri + 1) * cell_h, ci * cell_w:(ci + 1) * cell_w] = frame
            field = paper_field(frame[..., 3], card_margin)
            fields[(ri, ci)] = field
            paper[ri * paper_h:(ri + 1) * paper_h, ci * paper_w:(ci + 1) * paper_w] = field_texels(field)
            durations.append(dur)
        table.append({"action": action, "row": ri, "count": len(row), "loop": mode == "loop",
                      "hit": hit, "durations": durations})
    base_rig = rigs["base"][0]
    rest_ys = np.nonzero(base_rig.idx >= 0)[0]
    info = {
        "name": name,
        "cell": (cell_w, cell_h),
        "feet": (feet[0] - x0, feet[1] - y0),
        "rest_height": float(rest_ys.max() - rest_ys.min() + 3),  # with the ink line
        "world_height": spec["height"],
        "card_margin": card_margin,
        "actions": table,
        "atlas": atlas,
        "paper": paper,
        "paper_cell": (paper_w, paper_h),
        "fields": fields,
    }
    if opts["preview"]:
        write_preview(info, opts["preview"])
    return info


def write_preview(info, folder):
    F = CARD_SCALE
    m = info["card_margin"] * F
    rows = []
    cw, ch = info["cell"]
    for entry in info["actions"]:
        row = []
        for ci in range(entry["count"]):
            frame = info["atlas"][entry["row"] * ch:(entry["row"] + 1) * ch, ci * cw:(ci + 1) * cw]
            big = np.repeat(np.repeat(frame, F, 0), F, 1)
            comp = paper_preview(info["fields"][(entry["row"], ci)], F)
            region = comp[m:m + big.shape[0], m:m + big.shape[1]]
            a = big[..., 3:4]
            region[..., :3] = big[..., :3] * a + region[..., :3] * (1 - a)
            region[..., 3] = np.maximum(region[..., 3], big[..., 3])
            row.append(comp)
        rows.append(row)
        sheets.contact_sheet([row], os.path.join(folder, f"{info['name']}_{entry['action']}.png"), 1, 10)
    sheets.contact_sheet(rows, os.path.join(folder, f"{info['name']}_preview.png"), 1, 10)


ONCE_UNIT_MS = 62   # one weight unit of a cue-driven clip
MAX_FRAMES = 8


def _odin_name(name):
    return "".join(part.capitalize() for part in name.split("_"))


def write_odin(built):
    names = [b["name"] for b in built]
    out = []
    out.append("// Generated by tools/art/build_sprites.py. Do not edit by hand: change the")
    out.append("// rigs in tools/art/characters.py and rebuild (see tools/art/README.md).")
    out.append("package gfx")
    out.append("")
    out.append("Flipbook_Character :: enum u8 {%s}" % ", ".join(_odin_name(n) for n in names))
    out.append("Flipbook_Action :: enum u8 {%s}" % ", ".join(_odin_name(a) for a in ACTION_ORDER))
    out.append("FLIPBOOK_MAX_FRAMES :: %d" % MAX_FRAMES)
    out.append("// The paper card: each drawing has a distance field to its silhouette")
    out.append("// (PAPER_SCALE units per pixel); the card is drawn PAPER pixels out, with")
    out.append("// an INK line and a cut EDGE offset down and right.")
    out.append("FLIPBOOK_PAPER_SCALE :: f32(%d)" % PAPER_SCALE)
    out.append("FLIPBOOK_PAPER :: f32(%.2f)" % CARD_PAPER)
    out.append("FLIPBOOK_INK :: f32(%.2f)" % CARD_INK)
    out.append("FLIPBOOK_EDGE :: f32(%.2f)" % CARD_EDGE)
    out.append("")
    out.append("// Durations are milliseconds per drawing. `hit` is the drawing that lands")
    out.append("// on the triggering cue's impact (-1: none).")
    out.append("Flipbook_Clip :: struct {row, count, hit: i32, loop: bool, durations: [FLIPBOOK_MAX_FRAMES]u16}")
    out.append("")
    out.append("// `cell` is one drawing in logical pixels; `feet` is the ground contact")
    out.append("// inside it; the card adds `card_margin` pixels of paper on every side.")
    out.append("Flipbook_Sheet :: struct {")
    out.append("\tcell: [2]i32,")
    out.append("\tfeet: [2]f32,")
    out.append("\trest_height, world_height: f32,")
    out.append("\tcard_margin: i32,")
    out.append("\tpaper_cell: [2]i32,")
    out.append("\tclips: [Flipbook_Action]Flipbook_Clip,")
    out.append("}")
    out.append("")
    out.append("@(rodata)")
    out.append("FLIPBOOK_SHEETS := [Flipbook_Character]Flipbook_Sheet{")
    for b in built:
        clips = {a["action"]: a for a in b["actions"]}
        out.append("\t.%s = {cell = {%d, %d}, feet = {%.1f, %.1f}, rest_height = %.1f, world_height = %.3f, card_margin = %d, paper_cell = {%d, %d}, clips = {"
                   % (_odin_name(b["name"]), b["cell"][0], b["cell"][1], b["feet"][0], b["feet"][1],
                      b["rest_height"], b["world_height"], b["card_margin"], b["paper_cell"][0], b["paper_cell"][1]))
        for action in ACTION_ORDER:
            entry = clips.get(action)
            if entry is None:
                out.append("\t\t.%s = {hit = -1}," % _odin_name(action))
                continue
            durations = [int(d) if entry["loop"] else int(d * ONCE_UNIT_MS) for d in entry["durations"]]
            durations += [0] * (MAX_FRAMES - len(durations))
            out.append("\t\t.%s = {row = %d, count = %d, hit = %d, loop = %s, durations = {%s}},"
                       % (_odin_name(action), entry["row"], entry["count"], entry["hit"],
                          "true" if entry["loop"] else "false", ", ".join(str(d) for d in durations)))
        out.append("\t}},")
    out.append("}")
    out.append("")
    for kind, suffix in (("FRAMES", ""), ("PAPER", "-paper")):
        out.append("FLIPBOOK_%s_PNG := [Flipbook_Character][]u8{" % kind)
        for n in names:
            out.append('\t.%s = #load("../../../assets/gothic/flipbook/%s%s.png"),' % (_odin_name(n), n, suffix))
        out.append("}")
        out.append("")
    with open(ODIN_OUT, "w", newline="\n") as f:
        f.write("\n".join(out))


def main():
    opts = args()
    px = pr.load_rgba(SRC)
    built = []
    for name, spec in characters.CHARACTERS.items():
        if opts["only"] and name not in opts["only"]:
            continue
        info = build_character(name, spec, px, opts)
        if info is None:
            continue
        print("BUILT", name, "cell", info["cell"], "frames",
              sum(a["count"] for a in info["actions"]))
        built.append(info)
        if opts["write"]:
            pr.save_rgba(info["atlas"], os.path.join(OUT_DIR, f"{name}.png"))
            pr.save_rgba(info["paper"], os.path.join(OUT_DIR, f"{name}-paper.png"))
    if opts["write"] and not opts["only"]:
        write_odin(built)
        print("WROTE", ODIN_OUT)
    print("DONE")


main()
