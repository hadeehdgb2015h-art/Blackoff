/**
 * Player profiles: lifetime stats keyed by account id ("tg:<id>" or "dev:<name>").
 * The server works without a database (MemoryProfileStore, lost on restart);
 * with DATABASE_URL set it uses Postgres (PgProfileStore).
 */

export interface Profile {
  games: number;
  kills: number;
  headshots: number;
  bestWave: number;
  playSeconds: number;
  /** TON points in millionths (server-owned; the owner pays prizes by hand) */
  tonMicro: number;
  /** anti-cheat flags accumulated over all matches */
  suspicion: number;
}

export interface WeeklyRow { accountId: string; name: string; kills: number; tonMicro: number; games: number }

export interface WeeklyStanding { rank: number; kills: number; tonMicro: number }

/** One player's part in one zone, recorded when they leave it or it closes. */
export interface MatchResult {
  accountId: string;
  name: string;
  kills: number;
  headshots: number;
  wave: number;
  seconds: number;
  shots: number;
  hits: number;
  /** TON points earned in this match (millionths) */
  tonMicro: number;
  /** anti-cheat flags raised for this match */
  flags: string[];
}

/** Monday 00:00 UTC of the week containing `at`, as YYYY-MM-DD. */
export function weekStart(at: Date = new Date()): string {
  const d = new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate()));
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return d.toISOString().slice(0, 10);
}

/** ISO week label such as 2026-W40 for a week start date. */
export function weekLabel(start: string): string {
  const d = new Date(start + "T00:00:00Z");
  const thursday = new Date(d);
  thursday.setUTCDate(d.getUTCDate() + 3);
  const jan1 = new Date(Date.UTC(thursday.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((thursday.getTime() - jan1.getTime()) / 86400000 + 1) / 7);
  return `${thursday.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

/** One zone from creation to close. */
export interface MatchSummary {
  mapId: string;
  startedAt: Date;
  endedAt: Date;
  wave: number;
  players: number;
  reason: "game over" | "empty" | "shutdown";
}

/** Counts for the owner's panel. */
export interface StoreOverview { users: number; newToday: number; activeToday: number; matchesToday: number; totalKills: number }

/** One account found by id or name (owner's panel). */
export interface FoundPlayer { accountId: string; name: string; profile: Profile }

export interface ProfileStore {
  readonly kind: string;
  overview(): Promise<StoreOverview>;
  /** Telegram accounts ("tg:<id>"), most recently seen first (broadcasts). */
  telegramIds(limit: number): Promise<string[]>;
  /** Accounts whose id is `query` or whose name contains it. */
  find(query: string, limit: number): Promise<FoundPlayer[]>;
  /** Adds (or with a negative amount removes) TON points; null when the account is unknown. */
  addTon(accountId: string, micro: number): Promise<Profile | null>;
  /** Small persistent settings (the owner's runtime switches). */
  getSetting(key: string): Promise<unknown>;
  setSetting(key: string, value: unknown): Promise<void>;
  /** Creates the profile on first sight; refreshes the display name. */
  load(accountId: string, name: string): Promise<Profile>;
  /** Adds one match to the profile and returns the updated totals. */
  record(result: MatchResult): Promise<Profile>;
  recordMatch(summary: MatchSummary): Promise<void>;
  /** This week's standing of one account (rank 0 = no kills yet). */
  weekly(accountId: string, week?: string): Promise<WeeklyStanding>;
  /** This week's top hunters. */
  leaderboard(limit: number, week?: string): Promise<WeeklyRow[]>;
  /** Accounts with anti-cheat flags, most flagged first. */
  suspects(limit: number): Promise<{ accountId: string; name: string; suspicion: number; kills: number; shots: number; hits: number }[]>;
  close(): Promise<void>;
}

export const emptyProfile = (): Profile => ({ games: 0, kills: 0, headshots: 0, bestWave: 0, playSeconds: 0, tonMicro: 0, suspicion: 0 });

export function addResult(p: Profile, r: MatchResult): Profile {
  return {
    games: p.games + 1,
    kills: p.kills + r.kills,
    headshots: p.headshots + r.headshots,
    bestWave: Math.max(p.bestWave, r.wave),
    playSeconds: p.playSeconds + Math.round(r.seconds),
    tonMicro: p.tonMicro + r.tonMicro,
    suspicion: p.suspicion + r.flags.length,
  };
}

export class MemoryProfileStore implements ProfileStore {
  readonly kind = "memory";
  readonly profiles = new Map<string, Profile>();
  readonly matches: MatchSummary[] = [];
  readonly weeks = new Map<string, Map<string, WeeklyRow>>();
  readonly stats = new Map<string, { shots: number; hits: number }>();
  readonly names = new Map<string, string>();
  readonly seen = new Map<string, number>();
  readonly settings = new Map<string, unknown>();

  async load(accountId: string, name = ""): Promise<Profile> {
    let p = this.profiles.get(accountId);
    if (!p) this.profiles.set(accountId, (p = emptyProfile()));
    if (name) this.names.set(accountId, name);
    this.seen.set(accountId, Date.now());
    return { ...p };
  }

  async overview(): Promise<StoreOverview> {
    const day = Date.now() - 86_400_000;
    let kills = 0;
    for (const p of this.profiles.values()) kills += p.kills;
    return {
      users: this.profiles.size, newToday: 0, activeToday: [...this.seen.values()].filter((t) => t >= day).length,
      matchesToday: this.matches.filter((m) => m.endedAt.getTime() >= day).length, totalKills: kills,
    };
  }

  async telegramIds(limit: number): Promise<string[]> {
    return [...this.seen.entries()].filter(([id]) => id.startsWith("tg:")).sort((a, b) => b[1] - a[1]).slice(0, limit).map(([id]) => id);
  }

  async find(query: string, limit: number): Promise<FoundPlayer[]> {
    const q = query.toLowerCase();
    return [...this.profiles.entries()]
      .filter(([id]) => id === query || id === "tg:" + query || (this.names.get(id) ?? "").toLowerCase().includes(q))
      .slice(0, limit)
      .map(([id, p]) => ({ accountId: id, name: this.names.get(id) ?? "", profile: { ...p } }));
  }

  async addTon(accountId: string, micro: number): Promise<Profile | null> {
    const p = this.profiles.get(accountId);
    if (!p) return null;
    p.tonMicro = Math.max(0, p.tonMicro + micro);
    return { ...p };
  }

  async getSetting(key: string): Promise<unknown> {
    return this.settings.get(key) ?? null;
  }

  async setSetting(key: string, value: unknown): Promise<void> {
    this.settings.set(key, value);
  }

  async record(r: MatchResult): Promise<Profile> {
    const p = addResult(this.profiles.get(r.accountId) ?? emptyProfile(), r);
    this.profiles.set(r.accountId, p);
    const st = this.stats.get(r.accountId) ?? { shots: 0, hits: 0 };
    this.stats.set(r.accountId, { shots: st.shots + r.shots, hits: st.hits + r.hits });
    const week = weekStart();
    let rows = this.weeks.get(week);
    if (!rows) this.weeks.set(week, (rows = new Map()));
    const row = rows.get(r.accountId) ?? { accountId: r.accountId, name: r.name, kills: 0, tonMicro: 0, games: 0 };
    rows.set(r.accountId, { ...row, name: r.name, kills: row.kills + r.kills, tonMicro: row.tonMicro + r.tonMicro, games: row.games + 1 });
    return { ...p };
  }

  async weekly(accountId: string, week = weekStart()): Promise<WeeklyStanding> {
    const rows = await this.leaderboard(1_000_000, week);
    const i = rows.findIndex((r) => r.accountId === accountId);
    if (i < 0 || rows[i]!.kills === 0) return { rank: 0, kills: 0, tonMicro: 0 };
    return { rank: i + 1, kills: rows[i]!.kills, tonMicro: rows[i]!.tonMicro };
  }

  async leaderboard(limit: number, week = weekStart()): Promise<WeeklyRow[]> {
    const rows = [...(this.weeks.get(week)?.values() ?? [])].filter((r) => r.kills > 0);
    rows.sort((a, b) => b.kills - a.kills || b.tonMicro - a.tonMicro || a.accountId.localeCompare(b.accountId));
    return rows.slice(0, limit).map((r) => ({ ...r }));
  }

  async suspects(limit: number) {
    return [...this.profiles.entries()]
      .filter(([, p]) => p.suspicion > 0)
      .sort((a, b) => b[1].suspicion - a[1].suspicion)
      .slice(0, limit)
      .map(([id, p]) => ({ accountId: id, name: "", suspicion: p.suspicion, kills: p.kills, ...(this.stats.get(id) ?? { shots: 0, hits: 0 }) }));
  }

  async recordMatch(s: MatchSummary): Promise<void> {
    this.matches.push(s);
    if (this.matches.length > 1000) this.matches.shift();
  }

  async close(): Promise<void> {}
}
