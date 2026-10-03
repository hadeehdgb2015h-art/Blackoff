/**
 * The owner's in-game powers (phase 20): the DEV panel in the game sends
 * `dev {cmd, arg}`; the server applies it only for ADMIN_TELEGRAM_IDS
 * accounts (Session.onDev), in classic zombie games.
 */
import { PlayerState, type SimPlayer } from "../sim/entities.js";
import { Phase, WaveDirector } from "../sim/waveDirector.js";
import type { SimWorld } from "../sim/simWorld.js";

export enum DevCmd { GOD = 1, AMMO = 2, MONEY = 3, SKIP_WAVE = 4, SPAWN_BOSS = 5, KILL_ALL = 6, GOTO_WAVE = 7, HEAL = 8 }

/** Removes every zombie at once (no rewards), as the nuke does. */
function clearZombies(w: SimWorld): void {
  for (const z of [...w.zombies.values()]) {
    w.zombies.delete(z.id);
    w.director.killed += 1;
    w.emit({ type: "zombie_killed", zid: z.id, pid: 0, head: false, ztype: z.type, pos: { ...z.pos }, yaw: z.yaw });
  }
}

/** Applies one command; returns what it did (logged). */
export function applyDev(w: SimWorld, p: SimPlayer, cmd: number, arg: number): string {
  const d = w.director;
  switch (cmd) {
    case DevCmd.GOD:
      p.god = !p.god;
      return p.god ? "god on" : "god off";
    case DevCmd.AMMO:
      p.infiniteAmmo = !p.infiniteAmmo;
      return p.infiniteAmmo ? "ammo on" : "ammo off";
    case DevCmd.MONEY:
      w.addCurrency(p, Math.min(Math.max(arg, 1), 60000), "dev");
      return "money";
    case DevCmd.SKIP_WAVE:
      clearZombies(w);
      if (d.phase === Phase.WAVE) {
        d.spawned = d.toSpawn; // the wave clears on the next tick
        d.bossLeft = 0;
      } else {
        d.phaseEnd = w.time;
      }
      return "skip wave";
    case DevCmd.SPAWN_BOSS: {
      const b = w.defs.waves.boss;
      if (!w.zombieSys.spawn(b.type, Math.max(1, d.wave), WaveDirector.bossHealthMul(w.defs.waves, w.players.size))) return "no room for a boss";
      if (d.phase === Phase.WAVE) {
        d.toSpawn += 1;
        d.spawned += 1;
      }
      return "boss";
    }
    case DevCmd.KILL_ALL:
      clearZombies(w);
      return "kill all";
    case DevCmd.GOTO_WAVE:
      clearZombies(w);
      d.wave = Math.min(Math.max(arg, 1), 999) - 1;
      d.phase = Phase.INTERMISSION;
      d.phaseEnd = w.time;
      d.toSpawn = d.spawned = d.killed = d.bossLeft = 0;
      return "wave " + (d.wave + 1);
    case DevCmd.HEAL:
      if (p.state === PlayerState.DOWNED) p.state = PlayerState.ALIVE;
      p.hp = p.maxHp;
      return "heal";
  }
  return "unknown";
}
