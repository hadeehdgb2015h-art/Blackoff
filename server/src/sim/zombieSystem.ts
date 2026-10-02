/** Zombie spawning, pathing, separation, melee and damage/rewards
 *  (mirror of zombie_system.gd). */
import { PlayerState, SimZombie, ZombieState, type SimPlayer } from "./entities.js";
import { type V2, type V3, approachAngle, dist, dist2, len, len2, normalized, rotated, scale, sub, yawTo } from "./math.js";
import type { SimWorld } from "./simWorld.js";
import { WaveDirector } from "./waveDirector.js";

const DIRECT_CHASE_DIST = 10.0;
const REPATH_SEC = 0.8;
const REPATH_GOAL_DRIFT = 1.5;
const TURN_RATE = 8.0;

export class ZombieSystem {
  constructor(private readonly w: SimWorld) {}

  spawn(type: string, wave: number): boolean {
    const w = this.w;
    const entries = w.rng.shuffle([...w.map.zombieEntries]);
    let chosen = null;
    for (let pass = 0; pass < 2 && !chosen; pass++) {
      for (const e of entries) {
        if (this.blocked(e.pos, 0.9)) continue;
        if (pass === 0 && this.nearPlayer(e.pos, 8.0)) continue;
        chosen = e;
        break;
      }
    }
    if (!chosen) return false;
    const def = w.defs.zombies[type]!;
    const z = new SimZombie(w.allocId(), type, def);
    z.pos = { x: chosen.pos.x + w.rng.range(-0.3, 0.3), y: chosen.pos.y + w.rng.range(-0.3, 0.3) };
    z.prevPos = { ...z.pos };
    z.yaw = yawTo(chosen.pos, chosen.inside);
    z.maxHp = WaveDirector.healthFor(def, wave);
    z.hp = z.maxHp;
    z.speed = WaveDirector.speedFor(def, wave) * w.rng.range(0.92, 1.08);
    z.nextRepathTime = w.time + w.rng.range(0, 0.3);
    z.stuckCheckTime = w.time + 1.0;
    z.stuckCheckPos = { ...z.pos };
    w.zombies.set(z.id, z);
    w.emit({ type: "zombie_spawned", zid: z.id, ztype: type, entry: chosen.id });
    return true;
  }

  updateAll(): void {
    const targets = this.w.alivePlayers();
    for (const z of this.w.zombies.values()) {
      z.prevPos = { ...z.pos };
      this.update(z, targets);
    }
    this.separate();
  }

  private update(z: SimZombie, targets: SimPlayer[]): void {
    const w = this.w;
    z.moving = false;
    let target: SimPlayer | null = null;
    let best = Infinity;
    for (const p of targets) {
      const d = dist2(z.pos, p.pos);
      if (d < best) {
        best = d;
        target = p;
      }
    }
    if (!target) {
      z.state = ZombieState.CHASE;
      return;
    }
    z.targetId = target.id;
    const d = Math.sqrt(best);
    const reach = z.def.attackRange + w.constants.player.radius;
    if (z.state === ZombieState.WINDUP) {
      z.yaw = approachAngle(z.yaw, yawTo(z.pos, target.pos), TURN_RATE * w.dt);
      if (w.time >= z.windupEnd) {
        z.state = ZombieState.CHASE;
        z.attackReadyTime = w.time + z.def.attackCooldownSec;
        if (d <= reach + 0.35) w.damagePlayer(target, z.def.attackDamage, z.id);
      }
      return;
    }
    if (d <= reach && w.time >= z.attackReadyTime && w.map.segmentClear(z.pos, target.pos, 0.05)) {
      z.state = ZombieState.WINDUP;
      z.windupEnd = w.time + z.def.attackWindupSec;
      w.emit({ type: "zombie_attack", zid: z.id, pid: target.id });
      return;
    }
    if (d <= reach * 0.85) {
      z.yaw = approachAngle(z.yaw, yawTo(z.pos, target.pos), TURN_RATE * w.dt);
      return;
    }
    const goal = this.steerPoint(z, target.pos, d);
    const toGoal = sub(goal, z.pos);
    if (len2(toGoal) < 0.0001) return;
    const step = scale(normalized(toGoal), Math.min(z.speed * w.dt, len(toGoal) + 0.2));
    z.pos = w.map.moveCircle(z.pos, step, z.radius());
    z.moving = true;
    z.yaw = approachAngle(z.yaw, yawTo(z.prevPos, { x: z.prevPos.x + step.x, y: z.prevPos.y + step.y }), TURN_RATE * w.dt);
    this.checkStuck(z);
  }

  /** Straight at the target when clear, else along the grid path, skipping corners in clear line. */
  private steerPoint(z: SimZombie, target: V2, d: number): V2 {
    const w = this.w;
    if (d < DIRECT_CHASE_DIST && w.map.segmentClear(z.pos, target, z.radius() * 0.9)) {
      z.path = [];
      return target;
    }
    if (z.path.length === 0 || w.time >= z.nextRepathTime || dist(z.pathGoal, target) > REPATH_GOAL_DRIFT) {
      z.path = w.nav.findPath(z.pos, target);
      z.pathIndex = 0;
      z.pathGoal = { ...target };
      z.nextRepathTime = w.time + REPATH_SEC + w.rng.range(0, 0.3);
      if (z.path.length === 0) return target;
    }
    while (z.pathIndex < z.path.length - 1 && dist(z.pos, z.path[z.pathIndex]!) < 0.35) z.pathIndex += 1;
    if (z.pathIndex < z.path.length - 1 && w.map.segmentClear(z.pos, z.path[z.pathIndex + 1]!, z.radius() * 0.9)) z.pathIndex += 1;
    return z.path[z.pathIndex]!;
  }

  private checkStuck(z: SimZombie): void {
    const w = this.w;
    if (w.time < z.stuckCheckTime) return;
    if (dist(z.pos, z.stuckCheckPos) < 0.2) z.path = [];
    z.stuckCheckPos = { ...z.pos };
    z.stuckCheckTime = w.time + 1.0;
  }

  private separate(): void {
    const list = [...this.w.zombies.values()];
    for (let i = 0; i < list.length; i++) {
      const a = list[i]!;
      for (let j = i + 1; j < list.length; j++) {
        const b = list[j]!;
        const minD = a.radius() + b.radius();
        const diff = sub(a.pos, b.pos);
        const d2 = len2(diff);
        if (d2 >= minD * minD) continue;
        const d = Math.sqrt(d2);
        const n = d > 0.0001 ? scale(diff, 1 / d) : rotated({ x: 1, y: 0 }, a.id);
        const push = (minD - d) * 0.5;
        a.pos = this.w.map.resolveCircle({ x: a.pos.x + n.x * push, y: a.pos.y + n.y * push }, a.radius());
        b.pos = this.w.map.resolveCircle({ x: b.pos.x - n.x * push, y: b.pos.y - n.y * push }, b.radius());
      }
    }
  }

  /** Keeps players and zombies from overlapping (zombies push players a little). */
  separateFromPlayers(): void {
    const pr = this.w.constants.player.radius;
    for (const p of this.w.players.values()) {
      if (p.state === PlayerState.DEAD) continue;
      for (const z of this.w.zombies.values()) {
        const minD = pr + z.radius();
        const diff = sub(p.pos, z.pos);
        const d = len(diff);
        if (d >= minD) continue;
        const n = d > 0.0001 ? scale(diff, 1 / d) : { x: 0, y: 1 };
        const push = minD - d;
        p.pos = this.w.map.resolveCircle({ x: p.pos.x + n.x * push * 0.3, y: p.pos.y + n.y * push * 0.3 }, pr);
        z.pos = this.w.map.resolveCircle({ x: z.pos.x - n.x * push * 0.7, y: z.pos.y - n.y * push * 0.7 }, z.radius());
      }
    }
  }

  applyDamage(z: SimZombie, dmg: number, head: boolean, by: SimPlayer, point: V3): void {
    const w = this.w;
    z.hp -= dmg;
    if (w.powerups.isActive("instaKill")) z.hp = 0;
    w.emit({ type: "zombie_hit", zid: z.id, pid: by.id, damage: dmg, head, point });
    if (z.hp > 0) {
      w.addCurrency(by, w.constants.economy.hitReward, "hit");
      return;
    }
    const reward = z.def.killReward + (head ? w.constants.economy.headshotKillBonus : 0);
    by.kills += 1;
    if (head) by.headshots += 1;
    w.addCurrency(by, reward, "kill");
    w.zombies.delete(z.id);
    w.director.killed += 1;
    w.emit({ type: "zombie_killed", zid: z.id, pid: by.id, head, ztype: z.type, pos: { ...z.pos }, yaw: z.yaw });
    w.powerups.onKill(z.pos);
  }

  private blocked(p: V2, r: number): boolean {
    for (const z of this.w.zombies.values()) if (dist(z.pos, p) < r) return true;
    return false;
  }

  private nearPlayer(p: V2, r: number): boolean {
    for (const pl of this.w.players.values()) if (dist(pl.pos, p) < r) return true;
    return false;
  }
}
