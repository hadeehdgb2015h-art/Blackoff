import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { MemoryProfileStore } from "../src/db/profileStore.js";
import { Codec } from "../src/net/codec.js";
import { levelFor, rankFor, xpFor, xpToReach } from "../src/progression.js";
import { GameMode } from "../src/sim/simWorld.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

// Phase 26: levels and ranks from the server's own record of each game.
const P = defs().constants.progression;

describe("progression rules", () => {
  it("costs base + step per level, caps at the max level and gives ranks in order", () => {
    expect(xpToReach(1, P)).toBe(0);
    expect(xpToReach(2, P)).toBe(P.levelXpBase);
    expect(xpToReach(3, P) - xpToReach(2, P)).toBe(P.levelXpBase + P.levelXpStep);
    expect(levelFor(xpToReach(37, P), P)).toBe(37);
    expect(levelFor(xpToReach(37, P) - 1, P)).toBe(36);
    expect(levelFor(1e12, P)).toBe(P.maxLevel);
    expect(rankFor(1, P).id).toBe("recruit");
    expect(rankFor(P.maxLevel, P).id).toBe("legend");
    const levels = P.ranks.map((r) => r.level);
    expect([...levels].sort((a, b) => a - b)).toEqual(levels);
    expect(levels[0]).toBe(1);
  });

  it("gives xp for kills, headshots and the wave, or minutes played in infection", () => {
    expect(xpFor({ kills: 10, headshots: 2, wave: 4, seconds: 300, mode: GameMode.CLASSIC }, P))
      .toBe(10 * P.xpPerKill + 2 * P.xpPerHeadshot + 4 * P.xpPerWaveReached);
    expect(xpFor({ kills: 3, headshots: 0, wave: 2, seconds: 150, mode: GameMode.INFECTION }, P))
      .toBe(3 * P.xpPerKill + 2 * P.xpPerInfectionMinute);
  });

  it("adds a game's xp to the profile", async () => {
    const s = new MemoryProfileStore();
    await s.load("tg:1", "A");
    const p = await s.record({ accountId: "tg:1", name: "A", kills: 1, headshots: 0, wave: 1, seconds: 60, shots: 0, hits: 0, tonMicro: 0, flags: [], xp: 640 });
    expect(p.xp).toBe(640);
    expect((await s.record({ accountId: "tg:1", name: "A", kills: 0, headshots: 0, wave: 0, seconds: 5, shots: 0, hits: 0, tonMicro: 0, flags: [] })).xp).toBe(640);
  });
});

describe("progression over the wire", () => {
  let app: App;
  let url = "";
  const codec = new Codec(defs().protocol);
  beforeAll(async () => {
    app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1" }), defs());
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
  });
  afterAll(() => app.close());

  it("sends xp and level, levels up after a game, and shows levels in the roster", async () => {
    const c = await TestClient.connect(url, codec);
    c.hello("dev:Climber");
    const w = await c.waitFor("welcome");
    expect([w.xp, w.level]).toEqual([0, 1]);
    app.hub.onResult({ accountId: "dev:Climber", name: "Climber", kills: 120, headshots: 30, wave: 10, seconds: 900, shots: 0, hits: 0, mode: GameMode.CLASSIC, bossKills: 0 });
    const p = await c.waitFor("profile", (m) => (m.xp as number) > 0);
    const xp = 120 * P.xpPerKill + 30 * P.xpPerHeadshot + 10 * P.xpPerWaveReached;
    expect(p.xp).toBe(xp);
    expect(p.level).toBe(levelFor(xp, P));
    expect(p.level as number).toBeGreaterThan(1);
    c.send("quickPlay");
    await c.waitFor("zoneJoined");
    const roster = await c.waitFor("roster");
    expect((roster.players as { name: string; level: number }[])[0]).toMatchObject({ name: "Climber", level: levelFor(xp, P) });
  });
});
