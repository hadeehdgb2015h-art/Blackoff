/** Scripted player (mirror of bot_brain.gd) for tests and in-process load bots.
 *  It only produces PlayerIntents, exactly like a human client. */
import { Btn, type PlayerIntent, type SimZombie } from "./entities.js";
import { yawTo } from "./math.js";
import { Rng } from "./rng.js";
import type { SimWorld } from "./simWorld.js";

export class BotBrain {
  aimErrorDeg = 2.0;
  private rng: Rng;
  private seq = 0;
  private fireToggle = false;

  constructor(readonly pid: number, seed = 1) {
    this.rng = new Rng(seed);
  }

  think(w: SimWorld): PlayerIntent {
    const p = w.players.get(this.pid)!;
    this.seq = (this.seq + 1) % 65536;
    const it: PlayerIntent = { seq: this.seq, move: { x: 0, y: 0 }, yaw: p.yaw, pitch: p.pitch, buttons: 0 };
    if (!p.isAlive()) return it;
    const eye = { x: p.pos.x, y: w.constants.player.eyeHeight, z: p.pos.y };
    let target: SimZombie | null = null;
    let best = Infinity;
    for (const z of w.zombies.values()) {
      const d = (p.pos.x - z.pos.x) ** 2 + (p.pos.y - z.pos.y) ** 2;
      if (d >= best) continue;
      const to = { x: z.pos.x - eye.x, y: z.def.headCenterHeight - 0.35 - eye.y, z: z.pos.y - eye.z };
      const l = Math.hypot(to.x, to.y, to.z);
      if (w.map.raycast(eye, { x: to.x / l, y: to.y / l, z: to.z / l }, l) < l - 0.05) continue;
      best = d;
      target = z;
    }
    const wp = p.weapon()!;
    if (target) {
      const err = (this.aimErrorDeg * Math.PI) / 180;
      const to = { x: target.pos.x - eye.x, y: target.def.headCenterHeight - 0.3 - eye.y, z: target.pos.y - eye.z };
      it.yaw = yawTo(p.pos, target.pos) + this.rng.range(-err, err);
      it.pitch = Math.atan2(to.y, Math.hypot(to.x, to.z)) + this.rng.range(-err, err);
      if (wp.mag > 0) {
        if (wp.isAuto()) it.buttons |= Btn.FIRE_HELD;
        else {
          this.fireToggle = !this.fireToggle;
          if (this.fireToggle) it.buttons |= Btn.FIRE_PRESSED;
        }
      }
      if (Math.sqrt(best) < 3.5) it.move = { x: 0, y: -1 };
    }
    if (wp.mag === 0 && wp.reserve > 0 && !p.isReloading()) it.buttons |= Btn.RELOAD;
    if (wp.mag === 0 && wp.reserve === 0 && p.weapons.length > 1) it.buttons |= Btn.SWITCH;
    return it;
  }
}
