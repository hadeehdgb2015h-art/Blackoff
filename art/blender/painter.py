"""Procedural texture painter: rasterises a mesh's UV layout, recovers the
rest-pose 3D position of every texel, then evaluates numpy "paint" functions
over those positions. This gives clothing seams, wounds, blood drips and
facial features full control without hand painting.
"""
import numpy as np


# ---------------------------------------------------------------- noise

def _hash(ix, iy, iz, seed):
    h = (ix.astype(np.int64) * 73856093) ^ (iy.astype(np.int64) * 19349663) ^ (iz.astype(np.int64) * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float32) / float(0xFFFFFF)


def vnoise(p, freq, seed=0):
    """3D value noise in [0,1]. p: (N,3)."""
    q = p * freq
    i = np.floor(q)
    f = q - i
    f = f * f * (3 - 2 * f)
    i = i.astype(np.int64)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(p, freq, octaves=4, seed=0, gain=0.5):
    total = 0.0
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        total = total + amp * vnoise(p, freq * (2 ** o), seed + o * 17)
        norm += amp
        amp *= gain
    return total / norm


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def lerp(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a + (b - a) * t


# ---------------------------------------------------------------- rasteriser

def rasterize(ob, size):
    """Returns (pos (S,S,3), normal (S,S,3), part (S,S) int, valid (S,S) bool) in
    object space. `part` is the polygon material index (used as a part id)."""
    me = ob.data
    me.calc_loop_triangles()
    uv_layer = me.uv_layers.active.data
    n = len(me.loop_triangles)
    uvs = np.zeros((n, 3, 2), np.float32)
    pts = np.zeros((n, 3, 3), np.float32)
    nrm = np.zeros((n, 3, 3), np.float32)
    mat = np.zeros(n, np.int32)
    for t, tri in enumerate(me.loop_triangles):
        mat[t] = tri.material_index
        for k in range(3):
            li = tri.loops[k]
            uvs[t, k] = uv_layer[li].uv
            v = me.vertices[me.loops[li].vertex_index]
            pts[t, k] = v.co
            nrm[t, k] = v.normal
    pos = np.zeros((size, size, 3), np.float32)
    nor = np.zeros((size, size, 3), np.float32)
    valid = np.zeros((size, size), bool)
    part = np.full((size, size), -1, np.int32)
    px = uvs * size - 0.5
    for t in range(n):
        a, b, c = px[t]
        xmin = int(max(0, np.floor(min(a[0], b[0], c[0]))))
        xmax = int(min(size - 1, np.ceil(max(a[0], b[0], c[0]))))
        ymin = int(max(0, np.floor(min(a[1], b[1], c[1]))))
        ymax = int(min(size - 1, np.ceil(max(a[1], b[1], c[1]))))
        if xmax < xmin or ymax < ymin:
            continue
        xs, ys = np.meshgrid(np.arange(xmin, xmax + 1), np.arange(ymin, ymax + 1))
        v0 = b - a
        v1 = c - a
        d00 = v0 @ v0
        d01 = v0 @ v1
        d11 = v1 @ v1
        den = d00 * d11 - d01 * d01
        if abs(den) < 1e-12:
            continue
        v2x = xs - a[0]
        v2y = ys - a[1]
        d20 = v2x * v0[0] + v2y * v0[1]
        d21 = v2x * v1[0] + v2y * v1[1]
        w1 = (d11 * d20 - d01 * d21) / den
        w2 = (d00 * d21 - d01 * d20) / den
        w0 = 1 - w1 - w2
        inside = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
        if not inside.any():
            continue
        yy = ys[inside]
        xx = xs[inside]
        W = np.stack([w0[inside], w1[inside], w2[inside]], 1)
        pos[yy, xx] = W @ pts[t]
        nor[yy, xx] = W @ nrm[t]
        part[yy, xx] = mat[t]
        valid[yy, xx] = True
    return pos, nor, part, valid


def dilate(img, valid, iterations=8):
    """Bleeds colours into empty texels so UV seams don't show black edges."""
    img = img.copy()
    v = valid.copy()
    for _ in range(iterations):
        acc = np.zeros_like(img)
        cnt = np.zeros(v.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sv = np.roll(np.roll(v, dy, 0), dx, 1)
            si = np.roll(np.roll(img, dy, 0), dx, 1)
            acc += si * sv[..., None]
            cnt += sv
        grow = (~v) & (cnt > 0)
        img[grow] = acc[grow] / cnt[grow][:, None]
        v = v | grow
    return img


def to_image(bpy, name, rgb, valid, non_color=False):
    size = rgb.shape[0]
    rgb = dilate(rgb, valid)
    rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((size, size, 1), np.float32)], 2)
    img = bpy.data.images.new(name, size, size)
    # Colour space must be set before writing: changing it later reloads the
    # generated image and silently wipes the pixels (black ORM maps).
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    img.pixels = rgba.reshape(-1).tolist()
    img.pack()
    return img
