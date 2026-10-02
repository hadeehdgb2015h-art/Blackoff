#!/usr/bin/env python3
"""Generates original, tileable placeholder textures (project-owned, CC0).
Output: client/assets/textures/*.png. Pure Python (no Pillow needed)."""
import math
import os
import random
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "client", "assets", "textures")


def write_png(path, w, h, rows, channels):
    color_type = {1: 0, 3: 2}[channels]
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def value_noise(size, cells, rng):
    grid = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    def smooth(t):
        return t * t * (3 - 2 * t)
    out = []
    for y in range(size):
        fy = y / size * cells
        y0 = int(fy) % cells; y1 = (y0 + 1) % cells; ty = smooth(fy - int(fy))
        row = []
        for x in range(size):
            fx = x / size * cells
            x0 = int(fx) % cells; x1 = (x0 + 1) % cells; tx = smooth(fx - int(fx))
            a = grid[y0][x0] + (grid[y0][x1] - grid[y0][x0]) * tx
            b = grid[y1][x0] + (grid[y1][x1] - grid[y1][x0]) * tx
            row.append(a + (b - a) * ty)
        out.append(row)
    return out


def fbm(size, rng, octaves=((4, 0.5), (8, 0.25), (16, 0.15), (32, 0.1))):
    acc = [[0.0] * size for _ in range(size)]
    for cells, amp in octaves:
        n = value_noise(size, cells, rng)
        for y in range(size):
            for x in range(size):
                acc[y][x] += n[y][x] * amp
    return acc


def grime(size=256, seed=7):
    rng = random.Random(seed)
    n = fbm(size, rng)
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            v = n[y][x]
            v = 0.55 + (v - 0.5) * 0.9 + (rng.random() - 0.5) * 0.06
            row.append(max(0, min(255, int(v * 255))))
        rows.append(row)
    return rows


def hazard(size=128):
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            stripe = ((x + y) // (size // 4)) % 2
            c = (220, 160, 20) if stripe == 0 else (25, 25, 25)
            row.extend(c)
        rows.append(row)
    return rows


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write_png(os.path.join(OUT, "grime.png"), 256, 256, grime(), 1)
    write_png(os.path.join(OUT, "hazard.png"), 128, 128, hazard(), 3)
    print("textures written to", os.path.abspath(OUT))
