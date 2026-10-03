import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp, type App } from "../src/app.js";
import { loadEnv } from "../src/config/env.js";
import { Codec } from "../src/net/codec.js";
import { TestClient } from "./client.js";
import { defs } from "./helpers.js";

// Phase 19: invite links. A player's welcome carries an invite code; a friend
// who quick-plays with it lands in the same zone (any wave, the friend's mode).
let app: App;
let url = "";
const codec = new Codec(defs().protocol);
const connect = () => TestClient.connect(url, codec);

beforeAll(async () => {
  const env = loadEnv({ NODE_ENV: "test", ALLOW_DEV_AUTH: "1", TELEGRAM_BOT_TOKEN: "123456:TEST-token", TELEGRAM_BOT_USERNAME: "BlackoffTestBot" });
  app = createApp(env, defs());
  await new Promise<void>((r) => app.server.listen(0, "127.0.0.1", r));
  url = `ws://127.0.0.1:${(app.server.address() as AddressInfo).port}/ws`;
});
afterAll(() => app.close());

describe("invites", () => {
  it("puts a friend in the inviter's zone, even an infection lobby", async () => {
    const host = await connect();
    host.hello("dev:Host");
    const hw = await host.waitFor("welcome");
    expect(hw.botUsername).toBe("BlackoffTestBot");
    expect(String(hw.inviteCode)).toMatch(/^[A-Za-z0-9]{10}$/);
    host.send("quickPlay", { mode: 1 });
    const hz = await host.waitFor("zoneJoined");
    expect(hz.friend).toBe(0);

    const guest = await connect();
    guest.hello("dev:Guest");
    await guest.waitFor("welcome");
    guest.send("quickPlay", { mode: 0, friend: hw.inviteCode });
    const gz = await guest.waitFor("zoneJoined");
    expect(gz.zoneId).toBe(hz.zoneId);
    expect(gz.mode).toBe(1);
    expect(gz.friend).toBe(1);
    expect(gz.friendName).toBe("Host");
  });

  it("the same account always gets the same code", async () => {
    const a = await connect();
    a.hello("dev:Steady");
    const w1 = await a.waitFor("welcome");
    a.ws.close();
    const b = await connect();
    b.hello("dev:Steady");
    const w2 = await b.waitFor("welcome");
    expect(w2.inviteCode).toBe(w1.inviteCode);
  });

  it("falls back to quick play when the friend is not playing, or the code is unknown or one's own", async () => {
    const idle = await connect();
    idle.hello("dev:Idle");
    const iw = await idle.waitFor("welcome"); // logged in, but not in a game
    const c = await connect();
    c.hello("dev:Late");
    const cw = await c.waitFor("welcome");
    c.send("quickPlay", { friend: iw.inviteCode });
    const z = await c.waitFor("zoneJoined");
    expect(z.friend).toBe(2);
    expect(z.mode).toBe(0);

    const d = await connect();
    d.hello("dev:Self");
    const dw = await d.waitFor("welcome");
    d.send("quickPlay", { friend: dw.inviteCode });
    expect((await d.waitFor("zoneJoined")).friend).toBe(2);
    expect(cw.inviteCode).not.toBe(dw.inviteCode);

    const e = await connect();
    e.hello("dev:Junk");
    await e.waitFor("welcome");
    e.send("quickPlay", { friend: "not a code!" });
    expect((await e.waitFor("zoneJoined")).friend).toBe(2);
  });
});

describe("owner switches (phase 20)", () => {
  it("a banned account cannot log in; maintenance stops new games but not the owner", async () => {
    const ERR = defs().protocol.enums.errorCode!;
    app.hub.settings.banned.add("dev:Bad");
    const bad = await connect();
    bad.hello("dev:Bad");
    expect((await bad.waitFor("error")).code).toBe(ERR.authFailed);
    app.hub.settings.banned.clear();

    app.hub.settings.maintenance = true;
    app.hub.settings.maintenanceText = "soon";
    const p = await connect();
    p.hello("dev:Someone");
    await p.waitFor("welcome");
    p.send("quickPlay");
    const e = await p.waitFor("error");
    expect(e.code).toBe(ERR.serverShutdown);
    expect(e.message).toBe("soon");
    app.hub.settings.maintenance = false;
  });
});
