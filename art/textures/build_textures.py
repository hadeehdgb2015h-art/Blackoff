#!/usr/bin/env python3
"""Tileable surface textures for the facility (albedo + normal), pure numpy.

Run:  /opt/blender-venv/bin/python art/textures/build_textures.py   (any python3 with numpy)
Output: client/assets/textures/<name>_albedo.png, <name>_normal.png (512x512, seamless).
Palette: readable mid-values with a restrained dark-fantasy tint
(slate-violet walls, warm stone floors, bronze-tinted metal).
"""
import os
import struct
import zlib

import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "client", "assets", "textures")
S = 512


# ---------------------------------------------------------------- periodic noise

def _lattice(n, seed):
    return np.random.default_rng(seed).random((n, n)).astype(np.float32)


def pnoise(freq, seed, size=S):
    """Periodic value noise with `freq` cells across the tile."""
    g = _lattice(freq, seed)
    c = np.arange(size, dtype=np.float32) * freq / size
    i0 = np.floor(c).astype(int) % freq
    i1 = (i0 + 1) % freq
    f = c - np.floor(c)
    f = f * f * (3 - 2 * f)
    a = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
    b = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fbm(freq, seed, octaves=5, gain=0.5):
    t = np.zeros((S, S), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        t += amp * pnoise(freq * 2 ** o, seed + o * 31)
        norm += amp
        amp *= gain
    return t / norm


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


def lerp(a, b, t):
    return a + (b - a) * np.asarray(t)[..., None]


def grid_lines(cells, width, offset_rows=False):
    """Distance-to-grid mask (1 on lines) for `cells` x `cells` tiles."""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S * cells
    if offset_rows:
        x = x + (np.floor(y) % 2) * 0.5
    dx = np.abs(x - np.round(x))
    dy = np.abs(y - np.round(y))
    d = np.minimum(dx, dy) / cells * S
    return smooth(width, 0.0, d), np.floor(x) % cells, np.floor(y) % cells


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save_png(path, rgb):
    a = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w, _ = a.shape
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def write(name, albedo, height, strength):
    save_png(os.path.join(OUT, name + "_albedo.png"), albedo)
    save_png(os.path.join(OUT, name + "_normal.png"), normal_from_height(height, strength))
    print("texture", name)


# ---------------------------------------------------------------- surfaces

def floor_tiles():
    """Large worn stone/concrete tiles (4x4 per texture), warm grey."""
    lines, tx, ty = grid_lines(4, 3.0)
    var = pnoise(4, 7)  # per-tile tone variation (sampled at tile centres)
    tile_tone = var[(ty * S / 4 + S / 8).astype(int) % S, (tx * S / 4 + S / 8).astype(int) % S]
    base = lerp(hexc("#8a8379"), hexc("#6d6760"), tile_tone)
    grime = fbm(6, 3)
    base = lerp(base, hexc("#4f4a45"), smooth(0.5, 0.8, grime) * 0.6)
    cracks = smooth(0.012, 0.0, np.abs(fbm(10, 21, 4) - 0.5)) * smooth(0.55, 0.7, fbm(5, 22))
    base = lerp(base, hexc("#3a3632"), cracks * 0.8)
    speck = pnoise(128, 5)
    base *= (0.94 + 0.06 * speck)[..., None]
    base = lerp(base, hexc("#2a2724"), lines * 0.85)
    height = (1 - lines) * 0.6 + fbm(24, 9, 3) * 0.25 - cracks * 0.3
    write("floor_tiles", base, height, 3.0)


def wall_panels():
    """Painted concrete panels with seams, bolts and water streaks (slate-violet)."""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    seam_v = smooth(2.5, 0.0, np.abs(x * 2 - np.round(x * 2)) / 2 * S)
    seam_h = smooth(2.5, 0.0, np.abs(y - np.round(y)) * S)
    seams = np.maximum(seam_v, seam_h)
    base = lerp(hexc("#6c6e78"), hexc("#5a5c66"), fbm(5, 11))
    streak = fbm(3, 12) * pnoise(64, 13)[0:1, :].repeat(S, 0)  # vertical water streaks
    base = lerp(base, hexc("#3f4150"), smooth(0.35, 0.6, streak) * 0.5)
    chips = smooth(0.74, 0.77, fbm(22, 14, 4))
    base = lerp(base, hexc("#4a4b52"), chips * 0.4)  # small scuffs, darker than the paint
    bolts = np.zeros((S, S), np.float32)
    for bx in (0.04, 0.46, 0.54, 0.96):
        for by in (0.05, 0.5, 0.95):
            d = np.hypot((x - bx) * S, (y - by) * S)
            bolts = np.maximum(bolts, smooth(5.0, 3.0, d))
    base = lerp(base, hexc("#9c8a6a"), bolts * 0.8)  # brass bolts
    base = lerp(base, hexc("#2c2d36"), seams * 0.8)
    height = (1 - seams) * 0.5 + bolts * 0.6 - chips * 0.1 + fbm(30, 15, 3) * 0.15
    write("wall_panels", base, height, 2.5)


def metal_plate():
    """Bronze-tinted steel plate with rivet rows and wear."""
    lines, tx, ty = grid_lines(2, 2.0)
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    base = lerp(hexc("#5c574f"), hexc("#3f3b36"), fbm(6, 31))
    scratches = smooth(0.008, 0.0, np.abs(fbm(18, 32, 3) - 0.5))
    base = lerp(base, hexc("#9a948a"), scratches * 0.6)
    rust = smooth(0.62, 0.8, fbm(8, 33))
    base = lerp(base, hexc("#6e4128"), rust * 0.55)
    rivets = np.zeros((S, S), np.float32)
    for i in range(16):
        for k in (0.03, 0.47, 0.53, 0.97):
            for (cx, cy) in ((i / 16 + 1 / 32, k), (k, i / 16 + 1 / 32)):
                d = np.hypot((x - cx) * S, (y - cy) * S)
                rivets = np.maximum(rivets, smooth(4.0, 2.0, d))
    base = lerp(base, hexc("#7d776d"), rivets * 0.6)
    base = lerp(base, hexc("#22201d"), lines)
    height = (1 - lines) * 0.4 + rivets * 0.5 + fbm(40, 34, 2) * 0.1
    write("metal_plate", base, height, 3.0)


def ground():
    """Cracked asphalt and packed dirt for the yard, with moss/ichor tint."""
    base = lerp(hexc("#4d4c50"), hexc("#3a393d"), fbm(8, 41))
    dirt = smooth(0.5, 0.7, fbm(3, 42))
    base = lerp(base, hexc("#5e5243"), dirt * 0.7)
    moss = smooth(0.62, 0.78, fbm(5, 43)) * (1 - dirt)
    base = lerp(base, hexc("#3f4d40"), moss * 0.6)
    cracks = smooth(0.01, 0.0, np.abs(fbm(6, 44, 5) - 0.5))
    base = lerp(base, hexc("#1d1c20"), cracks * 0.9)
    gravel = smooth(0.7, 0.75, pnoise(160, 45))
    base = lerp(base, hexc("#7a7672"), gravel * 0.35)
    height = fbm(30, 46, 3) * 0.5 - cracks * 0.6 + gravel * 0.2
    write("ground", base, height, 4.0)


def ceiling():
    """Acoustic ceiling panels in a dark grid frame."""
    lines, tx, ty = grid_lines(4, 2.5)
    base = lerp(hexc("#4a4b55"), hexc("#3d3e47"), fbm(5, 51))
    holes = smooth(0.85, 0.9, pnoise(96, 52))
    base = lerp(base, hexc("#2b2c33"), holes * 0.5)
    stain = smooth(0.6, 0.8, fbm(4, 53))
    base = lerp(base, hexc("#4b3d2f"), stain * 0.4)
    base = lerp(base, hexc("#1f2026"), lines)
    height = (1 - lines) * 0.4 - holes * 0.15
    write("ceiling", base, height, 2.0)


def stone_blocks():
    """Old dressed-stone wall: staggered dark blocks with pale mortar, moss and damp (crypt, chapel, cloister)."""
    lines, tx, ty = grid_lines(6, 2.2, offset_rows=True)
    var = pnoise(6, 61)
    block_tone = var[(ty * S / 6 + S / 12).astype(int) % S, (tx * S / 6 + S / 12).astype(int) % S]
    base = lerp(hexc("#4a4852"), hexc("#2f2e36"), block_tone)
    chip = smooth(0.55, 0.8, fbm(14, 62, 4))
    base = lerp(base, hexc("#5c5a62"), chip * 0.35)
    moss = smooth(0.62, 0.85, fbm(5, 63, 4)) * smooth(0.4, 0.6, 1 - ty)
    base = lerp(base, hexc("#3a4a30"), moss * 0.55)
    damp = smooth(0.5, 0.75, fbm(3, 64, 3))
    base = lerp(base, hexc("#232228"), damp * 0.4)
    speck = pnoise(96, 65)
    base *= (0.93 + 0.07 * speck)[..., None]
    base = lerp(base, hexc("#8a8578"), lines * 0.9)   # mortar
    height = (1 - lines) * 0.7 + fbm(20, 66, 3) * 0.2 - chip * 0.15
    write("stone_blocks", base, height, 3.5)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    floor_tiles()
    wall_panels()
    metal_plate()
    ground()
    ceiling()
    stone_blocks()
