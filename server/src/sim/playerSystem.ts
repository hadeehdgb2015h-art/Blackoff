/** Player movement, regen, weapons and interactions (mirror of player_system.gd).
 *  Every check is authoritative. */
import { Btn, WeaponState, type PlayerIntent, type SimPlayer, type SimZombie } from "./entities.js";
import { rayCharacter } from "./hitTest.js";
import { type V3, add, clamp, dir3, dist, dist2, forward, len2, limitLength, right, scale, wrapAngle } from "./math.js";
import type { SimWorld } from "./simWorld.js";

const DEG = Math.PI / 180;

export interface InteractOption {
  id: string;
  kind: string;
  item: string;
  action: string;
  cost: number;
  label: string;
  full: boolean;
  busy?: boolean;
  affordable: boolean;
}

export class PlayerSystem {
  constructor(private readonly w: SimWorld) {}

  private get cp() { return this.w.constants.player; }

  update(p: SimPlayer): void {
    const w = this.w;
    p.prevPos = { ...p.pos };
    const inp = p.input;
    const pressed = inp.buttons & ~p.buttonsPrev;
    p.buttonsPrev = inp.buttons;
    if (!p.isAlive()) {
      p.moving = false;
      return;
    }
    p.yaw = wrapAngle(inp.yaw);
    p.pitch = clamp(inp.pitch, -1.4, 1.4);
    this.move(p, inp);
    this.regen(p);
    if (p.isReloading() && w.time >= p.reloadEnd) {
      p.weapon()!.finishReload();
      p.reloadEnd = 0;
      w.emit({ type: "reload_done", pid: p.id });
    }
    if (pressed & Btn.SWITCH) this.switchWeapon(p);
    if (pressed & Btn.RELOAD) this.startReload(p);
    if (pressed & Btn.INTERACT) this.interact(p);
    this.fire(p, inp, (inp.buttons & Btn.FIRE_PRESSED) !== 0);
  }

  private move(p: SimPlayer, inp: PlayerIntent): void {
    const mv = limitLength(inp.move, 1.0);
    p.moving = len2(mv) > 0.01;
    if (!p.moving) return;
    const dir = add(scale(right(p.yaw), mv.x), scale(forward(p.yaw), mv.y));
    p.pos = this.w.map.moveCircle(p.pos, scale(dir, this.cp.moveSpeed * this.w.dt), this.cp.radius);
  }

  private regen(p: SimPlayer): void {
    if (p.hp < p.maxHp && this.w.time - p.lastDamageTime >= this.cp.healthRegenDelaySec) {
      p.hp = Math.min(p.maxHp, p.hp + this.cp.healthRegenPerSec * this.w.dt);
    }
  }

  private switchWeapon(p: SimPlayer): void {
    if (p.weapons.length < 2) return;
    p.slot = (p.slot + 1) % p.weapons.length;
    p.reloadEnd = 0;
    p.switchEnd = this.w.time + this.cp.weaponSwitchSec;
    this.w.emit({ type: "weapon_switched", pid: p.id, weapon: p.weapon()!.id });
  }

  private startReload(p: SimPlayer): boolean {
    const wp = p.weapon();
    if (!wp || p.isReloading() || this.w.time < p.switchEnd || !wp.canReload()) return false;
    p.reloadEnd = this.w.time + wp.def.reloadSec;
    this.w.emit({ type: "reload_started", pid: p.id, duration: wp.def.reloadSec });
    return true;
  }

  private fire(p: SimPlayer, inp: PlayerIntent, pressed: boolean): void {
    const w = this.w;
    const wp = p.weapon();
    if (!wp) return;
    const held = (inp.buttons & Btn.FIRE_HELD) !== 0 || pressed;
    if (!held || p.isReloading() || w.time < p.switchEnd) return;
    if (wp.mag <= 0) {
      if (!this.startReload(p) && pressed) w.emit({ type: "dry_fire", pid: p.id });
      return;
    }
    if (!wp.isAuto() && !pressed) return;
    // Shots are scheduled inside this tick's window so fire rate is exact at any
    // tick rate; idle time never banks extra shots.
    let t = Math.max(p.nextFireTime, w.time - w.dt);
    let shots = 0;
    while (t <= w.time && wp.mag > 0 && shots < 3) {
      this.shoot(p, wp, inp);
      shots += 1;
      t += wp.interval();
      if (!wp.isAuto()) break;
    }
    if (shots > 0) p.nextFireTime = t;
  }

  private shoot(p: SimPlayer, wp: WeaponState, inp: PlayerIntent): void {
    const w = this.w;
    wp.mag -= 1;
    p.shotsFired += 1;
    const spread = (p.moving ? wp.def.moveSpreadDeg : wp.def.spreadDeg) * DEG;
    const origin: V3 = { x: p.pos.x, y: this.cp.eyeHeight, z: p.pos.y };
    const rngMax = wp.def.range;
    const pellets = Math.max(1, wp.def.pellets);
    const ends: V3[] = [];
    const hits = new Map<number, { z: SimZombie; dmg: number; head: boolean; point: V3 }>();
    let anyWall = false;
    for (let i = 0; i < pellets; i++) {
      const ang = w.rng.randf() * spread;
      const az = w.rng.randf() * Math.PI * 2;
      const yaw = inp.yaw + Math.cos(az) * ang;
      const pitch = clamp(inp.pitch + Math.sin(az) * ang, -1.5, 1.5);
      const dir = dir3(yaw, pitch);
      let bestT = w.map.raycast(origin, dir, rngMax);
      const hitWall = bestT < rngMax;
      let target: SimZombie | null = null;
      let head = false;
      for (const z of w.zombies.values()) {
        if (dist2(z.pos, p.pos) > (rngMax + 1) * (rngMax + 1)) continue;
        const h = rayCharacter(origin, dir, z.pos, z.radius(), z.def.headCenterHeight, z.def.headRadius);
        if (h && h.t < bestT) {
          bestT = h.t;
          target = z;
          head = h.head;
        }
      }
      const end = { x: origin.x + dir.x * bestT, y: origin.y + dir.y * bestT, z: origin.z + dir.z * bestT };
      ends.push(end);
      if (target) {
        const dmg = wp.def.damage * (head ? wp.def.headMultiplier : 1);
        let h = hits.get(target.id);
        if (!h) hits.set(target.id, (h = { z: target, dmg: 0, head: false, point: end }));
        h.dmg += dmg;
        h.head = h.head || head;
      } else if (hitWall) {
        anyWall = true;
      }
    }
    w.emit({ type: "shot", pid: p.id, weapon: wp.id, from: origin, to: ends[0], ends,
      hit: hits.size > 0 ? "zombie" : anyWall ? "wall" : "none" });
    // One damage application per zombie per trigger pull (pellets are summed).
    for (const h of hits.values()) {
      if (w.zombies.has(h.z.id)) w.zombieSys.applyDamage(h.z, h.dmg, h.head, p, h.point);
    }
  }

  /** Gives a weapon: refills it if owned, fills a free slot, else replaces the held one. */
  giveWeapon(p: SimPlayer, id: string): void {
    const owned = p.findWeapon(id);
    if (owned >= 0) {
      const ow = p.weapons[owned]!;
      ow.mag = ow.def.magSize;
      ow.reserve = ow.def.reserveMax;
      p.slot = owned;
    } else {
      const ws = new WeaponState(id, this.w.defs.weapons[id]!);
      if (p.weapons.length < this.cp.maxWeaponSlots) {
        p.weapons.push(ws);
        p.slot = p.weapons.length - 1;
      } else {
        p.weapons[p.slot] = ws;
      }
    }
    p.reloadEnd = 0;
    p.switchEnd = this.w.time + this.cp.weaponSwitchSec;
  }

  interactOption(p: SimPlayer): InteractOption | null {
    const w = this.w;
    if (!p.isAlive()) return null;
    let best = null;
    let bestD = Infinity;
    for (const it of w.map.interactables) {
      const d = dist(p.pos, it.pos);
      if (d <= Math.min(it.radius, this.cp.interactRange + 0.5) && d < bestD) {
        best = it;
        bestD = d;
      }
    }
    if (!best) return null;
    let opt: Omit<InteractOption, "affordable">;
    if (best.kind === "box") {
      opt = { id: best.id, kind: best.kind, item: best.item, ...w.boxSys.option(w.boxSys.boxes.get(best.id)!, p) };
    } else if (best.kind === "weapon") {
      const def = w.defs.weapons[best.item]!;
      const owned = p.findWeapon(best.item);
      opt = owned >= 0
        ? { id: best.id, kind: best.kind, item: best.item, action: "ammo", cost: def.ammoPrice, label: "Ammo: " + def.displayName,
          full: p.weapons[owned]!.reserve >= def.reserveMax }
        : { id: best.id, kind: best.kind, item: best.item, action: "weapon", cost: def.price, label: def.displayName, full: false };
    } else {
      const wp = p.weapon()!;
      opt = { id: best.id, kind: best.kind, item: wp.id, action: "ammo", cost: wp.def.ammoPrice, label: "Ammo: " + wp.def.displayName,
        full: wp.reserve >= wp.def.reserveMax };
    }
    return { ...opt, affordable: p.currency >= opt.cost && !opt.busy };
  }

  private interact(p: SimPlayer): void {
    const w = this.w;
    const opt = this.interactOption(p);
    if (!opt) return;
    if (opt.full) {
      w.emit({ type: "purchase_denied", pid: p.id, reason: "full" });
      return;
    }
    if (opt.busy) return;
    if (!opt.affordable) {
      w.emit({ type: "purchase_denied", pid: p.id, reason: "funds" });
      return;
    }
    if (opt.action === "box") {
      if (!w.boxSys.open(w.boxSys.boxes.get(opt.id)!, p)) w.emit({ type: "purchase_denied", pid: p.id, reason: "full" });
      return;
    }
    if (opt.action === "take") {
      w.boxSys.take(w.boxSys.boxes.get(opt.id)!, p);
      return;
    }
    if (opt.action === "weapon") {
      this.giveWeapon(p, opt.item);
    } else {
      const wp = p.weapons[p.findWeapon(opt.item)]!;
      wp.reserve = wp.def.reserveMax;
    }
    w.addCurrency(p, -opt.cost, "purchase");
    w.emit({ type: "purchase", pid: p.id, action: opt.action, item: opt.item, cost: opt.cost });
  }
}
