/**
 * Daily reward and missions (phase 23): pure functions over the small state
 * kept per account in the store. The server owns every number; the client only
 * shows the state and asks to claim.
 *
 * - Streak reward: one claim per UTC day. Claiming on consecutive days walks
 *   the 7-day calendar (day 7 pays the most, then it starts again at day 1);
 *   a missed day restarts at day 1.
 * - Missions: three a day (easy, medium, hard), picked from the account id and
 *   the day, so they are the same on every device and after a restart. Finished
 *   games add progress; a mission pays as soon as it is done, and finishing all
 *   three pays a bonus.
 * Rewards are counted in kills and paid in TON points (× TON per kill in force).
 */
import type { Constants } from "../shared/schemas.js";

export type DailyDefs = Constants["daily"];

/** Order = protocol enum missionKind. */
export const MISSION_KINDS = ["kills", "headshots", "wave", "boss", "games"] as const;
export type MissionKind = (typeof MISSION_KINDS)[number];

export interface Mission {
  kind: MissionKind;
  goal: number;
  progress: number;
  rewardKills: number;
  done: boolean;
}

export interface DailyState {
  /** UTC day (YYYY-MM-DD) of `missions` */
  day: string;
  missions: Mission[];
  bonusDone: boolean;
  /** last day the streak reward was claimed ("" = never) */
  lastClaim: string;
  /** streak day (1-7) that claim paid */
  streak: number;
}

/** One finished game of one player, as far as missions care. */
export interface GameStats {
  kills: number;
  headshots: number;
  wave: number;
  bossKills: number;
  seconds: number;
  /** a zombies (co-op) game; infection games only count for "games" */
  zombies: boolean;
}

export const freshDaily = (): DailyState => ({ day: "", missions: [], bonusDone: false, lastClaim: "", streak: 0 });

export function dayKey(at: Date): string {
  return at.toISOString().slice(0, 10);
}

function prevDay(day: string): string {
  const d = new Date(day + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() - 1);
  return dayKey(d);
}

/** Seconds until the next day starts (00:00 UTC). */
export function secondsToReset(at: Date): number {
  const next = Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - at.getTime()) / 1000));
}

/** Small seeded generator (FNV-1a seed, mulberry32 steps). */
function random(seed: string): () => number {
  let h = 0x811c9dc5;
  for (let i = 0; i < seed.length; i++) h = Math.imul(h ^ seed.charCodeAt(i), 0x01000193);
  return () => {
    h = (h + 0x6d2b79f5) | 0;
    let t = Math.imul(h ^ (h >>> 15), 1 | h);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Today's three missions of one account: easy, medium, hard, three different kinds. */
export function missionsFor(accountId: string, day: string, defs: DailyDefs): Mission[] {
  const rnd = random(accountId + "|" + day);
  const used = new Set<MissionKind>();
  const out: Mission[] = [];
  for (let tier = 0; tier < 3; tier++) {
    const options = MISSION_KINDS.filter((k) => !used.has(k) && defs.missions[k].goals[tier]! > 0);
    if (!options.length) continue;
    const kind = options[Math.floor(rnd() * options.length)]!;
    used.add(kind);
    out.push({ kind, goal: defs.missions[kind].goals[tier]!, progress: 0, rewardKills: defs.missions[kind].rewardKills[tier]!, done: false });
  }
  return out;
}

/** The state on `day`: new missions once the day has turned. */
export function rollover(s: DailyState, accountId: string, day: string, defs: DailyDefs): DailyState {
  if (s.day === day) return s;
  return { ...s, day, missions: missionsFor(accountId, day, defs), bonusDone: false };
}

/** Whether today's streak reward is still to claim, and which calendar day (1-7) it is. */
export function streakStatus(s: DailyState, day: string): { canClaim: boolean; nextDay: number } {
  if (s.lastClaim === day) return { canClaim: false, nextDay: s.streak };
  return { canClaim: true, nextDay: s.lastClaim === prevDay(day) ? (s.streak % 7) + 1 : 1 };
}

export function claimStreak(s: DailyState, day: string, defs: DailyDefs): { state: DailyState; paidKills: number } {
  const st = streakStatus(s, day);
  if (!st.canClaim) return { state: s, paidKills: 0 };
  return { state: { ...s, lastClaim: day, streak: st.nextDay }, paidKills: defs.streakKills[st.nextDay - 1]! };
}

/** Adds one finished game to today's missions; pays the missions it completes (and the bonus). */
export function applyGame(s: DailyState, g: GameStats, defs: DailyDefs): { state: DailyState; paidKills: number } {
  let paid = 0;
  const counts = g.seconds >= defs.minGameSec;
  const missions = s.missions.map((m) => {
    if (m.done) return m;
    let progress = m.progress;
    if (m.kind === "games") progress += counts ? 1 : 0;
    else if (g.zombies) {
      if (m.kind === "kills") progress += g.kills;
      else if (m.kind === "headshots") progress += g.headshots;
      else if (m.kind === "boss") progress += g.bossKills;
      else if (m.kind === "wave") progress = Math.max(progress, g.wave);
    }
    progress = Math.min(progress, m.goal);
    if (progress === m.progress) return m;
    const done = progress >= m.goal;
    if (done) paid += m.rewardKills;
    return { ...m, progress, done };
  });
  let bonusDone = s.bonusDone;
  if (!bonusDone && missions.length > 0 && missions.every((m) => m.done)) {
    bonusDone = true;
    paid += defs.allMissionsBonusKills;
  }
  return { state: { ...s, missions, bonusDone }, paidKills: paid };
}

const int = (v: unknown, max: number): number => (typeof v === "number" && Number.isFinite(v) ? Math.max(0, Math.min(max, Math.floor(v))) : 0);
const isDay = (v: unknown): v is string => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);

/** A state read back from the store, checked field by field (anything odd starts fresh). */
export function parseDaily(raw: unknown): DailyState {
  if (!raw || typeof raw !== "object") return freshDaily();
  const r = raw as Record<string, unknown>;
  const missions: Mission[] = [];
  if (Array.isArray(r.missions)) {
    for (const m of r.missions.slice(0, 3) as Record<string, unknown>[]) {
      if (!m || !MISSION_KINDS.includes(m.kind as MissionKind)) continue;
      const goal = Math.max(1, int(m.goal, 65535));
      const progress = Math.min(goal, int(m.progress, 65535));
      missions.push({ kind: m.kind as MissionKind, goal, progress, rewardKills: int(m.rewardKills, 100000), done: m.done === true && progress >= goal });
    }
  }
  return {
    day: isDay(r.day) ? r.day : "",
    missions,
    bonusDone: r.bonusDone === true,
    lastClaim: isDay(r.lastClaim) ? r.lastClaim : "",
    streak: Math.min(7, int(r.streak, 7)),
  };
}
