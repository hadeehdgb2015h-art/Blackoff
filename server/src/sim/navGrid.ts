/**
 * Navigation grid (mirror of nav_grid.gd): walkable floors minus walls
 * inflated by the agent radius, 8-connected A* with diagonals only when both
 * neighbouring cells are open (Godot DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES),
 * octile heuristic, collinear points dropped.
 */
import type { MapData } from "./mapData.js";
import { type V2, normalized, dot } from "./math.js";

const SQRT2 = Math.SQRT2;

export class NavGrid {
  readonly w: number;
  readonly h: number;
  readonly ox: number;
  readonly oy: number;
  private open: Uint8Array;
  // reusable search buffers
  private g: Float64Array;
  private parent: Int32Array;
  private stamp: Uint32Array;
  private closed: Uint32Array;
  private run = 0;

  constructor(readonly map: MapData, readonly cell: number, readonly agentRadius: number) {
    this.ox = map.bounds.x;
    this.oy = map.bounds.y;
    this.w = Math.ceil(map.bounds.w / cell);
    this.h = Math.ceil(map.bounds.h / cell);
    const n = this.w * this.h;
    this.open = new Uint8Array(n);
    this.g = new Float64Array(n);
    this.parent = new Int32Array(n);
    this.stamp = new Uint32Array(n);
    this.closed = new Uint32Array(n);
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) this.open[y * this.w + x] = this.cellOpen(x, y) ? 1 : 0;
  }

  cellOf(p: V2): [number, number] {
    return [Math.floor((p.x - this.ox) / this.cell), Math.floor((p.y - this.oy) / this.cell)];
  }

  centerOf(x: number, y: number): V2 {
    return { x: this.ox + (x + 0.5) * this.cell, y: this.oy + (y + 0.5) * this.cell };
  }

  isOpen(x: number, y: number): boolean {
    return x >= 0 && y >= 0 && x < this.w && y < this.h && this.open[y * this.w + x] === 1;
  }

  /** World-space path from a to b (snapped to the nearest open cells). Empty if unreachable. */
  findPath(a: V2, b: V2): V2[] {
    const ca = this.nearestOpen(...this.cellOf(a));
    const cb = this.nearestOpen(...this.cellOf(b));
    if (!ca || !cb) return [];
    const raw = this.astar(ca[0], ca[1], cb[0], cb[1]);
    if (raw.length === 0) return raw;
    if (this.map.isWalkable(b)) raw[raw.length - 1] = { x: b.x, y: b.y };
    return compress(raw);
  }

  /** Spiral search for the closest open cell (agents pushed against walls). */
  nearestOpen(cx: number, cy: number, maxR = 4): [number, number] | null {
    if (this.isOpen(cx, cy)) return [cx, cy];
    for (let r = 1; r <= maxR; r++) {
      for (let dx = -r; dx <= r; dx++) {
        for (const dy of [-r, r]) if (this.isOpen(cx + dx, cy + dy)) return [cx + dx, cy + dy];
      }
      for (let dy = -r + 1; dy < r; dy++) {
        for (const dx of [-r, r]) if (this.isOpen(cx + dx, cy + dy)) return [cx + dx, cy + dy];
      }
    }
    return null;
  }

  private astar(sx: number, sy: number, tx: number, ty: number): V2[] {
    const W = this.w;
    const start = sy * W + sx;
    const goal = ty * W + tx;
    const run = ++this.run;
    const heap = new MinHeap();
    this.stamp[start] = run;
    this.g[start] = 0;
    this.parent[start] = -1;
    heap.push(start, octile(sx, sy, tx, ty));
    while (heap.size > 0) {
      const cur = heap.pop();
      if (this.closed[cur] === run) continue;
      this.closed[cur] = run;
      if (cur === goal) break;
      const cx = cur % W;
      const cy = (cur - cx) / W;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (dx === 0 && dy === 0) continue;
          const nx = cx + dx, ny = cy + dy;
          if (!this.isOpen(nx, ny)) continue;
          if (dx !== 0 && dy !== 0 && (!this.isOpen(cx + dx, cy) || !this.isOpen(cx, cy + dy))) continue;
          const ni = ny * W + nx;
          if (this.closed[ni] === run) continue;
          const ng = this.g[cur]! + (dx !== 0 && dy !== 0 ? SQRT2 : 1);
          if (this.stamp[ni] !== run || ng < this.g[ni]!) {
            this.stamp[ni] = run;
            this.g[ni] = ng;
            this.parent[ni] = cur;
            heap.push(ni, ng + octile(nx, ny, tx, ty));
          }
        }
      }
    }
    if (this.closed[goal] !== run) return [];
    const out: V2[] = [];
    for (let c = goal; c !== -1; c = this.parent[c]!) {
      const x = c % W;
      out.push(this.centerOf(x, (c - x) / W));
    }
    return out.reverse();
  }

  private cellOpen(x: number, y: number): boolean {
    const p = this.centerOf(x, y);
    if (!this.map.isWalkable(p)) return false;
    for (const idx of this.map.queryRects(p, this.agentRadius)) {
      if (this.map.moveRects[idx]!.grow(this.agentRadius).has(p)) return false;
    }
    return true;
  }
}

function octile(ax: number, ay: number, bx: number, by: number): number {
  const dx = Math.abs(ax - bx), dy = Math.abs(ay - by);
  return Math.max(dx, dy) + (SQRT2 - 1) * Math.min(dx, dy);
}

function compress(pts: V2[]): V2[] {
  if (pts.length < 3) return pts;
  const out = [pts[0]!];
  for (let k = 1; k < pts.length - 1; k++) {
    const d0 = normalized({ x: pts[k]!.x - pts[k - 1]!.x, y: pts[k]!.y - pts[k - 1]!.y });
    const d1 = normalized({ x: pts[k + 1]!.x - pts[k]!.x, y: pts[k + 1]!.y - pts[k]!.y });
    if (dot(d0, d1) < 0.999) out.push(pts[k]!);
  }
  out.push(pts[pts.length - 1]!);
  return out;
}

/** Binary min-heap of (node, priority). */
class MinHeap {
  private nodes: number[] = [];
  private prio: number[] = [];
  get size(): number { return this.nodes.length; }
  push(n: number, p: number): void {
    let i = this.nodes.length;
    this.nodes.push(n);
    this.prio.push(p);
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (this.prio[parent]! <= p) break;
      this.nodes[i] = this.nodes[parent]!;
      this.prio[i] = this.prio[parent]!;
      i = parent;
    }
    this.nodes[i] = n;
    this.prio[i] = p;
  }
  pop(): number {
    const top = this.nodes[0]!;
    const lastN = this.nodes.pop()!;
    const lastP = this.prio.pop()!;
    const n = this.nodes.length;
    if (n > 0) {
      let i = 0;
      for (;;) {
        const l = i * 2 + 1;
        if (l >= n) break;
        const r = l + 1;
        const c = r < n && this.prio[r]! < this.prio[l]! ? r : l;
        if (this.prio[c]! >= lastP) break;
        this.nodes[i] = this.nodes[c]!;
        this.prio[i] = this.prio[c]!;
        i = c;
      }
      this.nodes[i] = lastN;
      this.prio[i] = lastP;
    }
    return top;
  }
}
