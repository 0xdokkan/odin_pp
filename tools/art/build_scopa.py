"""Paint the Scopa cards (6 and 7 of coins) as pixel art.

    blender -b --factory-startup --python tools/art/build_scopa.py

Writes assets/gothic/scopa-denari.png: two portrait cards side by side
(6 di denari, then 7 di denari), in the Neapolitan pattern: ivory card,
double red border, golden coins with a crimson rosette, red corner pips.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import pixel_rig as pr  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "gothic", "scopa-denari.png")
W, H = 60, 96

INK = (13, 20, 30)
IVORY = (238, 228, 204)
IVORY_SHADE = (222, 208, 180)
RED = (178, 34, 38)
BLUE = (46, 70, 128)
GOLD = (232, 182, 64)
GOLD_LIGHT = (252, 226, 132)
GOLD_DARK = (150, 98, 30)
ROSE = (190, 40, 36)

DIGITS = {
    "6": ("0110", "1000", "1110", "1001", "1001", "0110"),
    "7": ("1111", "0001", "0010", "0010", "0100", "0100"),
}


def put(img, x, y, color):
    if 0 <= x < img.shape[1] and 0 <= y < img.shape[0]:
        img[y, x, :3] = np.array(color) / 255.0
        img[y, x, 3] = 1


def rect(img, x0, y0, x1, y1, color):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(img, x, y, color)


def frame(img, x0, y0, x1, y1, color):
    for x in range(x0, x1 + 1):
        put(img, x, y0, color)
        put(img, x, y1, color)
    for y in range(y0, y1 + 1):
        put(img, x0, y, color)
        put(img, x1, y, color)


def coin(img, cx, cy, r=7):
    for y in range(cy - r - 1, cy + r + 2):
        for x in range(cx - r - 1, cx + r + 2):
            d = math.hypot(x - cx, y - cy)
            if d <= r + 0.5:
                if d > r - 0.6:
                    c = INK
                elif d > r - 1.7:
                    c = GOLD_DARK
                else:
                    # Light from the top-left, as on the board.
                    lit = ((x - cx) + (y - cy)) / r
                    c = GOLD_LIGHT if lit < -0.75 else GOLD
                put(img, x, y, c)
    # The rosette: a crimson cross with a gold heart.
    for k in range(-3, 4):
        if abs(k) <= 3:
            put(img, cx + k, cy, ROSE)
            put(img, cx, cy + k, ROSE)
    for dx, dy in ((-2, -2), (2, -2), (-2, 2), (2, 2)):
        put(img, cx + dx, cy + dy, ROSE)
    put(img, cx, cy, GOLD_LIGHT)


def digit(img, ch, x, y, color):
    for gy, row in enumerate(DIGITS[ch]):
        for gx, v in enumerate(row):
            if v == "1":
                put(img, x + gx, y + gy, color)


def card(number):
    img = np.zeros((H, W, 4), np.float32)
    # Rounded ivory card with a faint mottling.
    rect(img, 1, 0, W - 2, H - 1, IVORY)
    rect(img, 0, 1, W - 1, H - 2, IVORY)
    rng = np.random.default_rng(number)
    for _ in range(140):
        put(img, int(rng.integers(3, W - 3)), int(rng.integers(3, H - 3)), IVORY_SHADE)
    for x in range(1, W - 1):
        put(img, x, 0, INK)
        put(img, x, H - 1, INK)
    for y in range(1, H - 1):
        put(img, 0, y, INK)
        put(img, W - 1, y, INK)
    put(img, 0, 0, (0, 0, 0))
    img[0, 0, 3] = img[0, W - 1, 3] = img[H - 1, 0, 3] = img[H - 1, W - 1, 3] = 0
    frame(img, 3, 3, W - 4, H - 4, RED)
    frame(img, 5, 5, W - 6, H - 6, BLUE)
    digit(img, str(number), 7, 7, RED)
    # The bottom pip reads upside down, as on a real card.
    for gy, row in enumerate(DIGITS[str(number)]):
        for gx, v in enumerate(row):
            if v == "1":
                put(img, W - 8 - gx, H - 8 - gy, RED)
    if number == 6:
        for y in (26, 48, 70):
            coin(img, 19, y)
            coin(img, W - 20, y)
    else:
        # Neapolitan seven: two columns of three and one coin between them.
        for y in (22, 48, 74):
            coin(img, 15, y, 6)
            coin(img, W - 16, y, 6)
        coin(img, W // 2 - 1, 35, 6)
    return img


def main():
    sheet = np.zeros((H, W * 2 + 2, 4), np.float32)
    sheet[:, :W] = card(6)
    sheet[:, W + 2:] = card(7)
    pr.save_rgba(sheet, OUT)
    pr.save_rgba(sheet, os.path.join(os.path.dirname(OUT), "..", "..", "tools", "art", "build", "scopa_x6.png"), 6) \
        if "--preview" in sys.argv else None
    print("WROTE", OUT)


main()
