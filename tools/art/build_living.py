"""Build the living cards (the PROVA MECCANICHE art test).

    blender -b --factory-startup --python tools/art/build_living.py -- [options]

Options
  --only NAME[,NAME]  build only these characters (does not rewrite the tables)
  --preview DIR       write an animated PNG per action and a contact sheet
  --no-write          do not touch assets/ or src/ (useful with --preview)

Outputs
  assets/gothic/flipbook/living/<name>.png        drawings, LIVING_COLUMNS per row
  assets/gothic/flipbook/living/<name>-paper.png  the card's distance field
  src/engine/gfx/living_data.odin                 clip tables (generated)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import build_sprites as classic  # noqa: E402
import characters  # noqa: E402
import living  # noqa: E402
import living_actions  # noqa: E402
import pixel_rig as pr  # noqa: E402
import sheets  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "gothic", "flipbook", "living")
ODIN_OUT = os.path.join(ROOT, "src", "engine", "gfx", "living_data.odin")


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"only": None, "preview": None, "write": True}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            opts["only"] = argv[i + 1].split(",")
            i += 1
        elif a == "--preview":
            opts["preview"] = argv[i + 1]
            i += 1
        elif a == "--no-write":
            opts["write"] = False
        i += 1
    return opts


def contact_sheet(info, folder):
    rows = []
    for action, (shots, _) in info["previews"].items():
        row = [living.card_image(frame, info["field"], 2) for frame, _ in shots[:living.COLUMNS]]
        rows.append(row)
        # Each action on its own, larger, in rows of eight drawings.
        sheets.contact_sheet([row[i:i + 8] for i in range(0, len(row), 8)],
                             os.path.join(folder, "%s_%s_sheet.png" % (info["name"], action)), 2, 6)
    sheets.contact_sheet(rows, os.path.join(folder, "%s_living.png" % info["name"]), 1, 6)


def main():
    opts = args()
    px = pr.load_rgba(classic.SRC)
    built = []
    for name, spec in characters.CHARACTERS.items():
        if opts["only"] and name not in opts["only"]:
            continue
        choreography = living_actions.LIVING.get(name)
        if choreography is None:
            continue
        print("LIVING", name)
        info = living.build(name, spec, choreography, px, classic.figure_cell, classic.feet_anchor,
                            classic.BLOCK, classic.COLOURS, classic.PAD)
        print("BUILT", name, "cell", info["cell"], "drawings", sum(a["count"] for a in info["actions"]))
        built.append(info)
        if opts["write"]:
            pr.save_rgba(info["atlas"], os.path.join(OUT_DIR, "%s.png" % name))
            pr.save_rgba(living.field_texels(info["field"]), os.path.join(OUT_DIR, "%s-paper.png" % name))
        if opts["preview"]:
            living.preview(info, opts["preview"])
            contact_sheet(info, opts["preview"])
    if opts["write"] and not opts["only"]:
        living.write_odin(built, ODIN_OUT)
        print("WROTE", ODIN_OUT)
    print("DONE")


if __name__ == "__main__":
    main()
