#!/usr/bin/env python3
"""Effect textures for the dark-fantasy atmosphere, pure numpy.

Run:  python3 art/textures/build_fx_textures.py
Output (client/assets/textures/):
  fx_rune_circle.png  512² white + alpha: arcane circle (rings, glyph band, star)
  fx_glyphs.png       512² white + alpha: 4x4 atlas of runes for walls
  fx_veins.png        512² white + alpha: branching corruption veins (root at bottom centre)
  fx_mist.png         256² grey, seamless: fog noise for ground mist
Colour is applied by the shaders, so one texture serves every tint.
"""
import math
import os
import struct
import zlib

import numpy as np

from build_textures import pnoise, smooth

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "client", "assets", "textures")
S = 512


def save_rgba(path, rgba):
    a = (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w, c = a.shape
    ctype = {1: 0, 3: 2, 4: 6}[c]
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)
    print("fx", os.path.basename(path))


def white_alpha(alpha):
    out = np.ones(alpha.shape + (4,), np.float32)
    out[..., 3] = np.clip(alpha, 0, 1)
    return out


# ---------------------------------------------------------------- drawing

class Canvas:
    """Anti-aliased strokes on a float mask (coordinates in 0..1)."""

    def __init__(self, n):
        self.n = n
        y, x = np.mgrid[0:n, 0:n].astype(np.float32)
        self.x = (x + 0.5) / n
        self.y = (y + 0.5) / n
        self.m = np.zeros((n, n), np.float32)

    def segment(self, a, b, w, v=1.0):
        ax, ay = a
        bx, by = b
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy + 1e-9
        # only touch the stroke's bounding box
        pad = w + 2.0 / self.n
        x0 = max(int((min(ax, bx) - pad) * self.n), 0)
        x1 = min(int((max(ax, bx) + pad) * self.n) + 1, self.n)
        y0 = max(int((min(ay, by) - pad) * self.n), 0)
        y1 = min(int((max(ay, by) + pad) * self.n) + 1, self.n)
        if x0 >= x1 or y0 >= y1:
            return
        px = self.x[y0:y1, x0:x1]
        py = self.y[y0:y1, x0:x1]
        t = np.clip(((px - ax) * dx + (py - ay) * dy) / ll, 0, 1)
        d = np.hypot(px - ax - t * dx, py - ay - t * dy)
        px_w = 1.0 / self.n
        val = smooth(w + px_w, w - px_w * 0.5, d) * v
        self.m[y0:y1, x0:x1] = np.maximum(self.m[y0:y1, x0:x1], val)

    def ring(self, cx, cy, r, w, v=1.0):
        d = np.abs(np.hypot(self.x - cx, self.y - cy) - r)
        px_w = 1.0 / self.n
        self.m = np.maximum(self.m, smooth(w + px_w, w - px_w * 0.5, d) * v)

    def polyline(self, pts, w, v=1.0, closed=False):
        for i in range(len(pts) - (0 if closed else 1)):
            self.segment(pts[i], pts[(i + 1) % len(pts)], w, v)


def rune(rng, cx, cy, size, w, cv):
    """A random angular rune made of 2-4 strokes on a 3x3 lattice."""
    pts = [(cx + (i - 1) * size * 0.5, cy + (j - 1) * size * 0.5) for j in range(3) for i in range(3)]
    spine = rng.integers(0, 3)
    cv.segment(pts[spine], pts[6 + rng.integers(0, 3)], w)  # always a vertical-ish spine
    for _ in range(rng.integers(1, 4)):
        a, b = rng.choice(9, 2, replace=False)
        cv.segment(pts[a], pts[b], w)
    if rng.random() < 0.4:
        cv.ring(pts[rng.integers(0, 9)][0], pts[rng.integers(0, 9)][1], size * 0.12, w * 0.8)


def rotate(p, c, a):
    s, k = math.sin(a), math.cos(a)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * k - y * s, c[1] + x * s + y * k)


# ---------------------------------------------------------------- textures

def rune_circle():
    cv = Canvas(S)
    c = (0.5, 0.5)
    cv.ring(0.5, 0.5, 0.47, 0.006)
    cv.ring(0.5, 0.5, 0.445, 0.002)
    cv.ring(0.5, 0.5, 0.36, 0.004)
    cv.ring(0.5, 0.5, 0.34, 0.0018)
    cv.ring(0.5, 0.5, 0.12, 0.004)
    # glyph band between the outer rings
    rng = np.random.default_rng(7)
    n = 24
    for i in range(n):
        a = i / n * math.tau
        r = 0.405
        gx, gy = 0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r
        local = []
        size = 0.045
        # draw the rune upright relative to the circle tangent
        pts = [(gx + (i2 - 1) * size * 0.5, gy + (j2 - 1) * size * 0.5) for j2 in range(3) for i2 in range(3)]
        pts = [rotate(p, (gx, gy), a + math.pi / 2) for p in pts]
        spine = rng.integers(0, 3)
        local.append((pts[spine], pts[6 + rng.integers(0, 3)]))
        for _ in range(rng.integers(1, 4)):
            p0, p1 = rng.choice(9, 2, replace=False)
            local.append((pts[p0], pts[p1]))
        for p0, p1 in local:
            cv.segment(p0, p1, 0.0028)
    # seven-pointed star inside the inner ring
    star = [(0.5 + math.cos(-math.pi / 2 + k * math.tau / 7) * 0.34, 0.5 + math.sin(-math.pi / 2 + k * math.tau / 7) * 0.34) for k in range(7)]
    for k in range(7):
        cv.segment(star[k], star[(k + 3) % 7], 0.0026)
    # small orbs where the star touches the ring
    for p in star:
        cv.ring(p[0], p[1], 0.018, 0.003)
    # radial ticks on the outer edge
    for k in range(72):
        a = k / 72 * math.tau
        r0 = 0.47 + (0.012 if k % 6 else 0.0)
        cv.segment((0.5 + math.cos(a) * r0, 0.5 + math.sin(a) * r0),
                   (0.5 + math.cos(a) * 0.49, 0.5 + math.sin(a) * 0.49), 0.0016)
    # soft inner glow so the circle reads as light, not just lines
    d = np.hypot(cv.x - c[0], cv.y - c[1])
    glow = smooth(0.5, 0.1, d) * 0.12
    alpha = np.clip(cv.m + glow, 0, 1) * smooth(0.5, 0.48, d)
    save_rgba(os.path.join(OUT, "fx_rune_circle.png"), white_alpha(alpha))


def glyphs():
    cv = Canvas(S)
    rng = np.random.default_rng(23)
    for j in range(4):
        for i in range(4):
            cx, cy = (i + 0.5) / 4, (j + 0.5) / 4
            rune(rng, cx, cy, 0.13, 0.0055, cv)
            cv.ring(cx, cy, 0.105, 0.003, 0.7)
    blur = cv.m.copy()
    for _ in range(3):  # cheap halo
        blur = (blur + np.roll(blur, 2, 0) + np.roll(blur, -2, 0) + np.roll(blur, 2, 1) + np.roll(blur, -2, 1)) / 5
    save_rgba(os.path.join(OUT, "fx_glyphs.png"), white_alpha(np.maximum(cv.m, blur * 0.7)))


def veins():
    cv = Canvas(S)
    rng = np.random.default_rng(5)

    budget = [0]  # branches left for the current root, keeps the pattern readable

    def branch(p, ang, length, w, depth):
        if depth > 4 or w < 0.0015 or budget[0] <= 0:
            return
        budget[0] -= 1
        pts = [p]
        steps = int(length / 0.02) + 2
        for _ in range(steps):
            ang += rng.normal(0, 0.22) + (-math.pi / 2 - ang) * 0.06  # wander, drift upward
            q = (pts[-1][0] + math.cos(ang) * 0.02, pts[-1][1] + math.sin(ang) * 0.02)
            if not (0.02 < q[0] < 0.98 and 0.02 < q[1] < 0.98):
                break
            pts.append(q)
        cv.polyline(pts, w)
        for k in range(1, len(pts) - 1):
            if rng.random() < 0.14:
                branch(pts[k], ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.1), length * 0.6, w * 0.62, depth + 1)

    for x, a in ((0.38, -0.5), (0.47, -0.15), (0.53, 0.15), (0.62, 0.5)):
        budget[0] = 10
        branch((x, 0.97), -math.pi / 2 + a + rng.normal(0, 0.1), 0.75, 0.0075, 0)
    blur = cv.m.copy()
    for _ in range(4):
        blur = (blur + np.roll(blur, 3, 0) + np.roll(blur, -3, 0) + np.roll(blur, 3, 1) + np.roll(blur, -3, 1)) / 5
    y = cv.y
    fade = smooth(0.0, 0.5, y)  # strongest at the root (bottom)
    save_rgba(os.path.join(OUT, "fx_veins.png"), white_alpha(np.maximum(cv.m, blur * 0.8) * (0.35 + 0.65 * fade)))


def mist():
    n = 256
    t = np.zeros((n, n), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(4):
        t += amp * pnoise(3 * 2 ** o, 90 + o * 17, size=n)
        norm += amp
        amp *= 0.5
    t /= norm
    t = smooth(0.3, 0.75, t)
    save_rgba(os.path.join(OUT, "fx_mist.png"), np.repeat(t[..., None], 3, -1))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    rune_circle()
    glyphs()
    veins()
    mist()
