/**
 * Postgres profile store plus its schema migrations. Migrations live here as
 * code (no files to ship next to the bundle); each runs once, in a transaction,
 * under an advisory lock so two starting servers cannot race.
 */
import pg from "pg";
import { log } from "../log.js";
import type { MatchResult, MatchSummary, Profile, ProfileStore } from "./profileStore.js";

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

interface Row { games: number; kills: number; headshots: number; best_wave: number; play_seconds: string | number }

const toProfile = (r: Row): Profile => ({
  games: r.games, kills: r.kills, headshots: r.headshots, bestWave: r.best_wave, playSeconds: Number(r.play_seconds),
});

const COLS = "games, kills, headshots, best_wave, play_seconds";

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
      `INSERT INTO players (account_id, name, games, kills, headshots, best_wave, play_seconds)
       VALUES ($1, $2, 1, $3, $4, $5, $6)
       ON CONFLICT (account_id) DO UPDATE SET
         name = EXCLUDED.name,
         games = players.games + 1,
         kills = players.kills + EXCLUDED.kills,
         headshots = players.headshots + EXCLUDED.headshots,
         best_wave = GREATEST(players.best_wave, EXCLUDED.best_wave),
         play_seconds = players.play_seconds + EXCLUDED.play_seconds,
         last_seen = now()
       RETURNING ${COLS}`,
      [m.accountId, m.name, m.kills, m.headshots, m.wave, Math.round(m.seconds)],
    );
    return toProfile(r.rows[0]!);
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
