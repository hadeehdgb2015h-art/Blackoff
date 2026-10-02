/**
 * Vector and angle helpers. Conventions match client/scripts/sim/sim_math.gd:
 * the sim plane is Godot (x, z) stored as {x, y}; yaw = 0 faces -Z and positive
 * yaw turns left; pitch > 0 looks up.
 */
export interface V2 { x: number; y: number }
export interface V3 { x: number; y: number; z: number }

export const v2 = (x = 0, y = 0): V2 => ({ x, y });
export const v3 = (x = 0, y = 0, z = 0): V3 => ({ x, y, z });
export const add = (a: V2, b: V2): V2 => ({ x: a.x + b.x, y: a.y + b.y });
export const sub = (a: V2, b: V2): V2 => ({ x: a.x - b.x, y: a.y - b.y });
export const scale = (a: V2, s: number): V2 => ({ x: a.x * s, y: a.y * s });
export const dot = (a: V2, b: V2): number => a.x * b.x + a.y * b.y;
export const len2 = (a: V2): number => a.x * a.x + a.y * a.y;
export const len = (a: V2): number => Math.sqrt(len2(a));
export const dist2 = (a: V2, b: V2): number => (a.x - b.x) ** 2 + (a.y - b.y) ** 2;
export const dist = (a: V2, b: V2): number => Math.sqrt(dist2(a, b));
export const lerp2 = (a: V2, b: V2, t: number): V2 => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });

export function normalized(a: V2): V2 {
  const l = len(a);
  return l > 0 ? { x: a.x / l, y: a.y / l } : { x: 0, y: 0 };
}

export function limitLength(a: V2, max: number): V2 {
  const l = len(a);
  return l > max && l > 0 ? { x: (a.x / l) * max, y: (a.y / l) * max } : { x: a.x, y: a.y };
}

export function rotated(a: V2, angle: number): V2 {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return { x: a.x * c - a.y * s, y: a.x * s + a.y * c };
}

export const clamp = (v: number, lo: number, hi: number): number => (v < lo ? lo : v > hi ? hi : v);

/** Godot wrapf(). */
export function wrapf(v: number, min: number, max: number): number {
  const range = max - min;
  return range === 0 ? min : v - range * Math.floor((v - min) / range);
}

/** Godot round(): halves away from zero. */
export const roundHalfAway = (v: number): number => Math.sign(v) * Math.round(Math.abs(v));

export const wrapAngle = (a: number): number => wrapf(a, -Math.PI, Math.PI);
export const forward = (yaw: number): V2 => ({ x: -Math.sin(yaw), y: -Math.cos(yaw) });
export const right = (yaw: number): V2 => ({ x: Math.cos(yaw), y: -Math.sin(yaw) });

export function yawTo(from: V2, to: V2): number {
  return Math.atan2(-(to.x - from.x), -(to.y - from.y));
}

export function dir3(yaw: number, pitch: number): V3 {
  const cp = Math.cos(pitch);
  return { x: -Math.sin(yaw) * cp, y: Math.sin(pitch), z: -Math.cos(yaw) * cp };
}

export function approachAngle(cur: number, target: number, maxStep: number): number {
  return cur + clamp(wrapAngle(target - cur), -maxStep, maxStep);
}
