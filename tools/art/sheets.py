"""Debug sheets for authoring rigs: coordinate grids and frame contact sheets."""
import numpy as np

import pixel_rig as pr

_DIGITS = {
    '0': ("111", "101", "101", "101", "111"), '1': ("010", "110", "010", "010", "111"),
    '2': ("111", "001", "111", "100", "111"), '3': ("111", "001", "111", "001", "111"),
    '4': ("101", "101", "111", "001", "001"), '5': ("111", "100", "111", "001", "111"),
    '6': ("111", "100", "111", "101", "111"), '7': ("111", "001", "010", "010", "010"),
    '8': ("111", "101", "111", "101", "111"), '9': ("111", "101", "111", "001", "111"),
}


def _text(canvas, x, y, s, scale=2, col=(0.1, 0.1, 0.1, 1)):
    for ch in s:
        for gy, row in enumerate(_DIGITS[ch]):
            for gx, v in enumerate(row):
                if v == '1':
                    canvas[y + gy * scale:y + (gy + 1) * scale, x + gx * scale:x + (gx + 1) * scale] = col
        x += 4 * scale


def grid_sheet(rgba, path, scale=10, margin=22):
    h, w = rgba.shape[:2]
    canvas = np.ones((h * scale + margin, w * scale + margin, 4), np.float32)
    canvas[..., :3] = 0.86
    body = np.repeat(np.repeat(rgba, scale, 0), scale, 1)
    a = body[..., 3:4]
    region = canvas[margin:, margin:]
    region[..., :3] = body[..., :3] * a + region[..., :3] * (1 - a)
    for x in range(0, w + 1, 5):
        xx = margin + x * scale
        if xx < canvas.shape[1]:
            canvas[margin:, xx] = (1, 0, 1, 1) if x % 10 == 0 else (0.2, 0.6, 1, 1)
            _text(canvas, xx - 6 if x >= 10 else xx - 2, 3, str(x))
    for y in range(0, h + 1, 5):
        yy = margin + y * scale
        if yy < canvas.shape[0]:
            canvas[yy, margin:] = (1, 0, 1, 1) if y % 10 == 0 else (0.2, 0.6, 1, 1)
            _text(canvas, 1, yy - 4, str(y))
    pr.save_rgba(canvas, path)


def contact_sheet(rows, path, scale=4, gap=6):
    """rows: list of lists of RGBA frames (same size within the sheet)."""
    fh = max(f.shape[0] for r in rows for f in r)
    fw = max(f.shape[1] for r in rows for f in r)
    cols = max(len(r) for r in rows)
    H = len(rows) * (fh * scale + gap) + gap
    W = cols * (fw * scale + gap) + gap
    canvas = np.zeros((H, W, 4), np.float32)
    canvas[..., :3] = 0.80
    canvas[..., 3] = 1
    for ri, r in enumerate(rows):
        for ci, f in enumerate(r):
            big = np.repeat(np.repeat(f, scale, 0), scale, 1)
            y0 = gap + ri * (fh * scale + gap)
            x0 = gap + ci * (fw * scale + gap)
            cell = canvas[y0:y0 + big.shape[0], x0:x0 + big.shape[1]]
            cell[..., :3] = 0.70
            a = big[..., 3:4]
            cell[..., :3] = big[..., :3] * a + cell[..., :3] * (1 - a)
    pr.save_rgba(canvas, path)
