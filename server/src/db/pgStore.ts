/**
 * Postgres profile store plus its schema migrations. Migrations live here as
 * code (no files to ship next to the bundle); each runs once, in a transaction,
 * under an advisory lock so two starting servers cannot race.
 */
import pg from "pg";
import { log } from "../log.js";
import type { ActivityPatch, ActivityRow } from "../stats/analytics.js";
import { utcDay } from "../stats/analytics.js";
import { weekStart, type NewReport, type ReportRow, type FoundPlayer, type MatchResult, type MatchSummary, type Profile, type ProfileStore, type StoreOverview, type WeeklyRow, type WeeklyStanding } from "./profileStore.js";

export interface Migration { id: number; name: string; sql: string }

export const MIGRATIONS: Migration[] = [
  {
    id: 1,
    name: "players and matches",
    sql: `
      CREATE TABLE players (
        account_id   text PRIMARY KEY,
        name         text NOT NULL,
        games        integer NOT NULL DEFAULT 0,
        kills        integer NOT NULL DEFAULT 0,
        headshots    integer NOT NULL DEFAULT 0,
        best_wave    integer NOT NULL DEFAULT 0,
        play_seconds bigint  NOT NULL DEFAULT 0,
        created_at   timestamptz NOT NULL DEFAULT now(),
        last_seen    timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX players_best_wave ON players (best_wave DESC);
      CREATE TABLE matches (
        id         bigserial PRIMARY KEY,
        map        text NOT NULL,
        started_at timestamptz NOT NULL,
        ended_at   timestamptz NOT NULL,
        wave       integer NOT NULL,
        players    integer NOT NULL,
        reason     text NOT NULL
      );`,
  },
  {
    id: 2,
    name: "ton points, anti-cheat counters, weekly scores",
    sql: `
      ALTER TABLE players
        ADD COLUMN ton_micro  bigint  NOT NULL DEFAULT 0,
        ADD COLUMN suspicion  integer NOT NULL DEFAULT 0,
        ADD COLUMN shots      bigint  NOT NULL DEFAULT 0,
        ADD COLUMN hits       bigint  NOT NULL DEFAULT 0;
      CREATE TABLE weekly_scores (
        week       date   NOT NULL,
        account_id text   NOT NULL,
        name       text   NOT NULL,
        kills      integer NOT NULL DEFAULT 0,
        ton_micro  bigint  NOT NULL DEFAULT 0,
        games      integer NOT NULL DEFAULT 0,
        PRIMARY KEY (week, account_id)
      );
      CREATE INDEX weekly_scores_rank ON weekly_scores (week, kills DESC, ton_micro DESC);
      CREATE INDEX players_suspicion ON players (suspicion DESC);`,
  },
  {
    id: 3,
    name: "owner settings",
    sql: `
      CREATE TABLE settings (
        key        text PRIMARY KEY,
        value      jsonb NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX players_last_seen ON players (last_seen DESC);`,
  },
  {
    id: 4,
    name: "daily reward and missions",
    sql: `
      CREATE TABLE daily_state (
        account_id text PRIMARY KEY,
        data       jsonb NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now()
      );`,
  },
  {
    id: 5,
    name: "experience",
    sql: `ALTER TABLE players ADD COLUMN xp bigint NOT NULL DEFAULT 0;`,
  },
  {
    id: 6,
    name: "activity statistics and problem reports",
    sql: `
      CREATE TABLE activity (
        day          date    NOT NULL,
        account_id   text    NOT NULL,
        opens        integer NOT NULL DEFAULT 0,
        games        integer NOT NULL DEFAULT 0,
        play_seconds integer NOT NULL DEFAULT 0,
        best_wave    integer NOT NULL DEFAULT 0,
        platform     text    NOT NULL DEFAULT '',
        lang         text    NOT NULL DEFAULT '',
        fps_sum      integer NOT NULL DEFAULT 0,
        fps_n        integer NOT NULL DEFAULT 0,
        PRIMARY KEY (day, account_id)
      );
      CREATE INDEX activity_account ON activity (account_id, day);
      CREATE INDEX players_created ON players (created_at);
      CREATE TABLE reports (
        id         serial PRIMARY KEY,
        created_at timestamptz NOT NULL DEFAULT now(),
        account_id text    NOT NULL,
        name       text    NOT NULL,
        category   integer NOT NULL,
        info       jsonb   NOT NULL,
        notes      text    NOT NULL DEFAULT '',
        resolved   boolean NOT NULL DEFAULT false
      );
      CREATE INDEX reports_open ON reports (resolved, id DESC);`,
  },
];

const LOCK_ID = 0x0b1ac0ff;

export async function migrate(pool: pg.Pool, migrations = MIGRATIONS): Promise<number[]> {
  const c = await pool.connect();
  const applied: number[] = [];
  try {
    await c.query("SELECT pg_advisory_lock($1)", [LOCK_ID]);
    await c.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      id integer PRIMARY KEY, name text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())`);
    const done = new Set((await c.query<{ id: number }>("SELECT id FROM schema_migrations")).rows.map((r) => r.id));
    for (const m of [...migrations].sort((a, b) => a.id - b.id)) {
      if (done.has(m.id)) continue;
      await c.query("BEGIN");
      try {
        await c.query(m.sql);
        await c.query("INSERT INTO schema_migrations (id, name) VALUES ($1, $2)", [m.id, m.name]);
        await c.query("COMMIT");
      } catch (err) {
        await c.query("ROLLBACK");
        throw new Error(`migration ${m.id} (${m.name}) failed: ${(err as Error).message}`);
      }
      applied.push(m.id);
      log.info("migration applied", { id: m.id, name: m.name });
    }
  } finally {
    await c.query("SELECT pg_advisory_unlock($1)", [LOCK_ID]).catch(() => {});
    c.release();
  }
  return applied;
}

interface Row { games: number; kills: number; headshots: number; best_wave: number; play_seconds: string | number; ton_micro: string | number; suspicion: number; xp: string | number }

const toProfile = (r: Row): Profile => ({
  games: r.games, kills: r.kills, headshots: r.headshots, bestWave: r.best_wave, playSeconds: Number(r.play_seconds),
  tonMicro: Number(r.ton_micro), suspicion: r.suspicion, xp: Number(r.xp),
});

interface ReportDbRow { id: number; created_at: Date; account_id: string; name: string; category: number; info: Record<string, unknown>; notes: string; resolved: boolean }

const toReport = (r: ReportDbRow): ReportRow => ({
  id: r.id, createdAt: r.created_at, accountId: r.account_id, name: r.name, category: r.category, info: r.info, notes: r.notes, resolved: r.resolved,
});

const COLS = "games, kills, headshots, best_wave, play_seconds, ton_micro, suspicion, xp";

export class PgProfileStore implements ProfileStore {
  readonly kind = "postgres";

  constructor(readonly pool: pg.Pool) {}

  static async open(url: string): Promise<PgProfileStore> {
    const pool = new pg.Pool({
      connectionString: url,
      max: 4,
      connectionTimeoutMillis: 3000,
      idleTimeoutMillis: 30_000,
      statement_timeout: 5000,
      application_name: "blackoff",
    });
    pool.on("error", (err) => log.warn("postgres idle client error", { error: err.message }));
    await migrate(pool);
    return new PgProfileStore(pool);
  }

  async load(accountId: string, name: string): Promise<Profile> {
    const r = await this.pool.query<Row>(
      `INSERT INTO players (account_id, name) VALUES ($1, $2)
       ON CONFLICT (account_id) DO UPDATE SET name = EXCLUDED.name, last_seen = now()
       RETURNING ${COLS}`,
      [accountId, name],
    );
    return toProfile(r.rows[0]!);
  }

  async record(m: MatchResult): Promise<Profile> {
    const r = await this.pool.query<Row>(
      `INSERT INTO players (account_id, name, games, kills, headshots, best_wave, play_seconds, ton_micro, suspicion, shots, hits, xp)
       VALUES ($1, $2, 1, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       ON CONFLICT (account_id) DO UPDATE SET
         name = EXCLUDED.name,
         games = players.games + 1,
         kills = players.kills + EXCLUDED.kills,
         headshots = players.headshots + EXCLUDED.headshots,
         best_wave = GREATEST(players.best_wave, EXCLUDED.best_wave),
         play_seconds = players.play_seconds + EXCLUDED.play_seconds,
         ton_micro = players.ton_micro + EXCLUDED.ton_micro,
         suspicion = players.suspicion + EXCLUDED.suspicion,
         shots = players.shots + EXCLUDED.shots,
         hits = players.hits + EXCLUDED.hits,
         xp = players.xp + EXCLUDED.xp,
         last_seen = now()
       RETURNING ${COLS}`,
      [m.accountId, m.name, m.kills, m.headshots, m.wave, Math.round(m.seconds), m.tonMicro, m.flags.length, m.shots, m.hits, Math.round(m.xp ?? 0)],
    );
    await this.pool.query(
      `INSERT INTO weekly_scores (week, account_id, name, kills, ton_micro, games) VALUES ($1, $2, $3, $4, $5, 1)
       ON CONFLICT (week, account_id) DO UPDATE SET
         name = EXCLUDED.name, kills = weekly_scores.kills + EXCLUDED.kills,
         ton_micro = weekly_scores.ton_micro + EXCLUDED.ton_micro, games = weekly_scores.games + 1`,
      [weekStart(), m.accountId, m.name, m.kills, m.tonMicro],
    );
    return toProfile(r.rows[0]!);
  }

  async weekly(accountId: string, week = weekStart()): Promise<WeeklyStanding> {
    const r = await this.pool.query<{ rank: string; kills: number; ton_micro: string }>(
      `SELECT rank, kills, ton_micro FROM (
         SELECT account_id, kills, ton_micro, rank() OVER (ORDER BY kills DESC, ton_micro DESC, account_id) AS rank
         FROM weekly_scores WHERE week = $1 AND kills > 0) t
       WHERE account_id = $2`,
      [week, accountId],
    );
    const row = r.rows[0];
    return row ? { rank: Number(row.rank), kills: row.kills, tonMicro: Number(row.ton_micro) } : { rank: 0, kills: 0, tonMicro: 0 };
  }

  async leaderboard(limit: number, week = weekStart()): Promise<WeeklyRow[]> {
    const r = await this.pool.query<{ account_id: string; name: string; kills: number; ton_micro: string; games: number }>(
      `SELECT account_id, name, kills, ton_micro, games FROM weekly_scores
       WHERE week = $1 AND kills > 0 ORDER BY kills DESC, ton_micro DESC, account_id LIMIT $2`,
      [week, limit],
    );
    return r.rows.map((x) => ({ accountId: x.account_id, name: x.name, kills: x.kills, tonMicro: Number(x.ton_micro), games: x.games }));
  }

  async suspects(limit: number) {
    const r = await this.pool.query<{ account_id: string; name: string; suspicion: number; kills: number; shots: string; hits: string }>(
      "SELECT account_id, name, suspicion, kills, shots, hits FROM players WHERE suspicion > 0 ORDER BY suspicion DESC, kills DESC LIMIT $1",
      [limit],
    );
    return r.rows.map((x) => ({ accountId: x.account_id, name: x.name, suspicion: x.suspicion, kills: x.kills, shots: Number(x.shots), hits: Number(x.hits) }));
  }

  async overview(): Promise<StoreOverview> {
    const r = await this.pool.query<{ users: string; new_today: string; active_today: string; kills: string | null }>(
      `SELECT count(*) AS users,
              count(*) FILTER (WHERE created_at >= now() - interval '1 day') AS new_today,
              count(*) FILTER (WHERE last_seen >= now() - interval '1 day') AS active_today,
              sum(kills) AS kills
       FROM players`,
    );
    const m = await this.pool.query<{ n: string }>("SELECT count(*) AS n FROM matches WHERE ended_at >= now() - interval '1 day'");
    const x = r.rows[0]!;
    return { users: Number(x.users), newToday: Number(x.new_today), activeToday: Number(x.active_today), matchesToday: Number(m.rows[0]!.n), totalKills: Number(x.kills ?? 0) };
  }

  async telegramIds(limit: number): Promise<string[]> {
    const r = await this.pool.query<{ account_id: string }>(
      "SELECT account_id FROM players WHERE account_id LIKE 'tg:%' ORDER BY last_seen DESC LIMIT $1", [limit]);
    return r.rows.map((x) => x.account_id);
  }

  async find(query: string, limit: number): Promise<FoundPlayer[]> {
    const r = await this.pool.query<Row & { account_id: string; name: string }>(
      `SELECT account_id, name, ${COLS} FROM players
       WHERE account_id = $1 OR account_id = 'tg:' || $1 OR name ILIKE '%' || $1 || '%'
       ORDER BY last_seen DESC LIMIT $2`,
      [query, limit],
    );
    return r.rows.map((x) => ({ accountId: x.account_id, name: x.name, profile: toProfile(x) }));
  }

  async addTon(accountId: string, micro: number): Promise<Profile | null> {
    const r = await this.pool.query<Row>(
      `UPDATE players SET ton_micro = GREATEST(0, ton_micro + $2) WHERE account_id = $1 RETURNING ${COLS}`, [accountId, micro]);
    return r.rows[0] ? toProfile(r.rows[0]) : null;
  }

  async getSetting(key: string): Promise<unknown> {
    const r = await this.pool.query<{ value: unknown }>("SELECT value FROM settings WHERE key = $1", [key]);
    return r.rows[0]?.value ?? null;
  }

  async setSetting(key: string, value: unknown): Promise<void> {
    await this.pool.query(
      `INSERT INTO settings (key, value) VALUES ($1, $2::jsonb)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [key, JSON.stringify(value)],
    );
  }

  async getDaily(accountId: string): Promise<unknown> {
    const r = await this.pool.query<{ data: unknown }>("SELECT data FROM daily_state WHERE account_id = $1", [accountId]);
    return r.rows[0]?.data ?? null;
  }

  async setDaily(accountId: string, state: unknown): Promise<void> {
    await this.pool.query(
      `INSERT INTO daily_state (account_id, data) VALUES ($1, $2::jsonb)
       ON CONFLICT (account_id) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
      [accountId, JSON.stringify(state)],
    );
  }

  async touchActivity(accountId: string, p: ActivityPatch, day = utcDay()): Promise<void> {
    await this.pool.query(
      `INSERT INTO activity (day, account_id, opens, games, play_seconds, best_wave, platform, lang, fps_sum, fps_n)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       ON CONFLICT (day, account_id) DO UPDATE SET
         opens = activity.opens + EXCLUDED.opens,
         games = activity.games + EXCLUDED.games,
         play_seconds = activity.play_seconds + EXCLUDED.play_seconds,
         best_wave = GREATEST(activity.best_wave, EXCLUDED.best_wave),
         platform = CASE WHEN EXCLUDED.platform <> '' THEN EXCLUDED.platform ELSE activity.platform END,
         lang = CASE WHEN EXCLUDED.lang <> '' THEN EXCLUDED.lang ELSE activity.lang END,
         fps_sum = activity.fps_sum + EXCLUDED.fps_sum,
         fps_n = activity.fps_n + EXCLUDED.fps_n`,
      [day, accountId, p.opens ?? 0, p.games ?? 0, Math.round(p.seconds ?? 0), p.wave ?? 0, p.platform ?? "", p.lang ?? "",
        p.fps ? Math.round(p.fps) : 0, p.fps ? 1 : 0],
    );
  }

  async activitySince(day: string): Promise<ActivityRow[]> {
    const r = await this.pool.query<{ day: string; account_id: string; opens: number; games: number; play_seconds: number; best_wave: number; platform: string; lang: string; fps_sum: number; fps_n: number }>(
      `SELECT to_char(day, 'YYYY-MM-DD') AS day, account_id, opens, games, play_seconds, best_wave, platform, lang, fps_sum, fps_n
       FROM activity WHERE day >= $1`, [day]);
    return r.rows.map((x) => ({
      day: x.day, accountId: x.account_id, opens: x.opens, games: x.games, seconds: x.play_seconds, bestWave: x.best_wave,
      platform: x.platform, lang: x.lang, fpsSum: x.fps_sum, fpsN: x.fps_n,
    }));
  }

  async firstSeenSince(day: string): Promise<Map<string, string>> {
    const r = await this.pool.query<{ account_id: string; day: string }>(
      `SELECT account_id, to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day FROM players
       WHERE created_at >= ($1::date AT TIME ZONE 'UTC')`, [day]);
    return new Map(r.rows.map((x) => [x.account_id, x.day]));
  }

  async addReport(r: NewReport): Promise<number> {
    const q = await this.pool.query<{ id: number }>(
      "INSERT INTO reports (account_id, name, category, info) VALUES ($1, $2, $3, $4::jsonb) RETURNING id",
      [r.accountId, r.name, r.category, JSON.stringify(r.info)]);
    return q.rows[0]!.id;
  }

  async report(id: number): Promise<ReportRow | null> {
    const q = await this.pool.query<ReportDbRow>("SELECT * FROM reports WHERE id = $1", [id]);
    return q.rows[0] ? toReport(q.rows[0]) : null;
  }

  async reports(limit: number, open: boolean): Promise<ReportRow[]> {
    const q = await this.pool.query<ReportDbRow>(
      `SELECT * FROM reports ${open ? "WHERE NOT resolved" : ""} ORDER BY id DESC LIMIT $1`, [limit]);
    return q.rows.map(toReport);
  }

  async countOpenReports(): Promise<number> {
    const q = await this.pool.query<{ n: string }>("SELECT count(*) AS n FROM reports WHERE NOT resolved");
    return Number(q.rows[0]!.n);
  }

  async noteReport(id: number, text: string): Promise<void> {
    await this.pool.query(
      "UPDATE reports SET notes = left(CASE WHEN notes = '' THEN $2 ELSE notes || E'\\n' || $2 END, 4000) WHERE id = $1", [id, text]);
  }

  async resolveReport(id: number): Promise<boolean> {
    const q = await this.pool.query("UPDATE reports SET resolved = true WHERE id = $1 AND NOT resolved", [id]);
    return (q.rowCount ?? 0) > 0;
  }

  async recordMatch(s: MatchSummary): Promise<void> {
    await this.pool.query(
      "INSERT INTO matches (map, started_at, ended_at, wave, players, reason) VALUES ($1, $2, $3, $4, $5, $6)",
      [s.mapId, s.startedAt, s.endedAt, s.wave, s.players, s.reason],
    );
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}
