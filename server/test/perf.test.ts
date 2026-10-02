import { describe, expect, it } from "vitest";
import { Codec } from "../src/net/codec.js";
import { BotBrain } from "../src/sim/botBrain.js";
import { Zone, type ZoneClient } from "../src/zone/zone.js";
import { defs } from "./helpers.js";

describe("zone performance", () => {
  it("a full zone (4 players, 24 zombies) ticks in under 2 ms on average, snapshots included", () => {
    const codec = new Codec(defs().protocol);
    const zone = new Zone(1, defs(), codec, "facility_01", 77, 0);
    let bytes = 0;
    const client = (name: string): ZoneClient => ({ displayName: name, sendBytes: (b) => (bytes += b.length), onZoneClosed: () => {} });
    const bots = [0, 1, 2, 3].map((i) => new BotBrain(zone.join(client("p" + i), "a" + i).entityId, i + 1));
    const w = zone.world;
    for (const p of w.players.values()) {
      p.hp = p.maxHp = 1e9; // keep everyone alive so the zone stays full
      p.weapons[0]!.reserve = 1e6;
    }
    for (let t = 0; t < 400; t++) {
      while (w.zombies.size < 24 && w.zombieSys.spawn("runner", 10)) {
        const z = [...w.zombies.values()].at(-1)!;
        const walk = w.map.walkable[z.id % w.map.walkable.length]!;
        z.pos = { x: walk.x + walk.w / 2, y: walk.y + walk.h / 2 };
      }
      for (const b of bots) zone.pushInput(b.pid, { ...b.think(w), seq: t + 1 });
      zone.tick(t * 50);
    }
    let total = 0;
    const n = 400;
    for (let t = 400; t < 400 + n; t++) {
      while (w.zombies.size < 24 && w.zombieSys.spawn("runner", 10)) {}
      for (const b of bots) zone.pushInput(b.pid, { ...b.think(w), seq: t + 1 });
      const t0 = performance.now();
      zone.tick(t * 50);
      total += performance.now() - t0;
    }
    const avg = total / n;
    console.log(`zone tick avg ${avg.toFixed(3)} ms with ${w.zombies.size} zombies; ${(bytes / ((800 * 50) / 1000) / 4 / 1024).toFixed(1)} KiB/s per client`);
    expect(w.zombies.size).toBeGreaterThan(16);
    expect(avg).toBeLessThan(2.0);
  });
});
