/**
 * An AI soldier filling an online squad (phase 30). Like a human client it only
 * produces PlayerIntents; the simulation applies the same rules to it.
 *
 * Each tick, in order of priority:
 * - revive a downed teammate in reach (walking to one nearby when no zombie is close);
 * - back away from a zombie that is too close;
 * - keep near the nearest human (walking the nav grid when far);
 * - turn towards the nearest visible zombie at a human turn rate, with a short
 *   reaction time and some aim error, and shoot once on target.
 * Bots are deliberately a little worse than a good player: they help, the
 * human still does most of the work.
 */
import { Btn, PlayerState, type PlayerIntent, type SimPlayer, type SimZombie } from "./entities.js";
import { forward, right, yawTo, type V2 } from "./math.js";
import { Rng } from "./rng.js";
import type { SimWorld } from "./simWorld.js";

export interface SquadBotDefs { aimErrorDeg: number; reactionSec: number; turnDegPerSec: number; followDistance: number }

const TARGET_RANGE = 26;
const BACK_OFF = 2.6;
const REVIVE_SEEK = 14;
const WAYPOINT_REACHED = 0.6;
const PATH_EVERY = 1.0;

export class SquadBot {
  private readonly rng: Rng;
  private seq = 0;
  private fireToggle = false;
  private target = 0;
  private targetSince = 0;
  private nextScan = 0;
  private path: V2[] = [];
  private pathGoal: V2 | null = null;
  private pathAt = -99;
  private yaw: number | null = null;
  private pitch = 0;
  private errYaw = 0;
  private errPitch = 0;

  constructor(readonly pid: number, seed: number, private readonly d: SquadBotDefs) {
    this.rng = new Rng(seed);
  }

  think(w: SimWorld): PlayerIntent {
    const p = w.players.get(this.pid)!;
    this.seq = (this.seq + 1) % 65536;
    if (this.yaw === null) this.yaw = p.yaw;
    const it: PlayerIntent = { seq: this.seq, move: { x: 0, y: 0 }, yaw: this.yaw, pitch: this.pitch, buttons: 0 };
    if (!p.isAlive()) {
      this.path = [];
      return it;
    }
    const eye = { x: p.pos.x, y: w.constants.player.eyeHeight, z: p.pos.y };

    // what to shoot: the nearest zombie in sight, rescanned a few times a second
    if (w.time >= this.nextScan) {
      this.nextScan = w.time + 0.25;
      const z = this.pickTarget(w, p, eye);
      const id = z?.id ?? 0;
      if (id !== this.target) {
        this.target = id;
        this.targetSince = w.time;
        const err = (this.d.aimErrorDeg * Math.PI) / 180;
        this.errYaw = this.rng.range(-err, err);
        this.errPitch = this.rng.range(-err, err) * 0.6;
      }
    }
    const target = this.target ? w.zombies.get(this.target) ?? null : null;
    const nearest = this.nearestZombie(w, p);

    // where to go
    let goal: V2 | null = null;
    let stopAt = 0;
    const downed = this.downedTeammate(w, p);
    // revive when no zombie is on top of us, or whatever happens when time runs out
    const urgent = downed && w.bleedoutLeft(downed) < 12;
    const reviving = p.reviveTarget !== 0;
    if (downed && (!nearest || nearest.d > (reviving ? 1.2 : 2.2) || urgent)) {
      if (w.playerSys.reviveCandidate(p)) {
        it.buttons |= Btn.REVIVE;
      } else {
        goal = downed.pos;
        stopAt = 0.8;
      }
    } else if (nearest && nearest.d < BACK_OFF) {
      // step away from the zombie (the walls slide us along)
      const away = { x: p.pos.x - nearest.z.pos.x, y: p.pos.y - nearest.z.pos.y };
      this.steer(it, p, away);
    } else {
      const lead = this.leader(w, p);
      if (lead && dist(p.pos, lead.pos) > this.d.followDistance) {
        goal = lead.pos;
        stopAt = this.d.followDistance * 0.6;
      }
    }
    if (goal) this.walkTo(w, p, it, goal, stopAt);

    // aim: turn towards the target (or the way we walk) at a human rate
    let wantYaw = this.yaw;
    let wantPitch = 0;
    if (target) {
      const to = { x: target.pos.x - eye.x, y: target.def.headCenterHeight - 0.35 - eye.y, z: target.pos.y - eye.z };
      wantYaw = yawTo(p.pos, target.pos) + this.errYaw;
      wantPitch = Math.atan2(to.y, Math.hypot(to.x, to.z)) + this.errPitch;
    } else if (it.move.x !== 0 || it.move.y !== 0) {
      const dir = { x: right(this.yaw).x * it.move.x + forward(this.yaw).x * it.move.y, y: right(this.yaw).y * it.move.x + forward(this.yaw).y * it.move.y };
      wantYaw = Math.atan2(-dir.x, -dir.y);
    }
    const maxTurn = ((this.d.turnDegPerSec * Math.PI) / 180) * w.dt;
    const dy = wrap(wantYaw - this.yaw);
    const oldYaw = this.yaw;
    this.yaw = wrap(this.yaw + clamp(dy, -maxTurn, maxTurn));
    this.pitch += clamp(wantPitch - this.pitch, -maxTurn, maxTurn);
    it.yaw = this.yaw;
    it.pitch = this.pitch;
    // the move was worked out for the old facing: keep its world direction
    if (it.move.x !== 0 || it.move.y !== 0) {
      const world = { x: right(oldYaw).x * it.move.x + forward(oldYaw).x * it.move.y, y: right(oldYaw).y * it.move.x + forward(oldYaw).y * it.move.y };
      this.steer(it, p, world, this.yaw);
    }

    const wp = p.weapon();
    if (!wp) return it;
    const onTarget = target && Math.abs(wrap(wantYaw - this.yaw)) < 0.12 && w.time - this.targetSince >= this.d.reactionSec;
    if (onTarget && wp.mag > 0 && !(it.buttons & Btn.REVIVE)) {
      if (wp.isAuto()) it.buttons |= Btn.FIRE_HELD;
      else {
        this.fireToggle = !this.fireToggle;
        if (this.fireToggle) it.buttons |= Btn.FIRE_PRESSED;
      }
    }
    if (wp.mag === 0 && wp.reserve > 0 && !p.isReloading()) it.buttons |= Btn.RELOAD;
    if (!target && wp.mag < wp.def.magSize * 0.4 && wp.reserve > 0 && !p.isReloading()) it.buttons |= Btn.RELOAD;
    return it;
  }

  private pickTarget(w: SimWorld, p: SimPlayer, eye: { x: number; y: number; z: number }): SimZombie | null {
    let best: SimZombie | null = null;
    let bestD = TARGET_RANGE * TARGET_RANGE;
    for (const z of w.zombies.values()) {
      const d2 = (p.pos.x - z.pos.x) ** 2 + (p.pos.y - z.pos.y) ** 2;
      if (d2 >= bestD) continue;
      const to = { x: z.pos.x - eye.x, y: z.def.headCenterHeight - 0.35 - eye.y, z: z.pos.y - eye.z };
      const l = Math.hypot(to.x, to.y, to.z);
      if (w.map.raycast(eye, { x: to.x / l, y: to.y / l, z: to.z / l }, l) < l - 0.05) continue;
      best = z;
      bestD = d2;
    }
    return best;
  }

  private nearestZombie(w: SimWorld, p: SimPlayer): { z: SimZombie; d: number } | null {
    let best: { z: SimZombie; d: number } | null = null;
    for (const z of w.zombies.values()) {
      const d = dist(p.pos, z.pos);
      if (!best || d < best.d) best = { z, d };
    }
    return best;
  }

  /** The nearest human soldier who is still up (else any player). */
  private leader(w: SimWorld, p: SimPlayer): SimPlayer | null {
    let best: SimPlayer | null = null;
    let bestD = Infinity;
    for (const o of w.players.values()) {
      if (o === p || o.bot || o.state === PlayerState.DEAD) continue;
      const d = dist(p.pos, o.pos);
      if (d < bestD) {
        best = o;
        bestD = d;
      }
    }
    return best;
  }

  private downedTeammate(w: SimWorld, p: SimPlayer): SimPlayer | null {
    let best: SimPlayer | null = null;
    let bestD = REVIVE_SEEK;
    for (const o of w.players.values()) {
      if (o === p || o.state !== PlayerState.DOWNED) continue;
      const d = dist(p.pos, o.pos);
      if (d < bestD && !w.reviverOf(o)) {
        best = o;
        bestD = d;
      }
    }
    return best ?? (w.playerSys.reviveCandidate(p) ?? null);
  }

  /** Walks the nav grid towards `goal`, stopping `stopAt` metres short. */
  private walkTo(w: SimWorld, p: SimPlayer, it: PlayerIntent, goal: V2, stopAt: number): void {
    if (dist(p.pos, goal) <= stopAt) {
      this.path = [];
      return;
    }
    const moved = !this.pathGoal || dist(this.pathGoal, goal) > 2;
    if (this.path.length === 0 || moved || w.time - this.pathAt > PATH_EVERY) {
      this.path = w.nav.findPath(p.pos, goal);
      this.pathGoal = { ...goal };
      this.pathAt = w.time;
    }
    while (this.path.length > 1 && dist(p.pos, this.path[0]!) < WAYPOINT_REACHED) this.path.shift();
    const next = this.path[0] ?? goal;
    this.steer(it, p, { x: next.x - p.pos.x, y: next.y - p.pos.y });
  }

  /** Sets the move so the player walks along the world direction `dir`. */
  private steer(it: PlayerIntent, _p: SimPlayer, dir: V2, yaw = this.yaw ?? 0): void {
    const l = Math.hypot(dir.x, dir.y);
    if (l < 1e-6) return;
    const d = { x: dir.x / l, y: dir.y / l };
    const r = right(yaw);
    const f = forward(yaw);
    it.move = { x: d.x * r.x + d.y * r.y, y: d.x * f.x + d.y * f.y };
  }
}

const dist = (a: V2, b: V2) => Math.hypot(a.x - b.x, a.y - b.y);
const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
const wrap = (a: number) => Math.atan2(Math.sin(a), Math.cos(a));

/** Call-signs for AI soldiers. */
export const BOT_NAMES = ["Raven", "Ghost", "Viper", "Falcon", "Wolf", "Hawk", "Cobra", "Shadow", "Titan", "Sparrow"];
