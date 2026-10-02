/**
 * Gameplay geometry of a map (mirror of map_data.gd), built from
 * shared/maps/<id>.json: a flat plane (Godot x, z) with axis-aligned wall
 * boxes. Boxes taller than stepHeight block movement; every box blocks
 * bullets inside its own height range.
 */
import type { MapDef } from "../shared/schemas.js";
import { type V2, type V3, dist, lerp2 } from "./math.js";

export const BUCKET = 2.0;

/** Axis-aligned rectangle; `has` follows Godot Rect2.has_point (end exclusive). */
export class Rect {
  constructor(public x: number, public y: number, public w: number, public h: number) {}
  static fromMinMax(min: readonly number[], max: readonly number[]): Rect {
    return new Rect(min[0]!, min[1]!, max[0]! - min[0]!, max[1]! - min[1]!);
  }
  get ex(): number { return this.x + this.w; }
  get ey(): number { return this.y + this.h; }
  has(p: V2): boolean { return p.x >= this.x && p.y >= this.y && p.x < this.ex && p.y < this.ey; }
  grow(by: number): Rect { return new Rect(this.x - by, this.y - by, this.w + by * 2, this.h + by * 2); }
}

export interface Box3 { min: V3; max: V3 }
export interface ZombieEntry { id: string; pos: V2; inside: V2 }
export interface Interactable { id: string; kind: "weapon" | "ammo" | "box"; item: string; pos: V2; radius: number }

export class MapData {
  id: string;
  floorHeight: number;
  bounds: Rect;
  walkable: Rect[] = [];
  wallBoxes: Box3[] = [];
  moveRects: Rect[] = [];
  playerSpawns: { pos: V2; yaw: number }[] = [];
  zombieEntries: ZombieEntry[] = [];
  interactables: Interactable[] = [];
  safeArea: Rect;
  private buckets = new Map<string, number[]>();

  constructor(d: MapDef, stepHeight: number) {
    this.id = d.id;
    this.floorHeight = d.floorHeight;
    this.bounds = Rect.fromMinMax(d.bounds.min, d.bounds.max);
    for (const w of d.walkable) this.walkable.push(Rect.fromMinMax(w.min, w.max));
    for (const w of d.walls) {
      const [x0, y0, z0] = w.min;
      const [x1, y1, z1] = w.max;
      this.wallBoxes.push({ min: { x: x0, y: y0, z: z0 }, max: { x: x1, y: y1, z: z1 } });
      if (y1 > stepHeight) this.moveRects.push(new Rect(x0, z0, x1 - x0, z1 - z0));
    }
    for (const s of d.playerSpawns) this.playerSpawns.push({ pos: { x: s.pos[0], y: s.pos[1] }, yaw: s.yaw });
    for (const e of d.zombieEntries) {
      this.zombieEntries.push({ id: e.id, pos: { x: e.pos[0], y: e.pos[1] }, inside: { x: e.inside[0], y: e.inside[1] } });
    }
    for (const it of d.interactables) {
      this.interactables.push({ id: it.id, kind: it.kind, item: it.item ?? "", pos: { x: it.pos[0], y: it.pos[1] }, radius: it.radius });
    }
    this.safeArea = Rect.fromMinMax(d.safeArea.min, d.safeArea.max);
    this.buildBuckets();
  }

  isWalkable(p: V2): boolean {
    for (const r of this.walkable) if (r.has(p)) return true;
    return false;
  }

  /** Moves a circle by delta with wall sliding, sub-stepped against tunnelling. */
  moveCircle(pos: V2, delta: V2, radius: number): V2 {
    const l = Math.hypot(delta.x, delta.y);
    const steps = Math.max(1, Math.ceil(l / (radius * 0.5)));
    const sx = delta.x / steps, sy = delta.y / steps;
    let p = pos;
    for (let i = 0; i < steps; i++) p = this.resolveCircle({ x: p.x + sx, y: p.y + sy }, radius);
    return p;
  }

  /** Pushes a circle out of every overlapping movement-blocking wall. */
  resolveCircle(pos: V2, radius: number): V2 {
    let px = pos.x, py = pos.y;
    for (let iter = 0; iter < 3; iter++) {
      let moved = false;
      for (const idx of this.queryRects({ x: px, y: py }, radius)) {
        const r = this.moveRects[idx]!;
        const cx = Math.min(Math.max(px, r.x), r.ex);
        const cy = Math.min(Math.max(py, r.y), r.ey);
        const dx = px - cx, dy = py - cy;
        const d2 = dx * dx + dy * dy;
        if (d2 >= radius * radius) continue;
        if (d2 > 0.000001) {
          const d = Math.sqrt(d2);
          px += (dx / d) * (radius - d);
          py += (dy / d) * (radius - d);
        } else {
          const left = px - r.x, right = r.ex - px, top = py - r.y, bottom = r.ey - py;
          const m = Math.min(left, right, top, bottom);
          if (m === left) px = r.x - radius;
          else if (m === right) px = r.ex + radius;
          else if (m === top) py = r.y - radius;
          else py = r.ey + radius;
        }
        moved = true;
      }
      if (!moved) break;
    }
    return { x: px, y: py };
  }

  /** Distance along a normalised 3D ray to the first wall box, or maxDist. */
  raycast(origin: V3, dir: V3, maxDist: number): number {
    let best = maxDist;
    for (const box of this.wallBoxes) {
      const t = rayAabb(origin, dir, box.min, box.max, best);
      if (t >= 0 && t < best) best = t;
    }
    return best;
  }

  /** True if a circle of the given radius can slide straight from a to b. */
  segmentClear(a: V2, b: V2, radius: number): boolean {
    const dx = b.x - a.x, dy = b.y - a.y;
    const l = Math.hypot(dx, dy);
    if (l < 0.0001) return true;
    const d3 = { x: dx / l, y: 0, z: dy / l };
    const o3 = { x: a.x, y: 0.5, z: a.y };
    for (const idx of this.querySegment(a, b)) {
      const r = this.moveRects[idx]!;
      const t = rayAabb(o3, d3, { x: r.x - radius, y: 0, z: r.y - radius }, { x: r.ex + radius, y: 1, z: r.ey + radius }, l);
      if (t >= 0 && t <= l) return false;
    }
    return true;
  }

  queryRects(pos: V2, radius: number): readonly number[] {
    // Rects are bucketed with a 1 m margin, so one bucket covers radius <= 1.
    if (radius <= 1.0) return this.buckets.get(key(Math.floor(pos.x / BUCKET), Math.floor(pos.y / BUCKET))) ?? EMPTY;
    return this.moveRects.map((_, i) => i);
  }

  private querySegment(a: V2, b: V2): number[] {
    const out: number[] = [];
    const seen = new Set<string>();
    const n = Math.max(1, Math.ceil(dist(a, b) / (BUCKET * 0.5)));
    for (let k = 0; k <= n; k++) {
      const p = lerp2(a, b, k / n);
      const kk = key(Math.floor(p.x / BUCKET), Math.floor(p.y / BUCKET));
      if (seen.has(kk)) continue;
      seen.add(kk);
      const list = this.buckets.get(kk);
      if (list) out.push(...list);
    }
    return out;
  }

  private buildBuckets(): void {
    this.moveRects.forEach((rect, i) => {
      const r = rect.grow(1.0);
      for (let bx = Math.floor(r.x / BUCKET); bx <= Math.floor(r.ex / BUCKET); bx++) {
        for (let bz = Math.floor(r.y / BUCKET); bz <= Math.floor(r.ey / BUCKET); bz++) {
          const k = key(bx, bz);
          let list = this.buckets.get(k);
          if (!list) this.buckets.set(k, (list = []));
          list.push(i);
        }
      }
    });
  }
}

const EMPTY: readonly number[] = [];
const key = (x: number, y: number): string => `${x},${y}`;

/** Slab test. Returns entry distance (0 if the origin is inside) or -1. */
export function rayAabb(o: V3, d: V3, mn: V3, mx: V3, maxT: number): number {
  let tmin = 0;
  let tmax = maxT;
  for (const axis of ["x", "y", "z"] as const) {
    const oa = o[axis], da = d[axis];
    if (Math.abs(da) < 1e-8) {
      if (oa < mn[axis] || oa > mx[axis]) return -1;
    } else {
      const inv = 1 / da;
      let t1 = (mn[axis] - oa) * inv;
      let t2 = (mx[axis] - oa) * inv;
      if (t1 > t2) [t1, t2] = [t2, t1];
      tmin = Math.max(tmin, t1);
      tmax = Math.min(tmax, t2);
      if (tmin > tmax) return -1;
    }
  }
  return tmin;
}
