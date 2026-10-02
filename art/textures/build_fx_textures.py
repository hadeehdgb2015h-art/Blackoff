#!/usr/bin/env python3
"""Effect textures for the dark-fantasy atmosphere, pure numpy.
No circles, stars or sigils (owner request): veins, mist, moon face, lightning only.

Run:  python3 art/textures/build_fx_textures.py
Output (client/assets/textures/):
  fx_veins.png        512² white + alpha: branching corruption veins (root at bottom centre)
  fx_mist.png         256² grey, seamless: fog noise for ground mist
  fx_moon_face.png    512² RGBA: pale blue moon with a grinning face and glowing eyes
  fx_bolt.png         256x512 white + alpha: branching lightning bolt
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


# ---------------------------------------------------------------- textures

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


def moon_face():
    n = 512
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    u = (x + 0.5) / n * 2 - 1
    v = (y + 0.5) / n * 2 - 1  # +v is down
    r = np.hypot(u, v)
    disc = smooth(0.97, 0.95, r)
    h = np.sqrt(np.clip(1 - r * r, 0, 1)) * 0.6

    def blob(cx, cy, sx, sy, amp, rot=0.0):
        c, s_ = math.cos(rot), math.sin(rot)
        dx, dy = u - cx, v - cy
        px, py = dx * c + dy * s_, -dx * s_ + dy * c
        return amp * np.exp(-((px / sx) ** 2 + (py / sy) ** 2))

    rng = np.random.default_rng(3)
    for _ in range(26):  # craters near the rim, keeping the face clean
        a, rad = rng.uniform(0, math.tau), rng.uniform(0.62, 0.88)
        cx, cy, rr = math.cos(a) * rad, math.sin(a) * rad, rng.uniform(0.02, 0.07)
        d = np.hypot(u - cx, v - cy)
        h += 0.03 * np.exp(-((d - rr) / (rr * 0.35)) ** 2) - 0.04 * np.exp(-(d / (rr * 0.8)) ** 2)
    for sx in (-1, 1):
        h += blob(sx * 0.33, -0.36, 0.2, 0.06, 0.16, sx * 0.25)      # brows
        h += blob(sx * 0.43, 0.12, 0.17, 0.14, 0.13)                  # cheeks
        h -= blob(sx * 0.31, -0.17, 0.15, 0.05, 0.22, -sx * 0.15)     # squinting eye slits
    h += blob(0, -0.02, 0.07, 0.17, 0.2)                              # nose
    h += blob(0, 0.1, 0.13, 0.05, 0.08)                               # nostrils ridge
    # wide open grin: smile-curved upper lip, deep mouth
    top = 0.3 - 0.32 * u * u      # corners curl up into a grin
    bottom = 0.58 - 0.62 * u * u
    mouth = smooth(0.02, -0.02, top - v) * smooth(0.02, -0.02, v - bottom) * smooth(0.6, 0.52, np.abs(u))
    h -= mouth * 0.32
    teeth = np.zeros_like(u)
    for i in range(-6, 7):
        tx = i * 0.075
        if abs(tx) > 0.52:
            continue
        ty = 0.3 - 0.32 * tx * tx
        teeth = np.maximum(teeth, blob(tx, ty + 0.04, 0.026, 0.045, 1.0))
        teeth = np.maximum(teeth, blob(tx + 0.035, 0.58 - 0.62 * (tx + 0.035) ** 2 - 0.035, 0.022, 0.035, 0.9))
    teeth *= mouth
    h += teeth * 0.2
    gy, gx = np.gradient(h)
    nx, ny, nz = -gx * 60, -gy * 60, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    L = np.array([-0.45, -0.55, 0.7])
    L /= np.linalg.norm(L)
    shade = np.clip((nx * L[0] + ny * L[1] + nz * L[2]) / ln, 0, 1) * 0.85 + 0.2
    maria = smooth(0.35, 0.7, fbm_n(n, 4, 21))
    base = np.stack([0.62 + 0.1 * maria, 0.78 + 0.08 * maria, 1.0 + 0 * maria], -1)
    col = base * shade[..., None]
    col = col * (1 - mouth[..., None] * 0.85) + np.array([0.03, 0.05, 0.16]) * mouth[..., None] * 0.85
    col = col * (1 - teeth[..., None]) + np.array([0.85, 0.92, 1.0]) * teeth[..., None] * shade[..., None]
    eyes = np.zeros_like(u)
    for sx in (-1, 1):
        eyes = np.maximum(eyes, blob(sx * 0.31, -0.17, 0.13, 0.035, 1.0, -sx * 0.15))
    eyes = np.clip(eyes * 1.6, 0, 1)
    col = col * (1 - eyes[..., None]) + np.array([0.85, 0.97, 1.0]) * eyes[..., None]
    rim = smooth(0.7, 0.96, r) * 0.25
    col = np.clip(col + np.array([0.2, 0.35, 0.8]) * rim[..., None], 0, 1)
    out = np.concatenate([col, disc[..., None]], -1)
    save_rgba(os.path.join(OUT, "fx_moon_face.png"), out)


def fbm_n(n, freq, seed):
    t = np.zeros((n, n), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(4):
        t += amp * pnoise(freq * 2 ** o, seed + o * 13, size=n)
        norm += amp
        amp *= 0.5
    return t / norm


def bolt():
    w, hgt = 256, 512
    cv = Canvas(hgt)  # square canvas, the bolt lives in the middle half
    rng = np.random.default_rng(9)

    def strike(p, ang, length, width, depth):
        pts = [p]
        for _ in range(int(length / 0.03)):
            ang += rng.normal(0, 0.45)
            ang = max(min(ang, math.pi * 0.8), math.pi * 0.2)  # mostly downward
            q = (pts[-1][0] + math.cos(ang) * 0.03, pts[-1][1] + math.sin(ang) * 0.03)
            if not (0.27 < q[0] < 0.73 and q[1] < 0.99):
                break
            pts.append(q)
        cv.polyline(pts, width)
        if depth < 2:
            for k in range(2, len(pts) - 2):
                if rng.random() < 0.08:
                    strike(pts[k], ang + rng.choice([-1, 1]) * 0.7, length * 0.4, width * 0.55, depth + 1)

    strike((0.5, 0.01), math.pi / 2, 1.0, 0.006, 0)
    core = cv.m[:, hgt // 2 - w // 2: hgt // 2 + w // 2]
    glow = core.copy()
    for _ in range(6):
        glow = (glow + np.roll(glow, 2, 0) + np.roll(glow, -2, 0) + np.roll(glow, 2, 1) + np.roll(glow, -2, 1)) / 5
    save_rgba(os.path.join(OUT, "fx_bolt.png"), white_alpha(np.clip(core + glow * 1.5, 0, 1)))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    veins()
    mist()
    moon_face()
    bolt()
