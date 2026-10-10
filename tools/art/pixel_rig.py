"""Pixel-art cutout rig used to build the flipbook frames.

Runs inside Blender's Python (it ships numpy); see build_sprites.py.

A character is a logical-resolution sprite split into bones. Each opaque
pixel is skinned to one bone (with a soft band at the joints), every frame is
a hand-authored key pose, and the pose is rendered by forward-mapping 8x8
sub-samples per source pixel into a 4x canvas, then reduced back to logical
pixels by majority vote. Only colours of the original palette ever appear, so
each frame stays clean pixel art instead of a resampled image.
"""
import math
import os

import bpy
import numpy as np

INK = (13, 20, 30)
SUB = 8      # sub-samples per source pixel and axis
CANVAS = 4   # canvas cells per logical pixel and axis


# --------------------------------------------------------------------------
# Image I/O through Blender (no PIL in Blender's Python).

def load_rgba(path):
    image = bpy.data.images.load(path, check_existing=False)
    w, h = image.size
    data = np.array(image.pixels[:], np.float32).reshape(h, w, 4)[::-1].copy()
    bpy.data.images.remove(image)
    return data


def save_rgba(arr, path, scale=1):
    if scale > 1:
        arr = np.repeat(np.repeat(arr, scale, 0), scale, 1)
    h, w = arr.shape[:2]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    image.alpha_mode = 'STRAIGHT'
    image.pixels[:] = np.ascontiguousarray(arr[::-1], np.float32).ravel()
    image.filepath_raw = path
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)


# --------------------------------------------------------------------------
# Conversion of the painted atlas into true pixel art.

def _kmeans(data, k, iters=30, seed=3):
    rng = np.random.default_rng(seed)
    cent = [data[rng.integers(len(data))]]
    for _ in range(1, k):
        d = np.min(((data[:, None] - np.array(cent)[None]) ** 2).sum(-1), 1)
        cent.append(data[rng.choice(len(data), p=d / d.sum())])
    cent = np.array(cent)
    for _ in range(iters):
        lab = np.argmin(((data[:, None] - cent[None]) ** 2).sum(-1), 1)
        for j in range(k):
            members = data[lab == j]
            if len(members):
                cent[j] = members.mean(0)
    lab = np.argmin(((data[:, None] - cent[None]) ** 2).sum(-1), 1)
    return cent, lab


def _despeckle(idx, mask, cent, passes=2):
    # A pixel matching none of its four neighbours is replaced when three of
    # them agree, but only between close shades so eyes and gems survive.
    h, w = idx.shape
    for _ in range(passes):
        out = idx.copy()
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                if not mask[y, x]:
                    continue
                n = (idx[y - 1, x], idx[y + 1, x], idx[y, x - 1], idx[y, x + 1])
                if min(n) < 0 or idx[y, x] in n:
                    continue
                vals, counts = np.unique(n, return_counts=True)
                if counts.max() >= 3:
                    rep = vals[np.argmax(counts)]
                    if np.linalg.norm(cent[rep] - cent[idx[y, x]]) < 0.22:
                        out[y, x] = rep
        idx = out
    return idx


def repixelate(cell, block=4, colours=15):
    """Return (palette uint8 [P,3], index map int [-1 = empty]) for a painted cell."""
    best = None
    for oy in range(block):
        for ox in range(block):
            c = cell[oy:, ox:]
            h = (c.shape[0] // block) * block
            w = (c.shape[1] // block) * block
            b = c[:h, :w].reshape(h // block, block, w // block, block, 4)
            b = b.transpose(0, 2, 1, 3, 4).reshape(h // block, w // block, block * block, 4)
            opaque = b[..., 3].mean(axis=2) > 0.5
            var = float(b[..., :3].var(axis=2).sum(-1)[opaque].mean())
            if best is None or var < best[0]:
                best = (var, b)
    blocks = best[1]
    mask = blocks[..., 3].mean(axis=2) > 0.5
    rgb = np.median(blocks[..., :3], axis=2)
    cent, lab = _kmeans(rgb[mask], colours)
    ink = np.array(INK, np.float32) / 255
    for j in range(len(cent)):
        if cent[j].max() < 0.11:
            cent[j] = ink
    idx = np.full(mask.shape, -1, np.int32)
    idx[mask] = lab
    idx = _despeckle(idx, mask, cent)
    palette = np.clip(np.round(cent * 255), 0, 255).astype(np.uint8)
    ys, xs = np.nonzero(idx >= 0)
    idx = idx[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return _compact_palette(palette, idx)


def _compact_palette(palette, idx):
    # Merge duplicate colours (the ink fold creates some) and keep ink at 0.
    ink = np.array(INK, np.uint8)
    colours = [tuple(ink)]
    remap = {}
    for j, c in enumerate(palette):
        t = tuple(int(v) for v in c)
        if t not in colours:
            colours.append(t)
        remap[j] = colours.index(t)
    out = np.full(idx.shape, -1, np.int32)
    for j, k in remap.items():
        out[idx == j] = k
    return np.array(colours, np.uint8), out


def to_rgba(palette, idx):
    out = np.zeros(idx.shape + (4,), np.float32)
    m = idx >= 0
    out[m, :3] = palette[idx[m]] / 255.0
    out[m, 3] = 1
    return out


def outline(idx, ink=0):
    """Add the 1 px ink silhouette (4-neighbourhood) around an index map."""
    m = idx >= 0
    edge = np.zeros_like(m)
    edge[1:] |= m[:-1]
    edge[:-1] |= m[1:]
    edge[:, 1:] |= m[:, :-1]
    edge[:, :-1] |= m[:, 1:]
    edge &= ~m
    out = idx.copy()
    out[edge] = ink
    return out


def pad(idx, n):
    return np.pad(idx, n, constant_values=-1)


# --------------------------------------------------------------------------
# Rig.

def _point_in_poly(xs, ys, poly):
    inside = np.zeros(xs.shape, bool)
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        cond = (y1 > ys) != (y2 > ys)
        with np.errstate(divide='ignore', invalid='ignore'):
            xint = (x2 - x1) * (ys - y1) / (y2 - y1 + 1e-12) + x1
        inside ^= cond & (xs < xint)
    return inside


class Bone:
    def __init__(self, name, parent, pivot, depth=0.0, region=None, back=False, blend=3.0,
                 joint=None, reach=11.0):
        self.name = name
        self.parent = parent
        self.pivot = np.array(pivot, np.float64)
        self.depth = depth
        self.region = region    # polygon(s) in logical pixel coordinates
        # Leaves a filled plate behind when it moves; an int sets how far the
        # plate may bridge gaps in the body behind it.
        self.back = back
        self.blend = blend      # joint softness in pixels, each side of the seam
        self.joint = joint      # bone it is sewn to (default: parent)
        self.reach = reach      # only seams this close to the pivot are sewn


class Rig:
    """Bones over an index map; `idx` must be the sprite without its outline."""

    def __init__(self, palette, idx, bones, root):
        self.palette = palette
        self.idx = idx
        self.bones = {b.name: b for b in bones}
        self.order = [b.name for b in bones]
        self.root = root
        self._segment()

    # Each pixel goes to the last bone whose region contains it (so later,
    # smaller regions win), else to the root.
    def _segment(self):
        h, w = self.idx.shape
        ys, xs = np.nonzero(self.idx >= 0)
        self.ys, self.xs = ys, xs
        root_index = self.order.index(self.root)
        owner = np.full(len(xs), root_index, np.int32)
        cx, cy = xs + 0.5, ys + 0.5
        for bi, name in enumerate(self.order):
            bone = self.bones[name]
            if bone.region is None:
                continue
            polys = bone.region if isinstance(bone.region[0][0], (list, tuple)) else [bone.region]
            hit = np.zeros(len(xs), bool)
            for poly in polys:
                hit |= _point_in_poly(cx, cy, poly)
            owner[hit] = bi
        self.owner = owner
        own_map = np.full((h, w), -1, np.int32)
        own_map[ys, xs] = owner
        self.own_map = own_map
        # Soft joints: near the pivot, the seam between a bone and the bone it
        # is sewn to blends symmetrically (0.5 on the seam), so the joint
        # bends instead of tearing. Seams far from the pivot stay crisp: there
        # the part simply overlaps the body.
        nb = len(self.order)
        weights = np.zeros((len(xs), nb), np.float64)
        weights[np.arange(len(xs)), owner] = 1.0
        for bi, name in enumerate(self.order):
            bone = self.bones[name]
            partner = bone.joint or bone.parent
            if partner is None or bone.blend <= 0:
                continue
            pi = self.order.index(partner)
            mine = own_map == bi
            if not mine.any():
                continue
            theirs = own_map == pi
            if not theirs.any():
                continue
            d_in = chamfer(theirs)[ys, xs]  # child pixels: distance to the partner
            d_out = chamfer(mine)[ys, xs]   # partner pixels: distance to the part
            near = np.hypot(cx - bone.pivot[0], cy - bone.pivot[1]) <= bone.reach
            sel = (owner == bi) & near
            t = np.clip((d_in[sel] - 0.5) / bone.blend, 0, 1)
            share = 0.5 * (1 - t)
            rows = np.nonzero(sel)[0]
            weights[rows, bi] -= share
            weights[rows, pi] += share
            sel = (owner == pi) & near & (d_out <= bone.blend + 0.5)
            t = np.clip((d_out[sel] - 0.5) / bone.blend, 0, 1)
            share = 0.5 * (1 - t)
            rows = np.nonzero(sel)[0]
            weights[rows, pi] -= share
            weights[rows, bi] += share
        weights = np.clip(weights, 0, None)
        weights /= weights.sum(1, keepdims=True)
        self.weights = weights
        self.root_index = root_index
        self._backplate()

    def _backplate(self):
        # Pixels of moving "back" bones that sit inside the rest of the body
        # get a filler colour taken from the surrounding body, bound to the
        # parent; it shows only where the limb uncovers it.
        h, w = self.idx.shape
        back_bones = [i for i, n in enumerate(self.order) if self.bones[n].back]
        if not back_bones:
            self.plate = None
            return
        moving = np.isin(self.own_map, back_bones)
        body = (self.own_map >= 0) & ~moving
        plate_mask = np.zeros_like(moving)
        for bi in back_bones:
            back = self.bones[self.order[bi]].back
            radius = 4 if back is True else int(back)
            plate_mask |= (self.own_map == bi) & _close(body, radius)
        filler = self.idx.copy()
        filler[~body] = -1
        filler = _inpaint(filler, plate_mask)
        ys, xs = np.nonzero(plate_mask)
        parents = []
        for y, x in zip(ys, xs):
            # The plate belongs to the body behind the part: the first
            # ancestor that is not itself a moving part.
            bone = self.bones[self.order[self.own_map[y, x]]]
            while bone.parent is not None and bone.back:
                bone = self.bones[bone.parent]
            parents.append(self.order.index(bone.name))
        self.plate = (ys, xs, filler[ys, xs], np.array(parents, np.int32))

    def global_transforms(self, pose):
        """pose: {bone: (angle_degrees, dx, dy[, sx, sy])} -> {bone: 2x3 matrix}."""
        mats = {}

        def local(name):
            bone = self.bones[name]
            p = pose.get(name, (0, 0, 0))
            angle, dx, dy = p[0], p[1], p[2]
            sx = p[3] if len(p) > 3 else 1.0
            sy = p[4] if len(p) > 4 else sx
            a = math.radians(angle)
            c, s = math.cos(a), math.sin(a)
            px, py = bone.pivot
            # translate(-pivot) -> scale -> rotate -> translate(pivot + d)
            m = np.array([[c * sx, -s * sy, 0], [s * sx, c * sy, 0]], np.float64)
            m[:, 2] = np.array([px + dx, py + dy]) - m[:, :2] @ np.array([px, py])
            return m

        def compose(a, b):
            # a after b
            out = np.zeros((2, 3))
            out[:, :2] = a[:, :2] @ b[:, :2]
            out[:, 2] = a[:, :2] @ b[:, 2] + a[:, 2]
            return out

        def resolve(name):
            if name in mats:
                return mats[name]
            bone = self.bones[name]
            m = local(name)
            if bone.parent is not None:
                m = compose(resolve(bone.parent), m)
            mats[name] = m
            return m

        for name in self.order:
            resolve(name)
        return mats

    def render(self, pose, size, origin):
        """Render a pose into an index map of `size` (h, w); `origin` is where
        source pixel (0,0) lands at rest."""
        mats = self.global_transforms(pose)
        stack = np.stack([mats[n] for n in self.order])  # [B,2,3]
        offs = (np.arange(SUB) + 0.5) / SUB
        ox, oy = np.meshgrid(offs, offs)
        ox, oy = ox.ravel(), oy.ravel()
        n = len(self.xs)
        sx = (self.xs[:, None] + ox[None]).ravel()
        sy = (self.ys[:, None] + oy[None]).ravel()
        pix = np.repeat(np.arange(n), SUB * SUB)
        wts = self.weights[pix]                                 # [N,B]
        m = np.einsum('nb,bij->nij', wts, stack)                # blended matrix
        dx = m[:, 0, 0] * sx + m[:, 0, 1] * sy + m[:, 0, 2]
        dy = m[:, 1, 0] * sx + m[:, 1, 1] * sy + m[:, 1, 2]
        depth = wts @ np.array([self.bones[b].depth for b in self.order])
        col = self.idx[self.ys, self.xs][pix]
        if self.plate is not None:
            pys, pxs, pcol, ppar = self.plate
            psx = (pxs[:, None] + ox[None]).ravel()
            psy = (pys[:, None] + oy[None]).ravel()
            ppix = np.repeat(np.arange(len(pxs)), SUB * SUB)
            pm = stack[ppar[ppix]]
            pdx = pm[:, 0, 0] * psx + pm[:, 0, 1] * psy + pm[:, 0, 2]
            pdy = pm[:, 1, 0] * psx + pm[:, 1, 1] * psy + pm[:, 1, 2]
            dx = np.concatenate([dx, pdx])
            dy = np.concatenate([dy, pdy])
            depth = np.concatenate([depth, np.full(len(pdx), -1000.0)])
            col = np.concatenate([col, pcol[ppix]])
        h, w = size
        cx = np.floor((dx + origin[0]) * CANVAS).astype(np.int64)
        cy = np.floor((dy + origin[1]) * CANVAS).astype(np.int64)
        ok = (cx >= 0) & (cy >= 0) & (cx < w * CANVAS) & (cy < h * CANVAS) & (col >= 0)
        cx, cy, depth, col = cx[ok], cy[ok], depth[ok], col[ok]
        flat = cy * (w * CANVAS) + cx
        order = np.lexsort((depth, flat))
        fs = flat[order]
        last = np.r_[fs[1:] != fs[:-1], True]
        sel = order[last]
        canvas = np.full(h * CANVAS * w * CANVAS, -1, np.int32)
        canvas[flat[sel]] = col[sel]
        canvas = canvas.reshape(h, CANVAS, w, CANVAS).transpose(0, 2, 1, 3).reshape(h, w, CANVAS * CANVAS)
        filled = (canvas >= 0).sum(-1)
        counts = np.zeros((h, w, len(self.palette)), np.int32)
        for k in range(len(self.palette)):
            counts[..., k] = (canvas == k).sum(-1)
        out = np.argmax(counts, -1).astype(np.int32)
        out[filled < (CANVAS * CANVAS) // 2] = -1
        return out


def _dilate(mask, r):
    out = mask.copy()
    for _ in range(r):
        grown = out.copy()
        grown[1:] |= out[:-1]
        grown[:-1] |= out[1:]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        out = grown
    return out


def _erode(mask, r):
    return ~_dilate(~mask, r)


def _close(mask, r):
    padded = np.pad(mask, r + 1)
    return _erode(_dilate(padded, r), r)[r + 1:-r - 1, r + 1:-r - 1]


def _inpaint(idx, target):
    # Grow known colours into the target pixels, nearest first.
    out = idx.copy()
    todo = target & (out < 0)
    for _ in range(64):
        if not todo.any():
            break
        ys, xs = np.nonzero(todo)
        changed = False
        for y, x in zip(ys, xs):
            for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < out.shape[0] and 0 <= xx < out.shape[1] and out[yy, xx] >= 0 and not todo[yy, xx]:
                    out[y, x] = out[yy, xx]
                    changed = True
                    break
        todo = target & (out < 0)
        if not changed:
            break
    return out


def _components(mask):
    """4-connected components: returns (labels, sizes)."""
    h, w = mask.shape
    labels = np.full((h, w), -1, np.int32)
    sizes = []
    for sy, sx in zip(*np.nonzero(mask)):
        if labels[sy, sx] >= 0:
            continue
        label = len(sizes)
        stack = [(sy, sx)]
        labels[sy, sx] = label
        count = 0
        while stack:
            y, x = stack.pop()
            count += 1
            for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and labels[yy, xx] < 0:
                    labels[yy, xx] = label
                    stack.append((yy, xx))
        sizes.append(count)
    return labels, np.array(sizes, np.int32)


def clean_frame(idx, min_island=8, max_hole=48):
    """Tidy a rendered pose before outlining: drop specks that broke off at the
    joints, close one-pixel cracks and fill small enclosed holes, so the ink
    line only ever follows the real silhouette."""
    out = idx.copy()
    solid = out >= 0
    labels, sizes = _components(solid)
    if len(sizes):
        keep = sizes >= min_island
        keep[np.argmax(sizes)] = True
        out[solid & ~keep[np.maximum(labels, 0)]] = -1
    solid = out >= 0
    target = _close(solid, 1) & ~solid
    empty = ~solid
    labels, sizes = _components(empty)
    border = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    for label, size in enumerate(sizes):
        if label not in border and size <= max_hole:
            target |= labels == label
    if target.any():
        out = _inpaint(out, target)
    return out


def strip_outline(idx, ink=0):
    """Remove the outer ink ring so the silhouette can be re-outlined per frame."""
    m = idx >= 0
    edge = np.zeros_like(m)
    edge[1:] |= ~m[:-1]
    edge[:-1] |= ~m[1:]
    edge[:, 1:] |= ~m[:, :-1]
    edge[:, :-1] |= ~m[:, 1:]
    edge[0, :] = True
    edge[-1, :] = True
    edge[:, 0] = True
    edge[:, -1] = True
    out = idx.copy()
    out[m & edge & (idx == ink)] = -1
    return out


# --------------------------------------------------------------------------
# Paper card (the rigid cutout behind the animated print).

def chamfer(mask):
    """Distance (in pixels) from every cell to the nearest True cell."""
    h, w = mask.shape
    inf = 1e9
    d = np.where(mask, 0.0, inf)
    a, b = 1.0, math.sqrt(2.0)
    for y in range(h):
        row = d[y]
        if y > 0:
            up = d[y - 1]
            row = np.minimum(row, up + a)
            row[1:] = np.minimum(row[1:], up[:-1] + b)
            row[:-1] = np.minimum(row[:-1], up[1:] + b)
        for x in range(1, w):
            if row[x - 1] + a < row[x]:
                row[x] = row[x - 1] + a
        d[y] = row
    for y in range(h - 1, -1, -1):
        row = d[y]
        if y < h - 1:
            dn = d[y + 1]
            row = np.minimum(row, dn + a)
            row[1:] = np.minimum(row[1:], dn[:-1] + b)
            row[:-1] = np.minimum(row[:-1], dn[1:] + b)
        for x in range(w - 2, -1, -1):
            if row[x + 1] + a < row[x]:
                row[x] = row[x + 1] + a
        d[y] = row
    return d


def gaussian(img, sigma):
    r = max(1, int(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = np.apply_along_axis(lambda v: np.convolve(v, k, mode='same'), 0, img)
    return np.apply_along_axis(lambda v: np.convolve(v, k, mode='same'), 1, out)
