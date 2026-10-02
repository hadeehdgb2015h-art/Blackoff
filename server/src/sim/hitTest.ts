/** Ray tests against character hit shapes (mirror of hit_test.gd): a vertical
 *  body cylinder from the ankles to the neck plus a head sphere. */
import type { V2, V3 } from "./math.js";

export const FEET = 0.1;

export function raySphere(o: V3, d: V3, c: V3, r: number): number {
  const ox = o.x - c.x, oy = o.y - c.y, oz = o.z - c.z;
  const b = ox * d.x + oy * d.y + oz * d.z;
  const cc = ox * ox + oy * oy + oz * oz - r * r;
  const disc = b * b - cc;
  if (disc < 0) return -1;
  const s = Math.sqrt(disc);
  let t = -b - s;
  if (t < 0) t = -b + s;
  return t >= 0 ? t : -1;
}

/** Side surface of a vertical cylinder at base (x, z) from y0 to y1. */
export function rayCylinder(o: V3, d: V3, base: V2, y0: number, y1: number, r: number): number {
  const ox = o.x - base.x, oz = o.z - base.y;
  const a = d.x * d.x + d.z * d.z;
  if (a < 1e-9) return -1;
  const b = ox * d.x + oz * d.z;
  const c = ox * ox + oz * oz - r * r;
  const disc = b * b - a * c;
  if (disc < 0) return -1;
  const s = Math.sqrt(disc);
  for (const t of [(-b - s) / a, (-b + s) / a]) {
    if (t >= 0) {
      const y = o.y + d.y * t;
      if (y >= y0 && y <= y1) return t;
    }
  }
  return -1;
}

export interface CharHit { t: number; head: boolean }

export function rayCharacter(o: V3, d: V3, pos: V2, radius: number, headY: number, headR: number): CharHit | null {
  const th = raySphere(o, d, { x: pos.x, y: headY, z: pos.y }, headR);
  const tb = rayCylinder(o, d, pos, FEET, headY - headR, radius);
  if (th >= 0 && (tb < 0 || th <= tb)) return { t: th, head: true };
  if (tb >= 0) return { t: tb, head: false };
  return null;
}
