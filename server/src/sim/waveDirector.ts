/** Infinite waves from shared/waves.json (mirror of wave_director.gd).
 *  The static formulas are the cross-language contract (golden tests). */
import type { WavesDef, ZombieDef } from "../shared/schemas.js";
import type { Rng } from "./rng.js";
import { roundHalfAway } from "./math.js";

export enum Phase { INTERMISSION = 0, WAVE = 1, STOPPED = 2 }

export class WaveDirector {
  phase = Phase.INTERMISSION;
  wave = 0;
  phaseEnd = 0;
  toSpawn = 0;
  spawned = 0;
  killed = 0;
  nextSpawnTime = 0;

  constructor(readonly cfg: WavesDef) {}

  start(now: number): void {
    this.phase = Phase.INTERMISSION;
    this.wave = 0;
    this.phaseEnd = now + this.cfg.firstWaveDelaySec;
  }

  remaining(): number { return this.toSpawn - this.killed; }

  static countFor(c: WavesDef, wave: number, players: number): number {
    const cc = c.count;
    const raw = Math.pow(cc.base + cc.perWave * (wave - 1), cc.exponent);
    const scaled = raw * (1 + cc.perExtraPlayer * Math.max(0, players - 1));
    return Math.min(cc.max, Math.max(1, roundHalfAway(scaled)));
  }

  static spawnIntervalFor(c: WavesDef, wave: number): number {
    const s = c.spawnIntervalSec;
    return Math.max(s.min, s.start + s.perWave * (wave - 1));
  }

  static healthFor(def: ZombieDef, wave: number): number {
    return def.baseHealth + def.healthPerWave * (wave - 1);
  }

  static speedFor(def: ZombieDef, wave: number): number {
    return Math.min(def.maxMoveSpeed, def.moveSpeed + def.moveSpeedPerWave * (wave - 1));
  }

  static mixFor(c: WavesDef, wave: number): Record<string, number> {
    let best = c.mix[0]!.weights;
    for (const entry of c.mix) if (entry.fromWave <= wave) best = entry.weights;
    return best;
  }

  static pickType(c: WavesDef, wave: number, rng: Rng): string {
    const weights = WaveDirector.mixFor(c, wave);
    const keys = Object.keys(weights);
    let total = 0;
    for (const k of keys) total += weights[k]!;
    let roll = rng.randf() * total;
    let last = "";
    for (const k of keys) {
      last = k;
      roll -= weights[k]!;
      if (roll <= 0) return k;
    }
    return last;
  }
}
