import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { Codec, type Msg } from "../src/net/codec.js";
import { Btn } from "../src/sim/entities.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

describe("revive over the wire", () => {
  let app: App;
  let url = "";
  const codec = new Codec(defs().protocol);
  const EV = defs().protocol.enums.eventKind!;
  beforeAll(async () => {
    app = createApp(loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1" }), defs());
    await app.hub.settings.load();
    app.hub.settings.squadBots = false; // two humans revive each other: no AI soldier in the way (phase 30)
    await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
    url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
  });
  afterAll(() => app.close());

  it("shows downed and being-revived state, then revives and sends the scoreboard at game over", async () => {
    const join = async (name: string) => {
      const c = await TestClient.connect(url, codec);
      c.hello("dev:" + name);
      await c.waitFor("welcome");
      c.send("quickPlay");
      return { c, joined: await c.waitFor("zoneJoined") };
    };
    const { c: a, joined: ja } = await join("Medic");
    const { c: b, joined: jb } = await join("Hurt");
    const zone = app.zones.zones.get(ja.zoneId as number)!;
    const w = zone.world;
    // hold the first wave back: on a slow runner zombies would otherwise arrive mid-revive
    w.director.phaseEnd = w.time + 3600;
    const pa = w.players.get(ja.entityId as number)!;
    const pb = w.players.get(jb.entityId as number)!;
    pb.pos = { x: pa.pos.x + 1, y: pa.pos.y };
    w.damagePlayer(pb, 500, 0); // between ticks (no event), as if a zombie hit landed
    const self = await b.waitFor("selfState", (m) => (m.bleedout as number) > 0);
    expect(self.state).toBe(1);

    // A holds REVIVE: B sees the progress, A's snapshot shows B flagged as being revived
    let seq = 0;
    const timer = setInterval(() => a.send("input", { seq: ++seq, moveX: 0, moveY: 0, yaw: 0, pitch: 0, buttons: Btn.REVIVE }), 50);
    try {
      await b.waitFor("selfState", (m) => (m.revive as number) > 0, 10_000);
      await a.waitFor("snapshot", (m) => (m.entities as Msg[]).some((e) => e.id === pb.id && ((e.flags as number) & 16) !== 0), 10_000);
      const ev = await a.waitFor("event", (m) => m.kind === EV.playerRevived, 12_000);
      expect([ev.a, ev.b]).toEqual([pb.id, pa.id]);
    } finally {
      clearInterval(timer);
    }
    expect(pb.isAlive()).toBe(true);
    expect(pa.revives).toBe(1);

    // everyone down: game over + scoreboard
    w.damagePlayer(pa, 500, 0);
    w.damagePlayer(pb, 500, 0);
    const board = await a.waitFor("scoreboard", () => true, 10_000);
    const rows = board.players as Msg[];
    expect(rows.map((r) => r.name).sort()).toEqual(["Hurt", "Medic"]);
    expect(rows.find((r) => r.name === "Medic")!.revives).toBe(1);
    expect(rows.find((r) => r.name === "Hurt")!.downs).toBe(2);
    a.ws.close();
    b.ws.close();
  }, 45_000); // real time: bleed-out and revive run on the server clock (about 4 s, more on a busy runner)
});
