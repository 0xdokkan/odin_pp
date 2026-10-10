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
ODIN_OUT = os.path.join(ROOT, "src", "render", "flipbook_data.odin")
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


def build_card(union):
    """union: bool mask of every frame (logical cell). Returns RGBA at CARD_SCALE
    covering the cell grown by `margin` logical pixels on each side."""
    margin = int(math.ceil(CARD_PAPER + CARD_INK + CARD_EDGE + 1))
    F = CARD_SCALE
    m = np.pad(union, margin)
    hi = np.repeat(np.repeat(m, F, 0), F, 1)
    dist = pr.chamfer(hi)
    paper = (dist <= CARD_PAPER * F).astype(np.float32)
    # Scissor-cut contour: smooth the stepped silhouette into curves.
    paper = pr.gaussian(paper, 2.6 * F)
    paper_mask = paper > 0.5
    shift = int(round(CARD_EDGE * F))
    edge_mask = np.zeros_like(paper_mask)
    edge_mask[shift:, shift:] = paper_mask[:-shift, :-shift]
    body = paper_mask | edge_mask
    dist_out = pr.chamfer(body)
    ink_cov = np.clip(CARD_INK * F + 0.5 - dist_out, 0, 1)
    h, w = hi.shape
    out = np.zeros((h, w, 4), np.float32)
    out[..., :3] = INK
    out[..., 3] = np.where(body, 1.0, ink_cov)
    out[edge_mask & ~paper_mask, :3] = PAPER_EDGE
    rng = np.random.default_rng(7)
    grain = pr.gaussian(rng.normal(0, 1, (h, w)), 0.9) * 0.012
    fibre = pr.gaussian(rng.normal(0, 1, (h, w)), 6.0) * 0.012
    paper_rgb = PAPER[None, None, :] + (grain + fibre)[..., None]
    # A thin highlight along the top-left cut edge sells the thickness.
    lit = np.zeros_like(paper_mask)
    lit[:-1, :-1] = paper_mask[:-1, :-1] & ~paper_mask[1:, 1:]
    rgb = np.clip(paper_rgb, 0, 1)
    rgb[lit] = np.clip(rgb[lit] + 0.06, 0, 1)
    out[paper_mask, :3] = rgb[paper_mask]
    return out, margin


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
    card, card_margin = build_card(union)
    cols = max(len(row) for _, _, _, row in rendered)
    atlas = np.zeros((cell_h * len(rendered), cell_w * cols, 4), np.float32)
    table = []
    for ri, (action, mode, hit, row) in enumerate(rendered):
        durations = []
        for ci, (rgba, dur) in enumerate(row):
            atlas[ri * cell_h:(ri + 1) * cell_h, ci * cell_w:(ci + 1) * cell_w] = rgba[y0:y1, x0:x1]
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
        "card": card,
    }
    if opts["preview"]:
        write_preview(info, opts["preview"])
    return info


def write_preview(info, folder):
    F = CARD_SCALE
    card = info["card"]
    m = info["card_margin"] * F
    rows = []
    cw, ch = info["cell"]
    for entry in info["actions"]:
        row = []
        for ci in range(entry["count"]):
            frame = info["atlas"][entry["row"] * ch:(entry["row"] + 1) * ch, ci * cw:(ci + 1) * cw]
            big = np.repeat(np.repeat(frame, F, 0), F, 1)
            comp = card.copy()
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
    out.append("package render")
    out.append("")
    out.append("Flipbook_Character :: enum u8 {%s}" % ", ".join(_odin_name(n) for n in names))
    out.append("Flipbook_Action :: enum u8 {%s}" % ", ".join(_odin_name(a) for a in ACTION_ORDER))
    out.append("FLIPBOOK_MAX_FRAMES :: %d" % MAX_FRAMES)
    out.append("FLIPBOOK_CARD_SCALE :: %d" % CARD_SCALE)
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
    out.append("\tclips: [Flipbook_Action]Flipbook_Clip,")
    out.append("}")
    out.append("")
    out.append("@(rodata)")
    out.append("FLIPBOOK_SHEETS := [Flipbook_Character]Flipbook_Sheet{")
    for b in built:
        clips = {a["action"]: a for a in b["actions"]}
        out.append("\t.%s = {cell = {%d, %d}, feet = {%.1f, %.1f}, rest_height = %.1f, world_height = %.3f, card_margin = %d, clips = {"
                   % (_odin_name(b["name"]), b["cell"][0], b["cell"][1], b["feet"][0], b["feet"][1],
                      b["rest_height"], b["world_height"], b["card_margin"]))
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
    for kind, suffix in (("FRAMES", ""), ("CARD", "-card")):
        out.append("FLIPBOOK_%s_PNG := [Flipbook_Character][]u8{" % kind)
        for n in names:
            out.append('\t.%s = #load("../../assets/gothic/flipbook/%s%s.png"),' % (_odin_name(n), n, suffix))
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
            pr.save_rgba(info["card"], os.path.join(OUT_DIR, f"{name}-card.png"))
    if opts["write"] and not opts["only"]:
        write_odin(built)
        print("WROTE", ODIN_OUT)
    print("DONE")


main()
