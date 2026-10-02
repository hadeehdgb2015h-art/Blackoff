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
}

/** One player's part in one zone, recorded when they leave it or it closes. */
export interface MatchResult {
  accountId: string;
  name: string;
  kills: number;
  headshots: number;
  wave: number;
  seconds: number;
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

export interface ProfileStore {
  readonly kind: string;
  /** Creates the profile on first sight; refreshes the display name. */
  load(accountId: string, name: string): Promise<Profile>;
  /** Adds one match to the profile and returns the updated totals. */
  record(result: MatchResult): Promise<Profile>;
  recordMatch(summary: MatchSummary): Promise<void>;
  close(): Promise<void>;
}

export const emptyProfile = (): Profile => ({ games: 0, kills: 0, headshots: 0, bestWave: 0, playSeconds: 0 });

export function addResult(p: Profile, r: MatchResult): Profile {
  return {
    games: p.games + 1,
    kills: p.kills + r.kills,
    headshots: p.headshots + r.headshots,
    bestWave: Math.max(p.bestWave, r.wave),
    playSeconds: p.playSeconds + Math.round(r.seconds),
  };
}

export class MemoryProfileStore implements ProfileStore {
  readonly kind = "memory";
  readonly profiles = new Map<string, Profile>();
  readonly matches: MatchSummary[] = [];

  async load(accountId: string): Promise<Profile> {
    let p = this.profiles.get(accountId);
    if (!p) this.profiles.set(accountId, (p = emptyProfile()));
    return { ...p };
  }

  async record(r: MatchResult): Promise<Profile> {
    const p = addResult(this.profiles.get(r.accountId) ?? emptyProfile(), r);
    this.profiles.set(r.accountId, p);
    return { ...p };
  }

  async recordMatch(s: MatchSummary): Promise<void> {
    this.matches.push(s);
    if (this.matches.length > 1000) this.matches.shift();
  }

  async close(): Promise<void> {}
}
