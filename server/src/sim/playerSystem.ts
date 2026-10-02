/** Player movement, regen, weapons, interactions and reviving downed teammates
 *  (mirror of player_system.gd). Every check is authoritative. */
import { Btn, PlayerState, Team, WeaponState, type PlayerIntent, type SimPlayer, type SimZombie } from "./entities.js";
import { rayCharacter } from "./hitTest.js";
import { type V3, add, clamp, dir3, dist, dist2, forward, len2, limitLength, right, scale, wrapAngle, yawTo } from "./math.js";
import type { SimWorld } from "./simWorld.js";

const DEG = Math.PI / 180;

export interface InteractOption {
  id: string;
  kind: string;
  item: string;
  action: "weapon" | "ammo" | "box" | "wait" | "take" | "revive" | "perk";
  cost: number;
  label: string;
  full: boolean;
  busy?: boolean;
  affordable: boolean;
  target?: number;
}

export class PlayerSystem {
  constructor(private readonly w: SimWorld) {}

  private get cp() { return this.w.constants.player; }

  /** Product of a perk multiplier over the player's perks (1 without perks). */
  perkMul(p: SimPlayer, key: "maxHealthMul" | "reloadMul" | "moveSpeedMul" | "switchMul"): number {
    let m = 1;
    for (const id of p.perks) m *= this.w.defs.perks[id]?.[key] ?? 1;
    return m;
  }

  private givePerk(p: SimPlayer, id: string): void {
    p.perks.push(id);
    const max = this.cp.maxHealth * this.perkMul(p, "maxHealthMul");
    p.hp += max - p.maxHp; // more health: the extra is granted at once
    p.maxHp = max;
  }

  clearPerks(p: SimPlayer): void {
    p.perks = [];
    p.maxHp = this.cp.maxHealth;
    p.hp = Math.min(p.hp, p.maxHp);
  }

  update(p: SimPlayer): void {
    const w = this.w;
    p.prevPos = { ...p.pos };
    const inp = p.input;
    const pressed = inp.buttons & ~p.buttonsPrev;
    p.buttonsPrev = inp.buttons;
    if (!p.isAlive()) {
      p.moving = false;
      p.reviveTarget = 0;
      p.reviveTicks = 0;
      return;
    }
    p.yaw = wrapAngle(inp.yaw);
    p.pitch = clamp(inp.pitch, -1.4, 1.4);
    const reviving = this.revive(p, inp);
    if (reviving) p.moving = false;
    else this.move(p, inp);
    this.regen(p);
    if (p.isReloading() && w.time >= p.reloadEnd) {
      p.weapon()!.finishReload();
      p.reloadEnd = 0;
      w.emit({ type: "reload_done", pid: p.id });
    }
    if (reviving) return; // hands are busy: no switching, reloading, buying or firing
    if (p.team === Team.ZOMBIE && w.infection) {
      w.infection.melee(p, inp, (inp.buttons & Btn.FIRE_PRESSED) !== 0); // infected: claws only
      return;
    }
    if (pressed & Btn.SWITCH) this.switchWeapon(p);
    if (pressed & Btn.RELOAD) this.startReload(p);
    if (pressed & Btn.INTERACT) this.interact(p);
    this.fire(p, inp, (inp.buttons & Btn.FIRE_PRESSED) !== 0);
  }

  /** Nearest downed teammate within reviveRange, or null. */
  reviveCandidate(p: SimPlayer): SimPlayer | null {
    let best: SimPlayer | null = null;
    let bestD = this.cp.reviveRange;
    for (const o of this.w.players.values()) {
      if (o === p || o.state !== PlayerState.DOWNED) continue;
      const d = dist(p.pos, o.pos);
      if (d <= bestD) {
        best = o;
        bestD = d;
      }
    }
    return best;
  }

  /** Ticks a revive needs (counted in ticks so both sims finish on the same tick). */
  reviveTicksNeeded(): number {
    return Math.round(this.cp.reviveTimeSec / this.w.dt);
  }

  /** Holding REVIVE next to a downed teammate revives them after reviveTimeSec.
   *  Returns true while reviving (the reviver stands still and cannot shoot). */
  private revive(p: SimPlayer, inp: PlayerIntent): boolean {
    const t = inp.buttons & Btn.REVIVE ? this.reviveCandidate(p) : null;
    if (!t) {
      p.reviveTarget = 0;
      p.reviveTicks = 0;
      return false;
    }
    if (p.reviveTarget !== t.id) {
      p.reviveTarget = t.id;
      p.reviveTicks = 0;
    }
    p.reviveTicks += 1;
    if (p.reviveTicks >= this.reviveTicksNeeded()) {
      t.state = PlayerState.ALIVE;
      t.hp = t.maxHp * 0.5;
      t.lastDamageTime = this.w.time;
      p.revives += 1;
      p.reviveTarget = 0;
      p.reviveTicks = 0;
      this.w.addCurrency(p, this.w.constants.economy.reviveReward, "revive");
      this.w.emit({ type: "player_revived", pid: t.id, by: p.id });
    }
    return true;
  }

  private move(p: SimPlayer, inp: PlayerIntent): void {
    const mv = limitLength(inp.move, 1.0);
    p.moving = len2(mv) > 0.01;
    if (!p.moving) return;
    const dir = add(scale(right(p.yaw), mv.x), scale(forward(p.yaw), mv.y));
    const teamMul = p.team === Team.ZOMBIE ? this.w.constants.infection.zombieSpeedMul : 1;
    p.pos = this.w.map.moveCircle(p.pos, scale(dir, this.cp.moveSpeed * this.perkMul(p, "moveSpeedMul") * teamMul * this.w.dt), this.cp.radius);
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
    p.switchEnd = this.w.time + this.cp.weaponSwitchSec * this.perkMul(p, "switchMul");
    this.w.emit({ type: "weapon_switched", pid: p.id, weapon: p.weapon()!.id });
  }

  private startReload(p: SimPlayer): boolean {
    const wp = p.weapon();
    if (!wp || p.isReloading() || this.w.time < p.switchEnd || !wp.canReload()) return false;
    const duration = wp.def.reloadSec * this.perkMul(p, "reloadMul");
    p.reloadEnd = this.w.time + duration;
    this.w.emit({ type: "reload_started", pid: p.id, duration });
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
    const origin: V3 = { x: p.pos.x, y: this.cp.eyeHeight, z: p.pos.y };
    if (wp.def.coneDeg > 0) return this.shootCone(p, wp, inp, origin);
    const spread = (p.moving ? wp.def.moveSpreadDeg : wp.def.spreadDeg) * DEG;
    const rngMax = wp.def.range;
    const pellets = Math.max(1, wp.def.pellets);
    const ends: V3[] = [];
    const hits = new Map<number, { z: SimZombie; dmg: number; head: boolean; point: V3 }>();
    const phits = new Map<number, { z: SimPlayer; dmg: number; head: boolean; point: V3 }>();
    const infected = this.infectedTargets(p);
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
      let ptarget: SimPlayer | null = null;
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
      for (const o of infected) {
        const h = rayCharacter(origin, dir, o.pos, this.cp.radius, this.cp.headCenterHeight, this.cp.headRadius);
        if (h && h.t < bestT) {
          bestT = h.t;
          target = null;
          ptarget = o;
          head = h.head;
        }
      }
      const end = { x: origin.x + dir.x * bestT, y: origin.y + dir.y * bestT, z: origin.z + dir.z * bestT };
      ends.push(end);
      if (target || ptarget) {
        const dmg = wp.def.damage * (head ? wp.def.headMultiplier : 1);
        if (ptarget) {
          let h = phits.get(ptarget.id);
          if (!h) phits.set(ptarget.id, (h = { z: ptarget, dmg: 0, head: false, point: end }));
          h.dmg += dmg;
          h.head = h.head || head;
        } else {
          let h = hits.get(target!.id);
          if (!h) hits.set(target!.id, (h = { z: target!, dmg: 0, head: false, point: end }));
          h.dmg += dmg;
          h.head = h.head || head;
        }
      } else if (hitWall) {
        anyWall = true;
      }
    }
    w.emit({ type: "shot", pid: p.id, weapon: wp.id, from: origin, to: ends[0], ends,
      hit: hits.size > 0 || phits.size > 0 ? "zombie" : anyWall ? "wall" : "none" });
    // Energy weapons: area damage around the first pellet's end point, hitting
    // every other zombie in range (the direct target takes the direct damage).
    if (wp.def.splashRadius > 0) {
      const end = ends[0]!;
      const r2 = wp.def.splashRadius * wp.def.splashRadius;
      for (const z of w.zombies.values()) {
        if (hits.has(z.id)) continue;
        if ((z.pos.x - end.x) ** 2 + (z.pos.y - end.z) ** 2 > r2) continue;
        hits.set(z.id, { z, dmg: wp.def.splashDamage, head: false, point: { x: z.pos.x, y: 1.2, z: z.pos.y } });
      }
      for (const o of infected) {
        if (phits.has(o.id)) continue;
        if ((o.pos.x - end.x) ** 2 + (o.pos.y - end.z) ** 2 > r2) continue;
        phits.set(o.id, { z: o, dmg: wp.def.splashDamage, head: false, point: { x: o.pos.x, y: 1.2, z: o.pos.y } });
      }
    }
    // One damage application per zombie per trigger pull (pellets are summed).
    for (const h of hits.values()) {
      if (w.zombies.has(h.z.id)) w.zombieSys.applyDamage(h.z, h.dmg, h.head, p, h.point);
    }
    for (const h of phits.values()) {
      if (h.z.isAlive()) w.infection!.hitZombie(h.z, h.dmg, h.head, p, h.point);
    }
  }

  /** Infection mode: living infected players, the soldiers' targets. */
  private infectedTargets(p: SimPlayer): SimPlayer[] {
    if (!this.w.infection) return [];
    return [...this.w.players.values()].filter((o) => o !== p && o.team === Team.ZOMBIE && o.isAlive());
  }

  /** Wind weapons: a blast that hits every zombie inside a cone in front of
   *  the player (within range, inside coneDeg, not behind a wall). */
  private shootCone(p: SimPlayer, wp: WeaponState, inp: PlayerIntent, origin: V3): void {
    const w = this.w;
    const half = (wp.def.coneDeg / 2) * DEG;
    const range = wp.def.range;
    const dir = dir3(inp.yaw, 0);
    const victims: SimZombie[] = [];
    const pvictims: SimPlayer[] = [];
    const inCone = (pos: { x: number; y: number }): boolean => {
      if (dist(pos, p.pos) > range) return false;
      if (Math.abs(wrapAngle(yawTo(p.pos, pos) - inp.yaw)) > half) return false;
      return w.map.segmentClear(p.pos, pos, 0.05);
    };
    for (const z of w.zombies.values()) if (inCone(z.pos)) victims.push(z);
    for (const o of this.infectedTargets(p)) if (inCone(o.pos)) pvictims.push(o);
    const to = { x: origin.x + dir.x * range, y: origin.y, z: origin.z + dir.z * range };
    w.emit({ type: "shot", pid: p.id, weapon: wp.id, from: origin, to, ends: [to], hit: victims.length || pvictims.length ? "zombie" : "none" });
    for (const z of victims) {
      if (w.zombies.has(z.id)) w.zombieSys.applyDamage(z, wp.def.damage, false, p, { x: z.pos.x, y: 1.2, z: z.pos.y });
    }
    for (const o of pvictims) {
      if (o.isAlive()) w.infection!.hitZombie(o, wp.def.damage, false, p, { x: o.pos.x, y: 1.2, z: o.pos.y });
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
    const downed = this.reviveCandidate(p);
    if (downed) {
      return { id: "revive", kind: "revive", item: "", action: "revive", cost: 0, label: "Hold to revive " + downed.name,
        full: false, affordable: true, target: downed.id };
    }
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
    } else if (best.kind === "perk") {
      const def = w.defs.perks[best.item!]!;
      opt = { id: best.id, kind: best.kind, item: best.item!, action: "perk", cost: def.price, label: def.displayName,
        full: p.perks.includes(best.item!) };
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
    if (!opt || opt.action === "revive") return;
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
    } else if (opt.action === "perk") {
      this.givePerk(p, opt.item);
    } else {
      const wp = p.weapons[p.findWeapon(opt.item)]!;
      wp.reserve = wp.def.reserveMax;
    }
    w.addCurrency(p, -opt.cost, "purchase");
    w.emit({ type: "purchase", pid: p.id, action: opt.action, item: opt.item, cost: opt.cost });
  }
}
