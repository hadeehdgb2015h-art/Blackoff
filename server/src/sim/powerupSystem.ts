/** Power-up drops (mirror of powerup_system.gd): a killed zombie may leave a
 *  pickup; any alive player walking over it applies it to the whole zone.
 *  Timed ones (insta-kill, double points, fire sale) keep an end time; the
 *  others act at once (max ammo, nuke). Rolls use the world RNG. */
import { PlayerState } from "./entities.js";
import { dist, type V2 } from "./math.js";
import type { SimWorld } from "./simWorld.js";

export class Powerup {
  constructor(readonly id: number, readonly type: string, readonly pos: V2, readonly until: number) {}
}

export class PowerupSystem {
  readonly drops = new Map<number, Powerup>();
  /** type -> end time of an active timed power-up */
  readonly active = new Map<string, number>();
  readonly types: string[];
  private lastDropTime = -1e9;

  constructor(private readonly w: SimWorld) {
    this.types = Object.keys(w.constants.powerups.types).sort();
  }

  private get cfg() { return this.w.constants.powerups; }

  isActive(type: string): boolean {
    const until = this.active.get(type);
    return until !== undefined && this.w.time < until;
  }

  /** Whole seconds left of a timed power-up (0 when off). */
  secondsLeft(type: string): number {
    const until = this.active.get(type);
    return until === undefined ? 0 : Math.max(0, Math.ceil(until - this.w.time));
  }

  /** Called on every zombie kill; may drop a pickup at the death position. */
  onKill(pos: V2): void {
    const w = this.w;
    const c = this.cfg;
    if (this.drops.size >= c.maxOnGround || w.time - this.lastDropTime < c.minSecondsBetween) return;
    if (w.rng.randf() >= c.dropChance) return;
    const type = this.pick();
    if (!type) return;
    this.lastDropTime = w.time;
    const until = w.time + c.lifetimeSec;
    const d = new Powerup(w.allocId(), type, { ...pos }, until);
    this.drops.set(d.id, d);
    w.emit({ type: "powerup_dropped", id: d.id, ptype: type, pos: { ...pos }, until });
  }

  private pick(): string {
    let total = 0;
    for (const t of this.types) total += this.cfg.types[t]!.weight;
    if (total <= 0) return "";
    let r = this.w.rng.randf() * total;
    for (const t of this.types) {
      r -= this.cfg.types[t]!.weight;
      if (r < 0) return t;
    }
    return this.types[this.types.length - 1]!;
  }

  update(): void {
    const w = this.w;
    for (const d of [...this.drops.values()]) {
      if (w.time >= d.until) {
        this.drops.delete(d.id);
        w.emit({ type: "powerup_expired", id: d.id });
        continue;
      }
      for (const p of w.players.values()) {
        if (p.state !== PlayerState.ALIVE || dist(p.pos, d.pos) > this.cfg.pickupRadius) continue;
        this.drops.delete(d.id);
        this.apply(d.type, p.id);
        break;
      }
    }
    for (const [t, until] of this.active) if (w.time >= until) this.active.delete(t);
  }

  private apply(type: string, pid: number): void {
    const w = this.w;
    const def = this.cfg.types[type]!;
    w.emit({ type: "powerup_taken", pid, ptype: type });
    if (def.durationSec > 0) this.active.set(type, w.time + def.durationSec);
    if (type === "maxAmmo") {
      for (const p of w.players.values()) {
        for (const wp of p.weapons) {
          wp.mag = wp.def.magSize;
          wp.reserve = wp.def.reserveMax;
        }
        if (p.isReloading()) p.reloadEnd = 0;
      }
    } else if (type === "nuke") {
      for (const z of [...w.zombies.values()]) {
        w.zombies.delete(z.id);
        w.director.killed += 1;
        w.emit({ type: "zombie_killed", zid: z.id, pid: 0, head: false, ztype: z.type, pos: { ...z.pos }, yaw: z.yaw });
      }
      for (const p of w.players.values()) if (p.isAlive()) w.addCurrency(p, def.reward ?? 0, "nuke");
    }
  }
}
