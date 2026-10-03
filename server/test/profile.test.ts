import type { AddressInfo } from "node:net";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { Codec } from "../src/net/codec.js";
import { MemoryProfileStore, type MatchResult } from "../src/db/profileStore.js";
import { MIGRATIONS, PgProfileStore, migrate } from "../src/db/pgStore.js";
import { Zone } from "../src/zone/zone.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

describe("profiles (memory store, over the wire)", () => {
  let app: App;
  let url = "";
  const store = new MemoryProfileStore();
  const codec = new Codec(defs().protocol);
  beforeAll(async () => {
    app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1" }), defs(), store);
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
  });
  afterAll(() => app.close());

  it("sends stats in welcome and an updated profile after a match", async () => {
    const a = await TestClient.connect(url, codec);
    a.hello("dev:Prof");
    const w = await a.waitFor("welcome");
    expect([w.games, w.kills, w.bestWave]).toEqual([0, 0, 0]);
    a.send("quickPlay");
    await a.waitFor("zoneJoined");
    await a.waitFor("snapshot");
    a.send("leave");
    const p = await a.waitFor("profile");
    expect(p.games).toBe(1);
    expect(store.profiles.get("dev:Prof")?.games).toBe(1);
    a.ws.close();
    await a.waitClosed();
    const b = await TestClient.connect(url, codec);
    b.hello("dev:Prof");
    expect((await b.waitFor("welcome")).games).toBe(1);
    b.ws.close();
  });
});

describe("zone results", () => {
  it("reports each member once with kills, wave and time", () => {
    const z = new Zone(1, defs(), new Codec(defs().protocol), "facility_01", 7, 0);
    const got: MatchResult[] = [];
    z.onResult = (r) => got.push(r);
    const client = { displayName: "A", sendBytes() {}, onZoneClosed() {} };
    const m = z.join(client, "dev:A", 1000);
    const m2 = z.join({ ...client, displayName: "B" }, "dev:B", 1000);
    z.world.players.get(m.entityId)!.kills = 5;
    z.world.players.get(m.entityId)!.headshots = 2;
    z.remove(m.entityId, 31_000);
    z.close(61_000);
    z.close(62_000);
    expect(got).toEqual([
      { accountId: "dev:A", name: "A", kills: 5, headshots: 2, wave: z.world.director.wave, seconds: 30, shots: 0, hits: 0, mode: 0, bossKills: 0 },
      { accountId: "dev:B", name: "B", kills: 0, headshots: 0, wave: z.world.director.wave, seconds: 60, shots: 0, hits: 0, mode: 0, bossKills: 0 },
    ]);
    expect(z.peakPlayers).toBe(2);
    expect(m2.entityId).not.toBe(m.entityId);
  });
});

// Runs against a real database when TEST_DATABASE_URL is set (CI and local dev).
const dbUrl = process.env.TEST_DATABASE_URL;
describe.skipIf(!dbUrl)("postgres store", () => {
  let pool: pg.Pool;
  beforeAll(async () => {
    pool = new pg.Pool({ connectionString: dbUrl });
    await pool.query("DROP TABLE IF EXISTS players, matches, weekly_scores, settings, daily_state, activity, reports, schema_migrations");
  });
  afterAll(() => pool.end());

  it("migrates once, then accumulates profiles and matches", async () => {
    expect(await migrate(pool)).toEqual(MIGRATIONS.map((m) => m.id));
    expect(await migrate(pool)).toEqual([]);
    const store = new PgProfileStore(pool);
    const extra = { shots: 0, hits: 0, tonMicro: 0, flags: [] as string[] };
    expect(await store.load("tg:1", "Ali")).toEqual({ games: 0, kills: 0, headshots: 0, bestWave: 0, playSeconds: 0, tonMicro: 0, suspicion: 0, xp: 0 });
    await store.record({ accountId: "tg:1", name: "Ali", kills: 10, headshots: 3, wave: 4, seconds: 100.4, ...extra });
    const p = await store.record({ accountId: "tg:1", name: "Ali K", kills: 2, headshots: 0, wave: 2, seconds: 50, ...extra });
    expect(p).toEqual({ games: 2, kills: 12, headshots: 3, bestWave: 4, playSeconds: 150, tonMicro: 0, suspicion: 0, xp: 0 });
    expect((await store.load("tg:1", "Ali K")).games).toBe(2);
    const name = await pool.query("SELECT name FROM players WHERE account_id = 'tg:1'");
    expect(name.rows[0].name).toBe("Ali K");
    // a result for an account never loaded still creates the row
    expect((await store.record({ accountId: "tg:2", name: "B", kills: 1, headshots: 1, wave: 1, seconds: 9, ...extra })).games).toBe(1);
    const t = new Date();
    await store.recordMatch({ mapId: "facility_01", startedAt: t, endedAt: t, wave: 4, players: 2, reason: "game over" });
    expect((await pool.query("SELECT count(*)::int AS n FROM matches")).rows[0].n).toBe(1);
  });

  it("keeps daily activity and problem reports (phase 29)", async () => {
    const store = new PgProfileStore(pool);
    await store.touchActivity("tg:1", { opens: 1, platform: "ios", lang: "ar" }, "2026-10-01");
    await store.touchActivity("tg:1", { games: 1, seconds: 60.4, wave: 4, fps: 41.6 }, "2026-10-01");
    await store.touchActivity("tg:1", { games: 1, seconds: 30, wave: 2, fps: 30, platform: "" }, "2026-10-01");
    await store.touchActivity("tg:1", { opens: 1 }, "2026-10-02");
    const rows = await store.activitySince("2026-10-01");
    expect(rows.find((r) => r.day === "2026-10-01")).toEqual({
      day: "2026-10-01", accountId: "tg:1", opens: 1, games: 2, seconds: 90, bestWave: 4, platform: "ios", lang: "ar", fpsSum: 72, fpsN: 2,
    });
    expect(rows).toHaveLength(2);
    expect((await store.firstSeenSince("2000-01-01")).get("tg:1")).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    const id = await store.addReport({ accountId: "tg:1", name: "Ali", category: 2, info: { where: "menu", client: { lang: "ar" } } });
    await store.noteReport(id, "first");
    await store.noteReport(id, "second");
    expect(await store.report(id)).toMatchObject({ id, category: 2, notes: "first\nsecond", resolved: false, info: { where: "menu" } });
    expect(await store.countOpenReports()).toBe(1);
    expect(await store.resolveReport(id)).toBe(true);
    expect(await store.resolveReport(id)).toBe(false);
    expect(await store.reports(10, true)).toEqual([]);
    expect((await store.reports(10, false))[0]!.id).toBe(id);
  });
});
