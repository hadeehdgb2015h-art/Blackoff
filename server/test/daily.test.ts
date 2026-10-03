import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { MemoryProfileStore } from "../src/db/profileStore.js";
import { Codec } from "../src/net/codec.js";
import {
  MISSION_KINDS, applyGame, claimStreak, freshDaily, missionsFor, parseDaily, rollover, secondsToReset, streakStatus, type GameStats,
} from "../src/daily/daily.js";
import { DailyService, Paid } from "../src/daily/dailyService.js";
import { GameMode } from "../src/sim/simWorld.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

// Phase 23: daily reward (7-day streak) and three daily missions, paid in TON points.
const D = defs().constants.daily;
const game = (g: Partial<GameStats> = {}): GameStats => ({ kills: 0, headshots: 0, wave: 0, bossKills: 0, seconds: 120, zombies: true, ...g });

describe("daily rules", () => {
  it("picks three different missions, easy to hard, the same for the same account and day", () => {
    const a = missionsFor("tg:1", "2026-10-03", D);
    expect(a.length).toBe(3);
    expect(new Set(a.map((m) => m.kind)).size).toBe(3);
    a.forEach((m, tier) => {
      expect(m.goal).toBe(D.missions[m.kind].goals[tier]);
      expect(m.goal).toBeGreaterThan(0);
    });
    expect(missionsFor("tg:1", "2026-10-03", D)).toEqual(a);
    // across many accounts and days every kind shows up, and boss is never the easy one
    const seen = new Set<string>();
    for (let i = 0; i < 200; i++) {
      const ms = missionsFor("tg:" + i, "2026-10-" + String(1 + (i % 28)).padStart(2, "0"), D);
      ms.forEach((m) => seen.add(m.kind));
      expect(ms[0]!.kind).not.toBe("boss");
    }
    expect([...seen].sort()).toEqual([...MISSION_KINDS].sort());
  });

  it("walks the 7-day calendar on consecutive days and restarts after a missed day", () => {
    let s = freshDaily();
    const days = ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08"];
    const paid: number[] = [];
    for (const d of days) {
      const r = claimStreak(s, d, D);
      paid.push(r.paidKills);
      s = r.state;
      expect(claimStreak(s, d, D).paidKills).toBe(0); // once a day
      expect(streakStatus(s, d)).toEqual({ canClaim: false, nextDay: s.streak });
    }
    expect(paid).toEqual([...D.streakKills, D.streakKills[0]]); // day 8 starts the calendar again
    expect(streakStatus(s, "2026-10-10")).toEqual({ canClaim: true, nextDay: 1 }); // missed the 9th
    expect(streakStatus(s, "2026-10-09")).toEqual({ canClaim: true, nextDay: 2 });
  });

  it("counts games into missions, pays each mission once and the bonus when all three are done", () => {
    let s = rollover(freshDaily(), "tg:7", "2026-10-03", D);
    s = { ...s, missions: [
      { kind: "kills", goal: 40, progress: 0, rewardKills: 10, done: false },
      { kind: "wave", goal: 7, progress: 0, rewardKills: 20, done: false },
      { kind: "games", goal: 2, progress: 0, rewardKills: 15, done: false },
    ] };
    let r = applyGame(s, game({ kills: 25, wave: 5 }), D);
    expect(r.paidKills).toBe(0);
    expect(r.state.missions.map((m) => m.progress)).toEqual([25, 5, 1]);
    r = applyGame(r.state, game({ kills: 30, wave: 3, zombies: false }), D); // infection: only "games" counts
    expect(r.state.missions.map((m) => m.progress)).toEqual([25, 5, 2]);
    expect(r.paidKills).toBe(15);
    r = applyGame(r.state, game({ kills: 30, wave: 8, seconds: 10 }), D); // too short for "games", still kills
    expect(r.state.missions.map((m) => [m.progress, m.done])).toEqual([[40, true], [7, true], [2, true]]);
    expect(r.paidKills).toBe(10 + 20 + D.allMissionsBonusKills);
    expect(applyGame(r.state, game({ kills: 99, wave: 20 }), D).paidKills).toBe(0);
    // the next day brings new missions and a fresh bonus
    const next = rollover(r.state, "tg:7", "2026-10-04", D);
    expect(next.bonusDone).toBe(false);
    expect(next.missions.every((m) => m.progress === 0 && !m.done)).toBe(true);
  });

  it("reads stored state defensively and counts down to midnight UTC", () => {
    expect(parseDaily(null)).toEqual(freshDaily());
    expect(parseDaily({ day: "x", streak: 99, missions: [{ kind: "nope" }, { kind: "kills", goal: 10, progress: 50, rewardKills: 5, done: true }] }))
      .toEqual({ day: "", streak: 7, lastClaim: "", bonusDone: false, missions: [{ kind: "kills", goal: 10, progress: 10, rewardKills: 5, done: true }] });
    expect(secondsToReset(new Date("2026-10-03T23:59:00Z"))).toBe(60);
  });
});

describe("daily service", () => {
  it("pays the streak in TON points per kill and never twice, even when claims race", async () => {
    const store = new MemoryProfileStore();
    await store.load("tg:5", "Five");
    let now = new Date("2026-10-03T10:00:00Z");
    const svc = new DailyService(store, D, () => 1000, () => now);
    const first = await svc.view("tg:5");
    expect(first.msg).toMatchObject({ canClaim: true, nextDay: 1, streak: 0, paidMicro: 0, day: "2026-10-03" });
    expect((first.msg.rewards as { tonMicro: number }[]).map((r) => r.tonMicro)).toEqual(D.streakKills.map((k) => k * 1000));
    const [a, b] = await Promise.all([svc.claim("tg:5"), svc.claim("tg:5")]);
    expect([a.msg.paidMicro, b.msg.paidMicro]).toEqual([D.streakKills[0]! * 1000, 0]);
    expect(a.msg.paidKind).toBe(Paid.STREAK);
    expect((await store.load("tg:5", "Five")).tonMicro).toBe(D.streakKills[0]! * 1000);
    now = new Date("2026-10-04T08:00:00Z");
    expect((await svc.claim("tg:5")).msg).toMatchObject({ paidMicro: D.streakKills[1]! * 1000, streak: 2, canClaim: false, nextDay: 2 });
  });
});

describe("daily over the wire", () => {
  let app: App;
  let url = "";
  const codec = new Codec(defs().protocol);
  beforeAll(async () => {
    app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1" }), defs());
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
  });
  afterAll(() => app.close());

  it("sends the state after welcome, claims once, and pays missions after a game", async () => {
    const c = await TestClient.connect(url, codec);
    c.hello("dev:Daily");
    await c.waitFor("welcome");
    const d0 = await c.waitFor("daily");
    expect(d0).toMatchObject({ canClaim: true, nextDay: 1, paidMicro: 0 });
    expect((d0.missions as unknown[]).length).toBe(3);
    c.send("claimDaily");
    const prof = await c.waitFor("profile");
    const d1 = await c.waitFor("daily", (m) => m.paidKind === Paid.STREAK);
    expect(prof.tonMicro).toBe(d1.paidMicro);
    expect(d1).toMatchObject({ canClaim: false, streak: 1 });
    c.send("claimDaily");
    expect((await c.waitFor("daily", (m) => m !== d1)).paidMicro).toBe(0);

    // a long zombies game that finishes every mission
    const missions = d1.missions as { kind: number; goal: number }[];
    const big = Object.fromEntries(MISSION_KINDS.map((k, i) => [k, missions.find((m) => m.kind === i)?.goal ?? 0]));
    const games = Math.max(1, big.games!);
    for (let i = 0; i < games; i++) {
      app.hub.onResult({
        accountId: "dev:Daily", name: "Daily", kills: big.kills!, headshots: big.headshots!, wave: big.wave!, bossKills: big.boss!,
        seconds: 300, shots: 0, hits: 0, mode: GameMode.CLASSIC,
      });
    }
    const done = await c.waitFor("daily", (m) => m.bonusDone === true);
    expect((done.missions as { done: boolean }[]).every((m) => m.done)).toBe(true);
    expect(done.paidKind).toBe(Paid.MISSIONS);
  });
});
