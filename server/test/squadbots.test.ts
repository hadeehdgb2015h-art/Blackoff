import { describe, expect, it } from "vitest";
import { Codec } from "../src/net/codec.js";
import { PlayerState } from "../src/sim/entities.js";
import { GameMode } from "../src/sim/simWorld.js";
import { Zone, type ZoneClient, type ZoneResult } from "../src/zone/zone.js";
import { defs } from "./helpers.js";

// Phase 30: AI soldiers fill an online zombies squad and make room for humans.
const C = defs().constants.zone.squadBots;
const codec = new Codec(defs().protocol);
const client = (name: string): ZoneClient => ({ displayName: name, sendBytes: () => {}, onZoneClosed: () => {} });

function run(zone: Zone, fromMs: number, seconds: number, each?: (t: number) => void): number {
  let t = fromMs;
  for (let i = 0; i < seconds * 20; i++) {
    t += 50;
    each?.(t);
    zone.tick(t);
  }
  return t;
}

describe("AI soldiers", () => {
  it("join a lone human one at a time, give way to humans, never get recorded and leave with the last human", () => {
    const zone = new Zone(1, defs(), codec, "facility_01", 5, 0);
    const results: ZoneResult[] = [];
    zone.onResult = (r) => results.push(r);
    const a = zone.join(client("Ali"), "tg:1", 0);
    let t = run(zone, 0, C.joinDelaySec - 1);
    expect(zone.botCount).toBe(0); // a friend with the invite gets the first seconds
    t = run(zone, t, 2);
    expect(zone.botCount).toBe(1);
    t = run(zone, t, 2);
    expect(zone.botCount).toBe(C.fillTo - 1);
    expect(zone.size).toBe(1);
    const bots = [...zone.members.values()].filter((m) => m.bot);
    expect(bots.map((m) => m.level)).toEqual([0, 0]);
    expect(zone.world.players.get(bots[0]!.entityId)!.bot).toBe(true);
    expect(zone.world.squadSize()).toBe(1 + (C.fillTo - 1) * C.waveWeight);
    // a second human takes a bot's place at once
    const b = zone.join(client("Omar"), "tg:2", t);
    expect([zone.size, zone.botCount]).toEqual([2, C.fillTo - 2]);
    zone.remove(b.entityId, t);
    t = run(zone, t, C.joinDelaySec + 2);
    expect(zone.botCount).toBe(C.fillTo - 1); // the gap is filled again
    zone.remove(a.entityId, t);
    expect([zone.size, zone.botCount, zone.members.size]).toEqual([0, 0, 0]);
    expect(zone.emptySince).toBe(t);
    expect(results.map((r) => r.accountId)).toEqual(["tg:2", "tg:1"]); // bots are never recorded
  });

  it("stay out of infection games and leave when the owner switches them off", () => {
    const inf = new Zone(2, defs(), codec, "facility_01", 5, 0, GameMode.INFECTION);
    inf.join(client("Ali"), "tg:1", 0);
    run(inf, 0, C.joinDelaySec + 4);
    expect(inf.botCount).toBe(0);
    const zone = new Zone(3, defs(), codec, "facility_01", 5, 0);
    zone.join(client("Ali"), "tg:1", 0);
    let on = true;
    zone.botsAllowed = () => on;
    let t = run(zone, 0, C.joinDelaySec + 4);
    expect(zone.botCount).toBe(C.fillTo - 1);
    on = false;
    t = run(zone, t, 1);
    expect(zone.botCount).toBe(0);
  });

  it("follow the human, kill zombies and revive a downed human", () => {
    const zone = new Zone(4, defs(), codec, "facility_01", 9, 0);
    const a = zone.join(client("Ali"), "tg:1", 0);
    const w = zone.world;
    const me = w.players.get(a.entityId)!;
    me.god = true;
    let t = run(zone, 0, C.joinDelaySec + 4);
    const bots = [...zone.members.values()].filter((m) => m.bot).map((m) => w.players.get(m.entityId)!);
    expect(bots).toHaveLength(C.fillTo - 1);
    // a few waves with the human standing still: the bots fight
    t = run(zone, t, 90, () => {
      if (!me.isAlive()) { me.state = PlayerState.ALIVE; me.hp = me.maxHp; }
    });
    const kills = bots.reduce((s, b) => s + b.kills, 0);
    expect(kills).toBeGreaterThan(5);
    for (const b of bots) if (b.isAlive()) expect(Math.hypot(b.pos.x - me.pos.x, b.pos.y - me.pos.y)).toBeLessThan(C.followDistance + 4);
    // the human goes down: a bot comes and revives them
    for (const b of bots) { b.state = PlayerState.ALIVE; b.hp = b.maxHp; b.god = true; }
    me.god = false;
    me.state = PlayerState.DOWNED;
    me.downedTime = w.time;
    me.hp = 0;
    let revived = false;
    run(zone, t, 20, () => {
      if (me.state === PlayerState.ALIVE) revived = true;
    });
    expect(revived).toBe(true);
  }, 30_000);
});
