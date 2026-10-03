/** Phase 11: TON points per kill, the weekly hunt leaderboard, anti-cheat flags. */
import type { AddressInfo } from "node:net";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { flagsFor } from "../src/anticheat.js";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { Codec, type Msg } from "../src/net/codec.js";
import { MemoryProfileStore, weekLabel, weekStart, type MatchResult } from "../src/db/profileStore.js";
import { PgProfileStore, migrate } from "../src/db/pgStore.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

const result = (accountId: string, kills: number, extra: Partial<MatchResult> = {}): MatchResult => ({
  accountId, name: accountId.slice(4), kills, headshots: 0, wave: 1, seconds: 60, shots: kills * 3, hits: kills, tonMicro: kills * 1000, flags: [], ...extra,
});

describe("anti-cheat flags", () => {
  const c = defs().constants.anticheat;
  it("flags inhuman hit and head-shot rates only over enough shots, and kill rates over time", () => {
    expect(flagsFor({ shots: 10, hits: 10, headshots: 10, kills: 10, seconds: 30 }, c)).toEqual([]);
    expect(flagsFor({ shots: 100, hits: 99, headshots: 20, kills: 20, seconds: 300 }, c)).toEqual(["hitRate"]);
    expect(flagsFor({ shots: 100, hits: 60, headshots: 58, kills: 30, seconds: 300 }, c)).toEqual(["headshotRate"]);
    expect(flagsFor({ shots: 100, hits: 60, headshots: 20, kills: 200, seconds: 120 }, c)).toEqual(["killsPerMin"]);
    expect(flagsFor({ shots: 100, hits: 60, headshots: 20, kills: 60, seconds: 120 }, c)).toEqual([]);
  });
});

describe("weeks", () => {
  it("start on Monday UTC and carry ISO labels", () => {
    expect(weekStart(new Date("2026-10-02T13:00:00Z"))).toBe("2026-09-28");
    expect(weekStart(new Date("2026-09-28T00:00:00Z"))).toBe("2026-09-28");
    expect(weekStart(new Date("2026-10-04T23:59:59Z"))).toBe("2026-09-28");
    expect(weekLabel("2026-09-28")).toBe("2026-W40");
    expect(weekLabel("2026-12-28")).toBe("2026-W53");
  });
});

describe("weekly hunt (memory store)", () => {
  it("ranks by kills, keeps TON totals and suspicion", async () => {
    const s = new MemoryProfileStore();
    await s.record(result("tg:1", 5));
    await s.record(result("tg:2", 9));
    await s.record(result("tg:1", 6, { flags: ["hitRate"] }));
    await s.record(result("tg:3", 0));
    const board = await s.leaderboard(10);
    expect(board.map((r) => [r.accountId, r.kills, r.tonMicro, r.games])).toEqual([["tg:1", 11, 11000, 2], ["tg:2", 9, 9000, 1]]);
    expect(await s.weekly("tg:2")).toEqual({ rank: 2, kills: 9, tonMicro: 9000 });
    expect(await s.weekly("tg:3")).toEqual({ rank: 0, kills: 0, tonMicro: 0 });
    expect((await s.load("tg:1", "1")).tonMicro).toBe(11000);
    expect((await s.suspects(5)).map((x) => [x.accountId, x.suspicion])).toEqual([["tg:1", 1]]);
  });
});

describe("over the wire", () => {
  let app: App;
  let url = "";
  const store = new MemoryProfileStore();
  const codec = new Codec(defs().protocol);
  beforeAll(async () => {
    app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1", TON_MICRO_PER_KILL: "2500", TON_PRIZE_TEXT: "1 TON", ADMIN_TOKEN: "secret" }), defs(), store);
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
  });
  afterAll(() => app.close());

  it("pays TON per kill, updates the weekly standing, serves the leaderboard and the admin views", async () => {
    const c = await TestClient.connect(url, codec);
    c.hello("dev:Hunter");
    const w = await c.waitFor("welcome");
    expect([w.tonMicro, w.weekKills, w.weekRank, w.tonPerKill]).toEqual([0, 0, 0, 2500]);
    c.send("quickPlay");
    const joined = await c.waitFor("zoneJoined");
    await c.waitFor("snapshot");
    const zone = app.zones.zones.get(joined.zoneId as number)!;
    zone.world.players.get(joined.entityId as number)!.kills = 4; // as if four zombies fell
    c.send("leave");
    const p = await c.waitFor("profile");
    expect([p.tonMicro, p.weekKills, p.weekRank]).toEqual([10000, 4, 1]);
    c.send("leaderboard");
    const board = await c.waitFor("leaderboard");
    expect(board.week).toBe(weekLabel(weekStart()));
    expect(board.prize).toBe("1 TON");
    expect((board.entries as Msg[]).map((e) => [e.rank, e.name, e.kills, e.tonMicro])).toEqual([[1, "Hunter", 4, 10000]]);
    expect([board.myRank, board.myKills, board.myTonMicro]).toEqual([1, 4, 10000]);
    c.ws.close();
    const base = url.replace("ws://", "http://").replace("/ws", "");
    expect((await fetch(base + "/admin/leaderboard")).status).toBe(404);
    expect((await fetch(base + "/admin/leaderboard?token=wrong")).status).toBe(404);
    const lb = (await (await fetch(base + "/admin/leaderboard?token=secret")).json()) as { entries: { accountId: string; kills: number }[]; tonMicroPerKill: number };
    expect(lb.tonMicroPerKill).toBe(2500);
    expect(lb.entries[0]).toMatchObject({ accountId: "dev:Hunter", kills: 4 });
    const sus = (await (await fetch(base + "/admin/suspects?token=secret")).json()) as { suspects: unknown[] };
    expect(sus.suspects).toEqual([]);
  });
});

const dbUrl = process.env.TEST_DATABASE_URL;
describe.skipIf(!dbUrl)("weekly hunt (postgres)", () => {
  let pool: pg.Pool;
  beforeAll(async () => {
    pool = new pg.Pool({ connectionString: dbUrl });
    await pool.query("DROP TABLE IF EXISTS players, matches, weekly_scores, settings, schema_migrations");
    await migrate(pool);
  });
  afterAll(() => pool.end());

  it("accumulates weekly rows, ranks and suspects", async () => {
    const s = new PgProfileStore(pool);
    await s.record(result("tg:1", 5));
    await s.record(result("tg:2", 9, { flags: ["hitRate", "headshotRate"] }));
    await s.record(result("tg:1", 6));
    expect((await s.leaderboard(10)).map((r) => [r.accountId, r.kills, r.tonMicro, r.games])).toEqual([["tg:1", 11, 11000, 2], ["tg:2", 9, 9000, 1]]);
    expect(await s.weekly("tg:1")).toEqual({ rank: 1, kills: 11, tonMicro: 11000 });
    expect(await s.weekly("tg:9")).toEqual({ rank: 0, kills: 0, tonMicro: 0 });
    expect((await s.load("tg:2", "2")).suspicion).toBe(2);
    expect((await s.suspects(5)).map((x) => [x.accountId, x.suspicion, x.shots, x.hits])).toEqual([["tg:2", 2, 27, 9]]);
    expect((await s.leaderboard(10, "2020-01-06")).length).toBe(0); // another week is empty
  });
});
