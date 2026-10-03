/**
 * One zone's side of the puzzles (phase 31): it implements PuzzleApi for the
 * secret module, keeps the objects, turns them into protocol messages (labels
 * in each player's language), works out which object a shot hit, checks that
 * a player using an object stands next to it, and never lets a module error
 * take the zone down.
 */
import { WeaponState, type SimEvent, type SimPlayer } from "../sim/entities.js";
import type { V2 } from "../sim/math.js";
import { Rng } from "../sim/rng.js";
import type { SimWorld } from "../sim/simWorld.js";
import { log } from "../log.js";
import type { Lang, PuzzleApi, PuzzleInstance, PuzzleModule, PuzzleObject, PuzzleObjectDef, Texts } from "./api.js";

/** What the host needs from its zone. */
export interface PuzzleZone {
  readonly id: number;
  readonly world: SimWorld;
  humans(): SimPlayer[];
  /** sends to every member (or one), built per language */
  sendEach(name: string, build: (lang: Lang) => Record<string, unknown>, to?: number): void;
  reward(pids: number[]): void;
}

const MAX_OBJECTS = 200;
const USE_SLACK = 0.8;

export class PuzzleHost implements PuzzleApi {
  readonly objects = new Map<number, PuzzleObject>();
  private nextId = 1;
  private readonly rng: Rng;
  private instance: PuzzleInstance | null = null;
  private failed = false;
  private dirty = false;

  constructor(private readonly zone: PuzzleZone, module: PuzzleModule, seed: number) {
    this.rng = new Rng(seed >>> 0 || 1);
    this.guard("create", () => {
      this.instance = module.create(this);
    });
  }

  get world(): SimWorld { return this.zone.world; }
  get zoneId(): number { return this.zone.id; }

  random(): number { return this.rng.next() / 4294967296; }
  humans(): SimPlayer[] { return this.zone.humans(); }

  add(def: PuzzleObjectDef): number {
    if (this.objects.size >= MAX_OBJECTS) throw new Error("too many puzzle objects");
    const id = this.nextId++;
    this.objects.set(id, {
      id, kind: def.kind, x: def.x, y: def.y, z: def.z, yaw: def.yaw ?? 0, size: def.size ?? 1, state: def.state ?? 0,
      text: def.text ?? "", label: def.label ?? null, useRadius: def.useRadius ?? 0, shootRadius: def.shootRadius ?? 0,
      shootHeight: def.shootHeight ?? 0, codeLength: def.codeLength ?? 0,
    });
    this.dirty = true;
    return id;
  }

  update(id: number, patch: Partial<PuzzleObject>): void {
    const o = this.objects.get(id);
    if (!o) return;
    const placeChanged = ["x", "y", "z", "yaw", "label", "useRadius", "shootRadius", "codeLength"].some((k) => k in patch && (patch as Record<string, unknown>)[k] !== (o as unknown as Record<string, unknown>)[k]);
    Object.assign(o, patch);
    if (placeChanged) this.dirty = true;
    else if ("state" in patch || "text" in patch) this.zone.sendEach("puzzleState", () => ({ id, state: clampU16(o.state), text: o.text.slice(0, 60) }));
  }

  remove(id: number): void {
    if (this.objects.delete(id)) this.dirty = true;
  }

  get(id: number): PuzzleObject | undefined { return this.objects.get(id); }

  say(text: Texts, opts: { to?: number; big?: boolean } = {}): void {
    this.zone.sendEach("puzzleMsg", (lang) => ({ text: (text[lang] || text.en).slice(0, 300), big: !!opts.big }), opts.to);
  }

  spawnZombies(type: string, count: number): number {
    let n = 0;
    const w = this.world;
    for (let i = 0; i < count; i++) if (w.zombieSys.spawn(type, Math.max(1, w.director.wave))) n += 1;
    return n;
  }

  giveWeapon(pid: number, weaponId: string): void {
    const w = this.world;
    const p = w.players.get(pid);
    const def = w.defs.weapons[weaponId];
    if (!p || !def) return;
    const have = p.weapons.findIndex((x) => x.id === weaponId);
    if (have >= 0) {
      const wp = p.weapons[have]!;
      wp.mag = def.magSize;
      wp.reserve = def.reserveMax;
      p.slot = have;
    } else if (p.weapons.length < 2) {
      p.weapons.push(new WeaponState(weaponId, def));
      p.slot = p.weapons.length - 1;
    } else {
      p.weapons[p.slot] = new WeaponState(weaponId, def);
    }
    p.reloadEnd = 0;
    w.emit({ type: "weapon_switched", pid, weapon: weaponId });
  }

  reward(pids: number[]): void {
    this.zone.reward(pids.filter((id) => this.world.players.get(id) && !this.world.players.get(id)!.bot));
  }

  walkableNear(p: V2, radius: number): V2 {
    const map = this.world.map;
    for (let i = 0; i < 40; i++) {
      const a = this.random() * Math.PI * 2;
      const r = this.random() * radius;
      const q = { x: p.x + Math.cos(a) * r, y: p.y + Math.sin(a) * r };
      if (map.isWalkable(q)) return q;
    }
    return { ...p };
  }

  // ------------------------------------------------------------------ from the zone

  tick(events: readonly SimEvent[]): void {
    if (!this.instance) return;
    for (const e of events) {
      if (e.type !== "shot") continue;
      const hit = this.shotTarget(Number(e.pid), e.to as { x: number; y: number; z: number });
      if (hit) this.guard("onShoot", () => this.instance!.onShoot?.(Number(e.pid), hit));
    }
    this.guard("tick", () => this.instance!.tick?.(events));
    this.flush();
  }

  /** A player asks to use an object: only within its reach, alive, and only usable objects. */
  use(pid: number, objectId: number, code: string): void {
    const o = this.objects.get(objectId);
    const p = this.world.players.get(pid);
    if (!this.instance || !o || !o.label || o.useRadius <= 0 || !p || !p.isAlive() || p.bot) return;
    if (Math.hypot(p.pos.x - o.x, p.pos.y - o.z) > o.useRadius + USE_SLACK) return;
    const clean = o.codeLength > 0 ? code.replace(/\D/g, "").slice(0, o.codeLength) : "";
    this.guard("onUse", () => this.instance!.onUse?.(pid, objectId, clean));
    this.flush();
  }

  answers(): string {
    if (!this.instance?.answers) return "";
    try {
      return this.instance.answers();
    } catch (err) {
      return "error: " + (err as Error).message;
    }
  }

  /** The whole set, as a protocol message in one language. */
  message(lang: Lang): Record<string, unknown> {
    return {
      objects: [...this.objects.values()].slice(0, 255).map((o) => ({
        id: o.id, kind: o.kind, x: o.x, y: o.y, z: o.z, yaw: o.yaw, size: o.size, state: clampU16(o.state), text: o.text.slice(0, 60),
        label: o.label ? (o.label[lang] || o.label.en).slice(0, 60) : "", useRadius: o.useRadius, shootRadius: o.shootRadius, codeLength: o.codeLength,
      })),
    };
  }

  private flush(): void {
    if (!this.dirty) return;
    this.dirty = false;
    this.zone.sendEach("puzzleObjects", (lang) => this.message(lang));
  }

  /** The first shootable object along the shot, before whatever stopped it. */
  private shotTarget(pid: number, to: { x: number; y: number; z: number }): number {
    const p = this.world.players.get(pid);
    if (!p) return 0;
    const o0 = { x: p.pos.x, y: this.world.constants.player.eyeHeight, z: p.pos.y };
    const d = { x: to.x - o0.x, y: to.y - o0.y, z: to.z - o0.z };
    const len = Math.hypot(d.x, d.y, d.z);
    if (len < 1e-6) return 0;
    d.x /= len; d.y /= len; d.z /= len;
    let best = 0;
    let bestT = len + 0.3;
    for (const o of this.objects.values()) {
      if (o.shootRadius <= 0) continue;
      const c = { x: o.x - o0.x, y: o.y + o.shootHeight - o0.y, z: o.z - o0.z };
      const t = c.x * d.x + c.y * d.y + c.z * d.z;
      if (t < 0 || t > bestT) continue;
      const miss = Math.hypot(c.x - d.x * t, c.y - d.y * t, c.z - d.z * t);
      if (miss <= o.shootRadius) {
        best = o.id;
        bestT = t;
      }
    }
    return best;
  }

  /** A module error is logged once and switches the puzzles off for this zone. */
  private guard(what: string, fn: () => void): void {
    if (this.failed) return;
    try {
      fn();
    } catch (err) {
      this.failed = true;
      this.instance = null;
      log.warn("puzzle module failed; puzzles off in this zone", { zone: this.zone.id, hook: what, error: (err as Error).message });
    }
  }
}

const clampU16 = (v: number) => Math.max(0, Math.min(0xffff, Math.round(v)));
