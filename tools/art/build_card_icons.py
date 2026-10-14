"""Add the hand-made rows to the card icon atlas.

    python tools/art/build_card_icons.py

(Any Python 3 will do, Blender's included: the script uses only the standard
library.)

assets/gothic/card-icons-pixel.png holds the 16 painted icons
(assets/gothic/generation-prompts.md) in four rows of four. This script keeps
those rows byte for byte and appends a fifth row of the same cells, painted
here as coarse pixel art in the atlas's style (24-28 square pixel units, a
few flat colours, a thick near-black outline):

    cell 16  Movimento Ombra: the ivory hooded Viandante, his face a dark void
             with two pale blue eyes, sinking into a violet pool of shadow.

The PNG is read and written here with zlib and struct, never through Blender
or an image library, so the painted pixels are never resampled or recoloured:
their scanlines are copied as they are, filter bytes included. The other
chunks of the original (its content credentials too) are kept unchanged; they
describe the painted sheet, so their image hash no longer matches. The same
atlas in gives the same bytes out, and running the script again rebuilds the
added row from scratch.

Options:
    --check        exit 1 if the atlas is not what this script would write
    --preview DIR  also write each added cell on a dark ground,
                   DIR/card-icon-<cell>.png
    --no-write     leave the atlas as it is
"""
import argparse
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ATLAS = os.path.join(ROOT, "assets", "gothic", "card-icons-pixel.png")

COLUMNS = 4
PAINTED_ROWS = 4
ROWS = 5
# One pixel unit of the icon, in atlas pixels (the painted icons' own size).
SCALE = 10
SIGNATURE = b"\x89PNG\r\n\x1a\n"

PALETTE = {
    "K": (6, 5, 9, 255),        # outline, near black
    "I": (236, 226, 200, 255),  # ivory cloak
    "i": (190, 178, 152, 255),  # ivory in shade
    "D": (24, 20, 34, 255),     # the face's void
    "E": (150, 222, 255, 255),  # pale blue eyes
    "T": (44, 46, 58, 255),     # the tunic under the open cloak
    "R": (178, 34, 38, 255),    # its crimson cross
    "S": (30, 8, 56, 255),      # the pool's depth
    "V": (70, 24, 118, 255),    # the pool
    "v": (128, 72, 186, 255),   # the pool's lit rim and ripple, rising wisps
}

# Movimento Ombra, 28x28 units, as the Viandante of the figure atlas: his hood
# and his cloak open on the crossed tunic stand out of the pool; its near half
# runs in front of him, so the rest of him is under it.
SHADOW_STEP = (
    "............................",
    ".............KK.............",
    "............KIIK............",
    "...........KIIIiK...........",
    "..........KIIIIIiK..........",
    ".........KIIIIIIIiK.........",
    ".........KIIKKKKIiK.........",
    "........KIIKDDDDKIiK........",
    "........KIKDDDDDDKiK........",
    ".......KIIKDEDDEDKiiK.......",
    ".......KIIKDDDDDDKiiK.......",
    ".......KIIIKDDDDKIiiK.......",
    "......KIIIIIKKKKIIiiiK...K..",
    "..K..KIIIIIKTTTTKIiiiiK.KvK.",
    ".KvK.KIIIIIKTRRTKIiiiiK.KvK.",
    "KvK..KIIIiIKRRRRKIIiiiiK.KvK",
    "KvK.KIIIIiIKTRRTKIIiiiiK.KvK",
    ".KvKKIIIIiIKTRRTKIIIiiiiKvK.",
    ".KvKKIIIIiIKTTTTKIIIiiiiKvK.",
    "..KVVvvvvSSSSSSSSSSvvvvVVK..",
    ".KVVVVSSSSvvvvvvvvSSSSVVVVK.",
    "KVVVVSSSSSSSSSSSSSSSSSSVVVVK",
    ".KVVVSSSSSSSSSSSSSSSSSSVVVK.",
    "..KVVVSSSSSSSSSSSSSSSSVVVK..",
    "...KVVVVVVVSSSSSSVVVVVVVK...",
    "....KKKKVVVVVVVVVVVVKKKK....",
    "........KKKKKKKKKKKK........",
    "............................",
)

# The hand-made cells of the added rows, by atlas cell.
ICONS = {16: SHADOW_STEP}


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != SIGNATURE:
        sys.exit(f"{path}: not a PNG")
    pos, header, idat, extra = 8, None, [], []
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        elif idat:
            sys.exit(f"{path}: a {kind!r} chunk after the image data is not supported")
        else:
            extra.append((kind, body))
    if header is None or not idat:
        sys.exit(f"{path}: no image")
    width, height, depth, colour, _, _, interlace = header
    if (depth, colour, interlace) != (8, 6, 0):
        sys.exit(f"{path}: expected 8-bit RGBA, not interlaced")
    return width, height, zlib.decompress(b"".join(idat)), extra


def cell_bounds(cell, width, height, rows):
    """The loader's rectangle of `cell` (render/gothic_theme.odin)."""
    left, right = cell % COLUMNS * width // COLUMNS, (cell % COLUMNS + 1) * width // COLUMNS
    top, bottom = cell // COLUMNS * height // rows, (cell // COLUMNS + 1) * height // rows
    return left, top, right, bottom


def paint(width, painted, height):
    """The added rows' pixels (RGBA, top to bottom), from atlas row `painted`."""
    pixels = bytearray(width * (height - painted) * 4)
    for cell, art in sorted(ICONS.items()):
        units = len(art)
        if any(len(line) != units for line in art):
            sys.exit(f"cell {cell}: its grid is not square")
        if any(unit != "." and unit not in PALETTE for line in art for unit in line):
            sys.exit(f"cell {cell}: a letter outside the palette")
        left, top, right, bottom = cell_bounds(cell, width, height, ROWS)
        if top < painted or units * SCALE > min(right - left, bottom - top):
            sys.exit(f"cell {cell} does not fit an added row")
        ox = left + (right - left - units * SCALE) // 2
        oy = top + (bottom - top - units * SCALE) // 2 - painted
        for y, line in enumerate(art):
            for x, unit in enumerate(line):
                if unit == ".":
                    continue
                colour = bytes(PALETTE[unit])
                for yy in range(SCALE):
                    at = ((oy + y * SCALE + yy) * width + ox + x * SCALE) * 4
                    pixels[at:at + SCALE * 4] = colour * SCALE
    return pixels


def build(path):
    width, height, scanlines, extra = read_png(path)
    stride = width * 4 + 1
    if len(scanlines) != height * stride:
        sys.exit(f"{path}: the image data does not fill {width}x{height}")
    # The painted sheet is square: four rows of the same cells as its columns.
    painted = width
    extended = (painted * ROWS + PAINTED_ROWS - 1) // PAINTED_ROWS
    if height not in (painted, extended):
        sys.exit(f"{path}: {width}x{height} is neither the painted sheet nor its extension")
    for row in range(PAINTED_ROWS + 1):
        # The added row must leave every painted cell where the loader finds it.
        if row * extended // ROWS != row * painted // PAINTED_ROWS:
            sys.exit(f"{path}: an added row would move the painted cells")
    added = paint(width, painted, extended)
    rows = bytearray(scanlines[:painted * stride])
    row_bytes = width * 4
    for y in range(extended - painted):
        line = added[y * row_bytes:(y + 1) * row_bytes]
        if y == 0:
            rows += b"\x00" + line
        else:
            above = added[(y - 1) * row_bytes:y * row_bytes]
            rows += b"\x02" + bytes((a - b) & 255 for a, b in zip(line, above))
    out = SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, extended, 8, 6, 0, 0, 0))
    for kind, body in extra:
        out += chunk(kind, body)
    out += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    return out, width, painted, extended, added


def write_preview(directory, width, painted, height, added):
    """Each added cell on a dark ground: DIR/card-icon-<cell>.png."""
    os.makedirs(directory, exist_ok=True)
    ground = (40, 40, 46)
    for cell in sorted(ICONS):
        left, top, right, bottom = cell_bounds(cell, width, height, ROWS)
        rows = bytearray()
        for y in range(top - painted, bottom - painted):
            rows += b"\x00"
            for x in range(left, right):
                at = (y * width + x) * 4
                r, g, b, a = added[at:at + 4]
                k = a / 255
                rows += bytes(int(c * k + q * (1 - k) + 0.5) for c, q in zip((r, g, b), ground))
        data = SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", right - left, bottom - top, 8, 2, 0, 0, 0))
        data += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
        open(os.path.join(directory, f"card-icon-{cell}.png"), "wb").write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--preview")
    parser.add_argument("--no-write", action="store_true")
    args = parser.parse_args()
    out, width, painted, height, added = build(ATLAS)
    if args.preview:
        write_preview(args.preview, width, painted, height, added)
    current = open(ATLAS, "rb").read()
    if args.check:
        print("up to date" if out == current else "out of date")
        sys.exit(0 if out == current else 1)
    if not args.no_write and out != current:
        open(ATLAS, "wb").write(out)
    print(f"{os.path.relpath(ATLAS, ROOT)}: {width}x{height}, {len(ICONS)} added icon(s)")


if __name__ == "__main__":
    main()
