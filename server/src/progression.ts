/**
 * Levels and ranks (phase 26). XP comes from recorded online games only, from
 * the server's own numbers; the level is a pure function of the XP total, so
 * the client (client/scripts/core/progression.gd) shows the same thing
 * (shared/tests/golden.json checks both).
 */
import type { Constants } from "./shared/schemas.js";
import { GameMode } from "./sim/simWorld.js";

export type ProgressionDefs = Constants["progression"];
export type RankDef = ProgressionDefs["ranks"][number];

/** XP for one finished game. */
export function xpFor(r: { kills: number; headshots: number; wave: number; seconds: number; mode: GameMode }, p: ProgressionDefs): number {
  const base = r.kills * p.xpPerKill + r.headshots * p.xpPerHeadshot;
  const extra = r.mode === GameMode.INFECTION ? Math.floor(r.seconds / 60) * p.xpPerInfectionMinute : r.wave * p.xpPerWaveReached;
  return Math.max(0, Math.round(base + extra));
}

/** Total XP needed to stand at `level` (level 1 needs none). */
export function xpToReach(level: number, p: ProgressionDefs): number {
  const n = Math.max(0, Math.min(level, p.maxLevel) - 1);
  return n * p.levelXpBase + (p.levelXpStep * n * (n - 1)) / 2;
}

export function levelFor(xp: number, p: ProgressionDefs): number {
  let level = 1;
  while (level < p.maxLevel && xp >= xpToReach(level + 1, p)) level++;
  return level;
}

/** The highest rank whose level has been reached. */
export function rankFor(level: number, p: ProgressionDefs): RankDef {
  let rank = p.ranks[0]!;
  for (const r of p.ranks) if (level >= r.level) rank = r;
  return rank;
}
